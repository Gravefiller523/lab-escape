class_name EnemiesService
extends Node
## Autoload "Enemies". Spawns each floor's enemies (host, on floor_ready), bakes the navigation mesh
## enemies walk on, and removes them between floors. Console: `spawn enemy_<name>`, `killall`.
## Spec: docs/systems/enemies.md.
##
## The spawner spends RunDifficulty.enemy_budget(floor, players) on the department's enemy_spawns
## (weights, min_floor, spawn_cost) at enemy_spawn markers, never in the lift room.
## STUB (department content): a department with no enemy_spawns uses every enemy (weight 1).
##
## NEW 2026-10-30 (HL2 feel step 3): the host passes noises (EventBus.noise_made) and who hurt an enemy
## (EventBus.damage_dealt) on to the enemies, and watches heavy thrown props so enemies can jump aside.
## The navigation mesh is baked on a background thread (no freeze when a floor loads).
##
## NEW 2026-10-30 (doors): bodies in NAV_SKIP_GROUP (doors enemies can open, or that stand open) are left out
## of the bake, so enemies path through those doorways. A door that changes (locked, unlocked, a gate
## opened) asks for request_navigation_update(), and the mesh is baked again in the background; the old one
## stays in use until the new one is ready.

## NEW 2026-10-30: the navigation mesh for the floor is ready (baking happens in the background).
signal navigation_baked(region: NavigationRegion3D)

const NAV_REGION_NAME: String = "EnemyNavigation"
## CHANGED 2026-10-30 (doors): 0.25 (was 0.5). With 0.25 m cells, 0.5 kept the path a whole 0.5 m off every
## wall, which closed 1.2 to 1.3 m doorways (the size of a door). Enemies wider than this just slide along walls.
const NAV_AGENT_RADIUS: float = 0.25
const NAV_AGENT_HEIGHT: float = 1.0
## Room kind where every floor starts: no enemies there.
const START_ROOM_KIND: StringName = &"lift"
## NEW 2026-10-30: a thrown prop is watched for this long (s) for enemies to dodge.
const WATCH_THROWN_SECONDS: float = 2.0
## NEW 2026-10-30 (doors): bodies in this group are left out of the navigation bake (enemies path through them).
const NAV_SKIP_GROUP: StringName = &"nav_skip"
## NEW 2026-10-30 (doors): a bake asked for by request_navigation_update() waits this long (s), so a door that
## is still swinging has stopped, and several changes at once make one bake.
const NAV_UPDATE_DELAY: float = 1.0

var _spawner: EnemySpawner
var _nav_region: NavigationRegion3D
## NEW 2026-10-30 (doors): what was baked last (baked again by update_navigation), and regions a newer bake is
## replacing (in use until it is ready).
var _nav_root: Node3D
var _old_regions: Array[NavigationRegion3D] = []
## Seconds until an asked-for bake starts (< 0 = none asked for).
var _nav_update_left: float = -1.0
## Counts bakes, so a slow bake that finishes after a newer one started is thrown away.
var _bake_number: int = 0
## Thrown heavy props the host is watching: {"prop": WeakRef, "until": seconds}.
var _thrown: Array[Dictionary] = []


func _ready() -> void:
	_spawner = EnemySpawner.new()
	_spawner.name = "Spawner"
	add_child(_spawner)
	EventBus.floor_ready.connect(_on_floor_ready)
	EventBus.floor_loading.connect(func(_floor_number: int, _department_id: StringName) -> void: _clear_floor())
	EventBus.run_ended.connect(func(_result: StringName) -> void: _clear_floor())
	EventBus.noise_made.connect(func(at: Vector3, radius: float, _source_player_id: int) -> void:
		Enemy.hear_noise(get_tree(), at, radius))
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.prop_released.connect(_on_prop_released)
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
## CHANGED 2026-10-30 (HL2 feel step 3.5): the region is returned at once and its mesh is baked on a
## background thread; navigation_baked fires when it's ready (until then enemies head straight for things).
## `wait` true bakes on the spot instead (tests).
## CHANGED 2026-10-30 (doors): bodies in NAV_SKIP_GROUP are left out, so enemies path through doors they can open.
func bake_navigation(root: Node3D, wait: bool = false) -> NavigationRegion3D:
	_clear_navigation()
	_nav_root = root
	return _bake(root, wait)


## NEW 2026-10-30 (doors): host: something that changes where enemies can go (a door was locked or unlocked,
## a gate opened) happened: bake the navigation again in NAV_UPDATE_DELAY seconds. Does nothing before the
## first bake of a floor.
func request_navigation_update() -> void:
	if _nav_root == null or not is_instance_valid(_nav_root) or not multiplayer.is_server():
		return
	if _nav_update_left < 0.0:
		_nav_update_left = NAV_UPDATE_DELAY


