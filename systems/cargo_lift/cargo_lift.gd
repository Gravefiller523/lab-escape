class_name CargoLift
extends Node3D
## The cargo lift: the elevator that carries the team up through the facility (scene:
## systems/cargo_lift/cargo_lift.tscn). It stays loaded for the whole run; game_flow loads the Break
## Room and the floors around it, so everything inside it (players, crates, items, carts) rides along.
##
## The back wall has a slot for every kind of lift part (gear, fuse, light, button, counterweight,
## vacuum tube, cable spool, battery, lever: every PropData with a lift_slot, so a new part is just a
## new file). Each floor the lift arrives with 1 to 3 slots broken (picked with the run's seed). Broken
## slots spark; their parts are somewhere on the floor, as far from the lift as possible. Players carry
## each part back and drop it into its slot (a battery must be charged on a charger first; a vacuum tube
## shatters if thrown). Then everyone gets in and someone presses Go; it refuses with the missing names.
## In the Break Room nothing is broken: Go starts the run, and after afk_force_start_after seconds the
## host gets "Start anyway". On a boss floor, beating the boss fixes it.
##
## The host decides everything (slots, Go, doors, charging) and tells the other PCs. While it rides, the
## lift stays still and the shaft walls slide down past it, so it looks like it is going up.
## Spec: docs/systems/cargo_lift.md.

signal parts_changed(delivered: int, needed: int)
## Anything shown on the panel changed (broken, riding, doors).
signal state_changed()

const GROUP: StringName = &"cargo_lift"
const LIFT_PART_TAG: String = "lift_part"
## Inside size (metres): width (x), depth (z), height. The gate is on the -z side.
const INSIDE: Vector3 = Vector3(5.0, 3.4, 5.0)
const WALL: float = 0.2
const DOOR_SPEED: float = 2.5
## The shaft drawn around the lift while it rides.
const SHAFT_GAP: float = 0.6
const SHAFT_HEIGHT: float = 60.0
const BEAM_SPACING: float = 3.0
## Seconds to speed up at the start of a ride and slow down at the end.
const RIDE_EASE_SECONDS: float = 1.0
## The slots on the back wall: a grid this many columns wide, starting from the left.
const SLOT_COLUMNS: int = 3
const SLOT_SIZE: Vector2 = Vector2(1.0, 0.65)
const SLOT_ORIGIN: Vector2 = Vector2(-1.9, 0.5)
## How often (seconds) the host checks that every broken slot's part still exists somewhere.
const PART_CHECK_SECONDS: float = 1.0
## The charger for batteries.
const CHARGER_SIZE: Vector3 = Vector3(1.2, 0.3, 1.2)
## How often the same "battery is flat" message may be shown (seconds).
const NOTE_REPEAT_SECONDS: float = 2.0

const PROMPT_GO: String = "Go up"
const PROMPT_START: String = "Start the run"
const PROMPT_START_ANYWAY: String = "Start anyway (players outside are brought in)"
const MSG_BROKEN: String = "The lift is broken. Fix it first: %s."
const MSG_WAITING: String = "Everyone into the lift first. Waiting for: %s"
const MSG_BOSS: String = "The lift won't move until the boss is beaten."
const MSG_FLAT: String = "The battery is flat. Charge it on the charger first."

var _net: NetService
var _config: GameConfig
## Synced state (the host's is the truth).
var _broken_slots: Array[StringName] = []
var _fixed_slots: Array[StringName] = []
var _in_break_room: bool = true
var _waiting_for_boss: bool = false
var _doors_open: bool = true
var _riding: bool = false
## Batteries (net ids) that have been charged.
var _charged: Dictionary[int, bool] = {}
## Host: seconds each battery (net id) has spent on the charger.
var _charge_time: Dictionary[int, float] = {}
## Host: when someone first stood in the lift in the Break Room (msec), or -1.
var _occupied_since_msec: int = -1
var _part_check_left: float = 0.0
var _last_note_msec: int = -100000
## Ride visuals (every PC).
var _ride_speed: float = 0.0
var _ride_target_speed: float = 0.0
var _ride_offset: float = 0.0

## Slot name -> the part that fits it (the first lift-part prop for that slot, by id).
var _slot_parts: Dictionary[StringName, PropData] = {}
## Slot name -> {"sparks": CPUParticles3D, "light": OmniLight3D, "installed": Node3D, "label": Label3D}
var _slot_nodes: Dictionary[StringName, Dictionary] = {}
var _zone: ElevatorZone
var _left_door: AnimatableBody3D
var _right_door: AnimatableBody3D
var _go_use: Interactable
var _force_body: StaticBody3D
var _force_use: Interactable
var _panel_label: Label3D
var _shaft: Node3D
var _beams: Array[Node3D] = []
var _spawns: Array[Node3D] = []
var _charger: Area3D


