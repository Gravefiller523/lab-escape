class_name NetProp
extends RigidBody3D
## Root of every prop scene (crates, gems, meat, lift parts...). Spawned only by a PropSpawner.
##
## One PC runs each prop's physics: its "physics owner". Normally that is the host. When a player
## picks up or pushes a prop, the host hands its physics to that player's PC (approach B), so it
## reacts with no delay for them; their PC sends where it is to the host, which passes it on.
## When they let go and it settles, the owner hands it back to the host. Heavy props held by several
## players stay with the host. Every other PC's copy is frozen and glides between snapshots.

signal hold_changed()

## How hard the hold spring pulls (per metre, per kg) and how much it damps.
const HOLD_STIFFNESS: float = 150.0
const HOLD_DAMPING: float = 22.0
## A held prop that stays further than hold_break_distance from its hold point this long is dropped.
const HOLD_BREAK_SECONDS: float = 0.4
## How quickly copies catch up with snapshots, and when they jump instead.
const SNAPSHOT_SMOOTHING: float = 40.0
const SNAPSHOT_SNAP_DISTANCE: float = 3.0
## A resting spot only counts as safe this far above the out-of-world height.
const SAFE_HEIGHT_MARGIN: float = 5.0
## A push counts for this long after the last report (milliseconds), so pushes don't flicker.
const PUSH_MEMORY_MSEC: int = 250
## Pushed props move a little slower than the pusher, so the pusher stays pressed against them.
const PUSH_SPEED_FACTOR: float = 0.9
## Snapshots kept per prop.
const MAX_SNAPSHOTS: int = 12
## A player's PC gives a prop back to the host after nobody has touched it for this long
## (milliseconds) and it has stopped moving.
const OWNER_IDLE_MSEC: int = 800
## "Stopped moving" for handing back (m/s).
const SETTLED_SPEED: float = 0.15
## Followers carry a late prop along its last speed for at most this long (seconds).
const MAX_EXTRAPOLATION_SECONDS: float = 0.2
## Contacts a prop reports per frame (for knock-on ownership).
const MAX_CONTACTS: int = 4
## Half-Life 2 numbers: held props weigh 1 kg (so they push gently), spin is damped while held, the
## hold turns at most 3600 degrees a second, and a dropped prop spins at most 720 degrees a second.
const HELD_MASS: float = 1.0
const HELD_ANGULAR_DAMP: float = 10.0
const HOLD_MAX_SPIN: float = 62.8
const RELEASE_MAX_SPIN: float = 12.6
## A thrown prop gets up to this much random spin (radians a second on each axis).
const THROW_SPIN: float = 3.0
## Claiming ahead: look this far ahead in time (seconds), with this much extra room (metres), this
## often (seconds).
const CLAIM_LOOKAHEAD: float = 0.15
const CLAIM_MARGIN: float = 0.15
const CLAIM_INTERVAL: float = 0.05

## Unique per spawned prop, set by the host.
var net_id: int = 0
## Content id, e.g. &"prop_crate".
var content_id: StringName = &""
## The prop's data (mass, key object...). Null for item pickups.
var data: PropData
## Last player who held or threw it (vendors use it to know who pays). 0 = nobody yet.
var last_holder_id: int = 0
## Spawn data (e.g. {"upgrade_id": &"mutation_fly"}).
var extra: Dictionary = {}
## NEW 2026-10-23 (carts branch): the host always runs this prop's physics (never handed to a client). Carts
## use it so the props riding in them follow one copy of the cart.
var keep_on_host: bool = false

