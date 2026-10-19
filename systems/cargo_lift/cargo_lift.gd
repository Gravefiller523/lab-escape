class_name CargoLift
extends Node3D
## The cargo lift: the elevator that carries the team up through the facility (scene:
## systems/cargo_lift/cargo_lift.tscn). It stays loaded for the whole run; game_flow loads the Break
## Room and the floors around it, so everything inside it (players, crates, items, carts) rides along.
##
## How a floor goes: the lift arrives broken. Players find the lift part (cargo_lift spawns it at the
## floor's lift_part marker farthest from the lift), slot it into the socket on the back wall, then
## everyone gets in and someone presses Go. It refuses with the missing names until all are inside.
## In the Break Room it isn't broken: Go starts the run, and after afk_force_start_after seconds the
## host gets "Start anyway". On a boss floor, beating the boss fixes it.
##
## The host decides everything (parts, Go, doors) and tells the other PCs. While it rides, the lift
## stays still and the shaft walls slide down past it, so it looks like it is going up.
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

const PROMPT_GO: String = "Go up"
const PROMPT_START: String = "Start the run"
const PROMPT_START_ANYWAY: String = "Start anyway (players outside are brought in)"
const MSG_BROKEN: String = "The lift is broken. Slot the lift part into the socket first (%d/%d)."
const MSG_WAITING: String = "Everyone into the lift first. Waiting for: %s"
const MSG_BOSS: String = "The lift won't move until the boss is beaten."

var _net: NetService
var _config: GameConfig
## Synced state (the host's is the truth).
var _parts_needed: int = 0
var _parts_delivered: int = 0
var _in_break_room: bool = true
var _waiting_for_boss: bool = false
var _doors_open: bool = true
var _riding: bool = false
## Host: when someone first stood in the lift in the Break Room (msec), or -1.
var _occupied_since_msec: int = -1
## Ride visuals (every PC).
var _ride_speed: float = 0.0
var _ride_target_speed: float = 0.0
var _ride_offset: float = 0.0

var _zone: ElevatorZone
var _left_door: AnimatableBody3D
var _right_door: AnimatableBody3D
var _go_use: Interactable
var _force_body: StaticBody3D
var _force_use: Interactable
var _socket: Area3D
var _panel_label: Label3D
var _shaft: Node3D
var _beams: Array[Node3D] = []
var _spawns: Array[Node3D] = []


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
	_build()
	_zone.occupants_changed.connect(_on_occupants_changed)
	EventBus.player_joined.connect(_on_player_joined)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.floor_ready.connect(_on_floor_ready)
	_refresh_panel()


# --- Public API -------------------------------------------------------------------------------

func get_zone() -> ElevatorZone:
	return _zone


func get_parts_needed() -> int:
	return _parts_needed


func get_parts_delivered() -> int:
	return _parts_delivered


## Fixed (or never broken), doors open and not riding: Go works once everyone is inside.
func is_ready() -> bool:
	return not is_broken() and not _riding and not _waiting_for_boss


func is_broken() -> bool:
	return _parts_delivered < _parts_needed


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
		return MSG_BROKEN % [_parts_delivered, _parts_needed]
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


## Host (game_flow): the lift has arrived somewhere. parts_needed 0 = it works (the Break Room);
## waiting_for_boss = it works once the boss is beaten. Opens the doors on every PC.
func arrive(parts_needed: int, in_break_room: bool, waiting_for_boss: bool = false) -> void:
	if not multiplayer.is_server():
		return
	_occupied_since_msec = -1
	_state_rpc.rpc(parts_needed, 0, in_break_room, waiting_for_boss, true, false)


## Host (game_flow): close the doors and ride (e.g. back to the Break Room after a run).
func depart_now() -> void:
	if multiplayer.is_server() and not _riding:
		_state_rpc.rpc(_parts_needed, _parts_delivered, _in_break_room, false, false, true)


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