## The lift in the game right now, or null.
static func current() -> CargoLift:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var lift := node as CargoLift
		if lift != null and lift.is_inside_tree() and not lift.is_queued_for_deletion():
			return lift
	return null


## Every kind of lift part, as slot name -> PropData (sorted heaviest first, then by id).
static func lift_part_kinds() -> Dictionary[StringName, PropData]:
	var parts: Array[PropData] = []
	for content: ContentData in ContentRegistry.get_all(&"prop"):
		var prop := content as PropData
		if prop != null and prop.lift_slot != &"":
			parts.append(prop)
	parts.sort_custom(func(a: PropData, b: PropData) -> bool:
		return a.mass > b.mass if not is_equal_approx(a.mass, b.mass) else String(a.id) < String(b.id))
	var kinds: Dictionary[StringName, PropData] = {}
	for prop: PropData in parts:
		if not kinds.has(prop.lift_slot):
			kinds[prop.lift_slot] = prop
	return kinds


## For tests only: a different Net and config. Call before adding the node to the tree.
func use_net(net: NetService, config: GameConfig) -> void:
	_net = net
	_config = config


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	add_to_group(GROUP)
	_slot_parts = lift_part_kinds()
	_build()
	_zone.occupants_changed.connect(_on_occupants_changed)
	EventBus.player_joined.connect(_on_player_joined)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.floor_ready.connect(_on_floor_ready)
	_refresh_panel()


# --- Public API -------------------------------------------------------------------------------

func get_zone() -> ElevatorZone:
	return _zone


## How many slots broke on this floor.
func get_parts_needed() -> int:
	return _broken_slots.size()


## How many of them have been fixed.
func get_parts_delivered() -> int:
	return _fixed_slots.size()


## NEW: every slot the lift has (one per kind of lift part).
func get_slot_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.assign(_slot_parts.keys())
	return names


## NEW: the slots still broken (their parts haven't been slotted in yet).
func get_broken_slots() -> Array[StringName]:
	var broken: Array[StringName] = []
	for slot: StringName in _broken_slots:
		if not _fixed_slots.has(slot):
			broken.append(slot)
	return broken


## NEW: the part that fits a slot.
func get_slot_part(slot: StringName) -> PropData:
	return _slot_parts.get(slot)


## NEW: true once a battery (or any part that needs charging) has been charged.
func is_charged(prop: NetProp) -> bool:
	return prop != null and (prop.data == null or prop.data.needs_charge_seconds <= 0.0 or _charged.has(prop.net_id))


## Fixed (or never broken), not riding and not waiting for a boss: Go works once everyone is inside.
func is_ready() -> bool:
	return not is_broken() and not _riding and not _waiting_for_boss


func is_broken() -> bool:
	return not get_broken_slots().is_empty()


func is_riding() -> bool:
	return _riding


func is_in_break_room() -> bool:
	return _in_break_room


## Where players appear inside the lift (8 spots; more players share them).
func get_spawn_points() -> Array[Node3D]:
	return _spawns.duplicate()


## What still stops the lift leaving, or "" if Go would work now (host).
func depart_blocker() -> String:
	if _riding:
		return ""
	if _waiting_for_boss:
		return MSG_BOSS
	if is_broken():
		var names: PackedStringArray = []
		for slot: StringName in get_broken_slots():
			names.append(_slot_title(slot))
		return MSG_BROKEN % ", ".join(names)
	var missing: PackedStringArray = []
	for player_id: int in _zone.get_missing_players():
		missing.append(_net.get_display_name(player_id))
	if not missing.is_empty():
		return MSG_WAITING % ", ".join(missing)
	return ""


## Local: press Go (the button does this). The host checks it.
func request_depart() -> void:
	if multiplayer.is_server():
		_try_depart(_net.local_player_id())
	else:
		_request_depart_rpc.rpc_id(1)


## Host (game_flow): the lift has arrived somewhere. break_count slots break (picked with the run's
## seed; 0 = it works, e.g. the Break Room). waiting_for_boss = it works once the boss is beaten.
## Opens the doors on every PC.
func arrive(break_count: int, in_break_room: bool, waiting_for_boss: bool = false) -> void:
	if not multiplayer.is_server():
		return
	_occupied_since_msec = -1
	_charge_time.clear()
	var broken: Array[StringName] = _pick_broken_slots(break_count)
	_state_rpc.rpc(_names(broken), [] as Array[String], in_break_room, waiting_for_boss, true, false)


