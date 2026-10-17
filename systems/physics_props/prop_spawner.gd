class_name PropSpawner
extends Node3D
## Put one in every level (Break Room, floors, test scenes). Props spawned here are children of this
## node and exist on every PC (a MultiplayerSpawner handles that, including late joiners).
## The host simulates them and sends snapshots of the moving ones; it also decides who holds what.
## Other systems use the Props autoload, which talks to the current level's PropSpawner.
##
## Grab rules (decided by Zachary, 2026-10-17):
## - normal props: the newest grab takes it (the old holder lets go);
## - heavy props (above grab_max_mass, up to two_player_lift_max_mass): a second grab joins the lift,
##   and it only lifts with two holders; a third grab is refused;
## - heavier than that: refused.

const REFUSE_TOO_HEAVY: String = "Too heavy"
const REFUSE_FULL: String = "Already two people lifting"
const REFUSE_TOO_FAR: String = "Too far away"
## Extra reach the host allows for network delay and the size of the prop (metres).
const REACH_TOLERANCE: float = 1.0

var _net: NetService
var _config: GameConfig
var _spawner: MultiplayerSpawner
var _props: Dictionary[int, NetProp] = {}
var _next_net_id: int = 1
var _near_timer: float = 0.0
var _far_timer: float = 0.0


## For tests only: a different Net and config. Call before adding the node to the tree.
func use_net(net: NetService, config: GameConfig) -> void:
	_net = net
	_config = config


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "PropReplicator"
	add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(self)
	_spawner.spawn_function = _make_prop
	_net.roster_changed.connect(_release_missing_players)
	Props.register_spawner(self)


func _exit_tree() -> void:
	Props.unregister_spawner(self)


func get_config() -> GameConfig:
	return _config


## Host: spawns a prop from its content id for everyone.
func spawn_prop(prop_id: StringName, xform: Transform3D, extra: Dictionary = {}) -> NetProp:
	if not multiplayer.is_server():
		push_error("PropSpawner.spawn_prop: only the host spawns props.")
		return null
	var prop_data := ContentRegistry.get_content(prop_id) as PropData
	if prop_data == null or prop_data.scene == null:
		push_error("PropSpawner.spawn_prop: no prop called '%s' (or it has no scene)." % prop_id)
		return null
	var net_id: int = _next_net_id
	_next_net_id += 1
	return _spawner.spawn({"content_id": prop_id, "net_id": net_id, "xform": xform, "extra": extra}) as NetProp


## Host: removes a prop for everyone.
func despawn(prop: NetProp) -> void:
	if multiplayer.is_server() and prop != null:
		_props.erase(prop.net_id)
		prop.queue_free()


func get_prop(net_id: int) -> NetProp:
	var prop: NetProp = _props.get(net_id)
	return prop if prop != null and is_instance_valid(prop) else null


## Every prop here, or only one kind.
func get_props(content_id: StringName = &"") -> Array[NetProp]:
	var result: Array[NetProp] = []
	for prop: NetProp in _props.values():
		if is_instance_valid(prop) and (content_id == &"" or prop.content_id == content_id):
			result.append(prop)
	return result


## Props of one kind that nobody holds and that aren't in a cart or machine.
func get_loose_count(content_id: StringName) -> int:
	var count: int = 0
	for prop: NetProp in get_props(content_id):
		if not prop.is_held() and not prop.is_attached():
			count += 1
	return count


## Host: pushes a prop.
func apply_impulse(prop: NetProp, impulse: Vector3) -> void:
	if multiplayer.is_server() and prop != null:
		prop.apply_central_impulse(impulse)


## Host: who may hold this prop if `player_id` grabs it now. Returns the new holder list, or an
## empty list plus a reason in `refusal` (refusal[0]) when the grab is refused.
func decide_grab(prop: NetProp, player_id: int, refusal: Array[String]) -> Array[int]:
	var holders: Array[int] = prop.get_holder_ids()
	if prop.mass > _config.two_player_lift_max_mass:
		refusal.append(REFUSE_TOO_HEAVY)
		return []
	if prop.mass <= _config.grab_max_mass:
		return [player_id] as Array[int]
	if holders.has(player_id):
		return holders
	if holders.size() >= 2:
		refusal.append(REFUSE_FULL)
		return []
	holders.append(player_id)
	return holders