var _holders: Array[int] = []
var _spawner: PropSpawner
var _anchor: Node3D
## Fragile props: how fast it was moving one physics step ago (the speed it hit something at).
var _last_speed: float = 0.0
## The network peer whose PC runs this prop's physics (1 = the host).
var _owner_peer: int = 1
## Goes up by one every time the owner changes (Glenn Fiedler's "ownership sequence").
var _owner_seq: int = 0
## Recent snapshots from the owner, oldest first: {"t": host-clock msec, "p": Vector3, "r": Quaternion}.
var _snapshots: Array[Dictionary] = []
## Owner: where each holder wants it (player id -> point).
var _hold_targets: Dictionary[int, Vector3] = {}
## Owner: players pushing it right now (player id -> {time, direction, speed}).
var _pushes: Dictionary[int, Dictionary] = {}
## Owner (a client): when someone last held or pushed it here.
var _last_touch_msec: int = 0
## Host: last place it was resting safely (for key objects).
var _safe_position: Vector3
var _stuck_seconds: float = 0.0
## Owner (a client): we already asked the host to take it back.
var _handback_sent: bool = false
## Props we already asked to take over after bumping into them (net id -> true).
var _knock_requested: Dictionary[int, bool] = {}
## Its real weight (kg). While fully lifted, `mass` is set to HELD_MASS instead.
var _true_mass: float = 1.0
## Cached size for holding (see get_radius); below 0 = not worked out yet.
var _radius: float = -1.0
## Owner (a player's PC): time until the next look-ahead for props to claim.
var _claim_timer: float = 0.0
## Owner: each holder's pick-up angle (relative to their facing) and their current facing.
var _hold_rotation_offsets: Dictionary[int, Quaternion] = {}
var _hold_facings: Dictionary[int, Quaternion] = {}


## The NetProp a node belongs to (the prop itself, or one of its children). Null if none.
static func of(node: Node) -> NetProp:
	var current: Node = node
	while current != null:
		if current is NetProp:
			return current as NetProp
		current = current.get_parent()
	return null


func _ready() -> void:
	collision_layer = PhysicsLayers.bit(PhysicsLayers.PROPS)
	# Not PLAYERS: players bump into props (their mask has PROPS) but can't shove them through walls
	# just by walking into them. Walking into a prop's side pushes it on purpose (see add_push).
	collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS) \
		| PhysicsLayers.bit(PhysicsLayers.CARTS) | PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	if data != null:
		mass = data.mass
	_true_mass = mass
	_safe_position = global_position
	# Light props fly very fast when thrown (a gem ~57 m/s, about 1 m per physics tick) and skipped
	# straight through thin walls. Continuous collision detection checks the whole path each tick.
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not is_simulated_here()
	sleeping_state_changed.connect(_on_sleeping_state_changed)
	body_entered.connect(_on_body_entered)
	max_contacts_reported = MAX_CONTACTS
	_update_contact_monitor()


func is_held() -> bool:
	return not _holders.is_empty()


## Who is holding it (any number for a heavy prop).
func get_holder_ids() -> Array[int]:
	return _holders.duplicate()


## True for heavy props (above grab_max_mass): one person can only drag them slowly; helpers speed it up.
func needs_help() -> bool:
	return _true_mass > _config().grab_max_mass


## How much of its weight its holders carry, 0 to 1. Normal props: 1 while held. Heavy props: each
## holder takes heavy_lift_per_holder kg off (1 holder of an 80 kg crate: 30/80 = 0.375).
func get_support() -> float:
	return support_for(_holders.size())


## How much of its weight `people` holders (or pushers) can move, 0 to 1 (see get_support).
func support_for(people: int) -> float:
	if people <= 0:
		return 0.0
	if not needs_help():
		return 1.0
	return clampf(float(people) * _config().heavy_lift_per_holder / _true_mass, 0.0, 1.0)


## True while it is fully off the ground in its holders' hands.
func is_lifted() -> bool:
	return get_support() >= 1.0


## Snapped into a cart, vendor or lift.
func is_attached() -> bool:
	return _anchor != null


## Host: freeze it and make it follow `anchor` (carts, vendor trays).
func attach_to(anchor: Node3D) -> void:
	if not multiplayer.is_server():
		return
	_anchor = anchor
	freeze = true


## Host: physics back on.
func detach() -> void:
	if not multiplayer.is_server():
		return
	_anchor = null
	freeze = not is_simulated_here()


## The spawner that made this prop.
func get_spawner() -> PropSpawner:
	return _spawner


## The network peer whose PC runs this prop's physics (1 = the host).
func get_owner_peer() -> int:
	return _owner_peer