## Host (game_flow): close the doors and ride (e.g. back to the Break Room after a run).
func depart_now() -> void:
	if multiplayer.is_server() and not _riding:
		_state_rpc.rpc(_names(_broken_slots), _names(_fixed_slots), _in_break_room, false, false, true)


## Host: brings everyone who isn't inside into the lift (Start anyway, the trip back after a run).
func gather_players() -> void:
	if not multiplayer.is_server():
		return
	var index: int = 0
	for player_id: int in _zone.get_missing_players():
		var body: PlayerCharacter = PlayerCharacter.find(player_id)
		if body != null:
			body.teleport(_spawns[index % _spawns.size()].global_transform)
			index += 1


## Host, Break Room: "Start anyway" may be used (someone has waited inside long enough).
func can_force_start() -> bool:
	if not multiplayer.is_server() or not _in_break_room or _riding or _config.afk_force_start_after <= 0.0:
		return false
	if _occupied_since_msec < 0:
		return false
	return Time.get_ticks_msec() - _occupied_since_msec >= int(_config.afk_force_start_after * 1000.0)


# --- Host logic -------------------------------------------------------------------------------

## Which slots break: break_count of them, picked with the run's seed and floor (the same run always
## breaks the same slots), from the department's lift_part_ids (all if empty).
func _pick_broken_slots(break_count: int) -> Array[StringName]:
	var candidates: Array[StringName] = []
	var department: DepartmentData = GameFlow.get_current_department()
	for slot: StringName in _slot_parts.keys():
		var part: PropData = _slot_parts[slot]
		if department == null or department.lift_part_ids.is_empty() or department.lift_part_ids.has(part.id):
			candidates.append(slot)
	var run: RunState = GameFlow.get_run()
	var rng: RandomNumberGenerator = SeededRng.make(run.run_seed if run != null else 0, &"lift_breaks",
		run.floor_number if run != null else 0)
	var picked: Array[StringName] = []
	for index: int in mini(break_count, candidates.size()):
		var choice: int = rng.randi_range(0, candidates.size() - 1)
		picked.append(candidates[choice])
		candidates.remove_at(choice)
	return picked


func _try_depart(player_id: int) -> void:
	if not multiplayer.is_server() or _riding:
		return
	var blocker: String = depart_blocker()
	if blocker.is_empty():
		_depart()
		return
	_tell(player_id, blocker)


func _depart() -> void:
	_state_rpc.rpc(_names(_broken_slots), _names(_fixed_slots), _in_break_room, false, false, true)
	_departed_rpc.rpc()


func _on_force_used(player_id: int) -> void:
	if not can_force_start() or player_id != _net.local_player_id():
		return
	gather_players()
	_depart()


func _on_go_used(player_id: int) -> void:
	_try_depart(player_id)


## Host: a prop touched a slot: if it is that slot's part (charged, if it needs it), install it.
func _on_slot_body_entered(body: Node3D, slot: StringName) -> void:
	if not multiplayer.is_server() or _riding:
		return
	var prop := body as NetProp
	if prop == null or prop.data == null or prop.data.lift_slot != slot:
		return
	if not get_broken_slots().has(slot):
		return
	if not is_charged(prop):
		if Time.get_ticks_msec() - _last_note_msec > int(NOTE_REPEAT_SECONDS * 1000.0):
			_last_note_msec = Time.get_ticks_msec()
			_tell(prop.last_holder_id, MSG_FLAT)
		return
	var spawner: PropSpawner = prop.get_spawner()
	if spawner == null:
		return
	spawner.despawn(prop)
	var fixed: Array[StringName] = _fixed_slots.duplicate()
	fixed.append(slot)
	_state_rpc.rpc(_names(_broken_slots), _names(fixed), _in_break_room, _waiting_for_boss, _doors_open, _riding)
	_part_delivered_rpc.rpc(fixed.size(), _broken_slots.size())


func _on_boss_defeated(_boss_id: StringName) -> void:
	if multiplayer.is_server() and _waiting_for_boss:
		_state_rpc.rpc(_names(_broken_slots), _names(_fixed_slots), _in_break_room, false, _doors_open, _riding)


