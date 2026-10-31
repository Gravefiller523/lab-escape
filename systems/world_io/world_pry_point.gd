class_name WorldPryPoint
extends WorldDevice
## NEW 2026-10-31 (floor generation step 4c): the gap of a jammed door. Hold E while your selected item is a
## crowbar (`tool_item_id`) for `pry_seconds` and it fires "pried" (wire it to the door: unlock, open). Without
## a crowbar in hand you get the "can't use" buzz. Let go early and the progress slowly falls back. Two
## players prying together go twice as fast. Its face points along +Z.
## Outputs: pried. Inputs: reset (and enable, disable).

@export var prompt: String = "Pry open (needs a crowbar)"
## The item you must have selected to pry (ItemData id).
@export var tool_item_id: StringName = &"item_crowbar"
## Seconds of holding E with the crowbar.
@export var pry_seconds: float = 3.0
## The gap's size (width, height), standing on the floor.
@export var size: Vector2 = Vector2(0.4, 1.8)

## The host sends progress to other PCs this often while it changes (seconds).
const SYNC_SECONDS: float = 0.15

var _progress: float = 0.0
var _done: bool = false
var _users: Dictionary[int, bool] = {}
var _dirty: bool = false
var _sync_left: float = 0.0
var _creak_left: float = 0.0
var _interactable: Interactable
var _gap: MeshInstance3D


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.12)
	shape.shape = box
	shape.position.y = size.y / 2.0 + 0.2
	body.add_child(shape)
	_gap = _box_mesh(Vector3(size.x * 0.3, size.y, 0.05), Color(0.05, 0.05, 0.06))
	_gap.position.y = size.y / 2.0 + 0.2
	body.add_child(_gap)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt_text = prompt
	_interactable.continuous = true
	_interactable.use_condition = func(player_id: int) -> bool: return not _done and has_tool(player_id)
	_interactable.use_started.connect(func(player_id: int) -> void: _users[player_id] = true)
	_interactable.use_tick.connect(_on_use_tick)
	_interactable.use_stopped.connect(func(player_id: int) -> void: _users.erase(player_id))
	body.add_child(_interactable)
	add_child(body)


func get_inputs() -> PackedStringArray:
	return PackedStringArray(["reset"])


## 0 (stuck) to 1 (pried open).
func get_progress() -> float:
	return _progress


func is_done() -> bool:
	return _done


func get_interactable() -> Interactable:
	return _interactable


## Does this player have the tool selected right now?
func has_tool(player_id: int) -> bool:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if body == null:
		return false
	var inventory: InventoryComponent = InventoryComponent.of(body)
	return inventory != null and inventory.get_active_item_id() == tool_item_id


func _on_input(action: StringName, _activator_id: int) -> void:
	if action == &"reset":
		_progress = 0.0
		_done = false
		push_state()


## Host: one physics step of someone prying.
func _on_use_tick(player_id: int, delta: float) -> void:
	if not _enabled or _done or not has_tool(player_id):
		return
	_progress = minf(_progress + delta / maxf(pry_seconds, 0.01), 1.0)
	_dirty = true
	_creak_left -= delta
	if _creak_left <= 0.0:
		_creak_left = 0.5
		_play(&"crank_turn", -4.0)
	if _progress >= 1.0:
		_done = true
		push_state()
		fire_output(&"pried", player_id)


func _physics_process(delta: float) -> void:
	if not _is_host():
		return
	if _users.is_empty() and _progress > 0.0 and not _done:
		_progress = maxf(_progress - delta / maxf(pry_seconds * 2.0, 0.01), 0.0)
		_dirty = true
	_sync_left -= delta
	if _dirty and _sync_left <= 0.0:
		_dirty = false
		_sync_left = SYNC_SECONDS
		push_state()


func get_state() -> Array:
	return [_progress, _done]


func _apply_state(state: Array) -> void:
	if state.size() < 2:
		return
	_progress = state[0]
	_done = state[1]
	if _gap != null:
		_gap.scale.x = 1.0 + _progress * 2.0


func _apply_enabled() -> void:
	if _interactable != null:
		_interactable.enabled = _enabled
