class_name InteractionController
extends Node
## Child "Interaction" of every player body (added by the Interaction autoload). On the PC that owns
## the body it finds what you're looking at, works out the "Press E to ..." prompt and handles the
## use key. On the host it checks use requests and fires Interactable.used.
##
## Other systems add their own use actions without editing this one:
##   register_use_handler(priority, func(target: Node3D) -> bool)   (true = "I handled the press")
##   register_prompt_provider(priority, func(target: Node3D) -> String)   ("" = no opinion)
## Higher priority runs first. What pressing use does: (1) handlers by priority, (2) otherwise the
## target's Interactable, sent to the host as a request.
##
## CHANGED 2026-10-30 (HL2 feel step 4.1):
## - The "can't use that" buzz (EventBus.use_denied, on your PC): pressing use when nothing takes it
##   (looking at a wall, at nothing, or at something out of reach or switched off), or when the host
##   says no (a locked door). At most once per Config.feel.interaction.deny_cooldown.
## - Continuous use (Interactable.continuous): while you hold use on it, the host fires use_tick.
## - Reach is measured to the Interactable's use point (a door handle), not the object's middle.
## - A fatter aim check: if the thin look ray finds nothing usable, a small ball
##   (Config.feel.interaction.aim_assist_radius) swept along the same line can, if no wall is in between.

signal target_changed(target: Node3D)

const NODE_NAME: String = "Interaction"
## How far the look ray reaches (metres). Each Interactable also has its own max_distance.
const RAY_LENGTH: float = 4.0
## The host allows this much extra distance, for network delay.
const HOST_DISTANCE_TOLERANCE: float = 0.75

var _body: PlayerCharacter
var _target: Node3D
var _handlers: Array[Dictionary] = []
var _providers: Array[Dictionary] = []
var _hold_target: Node3D
var _hold_time: float = 0.0
var _hold_sent: bool = false
## Your PC: the continuous-use target the host was last told about (null = none).
var _continuous_sent: Node3D
var _continuous_by_key: bool = false
## Host: what this player is turning right now (continuous use), or null.
var _continuous_target: Node3D
var _last_deny_msec: int = -100000
var _assist_shape: SphereShape3D
static var _default_tuning: UseTuning


func _ready() -> void:
	name = NODE_NAME
	_body = get_parent() as PlayerCharacter


func _exit_tree() -> void:
	_stop_continuous()


## What the local player is looking at (a collision object), or null.
func get_target() -> Node3D:
	_forget_freed()
	return _target


## FIX 2026-10-30 (found by Zachary): what we were looking at can be removed between physics steps (a crate
## broke, a prop was despawned); forget it, so nothing is handed a freed object.
func _forget_freed() -> void:
	# (A freed object compares equal to null, so only is_instance_valid can tell.)
	if not is_instance_valid(_target):
		_target = null
	if not is_instance_valid(_hold_target):
		_hold_target = null


## "Press E to ..." text for the current target, or "" for nothing to do.
func get_prompt() -> String:
	_forget_freed()
	if _target == null:
		return ""
	for entry: Dictionary in _providers:
		var provider: Callable = entry["callable"]
		var text: String = str(provider.call(_target))
		if not text.is_empty():
			return text
	var interactable: Interactable = Interactable.of(_target)
	if interactable == null or not interactable.enabled or not _in_reach(interactable, 0.0):
		return ""
	return interactable.prompt_text


## 0 to 1 while holding the use key on a hold-to-use object (for the HUD ring).
func get_hold_progress() -> float:
	_forget_freed()
	var interactable: Interactable = Interactable.of(_hold_target) if _hold_target != null else null
	if interactable == null or interactable.hold_seconds <= 0.0:
		return 0.0
	return clampf(_hold_time / interactable.hold_seconds, 0.0, 1.0)


func register_use_handler(priority: int, handler: Callable) -> void:
	_handlers.append({"priority": priority, "callable": handler})
	_handlers.sort_custom(_higher_first)


func unregister_use_handler(handler: Callable) -> void:
	_handlers = _handlers.filter(func(entry: Dictionary) -> bool: return entry["callable"] != handler)


func register_prompt_provider(priority: int, provider: Callable) -> void:
	_providers.append({"priority": priority, "callable": provider})
	_providers.sort_custom(_higher_first)


func unregister_prompt_provider(provider: Callable) -> void:
	_providers = _providers.filter(func(entry: Dictionary) -> bool: return entry["callable"] != provider)


## Presses use once on a target, as if the key went down (handlers first, then the Interactable).
## Used by the key and by tests. Returns true if something took the press. CHANGED 2026-10-30: if nothing
## did, you hear the "can't use" buzz.
func press_use(target: Node3D) -> bool:
	for entry: Dictionary in _handlers:
		var handler: Callable = entry["callable"]
		var handled: bool = handler.call(target)
		if handled:
			return true
	var interactable: Interactable = Interactable.of(target) if target != null else null
	if interactable == null or not interactable.enabled or not _in_reach(interactable, 0.0):
		deny()
		return false
	# Hold-to-use and continuous objects are driven by holding the key (_update_hold, _update_continuous).
	if interactable.hold_seconds > 0.0 or interactable.continuous:
		return true
	request_use(target, 0.0)
	return true