## Every PC: the floor is ready. The host puts each broken slot's part somewhere far from the lift;
## every PC puts the charger in (the same one everywhere) if a broken part needs charging.
func _on_floor_ready(floor_number: int, _department_id: StringName) -> void:
	if not is_inside_tree():
		return
	_build_charger(floor_number)
	if not multiplayer.is_server():
		return
	var spots: Array[RoomMarker] = _part_spots()
	for index: int in get_broken_slots().size():
		var part: PropData = _slot_parts.get(get_broken_slots()[index])
		if part != null and not spots.is_empty():
			Props.spawn_prop(part.id, spots[index % spots.size()].global_transform)
	_part_check_left = PART_CHECK_SECONDS


## lift_part markers, farthest from the lift first (a stable sort keeps the marker order for ties).
func _part_spots() -> Array[RoomMarker]:
	var order: Array[RoomMarker] = Level.get_markers(&"lift_part")
	order.sort_custom(func(a: RoomMarker, b: RoomMarker) -> bool:
		return a.global_position.distance_to(global_position) > b.global_position.distance_to(global_position))
	return order


## Host: a broken slot whose part no longer exists (it shattered, or was lost) gets a new one far away,
## so a floor can never become impossible.
func _replace_missing_parts() -> void:
	var spots: Array[RoomMarker] = _part_spots()
	if spots.is_empty():
		return
	for slot: StringName in get_broken_slots():
		var part: PropData = _slot_parts.get(slot)
		if part != null and Props.get_props(part.id).is_empty():
			Props.spawn_prop(part.id, spots[0].global_transform)


## Host: batteries on the charger charge up; when full they glow (on every PC) and fit their slot.
func _charge_batteries(delta: float) -> void:
	if _charger == null or not is_instance_valid(_charger):
		return
	for body: Node3D in _charger.get_overlapping_bodies():
		var prop := body as NetProp
		if prop == null or prop.data == null or prop.data.needs_charge_seconds <= 0.0 or _charged.has(prop.net_id):
			continue
		_charge_time[prop.net_id] = _charge_time.get(prop.net_id, 0.0) + delta
		if _charge_time[prop.net_id] >= prop.data.needs_charge_seconds:
			_charged_rpc.rpc(prop.net_id)


func _on_occupants_changed() -> void:
	if _zone.get_players_inside().is_empty():
		_occupied_since_msec = -1
	elif _occupied_since_msec < 0:
		_occupied_since_msec = Time.get_ticks_msec()


## Host: a player who just joined gets the lift as it is now.
func _on_player_joined(player_id: int) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var peer_id: int = _net.get_peer_id(player_id)
	if peer_id != 0 and peer_id != multiplayer.get_unique_id():
		_state_rpc.rpc_id(peer_id, _names(_broken_slots), _names(_fixed_slots), _in_break_room, _waiting_for_boss,
			_doors_open, _riding)


func _tell(player_id: int, text: String) -> void:
	var peer_id: int = _net.get_peer_id(player_id)
	if peer_id != 0:
		_note_rpc.rpc_id(peer_id, text)


static func _names(slots: Array[StringName]) -> Array[String]:
	var names: Array[String] = []
	for slot: StringName in slots:
		names.append(String(slot))
	return names


func _slot_title(slot: StringName) -> String:
	var part: PropData = _slot_parts.get(slot)
	return part.display_name.to_lower() if part != null else String(slot)


# --- RPCs -----------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _request_depart_rpc() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var player_id: int = _net.get_player_id_for_peer(multiplayer.get_remote_sender_id())
	if player_id != 0:
		_try_depart(player_id)


## Host -> everyone: the lift's state. (Plain arrays of slot names: typed arrays don't cross the network.)
@rpc("authority", "call_local", "reliable")
func _state_rpc(broken_slots: Array, fixed_slots: Array, in_break_room: bool, waiting_for_boss: bool,
		doors_open: bool, riding: bool) -> void:
	if not is_inside_tree():
		return
	var fixed_before: int = _fixed_slots.size()
	var was_riding: bool = _riding
	_broken_slots.clear()
	for slot: Variant in broken_slots:
		_broken_slots.append(StringName(str(slot)))
	_fixed_slots.clear()
	for slot: Variant in fixed_slots:
		_fixed_slots.append(StringName(str(slot)))
	_in_break_room = in_break_room
	_waiting_for_boss = waiting_for_boss
	_doors_open = doors_open
	_riding = riding
	if riding and not was_riding:
		_start_ride_visuals()
		_charged.clear()
		_remove_charger()
	elif was_riding and not riding:
		_stop_ride_visuals()
	if fixed_before != _fixed_slots.size() or not riding:
		parts_changed.emit(get_parts_delivered(), get_parts_needed())
	_refresh_panel()
	state_changed.emit()