## The prop's ownership number: goes up every time a different PC starts running it.
func get_owner_sequence() -> int:
	return _owner_seq


## True if this PC runs this prop's physics right now.
func is_simulated_here() -> bool:
	return _owner_peer == multiplayer.get_unique_id()


# --- Internal to physics_props (PropSpawner and GrabController call these; other systems don't) ---

## Where a key object goes back to if it falls out of the world.
func get_safe_position() -> Vector3:
	return _safe_position


func set_spawner(spawner: PropSpawner) -> void:
	_spawner = spawner


func apply_holders(holders: Array[int], last_holder: int) -> void:
	_holders = holders.duplicate()
	if last_holder != 0:
		last_holder_id = last_holder
	for player_id: int in _hold_targets.keys():
		if not _holders.has(player_id):
			_hold_targets.erase(player_id)
			_hold_rotation_offsets.erase(player_id)
			_hold_facings.erase(player_id)
	_apply_held_physics()
	_last_touch_msec = Time.get_ticks_msec()
	hold_changed.emit()


## Held props behave like Half-Life 2's: the holders carry part (or all) of the weight, and a fully
## lifted prop counts as very light (HELD_MASS) so it nudges other things gently instead of
## bulldozing them. Let go: real weight back, and no flinging it by spinning around.
func _apply_held_physics() -> void:
	var was_held_light: bool = not is_equal_approx(mass, _true_mass)
	gravity_scale = 1.0 - get_support()
	angular_damp = HELD_ANGULAR_DAMP if is_held() else 0.0
	mass = HELD_MASS if is_lifted() else _true_mass
	if was_held_light and not is_lifted():
		linear_velocity = linear_velocity.limit_length(_config().held_prop_release_max_speed)
		angular_velocity = angular_velocity.limit_length(RELEASE_MAX_SPIN)


