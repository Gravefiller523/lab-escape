class_name ObjectivesService
extends Node
## Autoload "Objectives" (NEW 2026-11-13, roadmap WP15): co-op floor tasks such as the hamster wheel. On each floor
## (not boss floors) the host picks RunDifficulty.floor_task_count(players) tasks (FloorTaskData) and where they go,
## then tells every PC; a late joiner asks once connected. Every PC puts the task scenes under this node with the
## same names, so their RPCs line up. Spec: docs/systems/objectives.md.
##
## Where tasks go: level_gen's `task` markers. STUB (level_gen): no tile has them yet, so until then a task goes on
## a `prop_spawn` marker outside the lift room that has room for it (TASK_SPACE clear of walls). A department with
## no task_ids uses every task there is (STUB, like enemy spawns).

## The space a task needs at its spot, in the spot's own space: centre and size (the wheel, plus room behind it to
## be carried off the belt).
## From just above the floor (a little clutter on the floor, like a cable, is fine) to below a 3.6 m ceiling.
const TASK_SPACE_CENTER: Vector3 = Vector3(0, 1.7, 0.7)
const TASK_SPACE_SIZE: Vector3 = Vector3(2.8, 2.6, 4.6)
## A spot is tried facing these ways (radians), and the task stands on the floor found this far below it.
const SPOT_TURNS: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
const FLOOR_SEARCH: float = 2.0
const START_ROOM_KIND: StringName = &"lift"
const NODE_PREFIX: String = "Task_"

## What the host decided for the current floor: [task_id (String), transform, floor_number] per task.
var _entries: Array = []
var _floor: int = 0


func _ready() -> void:
	EventBus.floor_ready.connect(_on_floor_ready)
	EventBus.floor_loading.connect(func(floor_number: int, _department_id: StringName) -> void:
		_floor = floor_number
		_clear_except(floor_number))
	EventBus.run_ended.connect(func(_result: StringName) -> void:
		_floor = 0
		_clear_except(-1))
	DebugConsole.register_spawner(&"task", _console_spawn)


## The tasks on this PC now.
func get_tasks() -> Array[FloorTask]:
	var found: Array[FloorTask] = []
	for child: Node in get_children():
		var task := child as FloorTask
		if task != null and not task.is_queued_for_deletion():
			found.append(task)
	return found


## Host: put a task here for everyone (the console, tests). Returns the host's copy.
func place_task(task_id: StringName, xform: Transform3D) -> FloorTask:
	if not multiplayer.is_server() or not ContentRegistry.get_content(task_id) is FloorTaskData:
		return null
	var entry: Array = [String(task_id), xform, _floor]
	_entries.append(entry)
	if multiplayer.has_multiplayer_peer():
		_place_rpc.rpc([entry])
	else:
		_place_rpc([entry])
	return get_node_or_null(NodePath(_node_name(_entries.size() - 1))) as FloorTask


## Host: which tasks this floor gets and where: [task_id, transform] pairs. Same seed, same choice.
func plan_floor(floor_number: int, department: DepartmentData, player_count: int, run_seed: int) -> Array:
	var plan: Array = []
	var candidates: Array[FloorTaskData] = _candidates(department, player_count)
	if candidates.is_empty():
		return plan
	var spots: Array[RoomMarker] = _spots()
	var rng: RandomNumberGenerator = SeededRng.make(run_seed, &"tasks", floor_number)
	for index: int in range(spots.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: RoomMarker = spots[index]
		spots[index] = spots[other]
		spots[other] = swap
	var wanted: int = RunDifficulty.floor_task_count(player_count)
	var weights := PackedFloat32Array()
	for task: FloorTaskData in candidates:
		weights.append(maxf(task.weight, 0.0))
	for marker: RoomMarker in spots:
		if plan.size() >= wanted:
			break
		var task: FloorTaskData = candidates[SeededRng.pick_weighted(rng, weights)]
		if not task.room_kind.is_empty():
			var room: RoomData = Level.get_room_for_position(marker.global_position)
			if room == null or room.room_kind != task.room_kind:
				continue
		var xform: Transform3D = _fit(marker)
		if xform == Transform3D():
			continue
		plan.append([task.id, xform])
	return plan


## Is there room for a task at `xform` (nothing solid in the task's space)?
func has_space(world_node: Node3D, xform: Transform3D) -> bool:
	var box := BoxShape3D.new()
	box.size = TASK_SPACE_SIZE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD)
	query.transform = xform * Transform3D(Basis.IDENTITY, TASK_SPACE_CENTER)
	return world_node.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _candidates(department: DepartmentData, player_count: int) -> Array[FloorTaskData]:
	var ids: Array[StringName] = []
	if department != null and not department.task_ids.is_empty():
		ids = department.task_ids
	else:
		ids = ContentRegistry.get_all_ids(&"task")
	ids.sort()
	var found: Array[FloorTaskData] = []
	for id: StringName in ids:
		var task := ContentRegistry.get_content(id) as FloorTaskData
		if task != null and task.scene != null and task.min_players <= maxi(player_count, 1):
			found.append(task)
	return found