## Asks the host to use a target's Interactable (it checks everything again).
func request_use(target: Node3D, held_seconds: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	_request_use_rpc.rpc_id(1, _multiplayer_root().get_path_to(target), held_seconds)


## NEW 2026-10-30: start (a target) or stop (null) holding use on a continuous object. The key does this
## for you; tests call it directly. Tells the host only when it changes.
func set_continuous_use(target: Node3D) -> void:
	if target == _continuous_sent:
		return
	_continuous_sent = target
	var path: NodePath = _multiplayer_root().get_path_to(target) if target != null and target.is_inside_tree() else NodePath()
	_continuous_rpc.rpc_id(1, path)


## NEW 2026-10-30: the "can't use that" buzz, on this player's PC (EventBus.use_denied).
func deny() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_deny_msec < int(_tuning().deny_cooldown * 1000.0):
		return
	_last_deny_msec = now
	EventBus.use_denied.emit(_body.player_id if _body != null else 0)


## Config.feel.interaction (a default copy if a test's FeelTuning has no interaction section).
static func _tuning() -> UseTuning:
	if Config.feel != null and Config.feel.interaction != null:
		return Config.feel.interaction
	if _default_tuning == null:
		_default_tuning = UseTuning.new()
	return _default_tuning


## Paths sent over the network are relative to the multiplayer root, so they match on every PC.
func _multiplayer_root() -> Node:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer != null and not scene_multiplayer.root_path.is_empty():
		return get_node(scene_multiplayer.root_path)
	return get_tree().root


static func _higher_first(a: Dictionary, b: Dictionary) -> bool:
	var first: int = a["priority"]
	var second: int = b["priority"]
	return first > second


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if multiplayer.is_server():
		_tick_continuous(delta)
	if not _body.is_local():
		return
	_update_target()
	_update_hold(delta)
	_update_continuous()


func _unhandled_input(event: InputEvent) -> void:
	if _body == null or not _body.is_local() or not event.is_action_pressed(InputActions.USE):
		return
	_forget_freed()
	if press_use(_target):
		get_viewport().set_input_as_handled()


func _update_target() -> void:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var from: Vector3 = _body.get_aim_origin()
	var direction: Vector3 = _body.get_aim_direction()
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RAY_LENGTH,
		PhysicsLayers.bit(PhysicsLayers.INTERACTABLES) | PhysicsLayers.bit(PhysicsLayers.PROPS)
		| PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.CARTS))
	query.collide_with_areas = true
	query.exclude = [_body.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	var collider: Node3D = hit.get("collider") as Node3D if not hit.is_empty() else null
	if not _is_usable(collider):
		var assisted: Node3D = _aim_assist(space, from, direction, hit)
		if assisted != null:
			collider = assisted
	if collider != _target:
		_target = collider
		target_changed.emit(_target)


## Something the use key can do anything with: it has an Interactable, or it's a prop or a cart.
func _is_usable(collider: Node3D) -> bool:
	if collider == null:
		return false
	if Interactable.of(collider) != null:
		return true
	var body := collider as CollisionObject3D
	var loose: int = PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.CARTS)
	return body != null and (body.collision_layer & loose) != 0


## NEW 2026-10-30: a small ball swept along the look line finds a usable thing just beside the crosshair,
## stopping at the wall the thin ray hit and never seeing through one. Null if none.
func _aim_assist(space: PhysicsDirectSpaceState3D, from: Vector3, direction: Vector3, ray_hit: Dictionary) -> Node3D:
	var radius: float = _tuning().aim_assist_radius
	if radius <= 0.0:
		return null
	if _assist_shape == null:
		_assist_shape = SphereShape3D.new()
	_assist_shape.radius = radius
	var length: float = RAY_LENGTH
	if not ray_hit.is_empty():
		length = minf(length, from.distance_to(ray_hit["position"] as Vector3) + radius)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _assist_shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = direction * length
	query.collision_mask = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES) | PhysicsLayers.bit(PhysicsLayers.PROPS) \
		| PhysicsLayers.bit(PhysicsLayers.CARTS)
	query.collide_with_areas = true
	query.exclude = [_body.get_rid()]
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return null
	query.transform = Transform3D(Basis.IDENTITY, from + query.motion * fractions[1])
	query.motion = Vector3.ZERO
	var info: Dictionary = space.get_rest_info(query)
	if info.is_empty():
		return null
	var collider_id: int = info["collider_id"]
	var collider := instance_from_id(collider_id) as Node3D
	if not _is_usable(collider):
		return null
	# Nothing solid between your eyes and it.
	var sight := PhysicsRayQueryParameters3D.create(from, info["point"] as Vector3, PhysicsLayers.bit(PhysicsLayers.WORLD))
	var excluded: Array[RID] = [_body.get_rid()]
	if collider is CollisionObject3D:
		excluded.append((collider as CollisionObject3D).get_rid())
	sight.exclude = excluded
	if not space.intersect_ray(sight).is_empty():
		return null
	return collider


