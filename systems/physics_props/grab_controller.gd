class_name GrabController
extends Node
## Child "Grab" of every player body (added by the Props autoload). On the PC that owns the body it
## plugs into interaction: looking at a prop and pressing use grabs it, pressing use again drops it,
## primary (left click) throws it, and drop (Q) always drops it.
## When the host confirms a grab, it hands the prop's physics to this PC (unless several people hold
## it), so it follows our hands with no delay. If the host says no, or someone takes it, we let go.

signal held_changed(prop: NetProp)

const NODE_NAME: String = "Grab"
## Use handler priority: above Interactables, so looking at a prop and pressing use grabs it.
const USE_PRIORITY: int = 50
## How often (per second) the hold point is sent to the host.
const HOLD_SEND_RATE: float = 30.0
## How often (per second) we tell the host we are pushing a prop, and the slowest push that counts.
const PUSH_SEND_RATE: float = 20.0
const MIN_PUSH_SPEED: float = 0.05
## A contact counts as "the side of a prop" when its normal points this little up or down.
const SIDE_CONTACT_MAX_Y: float = 0.5
## "Standing on it": a ray from just above our feet going this far down (metres).
const FEET_RAY_START: float = 0.1
const FEET_RAY_LENGTH: float = 0.3

const PROMPT_PICK_UP: String = "Pick up"
const PROMPT_DROP: String = "Drop"
const PROMPT_HEAVY: String = "Drag (heavy: more people make it faster)"
const PROMPT_HELP_LIFT: String = "Help lift (%d holding)"
const PROMPT_TAKE: String = "Take"
## Movement modifier source while carrying (NEW 2026-10-29: no sprinting while carrying).
const CARRY_MODIFIER: StringName = &"carrying_prop"

var _body: PlayerCharacter
var _held: NetProp
## True from our grab request until the host answers.
var _pending: bool = false
var _send_timer: float = 0.0
var _push_timer: float = 0.0


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


## CHANGED 2026-10-24: null once the held prop is gone (despawned this frame: put in a machine, a cart, a vendor),
## not a freed object.
func get_held() -> NetProp:
	return _held if is_instance_valid(_held) else null


## Local: grab a prop (it moves to your hands now; the host confirms or refuses).
func try_grab(prop: NetProp) -> void:
	if prop == null or prop.get_spawner() == null or prop.is_attached():
		return
	# Half-Life 2: you can't pick up what you're standing on. CHANGED 2026-10-29: nor what anyone stands on.
	if _standing_on(prop) or _anyone_standing_on(prop):
		return
	if _held != null:
		drop()
	_set_held(prop)
	_pending = true
	prop.get_spawner().request_grab(prop)


func drop() -> void:
	_let_go(Vector3.ZERO)


## Throw what you hold where you're looking.
func throw() -> void:
	_let_go(_body.get_aim_direction())


## True if this player can lift it alone (heavy props need helpers to lift fully).
func can_lift(prop: NetProp) -> bool:
	return not prop.needs_help()


func _let_go(throw_direction: Vector3) -> void:
	if _held == null:
		return
	var prop: NetProp = _held
	_set_held(null)
	if not is_instance_valid(prop) or prop.get_spawner() == null:
		return
	prop.let_go_here(_body.player_id, not throw_direction.is_zero_approx())
	# If our PC runs it, throw it now (no waiting for the host).
	if not throw_direction.is_zero_approx() and prop.is_simulated_here() and prop.is_lifted() \
			and not _body.multiplayer.is_server():
		prop.throw_now(throw_direction, prop.get_spawner().throw_strength(prop))
	prop.get_spawner().request_release(prop, throw_direction)


func _set_held(prop: NetProp) -> void:
	if _held != null and is_instance_valid(_held):
		if _held.hold_changed.is_connected(_on_hold_changed):
			_held.hold_changed.disconnect(_on_hold_changed)
	_held = prop
	_pending = false
	if _held != null:
		_held.hold_changed.connect(_on_hold_changed)
	_update_carry_modifier()
	held_changed.emit(_held)


