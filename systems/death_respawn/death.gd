class_name DeathService
extends Node
## Autoload "Death": what happens when a player dies and how they come back. Spec: docs/systems/death_respawn.md.
## - Dying (health reaches 0): everything you carry drops where you died (inventory items as pickups,
##   any prop you hold is let go), and you become a ghost: your body is hidden and doesn't move, and your
##   camera follows a living teammate (left / right click to switch). You can still talk.
## - Teammates bring meat to a 3D printer (Printer3D, placed at `printer` markers) to reprint you: you come
##   out with full health and your mutations, but not your items.
## - Solo: you get Config.game.solo_free_reprints_per_floor free reprints per floor (at the nearest printer,
##   or where you died). After that, dying ends the run.
## - Everyone dead at once: team_wiped (game_flow ends the run).
## The host decides; every PC hears about deaths through HealthComponent.died / revived.
## Console: `kill`, `meat <count>`.

const PRINTER_SCENE: PackedScene = preload("res://systems/death_respawn/printer_3d.tscn")
const DROP_SPREAD: float = 0.8
const GHOST_DISTANCE: float = 3.0
const GHOST_HEIGHT: float = 1.5
const MSG_DEAD: String = "You died. A teammate can reprint you: meat in a 3D printer."
const MSG_SOLO: String = "You died. Free reprint in %d s (%d left this floor)."

var _dead_order: Array[int] = []
var _died_msec: Dictionary[int, int] = {}
var _reprints_this_floor: int = 0
var _solo_free_left: int = 0
var _wiped: bool = false
var _ghost_camera: Camera3D
var _watch_index: int = 0


func _ready() -> void:
	_solo_free_left = Config.game.solo_free_reprints_per_floor
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.floor_ready.connect(func(_floor_number: int, _department_id: StringName) -> void:
		_new_floor()
		place_printers())
	EventBus.run_started.connect(func(_run_seed: int) -> void:
		# A new run: everyone starts alive.
		_wiped = false
		_dead_order.clear()
		_died_msec.clear()
		_new_floor())
	EventBus.player_left.connect(_on_player_left)
	EventBus.run_ended.connect(func(_result: StringName) -> void: _revive_everyone())
	DebugConsole.register_command(&"kill", _cmd_kill, "kill: die (to test reprinting)")
	DebugConsole.register_command(&"meat", _cmd_meat, "meat <count>: drop meat in front of you (default 1)")


func is_dead(player_id: int) -> bool:
	return _dead_order.has(player_id)


## Dead players, the one dead longest first.
func get_dead_players() -> Array[int]:
	return _dead_order.duplicate()


## Meat the next reprint costs on this floor (meat_per_reprint + growth per reprint already done).
func get_reprint_cost() -> int:
	return Config.game.meat_per_reprint + Config.game.meat_cost_growth_per_reprint * _reprints_this_floor


func get_free_reprints_left() -> int:
	return _solo_free_left


## Host: the dead player who would come out of a printer now (dead longest, waited reprint_min_wait), or 0.
func next_to_reprint() -> int:
	var now: int = Time.get_ticks_msec()
	for player_id: int in _dead_order:
		if now - _died_msec.get(player_id, 0) >= int(Config.game.reprint_min_wait * 1000.0):
			return player_id
	return 0


## The player dead longest (even if it's too soon to reprint them), or 0.
func longest_dead() -> int:
	return _dead_order[0] if not _dead_order.is_empty() else 0


## Host: kill a player (cheats, kill zones).
func kill(player_id: int, info: DamageInfo = null) -> void:
	if not multiplayer.is_server():
		return
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var health: HealthComponent = HealthComponent.of(body) if body != null else null
	if health == null or health.is_dead():
		return
	health.invulnerable = false
	var hit: DamageInfo = info if info != null else DamageInfo.make(health.get_current() * 100.0 + 1000.0, &"debug")
	health.apply_damage(hit)


