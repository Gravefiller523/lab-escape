class_name EnemiesService
extends Node
## Autoload "Enemies". Spawns each floor's enemies (host, on floor_ready), bakes the navigation mesh
## enemies walk on, and removes them between floors. Console: `spawn enemy_<name>`, `killall`.
## Spec: docs/systems/enemies.md.
##
## The spawner spends RunDifficulty.enemy_budget(floor, players) on the department's enemy_spawns
## (weights, min_floor, spawn_cost) at enemy_spawn markers, never in the lift room.
## STUB (department content): a department with no enemy_spawns uses every enemy (weight 1).

const NAV_REGION_NAME: String = "EnemyNavigation"
const NAV_AGENT_RADIUS: float = 0.5
const NAV_AGENT_HEIGHT: float = 1.0
## Room kind where every floor starts: no enemies there.
const START_ROOM_KIND: StringName = &"lift"

var _spawner: EnemySpawner
var _nav_region: NavigationRegion3D


func _ready() -> void:
	_spawner = EnemySpawner.new()
	_spawner.name = "Spawner"
	add_child(_spawner)
	EventBus.floor_ready.connect(_on_floor_ready)
	EventBus.floor_loading.connect(func(_floor_number: int, _department_id: StringName) -> void: _clear_floor())
	EventBus.run_ended.connect(func(_result: StringName) -> void: _clear_floor())
	DebugConsole.register_spawner(&"enemy", _console_spawn)
	DebugConsole.register_command(&"killall", _cmd_killall, "killall: kill every enemy")


## Host: spawn an enemy for everyone (health scaled for the number of players).
func spawn(enemy_id: StringName, xform: Transform3D) -> Enemy:
	return _spawner.spawn(enemy_id, xform, RunDifficulty.enemy_health_multiplier(Net.get_player_count()), _run_seed())


func get_alive() -> Array[Enemy]:
	return _spawner.get_alive()


## Host: remove every enemy.
func despawn_all() -> void:
	_spawner.despawn_all()


## NEW: the spawner node (tests).
func get_spawner() -> EnemySpawner:
	return _spawner


## Which enemies a floor gets: spend `budget` on weighted picks from `pool` that are allowed on this
## floor (min_floor) and affordable (spawn_cost). Same rng = same list.
static func plan_spawns(pool: Array[WeightedIdData], floor_in_department: int, budget: int,
		rng: RandomNumberGenerator) -> Array[StringName]:
	var picked: Array[StringName] = []
	var left: int = budget
	while left > 0:
		var ids: Array[StringName] = []
		var weights: PackedFloat32Array = []
		for entry: WeightedIdData in pool:
			var data := ContentRegistry.get_content(entry.content_id) as EnemyData
			if data == null or not data.enabled or data.min_floor > floor_in_department or data.spawn_cost > left \
					or data.spawn_cost <= 0:
				continue
			ids.append(entry.content_id)
			weights.append(entry.weight)
		var index: int = SeededRng.pick_weighted(rng, weights)
		if index < 0:
			break
		picked.append(ids[index])
		left -= (ContentRegistry.get_content(ids[index]) as EnemyData).spawn_cost
	return picked


## The department's enemy pool. STUB: none listed -> every enemy, weight 1.
static func pool_for(department: DepartmentData) -> Array[WeightedIdData]:
	if department != null and not department.enemy_spawns.is_empty():
		return department.enemy_spawns
	var pool: Array[WeightedIdData] = []
	for id: StringName in ContentRegistry.get_all_ids(&"enemy"):
		var entry := WeightedIdData.new()
		entry.content_id = id
		pool.append(entry)
	return pool


## Host: a navigation mesh for everything solid under `root` (rooms, arenas), so enemies path through
## doorways. Replaces the last one. Baked at runtime, so room scenes need no navigation region.
func bake_navigation(root: Node3D) -> NavigationRegion3D:
	_clear_navigation()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD)
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	mesh.agent_radius = NAV_AGENT_RADIUS
	mesh.agent_height = NAV_AGENT_HEIGHT
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = NAV_REGION_NAME
	_nav_region.navigation_mesh = mesh
	root.add_child(_nav_region)
	_nav_region.top_level = true
	_nav_region.global_transform = Transform3D.IDENTITY
	return _nav_region


## Host: spawn a floor's enemies at its enemy_spawn markers (not in the lift room). Returns them.
func spawn_floor(floor_in_department: int, department: DepartmentData, run_seed: int,
		markers: Array[RoomMarker]) -> Array[Enemy]:
	var spawned: Array[Enemy] = []
	var spots: Array[RoomMarker] = []
	for marker: RoomMarker in markers:
		var room: RoomData = Level.get_room_for_position(marker.global_position)
		if room == null or room.room_kind != START_ROOM_KIND:
			spots.append(marker)
	if spots.is_empty():
		return spawned
	var rng: RandomNumberGenerator = SeededRng.make(run_seed, &"enemy_spawns", floor_in_department)
	var budget: int = RunDifficulty.enemy_budget(floor_in_department, Net.get_player_count())
	var plan: Array[StringName] = plan_spawns(pool_for(department), floor_in_department, budget, rng)
	for index: int in plan.size():
		var marker: RoomMarker = spots[rng.randi_range(0, spots.size() - 1)]
		var spread := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		var enemy: Enemy = spawn(plan[index], Transform3D(Basis.IDENTITY, marker.global_position + spread))
		if enemy != null:
			spawned.append(enemy)
	return spawned


func _on_floor_ready(floor_number: int, _department_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var run: RunState = GameFlow.get_run()
	if run != null and run.is_boss_floor:
		return
	var rooms: Array[Node3D] = Level.get_room_nodes()
	if rooms.is_empty():
		return
	var root := rooms[0].get_parent() as Node3D
	if root != null:
		bake_navigation(root)
	var floor_in_department: int = run.floor_in_department if run != null else floor_number
	spawn_floor(floor_in_department, GameFlow.get_current_department(), _run_seed(), Level.get_markers(&"enemy_spawn"))


func _clear_floor() -> void:
	despawn_all()
	_clear_navigation()


func _clear_navigation() -> void:
	if _nav_region != null and is_instance_valid(_nav_region):
		_nav_region.queue_free()
	_nav_region = null


func _run_seed() -> int:
	var run: RunState = GameFlow.get_run()
	return run.run_seed if run != null else 0


func _console_spawn(id: StringName, at: Transform3D, count: int, _player_id: int) -> String:
	var spawned: int = 0
	for index: int in count:
		if spawn(id, at.translated(Vector3(float(index) * 0.8, 0.0, 0.0))) != null:
			spawned += 1
	return "Spawned %d x %s." % [spawned, id]


func _cmd_killall(_args: PackedStringArray, _player_id: int) -> String:
	var count: int = 0
	for enemy: Enemy in get_alive():
		var info := DamageInfo.make(99999.0, &"debug")
		enemy.get_health().apply_damage(info)
		count += 1
	return "Killed %d enemies." % count