## NEW 2026-10-29: no sprinting while carrying (Half-Life 2), if Config.feel.props says so.
func _update_carry_modifier() -> void:
	if _body == null:
		return
	var movement: PlayerMovement = _body.get_movement()
	if _held != null and Config.feel.props.disable_sprint_while_holding:
		var carrying := MovementEffectData.new()
		carrying.can_sprint = false
		movement.set_modifier(CARRY_MODIFIER, carrying)
	else:
		movement.remove_modifier(CARRY_MODIFIER)


## Interaction use handler: grab what we look at, or drop what we hold.
func _on_use(target: Node3D) -> bool:
	if _held != null:
		drop()
		return true
	var prop: NetProp = NetProp.of(target) if target != null else null
	# CHANGED 2026-10-29: the look ray missed (or hit a wall or floor): a prop near the middle of the view
	# still counts. Never when aiming at something else you can use (a button, a door).
	if prop == null and (target == null or Interactable.of(target) == null):
		prop = find_prop_in_view()
	if prop == null or prop.is_attached():
		return false
	try_grab(prop)
	return true


## NEW 2026-10-29: the loose prop within reach closest to the middle of the view (inside grab_cone_dot) that
## nothing solid hides, or null.
func find_prop_in_view() -> NetProp:
	var spawner: PropSpawner = Props.spawner_for(_body) if _body != null else null
	if spawner == null or _body == null:
		return null
	var tuning: PropTuning = Config.feel.props
	var origin: Vector3 = _body.get_aim_origin()
	var aim: Vector3 = _body.get_aim_direction()
	var best: NetProp = null
	var best_dot: float = tuning.grab_cone_dot
	for prop: NetProp in spawner.get_props():
		if not is_instance_valid(prop) or prop.is_attached():
			continue
		var to_prop: Vector3 = prop.global_position - origin
		var distance: float = to_prop.length()
		# CHANGED 2026-10-30: a bit further with the punt arm (PropSpawner.grab_reach_of).
		if distance > PropSpawner.grab_reach_of(_body) or distance < 0.01:
			continue
		var dot: float = aim.dot(to_prop / distance)
		if dot <= best_dot:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, prop.global_position, PhysicsLayers.bit(PhysicsLayers.WORLD))
		if not _body.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = prop
		best_dot = dot
	return best


## Interaction prompt provider.
func _prompt_for(target: Node3D) -> String:
	if _held != null:
		return PROMPT_DROP
	var prop: NetProp = NetProp.of(target) if target != null else null
	if prop == null or prop.is_attached() or prop.get_spawner() == null or _standing_on(prop) \
			or _anyone_standing_on(prop):
		return ""
	if prop.needs_help():
		return PROMPT_HELP_LIFT % prop.get_holder_ids().size() if prop.is_held() else PROMPT_HEAVY
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
	if _body != null and _body.is_local():
		_push_what_we_walk_into(delta)
	if _held == null:
		return
	if not is_instance_valid(_held):
		_set_held(null)
		return
	if _standing_on(_held):
		# Half-Life 2 rule: you can't ride what you hold, so stepping onto it drops it.
		drop()
		return
	# Our PC runs it: update every frame. Otherwise (host runs it): send a few times a second.
	if _held.is_simulated_here():
		_held.get_spawner().send_hold_point(_held, _body.player_id, _hold_point(), _body.rotation.y)
		return
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = 1.0 / HOLD_SEND_RATE
		_held.get_spawner().send_hold_point(_held, _body.player_id, _hold_point(), _body.rotation.y)