## Host: bring a dead player back at this spot with full health (upgrades stay; items were dropped).
func reprint(player_id: int, xform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var health: HealthComponent = HealthComponent.of(body) if body != null else null
	if health == null or not health.is_dead():
		return
	body.teleport(xform)
	health.revive(1.0)
	_reprints_this_floor += 1
	_count_rpc.rpc(_reprints_this_floor, _solo_free_left)


## Every PC: a printer at each `printer` marker of the level (child "Printer" of the marker). Returns them.
func place_printers() -> Array[Printer3D]:
	var placed: Array[Printer3D] = []
	for marker: RoomMarker in Level.get_markers(&"printer"):
		var printer := marker.get_node_or_null(^"Printer") as Printer3D
		if printer == null:
			printer = PRINTER_SCENE.instantiate() as Printer3D
			printer.name = "Printer"
			marker.add_child(printer)
		placed.append(printer)
	return placed


## Host: a short message to one player (a toast on their PC).
func tell(player_id: int, text: String) -> void:
	var peer: int = Net.get_peer_id(player_id)
	if peer == 0 or peer == multiplayer.get_unique_id():
		EventBus.toast_requested.emit(text)
	else:
		_tell_rpc.rpc_id(peer, text)


# --- Dying and coming back ---------------------------------------------------------------------------

func _on_player_spawned(_player_id: int, player_node: Node3D) -> void:
	var body := player_node as PlayerCharacter
	var health: HealthComponent = HealthComponent.of(body) if body != null else null
	if health == null:
		return
	if not health.died.is_connected(_on_died):
		health.died.connect(_on_died.bind(body))
		health.revived.connect(_on_revived.bind(body))


## Every PC (HealthComponent.died fires everywhere).
func _on_died(_info: DamageInfo, body: PlayerCharacter) -> void:
	if not is_instance_valid(body):
		return
	var player_id: int = body.player_id
	if not _dead_order.has(player_id):
		_dead_order.append(player_id)
	_died_msec[player_id] = Time.get_ticks_msec()
	body.set_ghost(true)
	EventBus.player_died.emit(player_id, body.global_position)
	if body.is_local():
		_start_ghost_camera()
	if not multiplayer.is_server():
		return
	Net.update_record(player_id, &"is_alive", false)
	_drop_everything(body)
	_after_death(player_id, body.global_position)


## Every PC (HealthComponent.revived fires everywhere).
func _on_revived(body: PlayerCharacter) -> void:
	if not is_instance_valid(body):
		return
	var player_id: int = body.player_id
	_dead_order.erase(player_id)
	_died_msec.erase(player_id)
	body.set_ghost(false)
	if body.is_local():
		_stop_ghost_camera()
	EventBus.player_reprinted.emit(player_id)
	if multiplayer.is_server():
		Net.update_record(player_id, &"is_alive", true)


## Host: solo free reprint, or a team wipe.
func _after_death(player_id: int, where: Vector3) -> void:
	if _wiped or _living_count() > 0:
		if not _wiped:
			tell(player_id, MSG_DEAD)
		return
	if Net.get_player_count() <= 1 and _solo_free_left > 0:
		_solo_free_left -= 1
		_count_rpc.rpc(_reprints_this_floor, _solo_free_left)
		tell(player_id, MSG_SOLO % [ceili(Config.game.reprint_min_wait), _solo_free_left])
		var spot: Transform3D = _nearest_printer_spot(where)
		get_tree().create_timer(Config.game.reprint_min_wait).timeout.connect(func() -> void: reprint(player_id, spot))
		return
	_wiped_rpc.rpc()


func _living_count() -> int:
	var living: int = 0
	for player_id: int in Net.get_player_ids():
		if Net.is_waiting_for_next_floor(player_id):
			continue
		var body: PlayerCharacter = PlayerCharacter.find(player_id)
		var health: HealthComponent = HealthComponent.of(body) if body != null else null
		if health != null and not health.is_dead():
			living += 1
	return living


func _nearest_printer_spot(where: Vector3) -> Transform3D:
	var best: Printer3D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(Printer3D.GROUP):
		var printer := node as Printer3D
		if printer == null or not printer.is_inside_tree():
			continue
		var distance: float = printer.global_position.distance_to(where)
		if distance < best_distance:
			best_distance = distance
			best = printer
	return best.get_output_transform() if best != null else Transform3D(Basis.IDENTITY, where + Vector3.UP * 0.5)


## Host: everything the player carries drops where they died.
func _drop_everything(body: PlayerCharacter) -> void:
	var player_id: int = body.player_id
	for prop: NetProp in Props.get_props():
		if prop.get_holder_ids().has(player_id) and prop.get_spawner() != null:
			prop.get_spawner().release_all(prop)
	var inventory: InventoryComponent = InventoryComponent.of(body)
	if inventory == null or Props.get_spawner() == null:
		return
	var index: int = 0
	for slot: InventorySlot in inventory.take_all():
		for copy: int in slot.count:
			var angle: float = TAU * float(index) / 6.0
			var spot := body.global_position + Vector3(cos(angle) * DROP_SPREAD, 0.6, sin(angle) * DROP_SPREAD)
			Props.spawn_item(slot.item_id, Transform3D(Basis.IDENTITY, spot), slot.uses_left)
			index += 1


func _on_player_left(player_id: int) -> void:
	_dead_order.erase(player_id)
	_died_msec.erase(player_id)
	if not multiplayer.is_server():
		return
	# Their things stay behind for the team (if their body is still here).
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if body != null and not body.is_queued_for_deletion():
		_drop_everything(body)


## The run is over (back to the Break Room): nobody stays a ghost. Host revives; every PC drops its ghost camera.
func _revive_everyone() -> void:
	if _ghost_camera != null and _ghost_camera.current:
		_stop_ghost_camera()
	if not multiplayer.is_server():
		return
	for player_id: int in _dead_order.duplicate():
		var body: PlayerCharacter = PlayerCharacter.find(player_id)
		var health: HealthComponent = HealthComponent.of(body) if body != null else null
		if health != null and health.is_dead():
			health.revive(1.0)
	_dead_order.clear()
	_died_msec.clear()


func _new_floor() -> void:
	_reprints_this_floor = 0
	_solo_free_left = Config.game.solo_free_reprints_per_floor


# --- Ghost camera (your PC only) -------------------------------------------------------------------

func _start_ghost_camera() -> void:
	if _ghost_camera == null:
		_ghost_camera = Camera3D.new()
		_ghost_camera.name = "GhostCamera"
		# Moved in _process (follows a teammate), so no physics interpolation.
		_ghost_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_ghost_camera)
	_watch_index = 0
	_ghost_camera.make_current()