## Host -> everyone: the lift has left (game_flow loads the next floor while it rides).
@rpc("authority", "call_local", "reliable")
func _departed_rpc() -> void:
	if not is_inside_tree():
		return
	var run: RunState = GameFlow.get_run()
	EventBus.lift_departed.emit(run.floor_number if run != null else 0)


@rpc("authority", "call_local", "reliable")
func _part_delivered_rpc(delivered: int, needed: int) -> void:
	if not is_inside_tree():
		return
	EventBus.lift_part_delivered.emit(delivered, needed)
	if delivered >= needed:
		EventBus.lift_ready.emit()


## Host -> everyone: this battery is charged (it glows green).
@rpc("authority", "call_local", "reliable")
func _charged_rpc(net_id: int) -> void:
	if not is_inside_tree():
		return
	_charged[net_id] = true
	var prop: NetProp = Props.get_prop(net_id)
	if prop == null:
		return
	var mesh := prop.get_node_or_null(^"Mesh") as MeshInstance3D
	if mesh != null:
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.3, 0.9, 0.4)
		glow.emission_enabled = true
		glow.emission = Color(0.2, 0.9, 0.3)
		glow.emission_energy_multiplier = 1.5
		mesh.material_override = glow
	EventBus.toast_requested.emit("The battery is charged!")


@rpc("authority", "call_local", "reliable")
func _note_rpc(text: String) -> void:
	if not is_inside_tree():
		return
	EventBus.toast_requested.emit(text)


# --- Every PC: doors, panel, slots, ride ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	var open_x: float = INSIDE.x * 0.75
	var closed_x: float = INSIDE.x * 0.25
	_left_door.position.x = move_toward(_left_door.position.x, -(open_x if _doors_open else closed_x), DOOR_SPEED * delta)
	_right_door.position.x = move_toward(_right_door.position.x, open_x if _doors_open else closed_x, DOOR_SPEED * delta)
	if multiplayer.is_server() and not _riding:
		_charge_batteries(delta)
		if is_broken():
			_part_check_left -= delta
			if _part_check_left <= 0.0:
				_part_check_left = PART_CHECK_SECONDS
				_replace_missing_parts()


func _process(delta: float) -> void:
	var can_force: bool = can_force_start()
	if _force_body.visible != can_force:
		_force_body.visible = can_force
		_force_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES) if can_force else 0
	# Broken slots flicker.
	for slot: StringName in _slot_nodes.keys():
		var light := _slot_nodes[slot]["light"] as OmniLight3D
		if light.visible:
			light.light_energy = randf_range(0.2, 2.5) if randf() < 0.3 else light.light_energy
	# The ride: the shaft's light beams slide down past the lift.
	var ease_rate: float = _config.lift_ride_speed / RIDE_EASE_SECONDS
	_ride_speed = move_toward(_ride_speed, _ride_target_speed, ease_rate * delta)
	if _shaft.visible:
		_ride_offset = fposmod(_ride_offset + _ride_speed * delta, BEAM_SPACING)
		for index: int in _beams.size():
			var beam: Node3D = _beams[index]
			beam.position.y = float(index) * BEAM_SPACING - SHAFT_HEIGHT / 2.0 - _ride_offset
		if not _riding and is_zero_approx(_ride_speed):
			_shaft.visible = false


func _start_ride_visuals() -> void:
	_shaft.visible = true
	_ride_target_speed = _config.lift_ride_speed


func _stop_ride_visuals() -> void:
	# Slow down; _process hides the shaft once it has stopped.
	_ride_target_speed = 0.0


func _refresh_panel() -> void:
	if _panel_label == null:
		return
	var broken: Array[StringName] = get_broken_slots()
	if _riding:
		_panel_label.text = "Going up..."
	elif _waiting_for_boss:
		_panel_label.text = "Beat the boss"
	elif not broken.is_empty():
		var names: PackedStringArray = []
		for slot: StringName in broken:
			names.append(_slot_title(slot).to_upper())
		_panel_label.text = "BROKEN: %s" % ", ".join(names)
	else:
		_panel_label.text = "Ready"
	_panel_label.modulate = Color(1, 0.35, 0.3) if not broken.is_empty() or _waiting_for_boss else Color(0.4, 1, 0.5)
	_go_use.prompt_text = PROMPT_START if _in_break_room else PROMPT_GO
	for slot: StringName in _slot_nodes.keys():
		var nodes: Dictionary = _slot_nodes[slot]
		var is_broken_now: bool = broken.has(slot) and not _riding
		(nodes["sparks"] as CPUParticles3D).emitting = is_broken_now
		(nodes["light"] as OmniLight3D).visible = is_broken_now
		(nodes["installed"] as Node3D).visible = not broken.has(slot)
		(nodes["label"] as Label3D).modulate = Color(1, 0.4, 0.3) if broken.has(slot) else Color(0.8, 0.85, 0.9)