## Host: everyone lets go of this prop (it got stuck, or fell out of the world).
func release_all(prop: NetProp) -> void:
	if multiplayer.is_server() and prop.is_held():
		_set_holders.rpc(prop.net_id, [], prop.last_holder_id, false)


## The moving props the host would send right now (near: props close to a player).
## Sleeping props are never sent: they cost nothing.
func get_snapshot_batch(near: bool) -> Array:
	var batch: Array = []
	for prop: NetProp in _props.values():
		if not is_instance_valid(prop):
			continue
		var awake: bool = not prop.sleeping or prop.is_held() or prop.is_attached()
		if awake and _is_near_a_player(prop) == near:
			batch.append([prop.net_id, prop.global_position, prop.global_basis.get_rotation_quaternion()])
	return batch


# --- Grabbing (called by GrabController on the PC that grabs) ---------------------------------

func request_grab(prop: NetProp) -> void:
	_request_grab_rpc.rpc_id(1, prop.net_id)


func request_release(prop: NetProp, throw_direction: Vector3) -> void:
	_request_release_rpc.rpc_id(1, prop.net_id, throw_direction)


func send_hold_point(prop: NetProp, player_id: int, point: Vector3) -> void:
	if multiplayer.is_server():
		prop.set_hold_target(player_id, point)
	else:
		_hold_point_rpc.rpc_id(1, prop.net_id, point)


