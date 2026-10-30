class_name WorldDoor
extends WorldDevice
## NEW 2026-10-30 (HL2 feel step 4.2): a hinged door, like Half-Life 2's. This node sits on the hinge; the
## door runs `width` metres along +X from it and is shut when it hasn't turned. Press E on it (reach is
## measured to the handle) and it swings AWAY from you; press again to shut it. If it is about to swing
## into a player or an enemy it goes back the other way instead (it never crushes or shoves people), while
## loose props just get pushed aside. A locked door gives the "can't use" buzz.
## Outputs: opening, opened, closing, closed, blocked, locked_use.
## Inputs: open, close, toggle, lock, unlock (and enable, disable).
## It keeps a SoundDoor (voice) in the doorway up to date. The host moves it; other PCs follow.

@export var width: float = 1.2
@export var height: float = 2.2
@export var thickness: float = 0.08
## How far it opens (degrees).
@export var swing_degrees: float = 95.0
## How fast it swings (degrees per second).
@export var speed_degrees: float = 150.0
## Shuts by itself this many seconds after it finished opening. 0 = stays open.
@export var auto_close_seconds: float = 0.0
@export var locked: bool = false
## False: players can't open it with E (only wires can), e.g. a gate worked by a valve.
@export var usable: bool = true
## True: it always opens the same way (towards -Z), instead of away from whoever opened it.
@export var one_way: bool = false
@export var color: Color = Color(0.45, 0.38, 0.3)

## Counts as open (for voice) past this many degrees.
const OPEN_FOR_SOUND_DEGREES: float = 3.0
## The handle: this far in from the door's free edge, this high up.
const HANDLE_INSET: float = 0.12
const HANDLE_HEIGHT: float = 1.0

var _angle: float = 0.0
var _target: float = 0.0
var _open_for: float = 0.0
var _panel: AnimatableBody3D
var _interactable: Interactable
var _sound_door: SoundDoor
var _shape_offset: Vector3
var _full_query: PhysicsShapeQueryParameters3D
var _inner_query: PhysicsShapeQueryParameters3D


func _build() -> void:
	_shape_offset = Vector3(width * 0.5, height * 0.5, 0.0)
	_panel = AnimatableBody3D.new()
	_panel.name = "Panel"
	_panel.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	_panel.collision_mask = 0
	_panel.sync_to_physics = true
	_panel.add_child(_box_shape(Vector3(width, height, thickness), _shape_offset))
	var slab := _box_mesh(Vector3(width, height, thickness), color)
	slab.position = _shape_offset
	_panel.add_child(slab)
	var handle := Node3D.new()
	handle.name = "Handle"
	handle.position = Vector3(width - HANDLE_INSET, HANDLE_HEIGHT, 0.0)
	_panel.add_child(handle)
	for side: float in [1.0, -1.0]:
		var knob := _box_mesh(Vector3(0.12, 0.04, 0.05), Color(0.75, 0.7, 0.55))
		knob.position = handle.position + Vector3(-0.03, 0.0, side * (thickness * 0.5 + 0.03))
		_panel.add_child(knob)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.use_point = NodePath("../Handle")
	_interactable.use_condition = func(_player_id: int) -> bool: return usable and not locked
	_interactable.used.connect(func(player_id: int) -> void: toggle(player_id))
	_interactable.refused.connect(func(player_id: int) -> void:
		if locked:
			fire_output(&"locked_use", player_id))
	_panel.add_child(_interactable)
	add_child(_panel)
	_sound_door = SoundDoor.new()
	_sound_door.name = "SoundDoor"
	_sound_door.add_child(_box_shape(Vector3(width, height, 0.4), _shape_offset))
	add_child(_sound_door)
	_sound_door.is_open = false
	_full_query = _make_query(Vector3(width, height, thickness))
	_inner_query = _make_query(Vector3(maxf(width - 0.1, 0.05), maxf(height - 0.1, 0.05), maxf(thickness - 0.06, 0.01)))
	_refresh_prompt()


func get_inputs() -> PackedStringArray:
	return PackedStringArray(["open", "close", "toggle", "lock", "unlock"])


## How far it has turned now (degrees; + and - are the two ways it can open).
func get_angle() -> float:
	return _angle


## Where it is heading (degrees; 0 = shut).
func get_target_angle() -> float:
	return _target


func is_open() -> bool:
	return absf(_angle) > OPEN_FOR_SOUND_DEGREES


func is_locked() -> bool:
	return locked


func get_interactable() -> Interactable:
	return _interactable