## Hold-to-use: count while the key is held on the same target; send once when full.
func _update_hold(delta: float) -> void:
	var interactable: Interactable = Interactable.of(_target) if _target != null else null
	var holding: bool = Input.is_action_pressed(InputActions.USE) and interactable != null \
		and interactable.hold_seconds > 0.0 and not interactable.continuous and interactable.enabled
	if not holding or _target != _hold_target:
		_hold_target = _target if holding else null
		_hold_time = 0.0
		_hold_sent = false
		if not holding:
			return
	_hold_time += delta
	if not _hold_sent and _hold_time >= interactable.hold_seconds:
		_hold_sent = true
		request_use(_target, _hold_time)


## Continuous use (NEW 2026-10-30): holding the key on a continuous object, in reach, keeps it going.
func _update_continuous() -> void:
	var interactable: Interactable = Interactable.of(_target) if _target != null else null
	var holding: bool = Input.is_action_pressed(InputActions.USE) and interactable != null \
		and interactable.continuous and interactable.enabled and _in_reach(interactable, 0.0)
	if holding:
		set_continuous_use(_target)
		_continuous_by_key = true
	elif _continuous_by_key:
		# Only let go of what the key started (code and tests can hold things too).
		set_continuous_use(null)
		_continuous_by_key = false


func _in_reach(interactable: Interactable, tolerance: float) -> bool:
	if interactable.get_anchor() == null or _body == null:
		return false
	return _body.get_aim_origin().distance_to(interactable.get_use_position()) <= interactable.max_distance + tolerance


## Host: one physics step of continuous use, while it's still in reach and allowed.
func _tick_continuous(delta: float) -> void:
	if _continuous_target == null:
		return
	var interactable: Interactable = Interactable.of(_continuous_target) if is_instance_valid(_continuous_target) else null
	if interactable == null or not _continuous_target.is_inside_tree() \
			or not _in_reach(interactable, HOST_DISTANCE_TOLERANCE) or not interactable.allows(_body.player_id):
		_stop_continuous()
		return
	interactable.use_tick.emit(_body.player_id, delta)


## Host: this player stops using their continuous object (if any).
func _stop_continuous() -> void:
	if _continuous_target == null:
		return
	var interactable: Interactable = Interactable.of(_continuous_target) if is_instance_valid(_continuous_target) else null
	_continuous_target = null
	if interactable != null and _body != null:
		interactable.use_stopped.emit(_body.player_id)


## Host: tell this player they can't use it (the buzz plays on their PC).
func _send_denied() -> void:
	if _body == null:
		return
	if _body.is_local():
		deny()
	else:
		_denied_rpc.rpc_id(_body.get_multiplayer_authority())


## Client -> host: "my player used this". The host checks it's really that player, close enough,
## held long enough, enabled and allowed, then fires used(player_id) on the host only.
@rpc("any_peer", "call_local", "reliable")
func _request_use_rpc(target_path: NodePath, held_seconds: float) -> void:
	if not is_inside_tree():
		return
	if not multiplayer.is_server() or _body == null:
		return
	if multiplayer.get_remote_sender_id() != _body.get_multiplayer_authority():
		return
	var target: Node = _multiplayer_root().get_node_or_null(target_path)
	var interactable: Interactable = Interactable.of(target) if target != null else null
	if interactable == null:
		return
	if not _in_reach(interactable, HOST_DISTANCE_TOLERANCE):
		return
	if held_seconds < interactable.hold_seconds:
		return
	if not interactable.allows(_body.player_id):
		interactable.refused.emit(_body.player_id)
		_send_denied()
		return
	interactable.used.emit(_body.player_id)


## NEW 2026-10-30. Client -> host: "my player is holding use on this continuous object" (empty path: let go).
@rpc("any_peer", "call_local", "reliable")
func _continuous_rpc(target_path: NodePath) -> void:
	if not is_inside_tree() or not multiplayer.is_server() or _body == null:
		return
	if multiplayer.get_remote_sender_id() != _body.get_multiplayer_authority():
		return
	_stop_continuous()
	if target_path.is_empty():
		return
	var target := _multiplayer_root().get_node_or_null(target_path) as Node3D
	var interactable: Interactable = Interactable.of(target) if target != null else null
	if interactable == null or not interactable.continuous or not _in_reach(interactable, HOST_DISTANCE_TOLERANCE):
		return
	if not interactable.allows(_body.player_id):
		interactable.refused.emit(_body.player_id)
		_send_denied()
		return
	_continuous_target = target
	interactable.use_started.emit(_body.player_id)


## NEW 2026-10-30. Host -> the player's PC: the host said no; play the buzz.
@rpc("any_peer", "call_remote", "reliable")
func _denied_rpc() -> void:
	if multiplayer.get_remote_sender_id() == 1:
		deny()