@rpc("any_peer", "call_local", "reliable")
func _request_grab_rpc(net_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var prop: NetProp = get_prop(net_id)
	var body: PlayerCharacter = _body_of_peer(sender)
	if prop == null or body == null:
		return
	if body.get_aim_origin().distance_to(prop.global_position) > _config.grab_reach + REACH_TOLERANCE:
		_grab_refused.rpc_id(sender, net_id, REFUSE_TOO_FAR)
		return
	var refusal: Array[String] = []
	var holders: Array[int] = decide_grab(prop, body.player_id, refusal)
	if not refusal.is_empty():
		_grab_refused.rpc_id(sender, net_id, refusal[0])
		return
	_set_holders.rpc(net_id, holders, body.player_id, false)


@rpc("any_peer", "call_local", "reliable")
func _request_release_rpc(net_id: int, throw_direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var prop: NetProp = get_prop(net_id)
	var body: PlayerCharacter = _body_of_peer(multiplayer.get_remote_sender_id())
	if prop == null or body == null or not prop.get_holder_ids().has(body.player_id):
		return
	var was_lifted: bool = prop.is_lifted()
	var thrown: bool = was_lifted and not throw_direction.is_zero_approx()
	var holders: Array[int] = prop.get_holder_ids()
	holders.erase(body.player_id)
	_set_holders.rpc(net_id, holders, body.player_id, thrown)
	if thrown:
		var strength: float = _config.throw_impulse * minf(prop.mass, _config.grab_max_mass)
		prop.apply_central_impulse(throw_direction.normalized() * strength)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _hold_point_rpc(net_id: int, point: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var prop: NetProp = get_prop(net_id)
	var body: PlayerCharacter = _body_of_peer(multiplayer.get_remote_sender_id())
	if prop != null and body != null:
		prop.set_hold_target(body.player_id, point)


## Host -> everyone: who holds this prop now. `thrown` = the last holder threw it.
## (Plain Array: typed arrays don't survive the network.)
@rpc("authority", "call_local", "reliable")
func _set_holders(net_id: int, holder_list: Array, last_holder: int, thrown: bool) -> void:
	var prop: NetProp = get_prop(net_id)
	if prop == null:
		return
	var holders: Array[int] = []
	for holder: Variant in holder_list:
		holders.append(int(holder))
	var before: Array[int] = prop.get_holder_ids()
	prop.apply_holders(holders, last_holder)
	for player_id: int in holders:
		if not before.has(player_id):
			EventBus.prop_grabbed.emit(player_id, prop)
	for player_id: int in before:
		if not holders.has(player_id):
			EventBus.prop_released.emit(player_id, prop, thrown and player_id == last_holder)


## Host -> one client: your grab was refused (the GrabController snaps the prop back).
@rpc("authority", "call_local", "reliable")
func _grab_refused(net_id: int, reason: String) -> void:
	var prop: NetProp = get_prop(net_id)
	if prop != null:
		Props.grab_refused.emit(prop, reason)


# --- Spawning and syncing ---------------------------------------------------------------------

## Runs on every PC (the MultiplayerSpawner replays it for late joiners).
func _make_prop(spawn_data: Variant) -> Node:
	var info: Dictionary = spawn_data
	var prop_id := StringName(str(info["content_id"]))
	var prop_data := ContentRegistry.get_content(prop_id) as PropData
	var prop := prop_data.scene.instantiate() as NetProp
	prop.net_id = int(info["net_id"])
	prop.name = "Prop%d" % prop.net_id
	prop.content_id = prop_id
	prop.data = prop_data
	prop.extra = info.get("extra", {})
	prop.transform = info["xform"]
	prop.set_spawner(self)
	_props[prop.net_id] = prop
	_next_net_id = maxi(_next_net_id, prop.net_id + 1)
	prop.tree_exiting.connect(_on_prop_exiting.bind(prop.net_id))
	return prop


func _on_prop_exiting(net_id: int) -> void:
	_props.erase(net_id)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_respawn_fallen_key_objects()
	if not _net.is_online():
		return
	_near_timer += delta
	_far_timer += delta
	if _near_timer >= 1.0 / float(maxi(_config.prop_sync_rate_near, 1)):
		_near_timer = 0.0
		_send_batch(get_snapshot_batch(true))
	if _far_timer >= 1.0 / float(maxi(_config.prop_sync_rate_far, 1)):
		_far_timer = 0.0
		_send_batch(get_snapshot_batch(false))


func _send_batch(batch: Array) -> void:
	if not batch.is_empty():
		_receive_snapshots.rpc(batch)


## Host -> clients: where the moving props are now.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_snapshots(batch: Array) -> void:
	for entry: Array in batch:
		var prop: NetProp = get_prop(int(entry[0]))
		if prop != null:
			prop.apply_snapshot(entry[1], entry[2])


func _is_near_a_player(prop: NetProp) -> bool:
	for body: PlayerCharacter in _bodies():
		if body.global_position.distance_to(prop.global_position) <= _config.prop_far_distance:
			return true
	return false


## Host: key objects that fell out of the world go back to their last safe resting spot.
func _respawn_fallen_key_objects() -> void:
	for prop: NetProp in _props.values():
		if not is_instance_valid(prop) or prop.data == null or not prop.data.is_key_object:
			continue
		if prop.global_position.y < _config.out_of_world_y:
			release_all(prop)
			prop.linear_velocity = Vector3.ZERO
			prop.angular_velocity = Vector3.ZERO
			prop.global_position = prop.get_safe_position()
			_key_respawned.rpc(prop.net_id)


@rpc("authority", "call_local", "reliable")
func _key_respawned(net_id: int) -> void:
	var prop: NetProp = get_prop(net_id)
	if prop != null:
		EventBus.key_object_respawned.emit(prop)


## Host: players who left let go of what they held.
func _release_missing_players() -> void:
	if not multiplayer.is_server():
		return
	var present: Array[int] = _net.get_player_ids()
	for prop: NetProp in _props.values():
		if not is_instance_valid(prop) or not prop.is_held():
			continue
		var holders: Array[int] = []
		for holder: int in prop.get_holder_ids():
			if present.has(holder):
				holders.append(holder)
		if holders.size() != prop.get_holder_ids().size():
			_set_holders.rpc(prop.net_id, holders, prop.last_holder_id, false)


## Player bodies that belong to this spawner's game (same multiplayer).
func _bodies() -> Array[PlayerCharacter]:
	var bodies: Array[PlayerCharacter] = []
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body != null and body.multiplayer == multiplayer and not body.is_queued_for_deletion():
			bodies.append(body)
	return bodies


func _body_of_peer(peer_id: int) -> PlayerCharacter:
	for body: PlayerCharacter in _bodies():
		if body.get_multiplayer_authority() == peer_id:
			return body
	return null