func _try_depart(player_id: int) -> void:
	if not multiplayer.is_server() or _riding:
		return
	var blocker: String = depart_blocker()
	if blocker.is_empty():
		_depart()
		return
	_tell(player_id, blocker)


func _depart() -> void:
	_state_rpc.rpc(_parts_needed, _parts_delivered, _in_break_room, false, false, true)
	_departed_rpc.rpc()


func _on_force_used(player_id: int) -> void:
	if not can_force_start() or player_id != _net.local_player_id():
		return
	gather_players()
	_depart()


func _on_go_used(player_id: int) -> void:
	_try_depart(player_id)


## Host: a lift part touched the socket: install it.
func _on_socket_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var prop := body as NetProp
	if prop == null or prop.data == null or not prop.data.tags.has(LIFT_PART_TAG):
		return
	if not is_broken() or _riding:
		return
	var spawner: PropSpawner = prop.get_spawner()
	if spawner == null:
		return
	spawner.despawn(prop)
	_state_rpc.rpc(_parts_needed, _parts_delivered + 1, _in_break_room, _waiting_for_boss, _doors_open, _riding)
	_part_delivered_rpc.rpc(_parts_delivered + 1, _parts_needed)


func _on_boss_defeated(_boss_id: StringName) -> void:
	if multiplayer.is_server() and _waiting_for_boss:
		_state_rpc.rpc(_parts_needed, _parts_delivered, _in_break_room, false, _doors_open, _riding)


## Host: the floor is ready: the parts that "broke" are somewhere on it, as far from the lift as possible.
func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	if not is_inside_tree() or not multiplayer.is_server() or _parts_needed <= 0:
		return
	var department: DepartmentData = GameFlow.get_current_department()
	var spots: Array[RoomMarker] = Level.get_markers(&"lift_part")
	if department == null or spots.is_empty():
		return
	if department.lift_part_prop_id == &"":
		push_warning("CargoLift: department '%s' has no lift_part_prop_id." % department.id)
		return
	# Farthest first; a stable sort keeps the marker order for ties, so every run is the same.
	var order: Array[RoomMarker] = spots.duplicate()
	order.sort_custom(func(a: RoomMarker, b: RoomMarker) -> bool:
		return a.global_position.distance_to(global_position) > b.global_position.distance_to(global_position))
	for index: int in _parts_needed:
		Props.spawn_prop(department.lift_part_prop_id, order[index % order.size()].global_transform)


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
		_state_rpc.rpc_id(peer_id, _parts_needed, _parts_delivered, _in_break_room, _waiting_for_boss,
			_doors_open, _riding)


func _tell(player_id: int, text: String) -> void:
	var peer_id: int = _net.get_peer_id(player_id)
	if peer_id != 0:
		_note_rpc.rpc_id(peer_id, text)


# --- RPCs -----------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _request_depart_rpc() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var player_id: int = _net.get_player_id_for_peer(multiplayer.get_remote_sender_id())
	if player_id != 0:
		_try_depart(player_id)


## Host -> everyone: the lift's state.
@rpc("authority", "call_local", "reliable")
func _state_rpc(parts_needed: int, parts_delivered: int, in_break_room: bool, waiting_for_boss: bool,
		doors_open: bool, riding: bool) -> void:
	if not is_inside_tree():
		return
	var parts_before: int = _parts_delivered
	var was_riding: bool = _riding
	_parts_needed = parts_needed
	_parts_delivered = parts_delivered
	_in_break_room = in_break_room
	_waiting_for_boss = waiting_for_boss
	_doors_open = doors_open
	_riding = riding
	if riding and not was_riding:
		_start_ride_visuals()
	elif was_riding and not riding:
		_stop_ride_visuals()
	if parts_before != parts_delivered or not riding:
		parts_changed.emit(_parts_delivered, _parts_needed)
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


@rpc("authority", "call_local", "reliable")
func _note_rpc(text: String) -> void:
	if not is_inside_tree():
		return
	EventBus.toast_requested.emit(text)