## Where tasks may go: `task` markers, or (STUB) prop spots outside the lift room.
func _spots() -> Array[RoomMarker]:
	var spots: Array[RoomMarker] = Level.get_markers(&"task")
	if not spots.is_empty():
		return spots
	for marker: RoomMarker in Level.get_markers(&"prop_spawn"):
		var room: RoomData = Level.get_room_for_position(marker.global_position)
		if room != null and room.room_kind != START_ROOM_KIND:
			spots.append(marker)
	return spots


## A level transform on the floor under `marker`, turned whichever way has room (SPOT_TURNS), or Transform3D() if
## none has.
func _fit(marker: RoomMarker) -> Transform3D:
	var base: Transform3D = _upright(marker.global_transform)
	var from: Vector3 = base.origin + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FLOOR_SEARCH,
		PhysicsLayers.bit(PhysicsLayers.WORLD))
	var hit: Dictionary = marker.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		base.origin.y = (hit["position"] as Vector3).y
	for turn: float in SPOT_TURNS:
		var xform := Transform3D(base.basis.rotated(Vector3.UP, turn), base.origin)
		if has_space(marker, xform):
			return xform
	return Transform3D()


## The same spot, turned only around the up axis (a task stands level).
static func _upright(xform: Transform3D) -> Transform3D:
	var forward: Vector3 = -xform.basis.z
	forward.y = 0.0
	var yaw: float = atan2(-forward.x, -forward.z) if forward.length() > 0.01 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), xform.origin)


func _on_floor_ready(floor_number: int, _department_id: StringName) -> void:
	_floor = floor_number
	if not multiplayer.is_server():
		if multiplayer.has_multiplayer_peer():
			HostLink.when_connected(self, _send_plan_request)
		return
	_entries.clear()
	var run: RunState = GameFlow.get_run()
	if run == null or run.is_boss_floor:
		return
	for pair: Array in plan_floor(floor_number, GameFlow.get_current_department(), Net.get_player_count(), run.run_seed):
		place_task(StringName(str(pair[0])), pair[1] as Transform3D)


func _send_plan_request() -> void:
	_request_plan_rpc.rpc_id(1)


func _node_name(index: int) -> String:
	return "%s%d" % [NODE_PREFIX, index]


func _clear_except(floor_number: int) -> void:
	for task: FloorTask in get_tasks():
		if (task.get_meta(&"floor", -1) as int) != floor_number or floor_number < 0:
			remove_child(task)
			task.queue_free()
	if floor_number < 0 or (not _entries.is_empty() and (_entries[0][2] as int) != floor_number):
		_entries.clear()


## Host -> everyone (or one late joiner): these tasks are on the floor. Each entry: [task_id, transform, floor].
## Placing one that is already there does nothing.
@rpc("authority", "call_local", "reliable")
func _place_rpc(entries: Array) -> void:
	for entry: Variant in entries:
		var parts: Array = entry as Array
		if parts == null or parts.size() < 3:
			continue
		var floor_number: int = parts[2] as int
		if floor_number != _floor and _floor != 0:
			continue
		var index: int = get_tasks().size()
		for task: FloorTask in get_tasks():
			if task.get_meta(&"xform", Transform3D()) == parts[1]:
				index = -1
		if index < 0:
			continue
		var data := ContentRegistry.get_content(StringName(str(parts[0]))) as FloorTaskData
		if data == null or data.scene == null:
			continue
		var task := data.scene.instantiate() as FloorTask
		if task == null:
			push_warning("Objectives: %s's scene root isn't a FloorTask." % data.id)
			continue
		task.name = _node_name(index)
		task.setup(data)
		task.set_meta(&"floor", floor_number)
		task.set_meta(&"xform", parts[1] as Transform3D)
		task.transform = parts[1] as Transform3D
		add_child(task)


## Client -> host: which tasks are on this floor? (a late joiner)
@rpc("any_peer", "call_remote", "reliable")
func _request_plan_rpc() -> void:
	if multiplayer.is_server() and not _entries.is_empty():
		_place_rpc.rpc_id(multiplayer.get_remote_sender_id(), _entries)


func _console_spawn(id: StringName, at: Transform3D, _count: int, _player_id: int) -> String:
	var task: FloorTask = place_task(id, _upright(at))
	return "Placed %s." % id if task != null else "Couldn't place %s." % id