## A new physics owner, starting from this state (sent by the host to every PC).
func apply_owner(peer_id: int, sequence: int, start: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	if sequence < _owner_seq:
		return
	_owner_peer = peer_id
	_owner_seq = sequence
	_snapshots.clear()
	_last_touch_msec = Time.get_ticks_msec()
	if _anchor != null:
		return
	_handback_sent = false
	if is_simulated_here():
		global_transform = start
		reset_physics_interpolation()
		freeze = false
		linear_velocity = velocity
		angular_velocity = spin
		sleeping = false
	else:
		freeze = true
	_update_contact_monitor()


## A copy that just appeared on a client (often a late joiner): jump to where the host says it is now and
## take on its current owner and owner number, so the owner's updates aren't ignored as old ones.
func apply_join_state(owner_peer: int, sequence: int, xform: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	if sequence < _owner_seq:
		return
	global_transform = xform
	reset_physics_interpolation()
	apply_owner(owner_peer, sequence, xform, velocity, spin)


## A snapshot from the owner (position, rotation, speed), stamped with the host's clock (milliseconds).
func apply_snapshot(sequence: int, host_msec: int, position_now: Vector3, rotation_now: Quaternion, velocity: Vector3) -> void:
	# Only updates from the current owner count; a previous owner's late ones are ignored.
	if is_simulated_here() or sequence != _owner_seq:
		return
	var last: Dictionary = _snapshots.back() if not _snapshots.is_empty() else {}
	if not last.is_empty() and host_msec <= _time_of(last):
		return
	_snapshots.append({"t": host_msec, "p": position_now, "r": rotation_now, "v": velocity})
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


## A snapshot's host time (milliseconds).
static func _time_of(snapshot: Dictionary) -> int:
	var msec: int = snapshot["t"]
	return msec


## NEW 2026-10-19: shatters when it hits something at PropData.fragile_break_speed or faster.
func is_fragile() -> bool:
	return data != null and data.fragile_break_speed > 0.0


## Owner: this PC's player let go. Stop pulling it toward their hands right now (don't wait for the
## host to confirm), so a throw flies at full speed instead of being held back for a moment.
func let_go_here(player_id: int) -> void:
	_hold_targets.erase(player_id)
	if _hold_targets.is_empty():
		gravity_scale = 1.0
		angular_damp = 0.0
		mass = _true_mass
		linear_velocity = linear_velocity.limit_length(_config().held_prop_release_max_speed)
		angular_velocity = angular_velocity.limit_length(RELEASE_MAX_SPIN)


## Owner: where a holder wants it now.
## `yaw` is the holder's facing (radians): like Half-Life 2, the prop keeps the angle it was picked up
## at, relative to the holder, so it turns as they turn.
func set_hold_target(player_id: int, target: Vector3, yaw: float) -> void:
	if not _holders.has(player_id):
		return
	_hold_targets[player_id] = target
	var facing := Quaternion(Vector3.UP, yaw)
	if not _hold_rotation_offsets.has(player_id):
		_hold_rotation_offsets[player_id] = facing.inverse() * global_basis.get_rotation_quaternion()
	_hold_facings[player_id] = facing
	_last_touch_msec = Time.get_ticks_msec()


## Owner: turn toward the first holder's facing times the angle it was picked up at (yaw only).
func _steer_rotation(delta: float) -> void:
	if _holders.is_empty() or not _hold_facings.has(_holders[0]):
		return
	var holder: int = _holders[0]
	var wanted: Quaternion = (_hold_facings[holder] as Quaternion) * (_hold_rotation_offsets[holder] as Quaternion)
	var current: Quaternion = global_basis.get_rotation_quaternion()
	var difference: Quaternion = (wanted * current.inverse()).normalized()
	if difference.w < 0.0:
		difference = -difference
	var angle: float = difference.get_angle()
	if angle < 0.001:
		angular_velocity = Vector3.ZERO
		return
	angular_velocity = (difference.get_axis() * angle / maxf(delta, 0.001)).limit_length(HOLD_MAX_SPIN)


## Owner: a player walking into this prop's side pushes it along `direction` at up to `speed` m/s,
## slowed by its weight the same way carrying is (light props move at full speed, heavy ones barely).
func add_push(player_id: int, direction: Vector3, speed: float) -> void:
	_pushes[player_id] = {"time": Time.get_ticks_msec(), "direction": direction, "speed": speed}
	_last_touch_msec = Time.get_ticks_msec()


## How fast it is moving: its real speed where it is simulated, otherwise the owner's last report.
## Used when handing it to another PC, so a flying prop keeps flying.
func get_estimated_velocity() -> Vector3:
	if is_simulated_here() or _snapshots.is_empty():
		return linear_velocity
	return _snapshots.back()["v"]


## Owner (a client): nobody here has touched it for a while and it has settled.
func is_idle_here() -> bool:
	return not _handback_sent and not is_held() and Time.get_ticks_msec() - _last_touch_msec > OWNER_IDLE_MSEC \
		and linear_velocity.length() < SETTLED_SPEED


## Owner (a client): we've asked the host to take it back (don't ask again).
func mark_handback_sent() -> void:
	_handback_sent = true


## Its real weight in kg (while it is lifted, the physics body weighs HELD_MASS instead).
func get_true_mass() -> float:
	return _true_mass


## About how far it reaches from its centre (metres), from its collision shape.
func get_radius() -> float:
	if _radius < 0.0:
		_radius = 0.3
		for child: Node in get_children():
			var shape_node := child as CollisionShape3D
			if shape_node != null and shape_node.shape != null:
				var size: Vector3 = shape_node.shape.get_debug_mesh().get_aabb().size
				_radius = maxf(size.x, maxf(size.y, size.z)) / 2.0
				break
	return _radius


## Owner: throw it (an impulse along `direction`, plus a little random spin like Half-Life 2).
func throw_now(direction: Vector3, strength: float) -> void:
	apply_central_impulse(direction.normalized() * strength)
	angular_velocity += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * THROW_SPIN


## For tests: pretend it weighs this much.
func set_true_mass(kilograms: float) -> void:
	_true_mass = kilograms
	mass = kilograms


func _config() -> GameConfig:
	return _spawner.get_config() if _spawner != null else Config.game


func _physics_process(delta: float) -> void:
	if _anchor != null:
		if is_instance_valid(_anchor):
			global_transform = _anchor.global_transform
		else:
			_anchor = null
			freeze = not is_simulated_here()
		return
	if is_simulated_here():
		_simulate(delta)
		_last_speed = linear_velocity.length()
	else:
		_follow(delta)


## Owner: pull a held prop toward its holders' hold point with a spring, and drop it if stuck.
## Heavy props that aren't fully lifted are pulled more weakly and more slowly (they drag).
func _simulate(delta: float) -> void:
	if not multiplayer.is_server():
		_claim_ahead(delta)
	_apply_pushes()
	var support: float = get_support()
	if support <= 0.0 or _hold_targets.is_empty():
		_stuck_seconds = 0.0
		return
	var target := Vector3.ZERO
	for point: Vector3 in _hold_targets.values():
		target += point
	target /= float(_hold_targets.size())
	var config: GameConfig = _config()
	var offset: Vector3 = target - global_position
	var max_speed: float = config.held_prop_max_speed * support
	if support >= 1.0:
		# Half-Life 2's "shadow control": each physics step, set the speed that gets it exactly to
		# the hold point by the next step (capped). Tight, no spring wobble, and it still collides.
		linear_velocity = (offset / maxf(delta, 0.001)).limit_length(config.held_prop_track_speed)
		_steer_rotation(delta)
	else:
		# Not fully lifted (a heavy prop with too few helpers): a weaker pull, so it drags.
		apply_central_force((offset * HOLD_STIFFNESS - linear_velocity * HOLD_DAMPING) * mass * support)
		if linear_velocity.length() > max_speed:
			linear_velocity = linear_velocity.limit_length(max_speed)
	if support >= 1.0 and offset.length() > config.hold_break_distance:
		_stuck_seconds += delta
		if _stuck_seconds > HOLD_BREAK_SECONDS and _spawner != null:
			_stuck_seconds = 0.0
			_spawner.report_stuck(self)
	else:
		_stuck_seconds = 0.0


## Owner: players walking into its side right now push it. More pushers = faster, like more holders.
func _apply_pushes() -> void:
	if _pushes.is_empty() or is_held():
		_pushes.clear()
		return
	var now: int = Time.get_ticks_msec()
	var direction := Vector3.ZERO
	var speed: float = 0.0
	for player_id: int in _pushes.keys():
		var push: Dictionary = _pushes[player_id]
		var pushed_at: int = push["time"]
		if now - pushed_at > PUSH_MEMORY_MSEC:
			_pushes.erase(player_id)
			continue
		direction += push["direction"] as Vector3
		var push_speed: float = push["speed"]
		speed = maxf(speed, push_speed)
	if _pushes.is_empty() or direction.is_zero_approx():
		return
	direction = Vector3(direction.x, 0.0, direction.z).normalized()
	var wanted: float = speed * PUSH_SPEED_FACTOR * support_for(_pushes.size())
	var current: float = linear_velocity.dot(direction)
	if current < wanted:
		linear_velocity += direction * (wanted - current)
		sleeping = false


## Everyone else: show where the owner had it a moment ago (interpolation delay), gliding between
## two snapshots so movement is even instead of hopping from snapshot to snapshot.
func _follow(delta: float) -> void:
	if _snapshots.is_empty() or _spawner == null:
		return
	# Like Source: at least two update intervals behind, so one late update never causes a stop.
	var delay: int = maxi(_config().prop_interpolation_delay_msec, floori(2000.0 / float(maxi(_config().prop_sync_rate_near, 1))))
	var render_msec: int = _spawner.get_host_clock_msec() - delay
	# Past the newest snapshot (it's late): carry on along its last known speed for a moment.
	var newest: Dictionary = _snapshots.back()
	var ahead_seconds: float = clampf(float(render_msec - _time_of(newest)) / 1000.0, 0.0, MAX_EXTRAPOLATION_SECONDS)
	var target_position: Vector3 = (newest["p"] as Vector3) + (newest["v"] as Vector3) * ahead_seconds
	var target_rotation: Quaternion = newest["r"]
	for index: int in range(_snapshots.size() - 1):
		var before: Dictionary = _snapshots[index]
		var after: Dictionary = _snapshots[index + 1]
		if _time_of(before) <= render_msec and render_msec <= _time_of(after):
			var span: float = maxf(float(_time_of(after) - _time_of(before)), 1.0)
			var t: float = float(render_msec - _time_of(before)) / span
			target_position = (before["p"] as Vector3).lerp(after["p"] as Vector3, t)
			target_rotation = (before["r"] as Quaternion).slerp(after["r"] as Quaternion, t)
			break
	if global_position.distance_to(target_position) > SNAPSHOT_SNAP_DISTANCE:
		global_transform = Transform3D(Basis(target_rotation), target_position)
		reset_physics_interpolation()
		return
	# The snapshots are already interpolated, and physics interpolation smooths between physics
	# steps, so only a light glide is added (it hides the small jump when the owner changes).
	var weight: float = 1.0 - exp(-SNAPSHOT_SMOOTHING * delta)
	global_position = global_position.lerp(target_position, weight)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(target_rotation, weight))


## Props this one is about to hit: its own shape where it will be in CLAIM_LOOKAHEAD seconds at its
## current speed, plus CLAIM_MARGIN metres of extra room.
func find_props_ahead() -> Array[NetProp]:
	var found: Array[NetProp] = []
	var shape_node: CollisionShape3D = null
	for child: Node in get_children():
		if child is CollisionShape3D:
			shape_node = child as CollisionShape3D
			break
	if shape_node == null or shape_node.shape == null or not is_inside_tree():
		return found
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	# Where it will be in CLAIM_LOOKAHEAD seconds (touching right now is handled by _on_body_entered).
	query.transform = shape_node.global_transform.translated(linear_velocity * CLAIM_LOOKAHEAD)
	query.margin = CLAIM_MARGIN
	query.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS)
	query.exclude = [get_rid()]
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, MAX_CONTACTS):
		var prop := hit.get("collider") as NetProp
		if prop != null and not found.has(prop):
			found.append(prop)
	return found


