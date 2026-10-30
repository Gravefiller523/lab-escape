class_name WorldButton
extends WorldDevice
## NEW 2026-10-30 (HL2 feel step 4.2): a button on a wall. Its face points along +Z (put it on a wall with
## +Z facing the room). Press E on it (or hold for `press_seconds`): it sinks in, clicks and fires
## "pressed", then pops back out after `reset_seconds` and fires "released". Pressing it while it's locked,
## switched off or still in gives the "can't use" buzz, and a locked one fires "denied".
## Outputs: pressed, released, denied. Inputs: press, lock, unlock (and enable, disable).

@export var prompt: String = "Press button"
@export var size: Vector3 = Vector3(0.22, 0.22, 0.08)
@export var color: Color = Color(0.8, 0.2, 0.15)
## 0 = a press. More than 0 = hold E this many seconds.
@export var press_seconds: float = 0.0
## Seconds before it pops back out and can be pressed again. 0 = it stays in for good.
@export var reset_seconds: float = 1.0
@export var locked: bool = false

var _pressed: bool = false
var _reset_left: float = 0.0
var _body: StaticBody3D
var _cap: MeshInstance3D
var _interactable: Interactable


func _build() -> void:
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	_body.collision_mask = 0
	_body.add_child(_box_shape(size))
	_cap = _box_mesh(size, color)
	_body.add_child(_cap)
	var back := _box_mesh(Vector3(size.x * 1.4, size.y * 1.4, 0.02), Color(0.25, 0.25, 0.28))
	back.position.z = -size.z * 0.5
	_body.add_child(back)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt_text = prompt
	_interactable.hold_seconds = press_seconds
	_interactable.use_condition = func(_player_id: int) -> bool: return not locked and not _pressed
	_interactable.used.connect(func(player_id: int) -> void: _press(player_id))
	_interactable.refused.connect(func(player_id: int) -> void:
		if locked:
			fire_output(&"denied", player_id))
	_body.add_child(_interactable)
	add_child(_body)


func get_inputs() -> PackedStringArray:
	return PackedStringArray(["press", "lock", "unlock"])


func is_pressed() -> bool:
	return _pressed


func is_locked() -> bool:
	return locked


func get_interactable() -> Interactable:
	return _interactable


func _on_input(action: StringName, activator_id: int) -> void:
	match action:
		&"press":
			_press(activator_id)
		&"lock":
			locked = true
			push_state()
		&"unlock":
			locked = false
			push_state()


## Host.
func _press(activator_id: int) -> void:
	if _pressed or not _enabled:
		return
	_pressed = true
	_reset_left = reset_seconds
	_show(true)
	push_state()
	fire_output(&"pressed", activator_id)


func _physics_process(delta: float) -> void:
	if not _pressed or reset_seconds <= 0.0 or not _is_host():
		return
	_reset_left -= delta
	if _reset_left <= 0.0:
		_pressed = false
		_show(false)
		push_state()
		fire_output(&"released")


## Every PC: the cap sinks in (with a click) or pops out.
func _show(pressed: bool) -> void:
	if _cap == null:
		return
	_cap.position.z = -size.z * 0.6 if pressed else 0.0
	if pressed:
		_play(&"button_press")


func get_state() -> Array:
	return [_pressed, locked]


func _apply_state(state: Array) -> void:
	if state.size() < 2:
		return
	var pressed: bool = state[0]
	locked = state[1]
	if pressed != _pressed:
		_pressed = pressed
		_show(pressed)


func _apply_enabled() -> void:
	if _interactable != null:
		_interactable.enabled = _enabled