## Host: open it away from this player (or the usual way if there's none, or it is one-way).
func open(activator_id: int = 0) -> void:
	var direction: float = 1.0
	var body: PlayerCharacter = PlayerCharacter.find(activator_id) if activator_id != 0 and not one_way else null
	if body != null and body.is_inside_tree():
		# Turning +Y swings the free edge towards -Z, away from someone standing on the +Z side.
		direction = 1.0 if to_local(body.global_position).z >= 0.0 else -1.0
	_set_target(swing_degrees * direction, activator_id)


## Host.
func close(activator_id: int = 0) -> void:
	_set_target(0.0, activator_id)


## Host: open if shut or shutting, else shut.
func toggle(activator_id: int = 0) -> void:
	if _target == 0.0:
		open(activator_id)
	else:
		close(activator_id)


func _on_input(action: StringName, activator_id: int) -> void:
	match action:
		&"open":
			if _target == 0.0:
				open(activator_id)
		&"close":
			close(activator_id)
		&"toggle":
			toggle(activator_id)
		&"lock":
			locked = true
			_refresh_prompt()
			push_state()
		&"unlock":
			locked = false
			_refresh_prompt()
			push_state()


## Host: start swinging towards `angle`.
func _set_target(angle: float, activator_id: int) -> void:
	if angle == _target:
		return
	_target = angle
	_open_for = 0.0
	_on_start_moving()
	push_state()
	fire_output(&"opening" if angle != 0.0 else &"closing", activator_id)


func _physics_process(delta: float) -> void:
	if _panel == null:
		return
	if _angle == _target:
		if _target != 0.0 and auto_close_seconds > 0.0 and _is_host():
			_open_for += delta
			if _open_for >= auto_close_seconds:
				close()
		return
	var next: float = move_toward(_angle, _target, speed_degrees * delta)
	if _is_host() and _would_hit_someone(next):
		_go_back()
		return
	_set_angle(next)
	if _angle == _target:
		_arrived()


## Every PC: it got where it was going.
func _arrived() -> void:
	if _target == 0.0:
		_play(&"door_shut", 0.0, _panel.global_position + _panel.global_basis * _shape_offset)
	if _is_host():
		_open_for = 0.0
		fire_output(&"opened" if _target != 0.0 else &"closed")


## Host: someone is in the way: go back the way it came.
func _go_back() -> void:
	var back: float = 0.0
	if _target == 0.0:
		back = swing_degrees * (signf(_angle) if _angle != 0.0 else 1.0)
	_target = back
	_open_for = 0.0
	push_state()
	fire_output(&"blocked")
	fire_output(&"opening" if back != 0.0 else &"closing")


func _set_angle(angle: float) -> void:
	_angle = angle
	_panel.rotation.y = deg_to_rad(angle)
	if _sound_door != null:
		_sound_door.is_open = is_open()


## Every PC: it starts to move (creak) and the prompt changes.
func _on_start_moving() -> void:
	_refresh_prompt()
	_play(&"door_move", -4.0, _panel.global_position + _panel.global_basis * _shape_offset)


func _refresh_prompt() -> void:
	if _interactable == null:
		return
	if locked:
		_interactable.prompt_text = "Locked door"
	else:
		_interactable.prompt_text = "Close door" if _target != 0.0 else "Open door"


## Would the door, turned to `angle`, newly run into a player or an enemy? Someone already overlapping
## it now doesn't count (so nobody gets the door stuck), but someone just touching it does.
func _would_hit_someone(angle: float) -> bool:
	if not is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var already: Dictionary[int, bool] = _hits(space, _inner_query, _angle)
	for id: int in _hits(space, _full_query, angle):
		if not already.has(id):
			return true
	return false


func _hits(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, angle: float) -> Dictionary[int, bool]:
	query.transform = global_transform * Transform3D(Basis(Vector3.UP, deg_to_rad(angle)), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, _shape_offset)
	query.exclude = [_panel.get_rid()]
	var found: Dictionary[int, bool] = {}
	for hit: Dictionary in space.intersect_shape(query, 8):
		var collider_id: int = hit["collider_id"]
		found[collider_id] = true
	return found


func _make_query(size: Vector3) -> PhysicsShapeQueryParameters3D:
	var box := BoxShape3D.new()
	box.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS) | PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	return query


func get_state() -> Array:
	return [_angle, _target, locked]


func _apply_state(state: Array) -> void:
	if state.size() < 3:
		return
	var target: float = state[1]
	var started: bool = target != _target
	locked = state[2]
	_target = target
	var angle: float = state[0]
	_set_angle(angle)
	if started:
		_on_start_moving()
	else:
		_refresh_prompt()


func _apply_enabled() -> void:
	if _interactable != null:
		_interactable.enabled = _enabled and usable