## Owner (a player's PC): claim loose props just BEFORE this one reaches them, so they never act like
## a wall here (the claim takes a moment to come back from the host).
func _claim_ahead(delta: float) -> void:
	_claim_timer -= delta
	if _claim_timer > 0.0 or linear_velocity.length() < SETTLED_SPEED:
		return
	_claim_timer = CLAIM_INTERVAL
	for prop: NetProp in find_props_ahead():
		_request_knock_on(prop)


## A player's PC that runs this prop watches what it bumps into (see _on_body_entered).
func _update_contact_monitor() -> void:
	contact_monitor = is_simulated_here() and (not multiplayer.is_server() or is_fragile())
	_knock_requested.clear()


## Knock-on ownership: on a player's PC, when a prop it runs hits a loose prop the host runs, ask to
## run that one too, so it gets knocked over here straight away instead of acting like a wall.
func _on_body_entered(other: Node) -> void:
	# Fragile: hitting anything hard enough shatters it (decided where it is simulated; the host breaks it).
	if is_fragile() and is_simulated_here() and not is_held() and _spawner != null \
			and _last_speed >= data.fragile_break_speed:
		_spawner.request_break(self)
		return
	var prop := other as NetProp
	if prop == null or _spawner == null or not is_simulated_here() or multiplayer.is_server():
		return
	_request_knock_on(prop)


func _request_knock_on(prop: NetProp) -> void:
	if _spawner == null or prop.is_simulated_here() or prop.is_held() or prop.is_attached() or _knock_requested.has(prop.net_id):
		return
	_knock_requested[prop.net_id] = true
	_spawner.request_knock_on(prop)


func _on_sleeping_state_changed() -> void:
	if sleeping and multiplayer.is_server() and _spawner != null \
			and global_position.y > _config().out_of_world_y + SAFE_HEIGHT_MARGIN:
		_safe_position = global_position