## Every PC: the charger for batteries, on one of the floor's charger markers (the same one on every
## PC: picked with the run's seed). Only when a broken part needs charging.
func _build_charger(floor_number: int) -> void:
	_remove_charger()
	var needs_charger: bool = false
	for slot: StringName in get_broken_slots():
		var part: PropData = _slot_parts.get(slot)
		needs_charger = needs_charger or (part != null and part.needs_charge_seconds > 0.0)
	var spots: Array[RoomMarker] = Level.get_markers(&"charger")
	if not needs_charger or spots.is_empty():
		return
	var run: RunState = GameFlow.get_run()
	var rng: RandomNumberGenerator = SeededRng.make(run.run_seed if run != null else 0, &"lift_charger", floor_number)
	var spot: RoomMarker = spots[rng.randi_range(0, spots.size() - 1)]
	_charger = Area3D.new()
	_charger.name = "ChargerPad"
	_charger.collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	_charger.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS)
	_charger.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CHARGER_SIZE.x, 1.2, CHARGER_SIZE.z)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	_charger.add_child(shape)
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = CHARGER_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.5, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.1, 0.3, 0.8)
	pad_mesh.material = material
	pad.mesh = pad_mesh
	pad.position = Vector3(0, CHARGER_SIZE.y / 2.0, 0)
	_charger.add_child(pad)
	var label := Label3D.new()
	label.text = "CHARGER\n(put the battery here)"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.position = Vector3(0, 1.4, 0)
	_charger.add_child(label)
	# On the floor's level (not the lift), so it goes when the level does.
	spot.add_child(_charger)


func _remove_charger() -> void:
	if _charger != null and is_instance_valid(_charger):
		_charger.queue_free()
	_charger = null


# --- Building the lift ------------------------------------------------------------------------------

func _build() -> void:
	var steel := Color(0.36, 0.4, 0.46)
	var dark := Color(0.2, 0.22, 0.25)
	var half := Vector3(INSIDE.x / 2.0, INSIDE.y, INSIDE.z / 2.0)
	# Floor, back wall, roof (solid).
	_box(self, "Platform", Vector3(0, -0.15, 0), Vector3(INSIDE.x + WALL * 2, 0.3, INSIDE.z + WALL * 2), steel, true)
	_box(self, "BackWall", Vector3(0, half.y / 2.0, half.z + WALL / 2.0), Vector3(INSIDE.x + WALL * 2, half.y, WALL), steel, true)
	_box(self, "Roof", Vector3(0, half.y + WALL / 2.0, 0), Vector3(INSIDE.x + WALL * 2, WALL, INSIDE.z + WALL * 2), dark, true)
	# Sides: a railing you can see over, and an invisible wall so nobody falls or jumps out.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (half.x + WALL / 2.0)
		var name_side: String = "Left" if side < 0.0 else "Right"
		_box(self, name_side + "Railing", Vector3(x, 1.05, 0), Vector3(WALL, 0.1, INSIDE.z), Color(0.8, 0.65, 0.2), false)
		_box(self, name_side + "Kick", Vector3(x, 0.15, 0), Vector3(WALL, 0.3, INSIDE.z), steel, false)
		for z: float in [-half.z, 0.0, half.z]:
			_box(self, "%sPost%d" % [name_side, int(z)], Vector3(x, half.y / 2.0, z), Vector3(WALL, half.y, WALL), steel, false)
		var invisible := _box(self, name_side + "Wall", Vector3(x, half.y / 2.0, 0), Vector3(WALL, half.y, INSIDE.z), steel, true)
		(invisible.get_node("Mesh") as MeshInstance3D).visible = false
	# The gate: two sliding doors on the -z side.
	_left_door = _door("LeftDoor", -1.0)
	_right_door = _door("RightDoor", 1.0)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, half.y - 0.3, 0)
	light.omni_range = 8.0
	light.light_energy = 1.4
	add_child(light)
	_build_panel()
	_zone = ElevatorZone.new()
	_zone.name = "Zone"
	_zone.use_net(_net)
	var zone_shape := CollisionShape3D.new()
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(INSIDE.x - 0.2, INSIDE.y - 0.2, INSIDE.z - 0.2)
	zone_shape.shape = zone_box
	_zone.add_child(zone_shape)
	_zone.position = Vector3(0, INSIDE.y / 2.0, 0)
	add_child(_zone)
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	add_child(spawns)
	for index: int in 8:
		var spot := Marker3D.new()
		spot.name = "Spawn%d" % index
		spot.position = Vector3((float(index % 4) - 1.5) * 1.1, 0.1, (floorf(float(index) / 4.0) - 0.5) * 1.4 - 0.6)
		spawns.add_child(spot)
		_spawns.append(spot)
	_build_shaft()