## Props block us; when we walk into the SIDE of one, push it (standing on top never pushes).
## Runs after the body moved this frame (children run after their parent).
func _push_what_we_walk_into(delta: float) -> void:
	_push_timer -= delta
	if _push_timer > 0.0 or delta <= 0.0:
		return
	for index: int in _body.get_slide_collision_count():
		var collision: KinematicCollision3D = _body.get_slide_collision(index)
		var prop := collision.get_collider() as NetProp
		if prop == null or prop == _held or prop.is_attached() or prop.get_spawner() == null:
			continue
		var normal: Vector3 = collision.get_normal()
		# Floor-like contact (standing on it) or ceiling-like: not a push.
		if absf(normal.y) > SIDE_CONTACT_MAX_Y:
			continue
		var into := -normal
		into.y = 0.0
		if into.is_zero_approx():
			continue
		into = into.normalized()
		# Still trying to move into it (once blocked, our own speed into it drops to almost nothing,
		# so push at walking speed instead; the host slows the prop by its weight).
		if collision.get_remainder().dot(into) / delta > MIN_PUSH_SPEED:
			_push_timer = 1.0 / PUSH_SEND_RATE
			var speed: float = _body.tuning.walk_speed * _body.get_movement().get_speed_multiplier()
			prop.get_spawner().request_push(prop, _body.player_id, into, speed)


## True if our feet are on this prop.
func _standing_on(prop: NetProp) -> bool:
	if prop == null:
		return false
	for index: int in _body.get_slide_collision_count():
		var collision: KinematicCollision3D = _body.get_slide_collision(index)
		if collision.get_collider() == prop and collision.get_normal().y > SIDE_CONTACT_MAX_Y:
			return true
	# Standing still reports no collisions, so also look straight down from our feet.
	var feet: Vector3 = _body.global_position + Vector3.UP * FEET_RAY_START
	var query := PhysicsRayQueryParameters3D.create(feet, feet + Vector3.DOWN * FEET_RAY_LENGTH,
		PhysicsLayers.bit(PhysicsLayers.PROPS))
	var hit: Dictionary = _body.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == prop


## NEW 2026-10-29: any player (us included) standing on it or above it, if that rule is on.
func _anyone_standing_on(prop: NetProp) -> bool:
	return Config.feel.props.no_grab_while_stood_on and prop.get_spawner() != null \
		and prop.get_spawner().is_under_a_player(prop)


## NEW 2026-10-29: where the held prop should be now (tests use it). Vector3.ZERO when holding nothing.
func get_hold_point() -> Vector3:
	return _hold_point() if get_held() != null else Vector3.ZERO


## Where held props float in front of the eyes. CHANGED 2026-10-29: hold_base_gap + our body's radius +
## the prop's depth along the view (was hold_distance + its radius), so it sits just in front of us.
func _hold_point() -> Vector3:
	var origin: Vector3 = _body.get_aim_origin()
	var direction: Vector3 = _body.get_aim_direction()
	var tuning: PropTuning = Config.feel.props
	# Half-Life 2: don't hold it straight up or down past 75 degrees.
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	var max_pitch: float = deg_to_rad(tuning.max_hold_pitch_degrees)
	var pitch: float = clampf(asin(clampf(direction.y, -1.0, 1.0)), -max_pitch, max_pitch)
	direction = (flat * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	# Further away for bigger props, so they never press into you.
	var radius: float = _held.get_depth_along(direction)
	var distance: float = tuning.hold_base_gap + _body.tuning.radius + radius
	# A wall in front: bring it in closer instead of pushing it into the wall.
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance,
		PhysicsLayers.bit(PhysicsLayers.WORLD))
	var hit: Dictionary = _body.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		distance = maxf(origin.distance_to(hit["position"] as Vector3) - radius, radius + tuning.min_hold_gap)
	var point: Vector3 = origin + direction * distance
	# CHANGED 2026-10-29 (Zachary's playtest): never inside our own body. Looking down, the point would be at
	# our feet and the prop would shove us backwards, so keep it out in front of us instead.
	var half_height: float = _held.get_depth_along(Vector3.UP)
	var feet: float = _body.global_position.y
	var head: float = feet + _body.get_movement().get_height()
	if point.y - half_height < head and point.y + half_height > feet:
		var clearance: float = _body.tuning.radius + _held.get_depth_along(flat) + tuning.hold_body_clearance
		var out := Vector3(point.x - _body.global_position.x, 0.0, point.z - _body.global_position.z)
		if out.length() < clearance:
			point = Vector3(_body.global_position.x, point.y, _body.global_position.z) + flat * clearance
	return point


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
