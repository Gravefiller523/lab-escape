class_name VoiceHearing
extends RefCounted
## How one listener hears one speaker right now: how far the sound travels, how muffled it is, and
## where it seems to come from. Worked out on each listener's PC (nothing goes over the network).
##
## 1. Clear line of sight: straight distance, no muffle, sound from the speaker.
## 2. Walls in the way, but a walkable route (navmesh) exists: the sound goes the long way round.
##    Distance = route length, sound seems to come from the last corner before you (the doorway),
##    and a light muffle grows with the number of corners.
## 3. Walls in the way and no route (or no navmesh): straight distance, fully muffled.
## Closed SoundDoors on the way add the closed-door muffle. Open doors add nothing.

## How far the sound travels, in metres (used for the distance fade).
var distance: float = 0.0
## 0 = clear, 1 = fully muffled.
var muffle: float = 0.0
## Where the voice seems to come from.
var source: Vector3 = Vector3.ZERO
## True when the sound went the long way round (through doors and hallways).
var used_path: bool = false
## How many closed doors the sound passed through.
var closed_doors: int = 0

## Rays from the listener's head to the speaker's head: one straight, two slightly to the sides.
const RAY_SIDE_OFFSET: float = 0.25
## A route only counts if it ends this close to the listener (metres).
const PATH_END_TOLERANCE: float = 1.0
## A route bends at a "corner" when it turns more than this.
const CORNER_ANGLE_DEGREES: float = 20.0
## Corners alone never muffle more than this, so a long way round never sounds like a wall.
const MAX_CORNER_MUFFLE: float = 0.4


## Works out how `listener` hears a voice at `speaker` in this world.
static func compute(listener: Vector3, speaker: Vector3, world: World3D, config: GameConfig) -> VoiceHearing:
	var hearing := VoiceHearing.new()
	hearing.source = speaker
	hearing.distance = listener.distance_to(speaker)
	var blocked: float = _blocked_fraction(listener, speaker, world, config)
	var doors: Array[SoundDoor] = _closed_doors(world)
	if blocked <= 0.0:
		hearing.closed_doors = _count_doors(doors, PackedVector3Array([speaker, listener]))
		hearing.muffle = _door_muffle(hearing.closed_doors, config)
		return hearing

	var path: PackedVector3Array = _walkable_path(speaker, listener, world)
	if path.size() >= 2:
		var head_offset: float = speaker.y - path[0].y
		hearing.used_path = true
		hearing.distance = speaker.distance_to(path[0]) + path_length(path) + path[path.size() - 1].distance_to(listener)
		var corners: PackedVector3Array = turning_points(path)
		hearing.source = corners[corners.size() - 1] + Vector3(0, head_offset, 0) if not corners.is_empty() else speaker
		hearing.closed_doors = _count_doors(doors, path)
		hearing.muffle = clampf(float(corners.size()) * config.voice_corner_muffle, 0.0, MAX_CORNER_MUFFLE) \
			+ _door_muffle(hearing.closed_doors, config)
		hearing.muffle = clampf(hearing.muffle, 0.0, 1.0)
		return hearing

	# No way round: through the wall.
	hearing.muffle = blocked
	return hearing


## The real corners of a route, in order (points where it turns more than CORNER_ANGLE_DEGREES).
## Navmesh routes also have in-between points on straight lines; those don't count.
static func turning_points(path: PackedVector3Array) -> PackedVector3Array:
	var corners := PackedVector3Array()
	for index: int in range(1, path.size() - 1):
		var before := Vector2(path[index].x - path[index - 1].x, path[index].z - path[index - 1].z)
		var after := Vector2(path[index + 1].x - path[index].x, path[index + 1].z - path[index].z)
		if before.is_zero_approx() or after.is_zero_approx():
			continue
		if absf(rad_to_deg(before.angle_to(after))) > CORNER_ANGLE_DEGREES:
			corners.append(path[index])
	return corners


## Total length of a route.
static func path_length(points: PackedVector3Array) -> float:
	var total: float = 0.0
	for index: int in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


## 0 = nothing in the way, 1 = all three rays hit a sound blocker.
static func _blocked_fraction(listener: Vector3, speaker: Vector3, world: World3D, config: GameConfig) -> float:
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return 0.0
	var direction: Vector3 = speaker - listener
	var side: Vector3 = direction.cross(Vector3.UP).normalized() * RAY_SIDE_OFFSET
	if side.is_zero_approx():
		side = Vector3.RIGHT * RAY_SIDE_OFFSET
	var hits: int = 0
	for offset: Vector3 in [Vector3.ZERO, side, -side]:
		var query := PhysicsRayQueryParameters3D.create(listener + offset, speaker + offset,
			PhysicsLayers.bit(config.voice_sound_blocker_layer))
		if not space.intersect_ray(query).is_empty():
			hits += 1
	return float(hits) / 3.0


## The walkable route from speaker to listener, or empty if there is no navmesh or no route.
static func _walkable_path(speaker: Vector3, listener: Vector3, world: World3D) -> PackedVector3Array:
	var map: RID = world.navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_regions(map).is_empty():
		return PackedVector3Array()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array()
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, speaker)
	var end: Vector3 = NavigationServer3D.map_get_closest_point(map, listener)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, end, true)
	if path.size() < 2 or path[path.size() - 1].distance_to(end) > PATH_END_TOLERANCE:
		return PackedVector3Array()
	return path


static func _closed_doors(world: World3D) -> Array[SoundDoor]:
	var doors: Array[SoundDoor] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return doors
	for node: Node in tree.get_nodes_in_group(SoundDoor.GROUP):
		var door := node as SoundDoor
		if door != null and not door.is_open and door.is_inside_tree() and door.get_world_3d() == world:
			doors.append(door)
	return doors


## How many closed doors a route (list of points) passes through.
static func _count_doors(doors: Array[SoundDoor], route: PackedVector3Array) -> int:
	var count: int = 0
	for door: SoundDoor in doors:
		for index: int in range(1, route.size()):
			if door.blocks_segment(route[index - 1], route[index]):
				count += 1
				break
	return count


static func _door_muffle(door_count: int, config: GameConfig) -> float:
	return clampf(float(door_count) * config.voice_closed_door_muffle, 0.0, 1.0)
