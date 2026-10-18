class_name PropSpawner
extends Node3D
## Put one in every level (Break Room, floors, test scenes). Props spawned here are children of this
## node and exist on every PC (a MultiplayerSpawner handles that, including late joiners).
## The host simulates them and sends snapshots of the moving ones; it also decides who holds what.
## Other systems use the Props autoload, which talks to the current level's PropSpawner.
##
## Grab rules (decided by Zachary, 2026-10-17):
## - normal props: the newest grab takes it (the old holder lets go);
## - heavy props (above grab_max_mass, any weight): every grab joins the lift, and each holder takes
##   heavy_lift_per_holder kg off its weight (more helpers = faster). Nothing is too heavy to move.

const REFUSE_TOO_FAR: String = "Too far away"
## A pusher must be this close to the prop (metres, body to prop centre).
const PUSH_REACH: float = 3.0
## Knock-on: one of the asker's props must be this close to the prop it wants (metres, centre to centre;
## generous because the host's copy of the asker's prop is a little behind).
const KNOCK_ON_REACH: float = 3.0
## How fast the clock offset estimate may creep later (ms per ms), to follow a growing delay.
const CLOCK_CREEP: float = 0.001
## Extra reach the host allows for network delay and the size of the prop (metres).
const REACH_TOLERANCE: float = 1.0

var _net: NetService
var _config: GameConfig
var _spawner: MultiplayerSpawner
var _props: Dictionary[int, NetProp] = {}
var _next_net_id: int = 1
var _near_timer: float = 0.0
var _far_timer: float = 0.0
var _peer_seen: MultiplayerPeer
## Clients: estimate of (local clock - host clock), for showing props at the right moment.
var _clock_offset_msec: float = 0.0
var _has_clock: bool = false
var _last_clock_msec: int = 0
## A player's PC: timer for sending the props it runs.
var _owned_timer: float = 0.0
## Host: when each prop last changed physics owner (msec), and hand-overs waiting for the cooldown.
var _owner_changed_msec: Dictionary[int, int] = {}
var _pending_owner: Dictionary[int, int] = {}


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
	_peer_seen = multiplayer.multiplayer_peer
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


## Host: pushes a prop (on whichever PC runs its physics).
func apply_impulse(prop: NetProp, impulse: Vector3) -> void:
	if multiplayer.is_server() and prop != null:
		_impulse_rpc.rpc(prop.net_id, impulse)


## Host: who may hold this prop if `player_id` grabs it now. Returns the new holder list, or an
## empty list plus a reason in `refusal` (refusal[0]) when the grab is refused.
@warning_ignore("unused_parameter")
func decide_grab(prop: NetProp, player_id: int, refusal: Array[String]) -> Array[int]:
	var holders: Array[int] = prop.get_holder_ids()
	if prop.get_true_mass() <= _config.grab_max_mass:
		return [player_id] as Array[int]
	# Heavy: everyone who grabs helps (no limit).
	if not holders.has(player_id):
		holders.append(player_id)
	return holders


## Host: everyone lets go of this prop (it got stuck, or fell out of the world).
func release_all(prop: NetProp) -> void:
	if multiplayer.is_server() and prop.is_held():
		_set_holders.rpc(prop.net_id, [], prop.last_holder_id, false)


## The PC running a held prop says it got stuck: everyone lets go.
func report_stuck(prop: NetProp) -> void:
	if multiplayer.is_server():
		release_all(prop)
	else:
		_report_stuck_rpc.rpc_id(1, prop.net_id)


## The moving props the host would send right now (near: props close to a player).
## Sleeping props are never sent: they cost nothing.
func get_snapshot_batch(near: bool) -> Array:
	var batch: Array = []
	for prop: NetProp in _props.values():
		if not is_instance_valid(prop):
			continue
		# Props run by a player's PC are always sent on (the host's copy just follows them).
		var awake: bool = not prop.sleeping or prop.is_held() or prop.is_attached() or prop.get_owner_peer() != 1
		if awake and _is_near_a_player(prop) == near:
			batch.append([prop.net_id, prop.global_position, prop.global_basis.get_rotation_quaternion(),
				prop.get_estimated_velocity(), prop.get_owner_sequence()])
	return batch


# --- Grabbing (called by GrabController on the PC that grabs) ---------------------------------

func request_grab(prop: NetProp) -> void:
	_request_grab_rpc.rpc_id(1, prop.net_id)


func request_release(prop: NetProp, throw_direction: Vector3) -> void:
	_request_release_rpc.rpc_id(1, prop.net_id, throw_direction)