func _door(door_name: String, side: float) -> AnimatableBody3D:
	var door := AnimatableBody3D.new()
	door.name = door_name
	door.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	door.collision_mask = 0
	door.position = Vector3(side * INSIDE.x * 0.75, (INSIDE.y - 0.4) / 2.0, -INSIDE.z / 2.0 - WALL / 2.0)
	var size := Vector3(INSIDE.x / 2.0, INSIDE.y - 0.4, 0.12)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.68, 0.7, 0.74)
	material.metallic = 0.5
	box_mesh.material = material
	mesh.mesh = box_mesh
	door.add_child(mesh)
	add_child(door)
	return door


## The back wall: the status sign, a slot for every kind of lift part, Go and Start anyway.
func _build_panel() -> void:
	var wall_z: float = INSIDE.z / 2.0 - 0.05
	_panel_label = Label3D.new()
	_panel_label.name = "PanelLabel"
	_panel_label.position = Vector3(0, 2.75, wall_z)
	_panel_label.rotation.y = PI
	_panel_label.font_size = 48
	_panel_label.pixel_size = 0.005
	_panel_label.outline_size = 8
	_panel_label.width = 900.0
	_panel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_panel_label)
	var index: int = 0
	for slot: StringName in _slot_parts.keys():
		var column: int = index % SLOT_COLUMNS
		var row: int = floori(float(index) / float(SLOT_COLUMNS))
		var center := Vector3(SLOT_ORIGIN.x + float(column) * SLOT_SIZE.x, SLOT_ORIGIN.y + float(row) * SLOT_SIZE.y, wall_z)
		_build_slot(slot, _slot_parts[slot], center)
		index += 1
	# Go button.
	var go := _box(self, "GoButton", Vector3(1.75, 1.25, wall_z - 0.1), Vector3(0.5, 0.5, 0.2), Color(0.2, 0.75, 0.3), false)
	go.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	_go_use = Interactable.new()
	_go_use.name = "Use"
	_go_use.max_distance = 3.0
	_go_use.used.connect(_on_go_used)
	go.add_child(_go_use)
	# Start anyway (Break Room, after the AFK timer, host only).
	_force_body = _box(self, "ForceButton", Vector3(1.75, 0.6, wall_z - 0.1), Vector3(0.4, 0.4, 0.2), Color(0.85, 0.2, 0.2), false)
	_force_body.collision_layer = 0
	_force_body.visible = false
	_force_use = Interactable.new()
	_force_use.name = "Use"
	_force_use.prompt_text = PROMPT_START_ANYWAY
	_force_use.max_distance = 3.0
	_force_use.used.connect(_on_force_used)
	_force_body.add_child(_force_use)


