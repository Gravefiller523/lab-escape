class_name FloorTask
extends Node3D
## The root of every co-op floor task scene (NEW 2026-11-13, roadmap WP15). It keeps the task's progress (0 to 1) and
## pays its reward when it reaches 1. The host decides: a task scene's own script calls add_work() while players do
## the task; progress reaches every PC a few times a second, and a late joiner asks for it once connected. Every PC
## has the task at the same path (placed by the Objectives autoload), so its RPCs line up. Spec:
## docs/systems/objectives.md.

signal progress_changed(progress: float)
signal completed()

## How often (s) the host sends the progress while it changes.
const SYNC_SECONDS: float = 0.25
## The reward appears this far above the task's origin (and in front of it, see reward_offset).
const REWARD_HEIGHT: float = 1.0

## Where the reward appears, in the task's own space.
@export var reward_offset: Vector3 = Vector3(0, 0, 2.5)

var task_data: FloorTaskData

var _progress: float = 0.0
var _done: bool = false
var _participants: Array[int] = []
var _sync_left: float = 0.0
var _dirty: bool = false


## Before adding it to the tree.
func setup(data: FloorTaskData) -> void:
	task_data = data


func _ready() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		HostLink.when_connected(self, _send_state_request)


func get_progress() -> float:
	return _progress


func is_done() -> bool:
	return _done


## The players who have helped so far.
func get_participants() -> Array[int]:
	return _participants.duplicate()


## Host: these players did `seconds` of work together (each one counts). Finishes it at work_seconds.
func add_work(player_ids: Array[int], seconds: float) -> void:
	if not multiplayer.is_server() or _done or player_ids.is_empty() or seconds <= 0.0:
		return
	for player_id: int in player_ids:
		if not _participants.has(player_id):
			_participants.append(player_id)
	var needed: float = maxf(task_data.work_seconds if task_data != null else 20.0, 0.01)
	_progress = minf(_progress + seconds * float(player_ids.size()) / needed, 1.0)
	_dirty = true
	progress_changed.emit(_progress)
	if _progress >= 1.0:
		complete()


## Host: it is done now: the reward appears and everyone hears about it.
func complete() -> void:
	if not multiplayer.is_server() or _done:
		return
	_progress = 1.0
	_give_reward()
	_state_rpc.rpc(_progress, true)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not _dirty:
		return
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = SYNC_SECONDS
		_dirty = false
		if multiplayer.has_multiplayer_peer():
			_progress_rpc.rpc(_progress)


func _give_reward() -> void:
	if task_data == null:
		return
	var at: Vector3 = global_transform * (reward_offset + Vector3.UP * REWARD_HEIGHT)
	match task_data.reward:
		&"loot":
			Loot.roll_and_spawn(task_data.reward_loot_id, at, task_data.id)
		_:
			push_warning("FloorTask: reward '%s' isn't made yet (only 'loot')." % task_data.reward)


func _send_state_request() -> void:
	_request_state_rpc.rpc_id(1)


## Host -> everyone: the progress, now and then while it changes.
@rpc("authority", "call_remote", "unreliable_ordered")
func _progress_rpc(progress: float) -> void:
	if _done or progress <= _progress:
		return
	_progress = progress
	progress_changed.emit(_progress)


## Host -> everyone (or one late joiner): the whole state.
@rpc("authority", "call_local", "reliable")
func _state_rpc(progress: float, done: bool) -> void:
	if not is_inside_tree():
		return
	if progress > _progress:
		_progress = progress
		progress_changed.emit(_progress)
	if done and not _done:
		_done = true
		completed.emit()
		EventBus.floor_task_completed.emit(task_data.id if task_data != null else &"")


## Client -> host: what is the state? (a late joiner)
@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), _progress, _done)