## Walking into a prop's side: if this PC runs it, push it now; otherwise ask the host (which
## usually hands the prop to us, so the next pushes are instant).
func request_push(prop: NetProp, player_id: int, direction: Vector3, speed: float) -> void:
	if prop.is_simulated_here():
		prop.add_push(player_id, direction, speed)
	else:
		_push_rpc.rpc_id(1, prop.net_id, direction, speed)


func send_hold_point(prop: NetProp, player_id: int, point: Vector3, yaw: float) -> void:
	if prop.is_simulated_here():
		prop.set_hold_target(player_id, point, yaw)
	elif not multiplayer.is_server():
		_hold_point_rpc.rpc_id(1, prop.net_id, point, yaw)
	# (On the host while another PC still runs it, e.g. during the hand-over cooldown: nothing to do.)


@rpc("any_peer", "call_local", "reliable")
func _request_grab_rpc(net_id: int) -> void:
	if not is_inside_tree():
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var prop: NetProp = get_prop(net_id)
	var body: PlayerCharacter = body_of_peer(sender)
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
	# One holder: their PC runs it (no delay for them). Several: the host does.
	hand_to(prop, sender if holders.size() == 1 else 1)


@rpc("any_peer", "call_local", "reliable")
func _request_release_rpc(net_id: int, throw_direction: Vector3) -> void:
	if not is_inside_tree():
		return
	if not multiplayer.is_server():
		return
	var prop: NetProp = get_prop(net_id)
	var body: PlayerCharacter = body_of_peer(multiplayer.get_remote_sender_id())
	if prop == null or body == null or not prop.get_holder_ids().has(body.player_id):
		return
	var was_lifted: bool = prop.is_lifted()
	var thrown: bool = was_lifted and not throw_direction.is_zero_approx()
	var holders: Array[int] = prop.get_holder_ids()
	holders.erase(body.player_id)
	_set_holders.rpc(net_id, holders, body.player_id, thrown)
	# The thrower's PC applies its own throw (it runs the prop); the host only throws what it runs.
	if thrown and prop.is_simulated_here():
		prop.throw_now(throw_direction, throw_strength(prop))
	if holders.size() == 1:
		hand_to(prop, peer_of_player(holders[0]))


@rpc("any_peer", "call_local", "unreliable_ordered")
func _push_rpc(net_id: int, direction: Vector3, speed: float) -> void:
	if not is_inside_tree():
		return
	if not multiplayer.is_server():
		return
	var prop: NetProp = get_prop(net_id)
	var body: PlayerCharacter = body_of_peer(multiplayer.get_remote_sender_id())
	if prop == null or body == null:
		return
	# Only players right next to it, and no faster than anyone can walk.
	if body.global_position.distance_to(prop.global_position) > PUSH_REACH:
		return
	var fastest: float = body.tuning.sprint_speed * body.get_movement().get_speed_multiplier()
	if prop.get_owner_peer() == 1 and not prop.is_held() and multiplayer.get_remote_sender_id() != 1:
		# Hand it to the pusher's PC so their pushes are instant from now on.
		hand_to(prop, multiplayer.get_remote_sender_id())
	# Still ours (the hand-over may be waiting for its cooldown): push it here meanwhile.
	if prop.is_simulated_here():
		prop.add_push(body.player_id, direction, clampf(speed, 0.0, fastest))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _hold_point_rpc(net_id: int, point: Vector3, yaw: float) -> void:
	if not is_inside_tree():
		return
	if not multiplayer.is_server():
		return
	var prop: NetProp = get_prop(net_id)
	var body: PlayerCharacter = body_of_peer(multiplayer.get_remote_sender_id())
	if prop != null and body != null and prop.is_simulated_here():
		prop.set_hold_target(body.player_id, point, yaw)


## Host -> everyone: who holds this prop now. `thrown` = the last holder threw it.
## (Plain Array: typed arrays don't survive the network.)
@rpc("authority", "call_local", "reliable")
func _set_holders(net_id: int, holder_list: Array, last_holder: int, thrown: bool) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if prop == null:
		return
	var holders: Array[int] = []
	for holder: Variant in holder_list:
		var holder_id: int = holder
		holders.append(holder_id)
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
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if prop != null:
		Props.grab_refused.emit(prop, reason)


# --- Physics ownership (approach B) -----------------------------------------------------------

