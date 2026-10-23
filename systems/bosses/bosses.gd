class_name BossesService
extends Node
## Autoload "Bosses". On a boss floor it turns the arena room into a BossArena (every PC) and the host
## spawns the department's boss at the boss_spawn marker, with health scaled for the number of players.
## Console: `spawn boss_<name>`. Spec: docs/systems/bosses.md.
## STUB (department content): a department with no boss_id uses the first boss there is.


func _ready() -> void:
	EventBus.boss_floor_started.connect(_on_boss_floor_started)
	EventBus.floor_ready.connect(_on_floor_ready)
	DebugConsole.register_spawner(&"boss", _console_spawn)


## Host: spawn a boss for everyone (health x RunDifficulty.boss_health_multiplier).
func spawn(boss_id: StringName, xform: Transform3D) -> Boss:
	var run: RunState = GameFlow.get_run()
	return Enemies.get_spawner().spawn(boss_id, xform, RunDifficulty.boss_health_multiplier(Net.get_player_count()),
		run.run_seed if run != null else 0) as Boss


## The boss a department fights (its boss_id; STUB: the first boss when it has none).
static func boss_for(department: DepartmentData) -> StringName:
	if department != null and department.boss_id != &"" and ContentRegistry.get_content(department.boss_id) is BossData:
		return department.boss_id
	var ids: Array[StringName] = ContentRegistry.get_all_ids(&"boss")
	return ids[0] if not ids.is_empty() else &""


## Every PC: make the arena (if this floor has one and it isn't there yet). Returns it, or null.
func make_arena() -> BossArena:
	var markers: Array[RoomMarker] = Level.get_markers(&"boss_spawn")
	if markers.is_empty():
		return null
	var room := markers[0].get_parent() as Node3D
	if room == null:
		return null
	var existing := room.get_node_or_null(NodePath(BossArena.NODE_NAME)) as BossArena
	if existing != null:
		return existing
	var room_data: RoomData = Level.get_room_for_position(markers[0].global_position)
	var cells := Vector2(2, 2)
	if room_data != null:
		cells = Vector2(room_data.size_cells.x, room_data.size_cells.z)
	var arena := BossArena.new()
	arena.setup(room, cells * Config.game.room_cell_size)
	room.add_child(arena)
	return arena


func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	# Joiners arriving on a boss floor get floor_ready too: they need the arena node.
	var run: RunState = GameFlow.get_run()
	if run != null and run.is_boss_floor:
		make_arena()


func _on_boss_floor_started(boss_id: StringName) -> void:
	make_arena()
	if not multiplayer.is_server():
		return
	var markers: Array[RoomMarker] = Level.get_markers(&"boss_spawn")
	if markers.is_empty():
		# No arena on this floor (game_flow's tests build floors without rooms): nothing to spawn.
		return
	var id: StringName = boss_id if ContentRegistry.get_content(boss_id) is BossData \
		else boss_for(GameFlow.get_current_department())
	if id == &"":
		push_error("Bosses: there is no boss content.")
		return
	spawn(id, markers[0].global_transform)


func _console_spawn(id: StringName, at: Transform3D, _count: int, _player_id: int) -> String:
	var boss: Boss = spawn(id, at)
	return "Spawned %s." % id if boss != null else "Couldn't spawn %s." % id
