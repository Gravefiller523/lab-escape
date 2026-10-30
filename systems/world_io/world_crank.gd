class_name WorldCrank
extends WorldDevice
## NEW 2026-10-30 (HL2 feel step 4.2): a valve wheel you turn by holding E (continuous use). Its face points
## along +Z. Hold E for `turn_seconds` to turn it all the way and it fires "completed". Let go early and it
## slowly turns back. Two players turning it together go twice as fast.
## Outputs: started (someone started turning it), completed, rewound (it turned all the way back).
## Inputs: reset, lock, unlock (and enable, disable).

@export var prompt: String = "Turn valve"
@export var radius: float = 0.25
## Seconds of holding E to turn it all the way.
@export var turn_seconds: float = 2.5
## Seconds to turn all the way back once nobody holds it. 0 = it stays where it was left.
@export var rewind_seconds: float = 4.0
## Done for good once completed (else it turns back after and can be done again).
@export var stays_done: bool = true
## How many times the wheel goes round from start to done (just for looks).
@export var turns: float = 2.0
@export var locked: bool = false
@export var color: Color = Color(0.75, 0.2, 0.15)

## The host sends the turn to other PCs this often while it changes (seconds).
const SYNC_SECONDS: float = 0.1
## A ratchet click every eighth of a turn.
const CLICKS_PER_TURN: int = 8

var _progress: float = 0.0
var _shown: float = 0.0
var _done: bool = false
var _turners: Dictionary[int, bool] = {}
var _dirty: bool = false
var _sync_left: float = 0.0
var _last_click: int = 0
var _wheel: Node3D
var _interactable: Interactable


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 0.1
	shape.shape = cylinder
	shape.rotation.x = PI * 0.5
	body.add_child(shape)
	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.8
	torus.outer_radius = radius
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	torus.material = material
	rim.mesh = torus
	rim.rotation.x = PI * 0.5
	_wheel.add_child(rim)
	for spoke_angle: float in [0.0, PI * 0.5]:
		var spoke := _box_mesh(Vector3(radius * 1.8, 0.04, 0.03), color)
		spoke.rotation.z = spoke_angle
		_wheel.add_child(spoke)
	body.add_child(_wheel)
	var axle := _box_mesh(Vector3(0.06, 0.06, 0.3), Color(0.35, 0.35, 0.38))
	axle.position.z = -0.15
	body.add_child(axle)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt_text = prompt
	_interactable.continuous = true
	_interactable.use_condition = func(_player_id: int) -> bool: return not locked and not (_done and stays_done)
	_interactable.use_started.connect(_on_use_started)
	_interactable.use_tick.connect(_on_use_tick)
	_interactable.use_stopped.connect(func(player_id: int) -> void: _turners.erase(player_id))
	body.add_child(_interactable)
	add_child(body)


func get_inputs() -> PackedStringArray:
	return PackedStringArray(["reset", "lock", "unlock"])


## 0 (start) to 1 (done).
func get_progress() -> float:
	return _progress


func is_done() -> bool:
	return _done


func get_interactable() -> Interactable:
	return _interactable


func _on_input(action: StringName, _activator_id: int) -> void:
	match action:
		&"reset":
			_progress = 0.0
			_done = false
		&"lock":
			locked = true
		&"unlock":
			locked = false
	push_state()


## Host.
func _on_use_started(player_id: int) -> void:
	var first: bool = _turners.is_empty()
	_turners[player_id] = true
	if first:
		fire_output(&"started", player_id)


## Host: one physics step of someone holding E on it.
func _on_use_tick(player_id: int, delta: float) -> void:
	if not _enabled or _done:
		return
	_progress = minf(_progress + delta / maxf(turn_seconds, 0.01), 1.0)
	_dirty = true
	if _progress >= 1.0:
		_done = true
		push_state()
		fire_output(&"completed", player_id)


func _physics_process(delta: float) -> void:
	if _wheel == null:
		return
	if _is_host():
		var can_rewind: bool = not _done or not stays_done
		if _turners.is_empty() and _progress > 0.0 and rewind_seconds > 0.0 and can_rewind:
			_progress = maxf(_progress - delta / rewind_seconds, 0.0)
			_dirty = true
			if _progress == 0.0:
				_done = false
				push_state()
				fire_output(&"rewound")
		_sync_left -= delta
		if _dirty and _sync_left <= 0.0:
			_dirty = false
			_sync_left = SYNC_SECONDS
			push_state()
		_shown = _progress
	else:
		_shown = lerpf(_shown, _progress, 1.0 - exp(-15.0 * delta))
	_wheel.rotation.z = -_shown * turns * TAU
	var click: int = floori(_shown * turns * float(CLICKS_PER_TURN))
	if click != _last_click:
		_last_click = click
		_play(&"crank_turn", -6.0)


func get_state() -> Array:
	return [_progress, _done, locked]


func _apply_state(state: Array) -> void:
	if state.size() < 3:
		return
	_progress = state[0]
	_done = state[1]
	locked = state[2]


func _apply_enabled() -> void:
	if _interactable != null:
		_interactable.enabled = _enabled