## How hard a throw is: throw_impulse per kg, counting at most grab_max_mass kg.
func throw_strength(prop: NetProp) -> float:
	# Half-Life 2's rule: the force grows with weight up to 15 kg (factor 0.5 to 4), so light things
	# fly fast and far and heavy things only go a little way.
	var factor: float = remap(clampf(prop.get_true_mass(), 0.5, 15.0), 0.5, 15.0, 0.5, 4.0)
	return _config.throw_force * factor


## The network peer of a player in this game, or 0.
func peer_of_player(player_id: int) -> int:
	var body: PlayerCharacter = get_body_of_player(player_id)
	return body.get_multiplayer_authority() if body != null else 0


## Host: let `peer_id`'s PC run this prop's physics (1 = the host itself). If it changed hands less
## than prop_owner_cooldown_msec ago, the hand-over waits until then (no ping-pong between PCs when
## two players keep grabbing the same prop).
func hand_to(prop: NetProp, peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	if prop.get_owner_peer() == peer_id:
		_pending_owner.erase(prop.net_id)
		return
	var changed_at: int = _owner_changed_msec.get(prop.net_id, -_config.prop_owner_cooldown_msec)
	var since: int = Time.get_ticks_msec() - changed_at
	if since < _config.prop_owner_cooldown_msec:
		_pending_owner[prop.net_id] = peer_id
		return
	_pending_owner.erase(prop.net_id)
	_owner_changed_msec[prop.net_id] = Time.get_ticks_msec()
	_broadcast_owner(prop, peer_id, prop.global_transform, prop.get_estimated_velocity(), prop.angular_velocity)


## Host: hand-overs that were waiting for the cooldown.
func _apply_pending_owners() -> void:
	for net_id: int in _pending_owner.keys():
		var prop: NetProp = get_prop(net_id)
		if prop == null:
			_pending_owner.erase(net_id)
			continue
		hand_to(prop, _pending_owner[net_id])


## A player's PC: a prop it runs bumped into `prop`; ask to run that one too (knock-on ownership).
func request_knock_on(prop: NetProp) -> void:
	_request_knock_on_rpc.rpc_id(1, prop.net_id)


## Player's PC -> host: "my prop hit this loose one, let me run it". Granted if it's loose, the host
## runs it, and one of the sender's props is right next to it.
@rpc("any_peer", "call_remote", "reliable")
func _request_knock_on_rpc(net_id: int) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or prop == null or prop.get_owner_peer() != 1 or prop.is_held() or prop.is_attached():
		return
	for other: NetProp in get_props():
		if other.get_owner_peer() == sender and other.global_position.distance_to(prop.global_position) <= KNOCK_ON_REACH:
			hand_to(prop, sender)
			return


## Host: a new physics owner, with the next ownership number (Glenn Fiedler's "ownership sequence"),
## so every PC can ignore late updates from the previous owner.
func _broadcast_owner(prop: NetProp, peer_id: int, start: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	_set_owner.rpc(prop.net_id, peer_id, prop.get_owner_sequence() + 1, start, velocity, spin)


## Host -> everyone: who runs this prop's physics now (and its ownership number), from this state.
@rpc("authority", "call_local", "reliable")
func _set_owner(net_id: int, peer_id: int, sequence: int, start: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if prop != null:
		if multiplayer.is_server():
			_owner_changed_msec[net_id] = Time.get_ticks_msec()
		prop.apply_owner(peer_id, sequence, start, velocity, spin)


## Owner (a player's PC) -> host: done with it (settled, nobody touching it); host takes it back.
@rpc("any_peer", "call_local", "reliable")
func _return_owner_rpc(net_id: int, sequence: int, last: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if multiplayer.is_server() and prop != null and multiplayer.get_remote_sender_id() == prop.get_owner_peer() \
			and sequence == prop.get_owner_sequence():
		_broadcast_owner(prop, 1, last, velocity, spin)


## Owner (a player's PC) -> host: where it is now (the host passes it on to everyone else).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _owner_snapshot_rpc(net_id: int, sequence: int, host_msec: int, position_now: Vector3,
		rotation_now: Quaternion, velocity: Vector3) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if multiplayer.is_server() and prop != null and multiplayer.get_remote_sender_id() == prop.get_owner_peer():
		prop.apply_snapshot(sequence, host_msec, position_now, rotation_now, velocity)


## Host -> everyone: push this prop (only the PC that runs it does).
@rpc("authority", "call_local", "reliable")
func _impulse_rpc(net_id: int, impulse: Vector3) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if prop != null and prop.is_simulated_here():
		prop.apply_central_impulse(impulse)


## Owner -> host: the held prop got stuck.
@rpc("any_peer", "call_local", "reliable")
func _report_stuck_rpc(net_id: int) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if multiplayer.is_server() and prop != null and multiplayer.get_remote_sender_id() == prop.get_owner_peer():
		release_all(prop)


## A player's PC: send the props it runs to the host, and hand back the ones it's done with.
func _run_owned_props(delta: float) -> void:
	_owned_timer += delta
	var send_now: bool = _owned_timer >= 1.0 / float(maxi(_config.prop_sync_rate_near, 1))
	if send_now:
		_owned_timer = 0.0
	for prop: NetProp in _props.values():
		if not is_instance_valid(prop) or not prop.is_simulated_here():
			continue
		if prop.is_idle_here():
			prop.mark_handback_sent()
			_return_owner_rpc.rpc_id(1, prop.net_id, prop.get_owner_sequence(), prop.global_transform,
				prop.linear_velocity, prop.angular_velocity)
			continue
		if send_now:
			_owner_snapshot_rpc.rpc_id(1, prop.net_id, prop.get_owner_sequence(), get_host_clock_msec(), prop.global_position,
				prop.global_basis.get_rotation_quaternion(), prop.linear_velocity)


# --- Spawning and syncing ---------------------------------------------------------------------

## Runs on every PC (the MultiplayerSpawner replays it for late joiners).
func _make_prop(spawn_data: Variant) -> Node:
	var info: Dictionary = spawn_data
	var prop_id := StringName(str(info["content_id"]))
	var prop_data := ContentRegistry.get_content(prop_id) as PropData
	var prop := prop_data.scene.instantiate() as NetProp
	prop.net_id = info["net_id"]
	prop.name = "Prop%d" % prop.net_id
	prop.content_id = prop_id
	prop.data = prop_data
	prop.extra = info.get("extra", {})
	prop.transform = info["xform"]
	prop.set_spawner(self)
	_props[prop.net_id] = prop
	_next_net_id = maxi(_next_net_id, prop.net_id + 1)
	prop.tree_exiting.connect(_on_prop_exiting.bind(prop.net_id))
	# The spawn data only says where it first appeared; a client asks where it is now.
	if not multiplayer.is_server():
		_request_state_rpc.rpc_id.call_deferred(1, prop.net_id)
	return prop


func _on_prop_exiting(net_id: int) -> void:
	_props.erase(net_id)


## Client -> host: send me this prop's current state (where it is, who runs it, who holds it).
@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc(net_id: int) -> void:
	if not is_inside_tree():
		return
	if not multiplayer.is_server():
		return
	var prop: NetProp = get_prop(net_id)
	if prop == null:
		return
	_prop_state.rpc_id(multiplayer.get_remote_sender_id(), net_id, prop.get_owner_peer(), prop.get_owner_sequence(),
		prop.global_transform, prop.get_estimated_velocity(), prop.angular_velocity, prop.get_holder_ids(),
		prop.last_holder_id)


## Host -> one client: a prop's current state, so props moved before you joined are in the right place.
@rpc("authority", "call_remote", "reliable")
func _prop_state(net_id: int, owner_peer: int, sequence: int, xform: Transform3D, velocity: Vector3, spin: Vector3,
		holder_list: Array, last_holder: int) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if prop == null:
		return
	prop.apply_join_state(owner_peer, sequence, xform, velocity, spin)
	var holders: Array[int] = []
	for holder: Variant in holder_list:
		var holder_id: int = holder
		holders.append(holder_id)
	prop.apply_holders(holders, last_holder)


func _process(_delta: float) -> void:
	# The connection changed (hosting, joining, leaving): props from the old session are stale.
	if multiplayer.multiplayer_peer != _peer_seen:
		_peer_seen = multiplayer.multiplayer_peer
		_restart_session()


## A new connection: the host spawns its props again so every new client gets them; a client
## drops its copies and waits for the host's.
func _restart_session() -> void:
	_has_clock = false
	var keep: Array[Dictionary] = []
	for prop: NetProp in get_props():
		keep.append({"content_id": prop.content_id, "xform": prop.global_transform, "extra": prop.extra})
		remove_child(prop)
		prop.queue_free()
	_props.clear()
	_next_net_id = 1
	if multiplayer.is_server():
		for entry: Dictionary in keep:
			var content_id: StringName = entry["content_id"]
			var xform: Transform3D = entry["xform"]
			var extra: Dictionary = entry["extra"]
			spawn_prop(content_id, xform, extra)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_run_owned_props(delta)
		return
	_handle_fallen_props()
	_apply_pending_owners()
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
		_receive_snapshots.rpc(Time.get_ticks_msec(), batch)


## The host's clock (milliseconds), as best this PC can tell. On the host, its own clock.
func get_host_clock_msec() -> int:
	if multiplayer.is_server() or not _has_clock:
		return Time.get_ticks_msec()
	return Time.get_ticks_msec() - int(_clock_offset_msec)


## Host -> clients: where the moving props are now, stamped with the host's clock.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_snapshots(host_msec: int, batch: Array) -> void:
	if not is_inside_tree():
		return
	# Clock offset = the smallest (local - host) seen, so network hiccups don't push it later. It
	# creeps up slowly so it can follow if the delay really grows.
	var now: int = Time.get_ticks_msec()
	var sample: float = float(now - host_msec)
	if not _has_clock:
		_clock_offset_msec = sample
		_has_clock = true
	else:
		_clock_offset_msec = minf(_clock_offset_msec + float(now - _last_clock_msec) * CLOCK_CREEP, sample)
	_last_clock_msec = now
	for entry: Array in batch:
		var net_id: int = entry[0]
		var prop: NetProp = get_prop(net_id)
		if prop != null:
			var sequence: int = entry[4]
			var position_now: Vector3 = entry[1]
			var rotation_now: Quaternion = entry[2]
			var velocity: Vector3 = entry[3]
			prop.apply_snapshot(sequence, host_msec, position_now, rotation_now, velocity)


func _is_near_a_player(prop: NetProp) -> bool:
	for body: PlayerCharacter in get_bodies():
		if body.global_position.distance_to(prop.global_position) <= _config.prop_far_distance:
			return true
	return false


## Host: key objects that fell out of the world go back to their last safe resting spot; other
## props that fell out are removed.
func _handle_fallen_props() -> void:
	for prop: NetProp in _props.values():
		if not is_instance_valid(prop) or prop.global_position.y >= _config.out_of_world_y:
			continue
		if prop.data == null or not prop.data.is_key_object:
			despawn(prop)
			continue
		release_all(prop)
		# Back to the host, at its safe spot, for everyone.
		var safe := Transform3D(prop.global_basis, prop.get_safe_position())
		if prop.get_owner_peer() != 1:
			_broadcast_owner(prop, 1, safe, Vector3.ZERO, Vector3.ZERO)
		else:
			prop.linear_velocity = Vector3.ZERO
			prop.angular_velocity = Vector3.ZERO
			prop.global_transform = safe
			prop.reset_physics_interpolation()
		_key_respawned.rpc(prop.net_id)


@rpc("authority", "call_local", "reliable")
func _key_respawned(net_id: int) -> void:
	if not is_inside_tree():
		return
	var prop: NetProp = get_prop(net_id)
	if prop != null:
		EventBus.key_object_respawned.emit(prop)


## Host: players who left let go of what they held, and props their PC ran come back to the host.
func _release_missing_players() -> void:
	# A level being unloaded (e.g. the host left) has no multiplayer any more.
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var present: Array[int] = _net.get_player_ids()
	var peers: PackedInt32Array = multiplayer.get_peers()
	for prop: NetProp in _props.values():
		if not is_instance_valid(prop):
			continue
		if prop.get_owner_peer() != 1 and not peers.has(prop.get_owner_peer()):
			_broadcast_owner(prop, 1, prop.global_transform, Vector3.ZERO, Vector3.ZERO)
		if not prop.is_held():
			continue
		var holders: Array[int] = []
		for holder: int in prop.get_holder_ids():
			if present.has(holder):
				holders.append(holder)
		if holders.size() != prop.get_holder_ids().size():
			_set_holders.rpc(prop.net_id, holders, prop.last_holder_id, false)


## Player bodies that belong to this spawner's game (same multiplayer).
func get_bodies() -> Array[PlayerCharacter]:
	var bodies: Array[PlayerCharacter] = []
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body != null and body.multiplayer == multiplayer and not body.is_queued_for_deletion():
			bodies.append(body)
	return bodies


func body_of_peer(peer_id: int) -> PlayerCharacter:
	for body: PlayerCharacter in get_bodies():
		if body.get_multiplayer_authority() == peer_id:
			return body
	return null


## A player's body in this game. Null if not spawned.
func get_body_of_player(player_id: int) -> PlayerCharacter:
	for body: PlayerCharacter in get_bodies():
		if body.player_id == player_id:
			return body
	return null