# --- Every PC: doors, panel, ride ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var open_x: float = INSIDE.x * 0.75
	var closed_x: float = INSIDE.x * 0.25
	_left_door.position.x = move_toward(_left_door.position.x, -(open_x if _doors_open else closed_x), DOOR_SPEED * delta)
	_right_door.position.x = move_toward(_right_door.position.x, open_x if _doors_open else closed_x, DOOR_SPEED * delta)


func _process(delta: float) -> void:
	var can_force: bool = can_force_start()
	if _force_body.visible != can_force:
		_force_body.visible = can_force
		_force_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES) if can_force else 0
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
	if _riding:
		_panel_label.text = "Going up..."
	elif _waiting_for_boss:
		_panel_label.text = "Beat the boss"
	elif is_broken():
		_panel_label.text = "BROKEN\nLift part %d/%d" % [_parts_delivered, _parts_needed]
	else:
		_panel_label.text = "Ready"
	_panel_label.modulate = Color(1, 0.35, 0.3) if is_broken() or _waiting_for_boss else Color(0.4, 1, 0.5)
	_go_use.prompt_text = PROMPT_START if _in_break_room else PROMPT_GO


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
		spot.position = Vector3((float(index % 4) - 1.5) * 1.1, 0.1, (floorf(float(index) / 4.0) - 0.5) * 1.4)
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


## The control panel on the back wall: the part socket, the status light and Go.
func _build_panel() -> void:
	var wall_z: float = INSIDE.z / 2.0 - 0.05
	_panel_label = Label3D.new()
	_panel_label.name = "PanelLabel"
	_panel_label.position = Vector3(0, 2.4, wall_z)
	_panel_label.rotation.y = PI
	_panel_label.font_size = 64
	_panel_label.pixel_size = 0.005
	_panel_label.outline_size = 8
	add_child(_panel_label)
	# Go button.
	var go := _box(self, "GoButton", Vector3(1.3, 1.25, wall_z - 0.1), Vector3(0.5, 0.5, 0.2), Color(0.2, 0.75, 0.3), false)
	go.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	_go_use = Interactable.new()
	_go_use.name = "Use"
	_go_use.max_distance = 3.0
	_go_use.used.connect(_on_go_used)
	go.add_child(_go_use)
	# Start anyway (Break Room, after the AFK timer, host only).
	_force_body = _box(self, "ForceButton", Vector3(2.0, 1.25, wall_z - 0.1), Vector3(0.4, 0.4, 0.2), Color(0.85, 0.2, 0.2), false)
	_force_body.collision_layer = 0
	_force_body.visible = false
	_force_use = Interactable.new()
	_force_use.name = "Use"
	_force_use.prompt_text = PROMPT_START_ANYWAY
	_force_use.max_distance = 3.0
	_force_use.used.connect(_on_force_used)
	_force_body.add_child(_force_use)
	# The part socket: a frame you drop the part into.
	_box(self, "SocketFrame", Vector3(-1.3, 0.55, wall_z - 0.25), Vector3(0.9, 0.1, 0.6), Color(0.85, 0.7, 0.2), true)
	_socket = Area3D.new()
	_socket.name = "PartSocket"
	_socket.collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	_socket.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS)
	_socket.monitorable = false
	_socket.position = Vector3(-1.3, 1.0, wall_z - 0.35)
	var socket_shape := CollisionShape3D.new()
	var socket_box := BoxShape3D.new()
	socket_box.size = Vector3(1.0, 0.8, 0.8)
	socket_shape.shape = socket_box
	_socket.add_child(socket_shape)
	_socket.body_entered.connect(_on_socket_body_entered)
	add_child(_socket)
	var socket_label := Label3D.new()
	socket_label.name = "SocketLabel"
	socket_label.text = "LIFT PART"
	socket_label.position = Vector3(-1.3, 1.6, wall_z)
	socket_label.rotation.y = PI
	socket_label.pixel_size = 0.004
	add_child(socket_label)


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
