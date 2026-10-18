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


func _ready() -> void:
	name = NODE_NAME
	_body = get_parent() as PlayerCharacter


## What the local player is looking at (a collision object), or null.
func get_target() -> Node3D:
	return _target


## "Press E to ..." text for the current target, or "" for nothing to do.
func get_prompt() -> String:
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
## Used by the key and by tests. Returns true if something took the press.
func press_use(target: Node3D) -> bool:
	for entry: Dictionary in _handlers:
		var handler: Callable = entry["callable"]
		var handled: bool = handler.call(target)
		if handled:
			return true
	var interactable: Interactable = Interactable.of(target) if target != null else null
	if interactable == null or interactable.hold_seconds > 0.0:
		return false
	request_use(target, 0.0)
	return true


## Asks the host to use a target's Interactable (it checks everything again).
func request_use(target: Node3D, held_seconds: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	_request_use_rpc.rpc_id(1, _multiplayer_root().get_path_to(target), held_seconds)


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
	if _body == null or not _body.is_local():
		return
	_update_target()
	_update_hold(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _body == null or not _body.is_local() or not event.is_action_pressed(InputActions.USE):
		return
	if press_use(_target):
		get_viewport().set_input_as_handled()


func _update_target() -> void:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var from: Vector3 = _body.get_aim_origin()
	var query := PhysicsRayQueryParameters3D.create(from, from + _body.get_aim_direction() * RAY_LENGTH,
		PhysicsLayers.bit(PhysicsLayers.INTERACTABLES) | PhysicsLayers.bit(PhysicsLayers.PROPS)
		| PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.CARTS))
	query.collide_with_areas = true
	query.exclude = [_body.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	var collider: Node3D = hit.get("collider") as Node3D if not hit.is_empty() else null
	if collider != _target:
		_target = collider
		target_changed.emit(_target)


## Hold-to-use: count while the key is held on the same target; send once when full.
func _update_hold(delta: float) -> void:
	var interactable: Interactable = Interactable.of(_target) if _target != null else null
	var holding: bool = Input.is_action_pressed(InputActions.USE) and interactable != null \
		and interactable.hold_seconds > 0.0 and interactable.enabled
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


func _in_reach(interactable: Interactable, tolerance: float) -> bool:
	var anchor: Node3D = interactable.get_anchor()
	if anchor == null or _body == null:
		return false
	return _body.get_aim_origin().distance_to(anchor.global_position) <= interactable.max_distance + tolerance


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
		return
	interactable.used.emit(_body.player_id)