## One slot: a frame with the part's name, an area that takes the part, the installed part, and sparks.
func _build_slot(slot: StringName, part: PropData, center: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "Slot_%s" % slot
	holder.position = center
	add_child(holder)
	_box(holder, "Frame", Vector3(0, 0, -0.03), Vector3(SLOT_SIZE.x - 0.08, SLOT_SIZE.y - 0.08, 0.06), Color(0.15, 0.16, 0.18), false)
	var label := Label3D.new()
	label.name = "Label"
	label.text = part.display_name.to_upper()
	label.position = Vector3(0, SLOT_SIZE.y / 2.0 - 0.1, -0.08)
	label.rotation.y = PI
	label.pixel_size = 0.0025
	label.font_size = 40
	label.outline_size = 6
	holder.add_child(label)
	# The part, shown in the slot when it's working (its own mesh, shrunk to fit).
	var installed := Node3D.new()
	installed.name = "Installed"
	installed.position = Vector3(0, -0.05, -0.15)
	holder.add_child(installed)
	if part.scene != null:
		var sample: Node = part.scene.instantiate()
		var mesh := sample.get_node_or_null(^"Mesh") as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var copy := MeshInstance3D.new()
			copy.mesh = mesh.mesh
			var size: float = mesh.mesh.get_aabb().get_longest_axis_size()
			copy.scale = Vector3.ONE * minf(1.0, 0.4 / maxf(size, 0.01))
			installed.add_child(copy)
		sample.free()
	# Where the part goes in: an area sticking out of the wall.
	var area := Area3D.new()
	area.name = "Socket"
	area.collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	area.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS)
	area.monitorable = false
	area.position = Vector3(0, 0, -0.45)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SLOT_SIZE.x - 0.1, SLOT_SIZE.y, 0.9)
	shape.shape = box
	area.add_child(shape)
	area.body_entered.connect(_on_slot_body_entered.bind(slot))
	holder.add_child(area)
	# Sparks and a flickering light while it's broken.
	var sparks := CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.emitting = false
	sparks.amount = 24
	sparks.lifetime = 0.45
	sparks.explosiveness = 0.6
	sparks.direction = Vector3(0, 0.3, -1)
	sparks.spread = 60.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 3.5
	sparks.gravity = Vector3(0, -9.8, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.03, 0.03, 0.03)
	var spark_material := StandardMaterial3D.new()
	spark_material.albedo_color = Color(1.0, 0.85, 0.4)
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.7, 0.2)
	spark_material.emission_energy_multiplier = 4.0
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material = spark_material
	sparks.mesh = spark_mesh
	sparks.position = Vector3(0, 0, -0.1)
	holder.add_child(sparks)
	var flicker := OmniLight3D.new()
	flicker.name = "Flicker"
	flicker.light_color = Color(1.0, 0.75, 0.35)
	flicker.omni_range = 1.8
	flicker.position = Vector3(0, 0, -0.3)
	flicker.visible = false
	holder.add_child(flicker)
	_slot_nodes[slot] = {"sparks": sparks, "light": flicker, "installed": installed, "label": label}


## The shaft walls and light beams shown around the lift while it rides (no collision).
func _build_shaft() -> void:
	_shaft = Node3D.new()
	_shaft.name = "Shaft"
	_shaft.visible = false
	add_child(_shaft)
	var outer := Vector3(INSIDE.x / 2.0 + WALL + SHAFT_GAP, 0, INSIDE.z / 2.0 + WALL + SHAFT_GAP)
	var wall_color := Color(0.16, 0.17, 0.19)
	_box(_shaft, "ShaftNorth", Vector3(0, 0, -outer.z), Vector3(outer.x * 2, SHAFT_HEIGHT, 0.2), wall_color, false)
	_box(_shaft, "ShaftSouth", Vector3(0, 0, outer.z), Vector3(outer.x * 2, SHAFT_HEIGHT, 0.2), wall_color, false)
	_box(_shaft, "ShaftWest", Vector3(-outer.x, 0, 0), Vector3(0.2, SHAFT_HEIGHT, outer.z * 2), wall_color, false)
	_box(_shaft, "ShaftEast", Vector3(outer.x, 0, 0), Vector3(0.2, SHAFT_HEIGHT, outer.z * 2), wall_color, false)
	var beam_material := StandardMaterial3D.new()
	beam_material.albedo_color = Color(1.0, 0.8, 0.45)
	beam_material.emission_enabled = true
	beam_material.emission = Color(1.0, 0.7, 0.3)
	beam_material.emission_energy_multiplier = 2.0
	var count: int = int(SHAFT_HEIGHT / BEAM_SPACING)
	for index: int in count:
		var ring := Node3D.new()
		ring.name = "Beam%d" % index
		_shaft.add_child(ring)
		for side: int in 4:
			var mesh := MeshInstance3D.new()
			var strip := BoxMesh.new()
			var along_x: bool = side < 2
			strip.size = Vector3(outer.x * 2, 0.12, 0.1) if along_x else Vector3(0.1, 0.12, outer.z * 2)
			strip.material = beam_material
			mesh.mesh = strip
			var facing: float = -1.0 if side % 2 == 0 else 1.0
			mesh.position = Vector3(0, 0, facing * (outer.z - 0.12)) if along_x else Vector3(facing * (outer.x - 0.12), 0, 0)
			ring.add_child(mesh)
		_beams.append(ring)


func _box(parent: Node3D, box_name: String, center: Vector3, size: Vector3, color: Color, solid: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = center
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD) if solid else 0
	body.collision_mask = 0
	if solid or box_name.ends_with("Button"):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	parent.add_child(body)
	return body