## NEW 2026-10-30 (doors): host: bake the last baked root again now. The old mesh stays in use until the new
## one is ready (`wait` true bakes on the spot, for tests). Null if nothing was baked yet.
func update_navigation(wait: bool = false) -> NavigationRegion3D:
	_nav_update_left = -1.0
	if _nav_root == null or not is_instance_valid(_nav_root) or not _nav_root.is_inside_tree():
		return null
	if _nav_region != null and is_instance_valid(_nav_region):
		_old_regions.append(_nav_region)
	return _bake(_nav_root, wait)


func _bake(root: Node3D, wait: bool) -> NavigationRegion3D:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD)
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	mesh.agent_radius = NAV_AGENT_RADIUS
	mesh.agent_height = NAV_AGENT_HEIGHT
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	var source: NavigationMeshSourceGeometryData3D = _parse_source(mesh, root)
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = NAV_REGION_NAME
	root.add_child(_nav_region)
	_nav_region.top_level = true
	_nav_region.global_transform = Transform3D.IDENTITY
	_bake_number += 1
	var region: NavigationRegion3D = _nav_region
	if wait:
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		_on_navigation_baked(mesh, region, _bake_number)
	else:
		var number: int = _bake_number
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, source,
			func() -> void: _on_navigation_baked.call_deferred(mesh, region, number))
	return region


## The solid shapes under `root`, leaving out bodies in NAV_SKIP_GROUP (they are taken off the world layer
## just while the shapes are read, which happens on the spot).
func _parse_source(mesh: NavigationMesh, root: Node3D) -> NavigationMeshSourceGeometryData3D:
	var skipped: Array[CollisionObject3D] = []
	var layers: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group(NAV_SKIP_GROUP):
		var body := node as CollisionObject3D
		if body != null and root.is_ancestor_of(body):
			skipped.append(body)
			layers.append(body.collision_layer)
			body.collision_layer = 0
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	for index: int in skipped.size():
		skipped[index].collision_layer = layers[index]
	return source


## True while a navigation mesh is still being baked in the background.
func is_baking_navigation() -> bool:
	return _nav_region != null and is_instance_valid(_nav_region) and _nav_region.navigation_mesh == null


func _on_navigation_baked(mesh: NavigationMesh, region: NavigationRegion3D, number: int) -> void:
	if number != _bake_number or not is_instance_valid(region) or region.is_queued_for_deletion():
		return
	# The regions it replaces stop counting at once (so the two never overlap) and go away.
	for old: NavigationRegion3D in _old_regions:
		if is_instance_valid(old):
			old.enabled = false
			old.queue_free()
	_old_regions.clear()
	region.navigation_mesh = mesh
	navigation_baked.emit(region)


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


## Host: an enemy got hurt; whoever did it (a player, or the player who threw the prop) makes it turn on them.
func _on_damage_dealt(target: Node, _amount: float, _damage_type: StringName, source: Node) -> void:
	var enemy := target as Enemy
	if enemy == null or not enemy.is_inside_tree() or not enemy.multiplayer.is_server() or source == null:
		return
	var attacker: PlayerCharacter = PlayerCharacter.of(source)
	var prop := source as NetProp
	if attacker == null and prop != null:
		var thrower: int = prop.get_recent_thrower(Config.feel.props.physics_attacker_window)
		if thrower != 0:
			attacker = PlayerCharacter.find(thrower)
	if attacker != null:
		enemy.on_hurt_by(attacker)


## Host: a heavy prop was thrown: watch it for a moment so enemies in its way can jump aside.
func _on_prop_released(_player_id: int, prop: Node3D, thrown: bool) -> void:
	var net_prop := prop as NetProp
	if not thrown or net_prop == null or not net_prop.multiplayer.is_server():
		return
	if net_prop.get_true_mass() < Config.feel.ai.dodge_min_mass:
		return
	_thrown.append({"prop": weakref(net_prop), "until": Time.get_ticks_msec() / 1000.0 + WATCH_THROWN_SECONDS})


func _physics_process(delta: float) -> void:
	if _nav_update_left >= 0.0:
		_nav_update_left -= delta
		if _nav_update_left < 0.0:
			update_navigation()
	if _thrown.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _thrown:
		var prop := (entry["prop"] as WeakRef).get_ref() as NetProp
		if prop == null or not prop.is_inside_tree() or float(entry["until"]) < now or prop.is_held():
			continue
		kept.append(entry)
		var moving: Vector3 = prop.get_estimated_velocity()
		if moving.length() < Config.feel.ai.dodge_min_speed:
			continue
		for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
			var enemy := node as Enemy
			if enemy != null and enemy.get_world_3d() == prop.get_world_3d():
				enemy.consider_dodge(prop.get_instance_id(), prop.global_position, moving)
	_thrown = kept


func _clear_floor() -> void:
	despawn_all()
	_clear_navigation()


func _clear_navigation() -> void:
	if _nav_region != null and is_instance_valid(_nav_region):
		_nav_region.queue_free()
	_nav_region = null
	for old: NavigationRegion3D in _old_regions:
		if is_instance_valid(old):
			old.queue_free()
	_old_regions.clear()
	_nav_root = null
	_nav_update_left = -1.0


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