func _stop_ghost_camera() -> void:
	if _ghost_camera != null:
		_ghost_camera.clear_current(true)
	var me: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if me != null and me.get_camera() != null:
		me.get_camera().make_current()


func _living_others() -> Array[PlayerCharacter]:
	var others: Array[PlayerCharacter] = []
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		var health: HealthComponent = HealthComponent.of(body) if body != null else null
		if body != null and body.player_id != Net.local_player_id() and health != null and not health.is_dead():
			others.append(body)
	return others


func _process(_delta: float) -> void:
	if _ghost_camera == null or not _ghost_camera.current:
		return
	var others: Array[PlayerCharacter] = _living_others()
	var watched: Node3D = null
	if not others.is_empty():
		watched = others[posmod(_watch_index, others.size())]
	else:
		watched = PlayerCharacter.find(Net.local_player_id())
	if watched == null:
		return
	var behind: Vector3 = watched.global_basis.z * GHOST_DISTANCE + Vector3.UP * GHOST_HEIGHT
	_ghost_camera.global_position = watched.global_position + behind
	_ghost_camera.look_at(watched.global_position + Vector3.UP * 1.2, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if _ghost_camera == null or not _ghost_camera.current:
		return
	if event.is_action_pressed(InputActions.PRIMARY):
		_watch_index += 1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.SECONDARY):
		_watch_index -= 1
		get_viewport().set_input_as_handled()


# --- Network -------------------------------------------------------------------------------------------

## Host -> everyone: the team is wiped (once per run).
@rpc("authority", "call_local", "reliable")
func _wiped_rpc() -> void:
	if _wiped:
		return
	_wiped = true
	EventBus.team_wiped.emit()


## Host -> everyone: reprint counts (for the printer screens).
@rpc("authority", "call_local", "reliable")
func _count_rpc(reprints: int, solo_left: int) -> void:
	_reprints_this_floor = reprints
	_solo_free_left = solo_left


@rpc("authority", "call_remote", "reliable")
func _tell_rpc(text: String) -> void:
	EventBus.toast_requested.emit(text)


# --- Console --------------------------------------------------------------------------------------------

func _cmd_kill(_args: PackedStringArray, player_id: int) -> String:
	kill(player_id)
	return "You died."


func _cmd_meat(args: PackedStringArray, player_id: int) -> String:
	var count: int = args[0].to_int() if args.size() > 0 and args[0].is_valid_int() else 1
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var forward: Vector3 = body.get_aim_direction() if body != null else Vector3.FORWARD
	forward.y = 0.0
	var at: Vector3 = (body.global_position if body != null else Vector3.ZERO) + forward.normalized() * 1.5 + Vector3.UP * 0.5
	for index: int in count:
		Props.spawn_prop(&"prop_meat", Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.3 * float(index)))
	return "Dropped %d meat." % count
