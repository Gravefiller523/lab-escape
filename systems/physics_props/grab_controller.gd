class_name GrabController
extends Node
## Child "Grab" of every player body (added by the Props autoload). On the PC that owns the body it
## plugs into interaction: looking at a prop and pressing use grabs it, pressing use again drops it,
## primary (left click) throws it, and drop (Q) always drops it.
## Light props are moved to the hold point straight away on this PC (prediction) while the host
## checks the grab; if the host says no, or someone else takes it, we let go.

signal held_changed(prop: NetProp)

const NODE_NAME: String = "Grab"
## Use handler priority: above Interactables, so looking at a prop and pressing use grabs it.
const USE_PRIORITY: int = 50
## How often (per second) the hold point is sent to the host.
const HOLD_SEND_RATE: float = 30.0

const PROMPT_PICK_UP: String = "Pick up"
const PROMPT_DROP: String = "Drop"
const PROMPT_TOO_HEAVY: String = "Too heavy"
const PROMPT_NEEDS_TWO: String = "Lift (needs two people)"
const PROMPT_HELP_LIFT: String = "Help lift"
const PROMPT_TAKE: String = "Take"

var _body: PlayerCharacter
var _held: NetProp
## True from our grab request until the host answers.
var _pending: bool = false
var _send_timer: float = 0.0


func _ready() -> void:
	name = NODE_NAME
	_body = get_parent() as PlayerCharacter
	if _body == null or not _body.is_local():
		return
	Props.grab_refused.connect(_on_grab_refused)
	_hook_into_interaction.call_deferred()


func _hook_into_interaction() -> void:
	var interaction: InteractionController = InteractionService.controller_of(_body)
	if interaction == null:
		push_error("GrabController: the body has no InteractionController.")
		return
	interaction.register_use_handler(USE_PRIORITY, _on_use)
	interaction.register_prompt_provider(USE_PRIORITY, _prompt_for)


func get_held() -> NetProp:
	return _held


## Local: grab a prop (it moves to your hands now; the host confirms or refuses).
func try_grab(prop: NetProp) -> void:
	if prop == null or prop.get_spawner() == null or prop.is_attached():
		return
	if prop.mass > prop.get_spawner().get_config().two_player_lift_max_mass:
		return
	if _held != null:
		drop()
	_set_held(prop)
	_pending = true
	_update_hold_point()
	prop.get_spawner().request_grab(prop)


func drop() -> void:
	_let_go(Vector3.ZERO)


## Throw what you hold where you're looking.
func throw() -> void:
	_let_go(_body.get_aim_direction())


## True if this player can lift it alone (heavy props need a second player).
func can_lift(prop: NetProp) -> bool:
	return not prop.needs_two_people()


func _let_go(throw_direction: Vector3) -> void:
	if _held == null:
		return
	var prop: NetProp = _held
	_set_held(null)
	if is_instance_valid(prop) and prop.get_spawner() != null:
		prop.get_spawner().request_release(prop, throw_direction)


func _set_held(prop: NetProp) -> void:
	if _held != null and is_instance_valid(_held):
		_held.stop_predicting()
		if _held.hold_changed.is_connected(_on_hold_changed):
			_held.hold_changed.disconnect(_on_hold_changed)
	_held = prop
	_pending = false
	if _held != null:
		_held.hold_changed.connect(_on_hold_changed)
	held_changed.emit(_held)


## Interaction use handler: grab what we look at, or drop what we hold.
func _on_use(target: Node3D) -> bool:
	if _held != null:
		drop()
		return true
	var prop: NetProp = NetProp.of(target) if target != null else null
	if prop == null or prop.is_attached():
		return false
	try_grab(prop)
	return true


## Interaction prompt provider.
func _prompt_for(target: Node3D) -> String:
	if _held != null:
		return PROMPT_DROP
	var prop: NetProp = NetProp.of(target) if target != null else null
	if prop == null or prop.is_attached() or prop.get_spawner() == null:
		return ""
	var config: GameConfig = prop.get_spawner().get_config()
	if prop.mass > config.two_player_lift_max_mass:
		return PROMPT_TOO_HEAVY
	if prop.needs_two_people():
		return PROMPT_HELP_LIFT if prop.is_held() else PROMPT_NEEDS_TWO
	return PROMPT_TAKE if prop.is_held() else PROMPT_PICK_UP


func _unhandled_input(event: InputEvent) -> void:
	if _body == null or not _body.is_local() or _held == null:
		return
	if event.is_action_pressed(InputActions.PRIMARY):
		throw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.DROP):
		drop()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _held == null:
		return
	if not is_instance_valid(_held):
		_set_held(null)
		return
	_update_hold_point()
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = 1.0 / HOLD_SEND_RATE
		_held.get_spawner().send_hold_point(_held, _body.player_id, _hold_point())


## Where held props float: hold_distance (config) in front of the eyes.
func _hold_point() -> Vector3:
	var distance: float = _held.get_spawner().get_config().hold_distance if _held != null else 1.6
	return _body.get_aim_origin() + _body.get_aim_direction() * distance


## Light props follow our hands on this PC right away; heavy ones wait for the host (two holders).
func _update_hold_point() -> void:
	if _held.needs_two_people():
		_held.stop_predicting()
	else:
		_held.start_predicting(_hold_point())


## The host changed who holds our prop: confirmed, or someone took it from us.
func _on_hold_changed() -> void:
	if _held == null:
		return
	if _held.get_holder_ids().has(_body.player_id):
		_pending = false
	elif not _pending:
		_set_held(null)


func _on_grab_refused(prop: NetProp, _reason: String) -> void:
	if prop == _held:
		_set_held(null)
