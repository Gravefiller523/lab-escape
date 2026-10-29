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

## CHANGED 2026-10-29: the hold, drop, throw and push numbers moved to Config.feel.props (PropTuning,
## res://config/feel_tuning.tres).
## How quickly copies catch up with snapshots, and when they jump instead.
const SNAPSHOT_SMOOTHING: float = 40.0
const SNAPSHOT_SNAP_DISTANCE: float = 3.0
## A resting spot only counts as safe this far above the out-of-world height.
const SAFE_HEIGHT_MARGIN: float = 5.0
## A push counts for this long after the last report (milliseconds), so pushes don't flicker.
const PUSH_MEMORY_MSEC: int = 250
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
## Claiming ahead: look this far ahead in time (seconds), with this much extra room (metres), this
## often (seconds).
const CLAIM_LOOKAHEAD: float = 0.15
const CLAIM_MARGIN: float = 0.15
const CLAIM_INTERVAL: float = 0.05
## "Touching" for settle_if_touching (metres).
const TOUCH_MARGIN: float = 0.04
## Scrapes: what counts as sliding (vertical speed below this, m/s), how far below its bottom the floor may
## be (metres), and how long the sound lingers after it stops sliding (seconds).
const SCRAPE_MAX_VERTICAL_SPEED: float = 0.5
const SCRAPE_FLOOR_GAP: float = 0.08
const SCRAPE_LINGER: float = 0.1
## Impact damage: a victim counts if it is this close (metres) and on the side the prop was slowed from
## (so a crate sliding down an enemy and hitting the floor doesn't hurt the enemy again).
const HIT_MARGIN: float = 0.12
const HIT_DIRECTION_MIN_DOT: float = 0.3

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
## NEW 2026-10-29: true while something else decides what this prop's hits do (a thrown inventory item's
## own damage), so impact damage leaves it alone.
var own_hit_damage: bool = false
## NEW 2026-10-29, host: how much wear a breakable prop can still take (below 0 = untouched, full health).
var health_left: float = -1.0
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
## Owner: smoothed distance from the hold point (the drop rule), when it was picked up, and how fast it may
## turn while touching something (1 = normal). NEW 2026-10-29.
var _hold_error: float = 0.0
var _held_since_msec: int = 0
var _contact_spin_scale: float = 1.0
## Owner: its speed at the end of the last physics step, for hearing hits (NEW 2026-10-29); ticks to skip
## after code changed its speed (a drop, a hand-over), and when it last made a knock.
var _velocity_after_step: Vector3 = Vector3.ZERO
var _impact_skip: int = 2
var _last_impact_msec: int = -100000
## Owner: when it last hurt each victim (instance id -> msec), and (every PC) when its holders last let go.
var _hit_msec: Dictionary[int, int] = {}
var _released_msec: int = -100000
## Every PC: where it was last physics step (to see how fast copies slide), and its scrape sound.
var _scrape_last_position: Vector3 = Vector3.INF
var _scrape_player: AudioStreamPlayer3D
var _scrape_linger: float = 0.0
## Half-size of its first collision shape, in its own axes (see get_depth_along); x < 0 = not worked out.
var _half_extents: Vector3 = Vector3(-1.0, 0.0, 0.0)
## Owner (a client): we already asked the host to take it back.
var _handback_sent: bool = false
## Props we already asked to take over after bumping into them (net id -> true).
var _knock_requested: Dictionary[int, bool] = {}
## Its real weight (kg). While fully lifted, `mass` is set to Config.feel.props.held_mass instead.
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
	return _true_mass > _tuning().grab_max_mass


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
	return clampf(float(people) * _tuning().heavy_lift_per_holder / _true_mass, 0.0, 1.0)


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
	if _holders.is_empty() and not holders.is_empty():
		_held_since_msec = Time.get_ticks_msec()
		_hold_error = 0.0
		_contact_spin_scale = 1.0
	if not _holders.is_empty() and holders.is_empty():
		_released_msec = Time.get_ticks_msec()
	_holders = holders.duplicate()
	_impact_skip = 2
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
## lifted prop counts as very light (Config.feel.props.held_mass) so it nudges other things gently instead of
## bulldozing them. Let go: real weight back, and no flinging it by spinning around.
func _apply_held_physics() -> void:
	var was_held_light: bool = not is_equal_approx(mass, _true_mass)
	gravity_scale = 1.0 - get_support()
	# A sleeping prop would freeze in its holder's hands (CHANGED 2026-10-29: held props stay awake).
	can_sleep = not is_held()
	if is_held():
		sleeping = false
	var tuning: PropTuning = _tuning()
	angular_damp = tuning.held_angular_damp if is_held() else 0.0
	mass = tuning.held_mass if is_lifted() else _true_mass
	if was_held_light and not is_lifted():
		linear_velocity = linear_velocity.limit_length(tuning.held_prop_release_max_speed)
		angular_velocity = angular_velocity.limit_length(tuning.release_max_spin)


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
		_impact_skip = 2
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


## NEW 2026-10-29: hard knocks wear it down until it breaks (PropData.health > 0).
func is_breakable() -> bool:
	return data != null and data.health > 0.0


## Half-size of its first collision shape, in its own axes (NEW 2026-10-29; broken pieces use it).
func get_half_extents() -> Vector3:
	get_depth_along(Vector3.UP)
	return _half_extents


## Its colour, from its first mesh's material (grey if it has none). Broken pieces use it.
func get_main_color() -> Color:
	for child: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var material := mesh.get_active_material(0) as StandardMaterial3D
		if material != null:
			return material.albedo_color
	return Color(0.55, 0.55, 0.55)


## NEW 2026-10-19: shatters when it hits something at PropData.fragile_break_speed or faster.
func is_fragile() -> bool:
	return data != null and data.fragile_break_speed > 0.0


## Owner: this PC's player let go. Stop pulling it toward their hands right now (don't wait for the
## host to confirm), so a throw flies at full speed instead of being held back for a moment.
## CHANGED 2026-10-29: `thrown` false (a plain drop) also stops it dead if it is touching something.
func let_go_here(player_id: int, thrown: bool = false) -> void:
	_hold_targets.erase(player_id)
	if _hold_targets.is_empty():
		_release_here(thrown)


## Owner: nobody's hands pull it any more. Real weight back, no flinging, and a plain drop against
## something stops it dead.
func _release_here(thrown: bool) -> void:
	gravity_scale = 1.0
	angular_damp = 0.0
	can_sleep = true
	mass = _true_mass
	linear_velocity = linear_velocity.limit_length(_tuning().held_prop_release_max_speed)
	angular_velocity = angular_velocity.limit_length(_tuning().release_max_spin)
	_impact_skip = 2
	if not thrown:
		settle_if_touching()


## Owner (NEW 2026-10-29): a plain drop while touching something (a wall, the floor, another prop) stops
## it dead, like Half-Life 2, so dropping a crate against a wall can't fling it.
func settle_if_touching() -> void:
	if not is_simulated_here() or not _tuning().drop_clears_velocity_on_contact or not is_touching_something():
		return
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## True if any of its collision shapes touches something it collides with (within a few centimetres).
func is_touching_something() -> bool:
	if not is_inside_tree():
		return false
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null or shape_node.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.margin = TOUCH_MARGIN
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return true
	return false


## Owner: where a holder wants it now.
## `yaw` is the holder's facing (radians): like Half-Life 2, the prop keeps the angle it was picked up
## at, relative to the holder, so it turns as they turn.
func set_hold_target(player_id: int, target: Vector3, yaw: float) -> void:
	if not _holders.has(player_id):
		return
	_hold_targets[player_id] = target
	var facing := Quaternion(Vector3.UP, yaw)
	if not _hold_rotation_offsets.has(player_id):
		# CHANGED 2026-10-29: nearly square to the world? Carry it square (Half-Life 2 does this).
		var held_as: Quaternion = tidy_rotation(global_basis.get_rotation_quaternion(),
			deg_to_rad(_tuning().carry_snap_angle_degrees))
		_hold_rotation_offsets[player_id] = facing.inverse() * held_as
	_hold_facings[player_id] = facing
	_last_touch_msec = Time.get_ticks_msec()


## NEW 2026-10-29: `rotation`, or the nearest rotation square to the world's axes if that is within
## `max_angle` radians.
static func tidy_rotation(rotation_now: Quaternion, max_angle: float) -> Quaternion:
	if max_angle <= 0.0:
		return rotation_now
	var basis := Basis(rotation_now)
	var x_axis: Vector3 = _nearest_axis(basis.x)
	var y_axis: Vector3 = _nearest_axis(basis.y)
	if absf(x_axis.dot(y_axis)) > 0.5:
		return rotation_now
	var tidy := Basis(x_axis, y_axis, x_axis.cross(y_axis)).get_rotation_quaternion()
	return tidy if rotation_now.angle_to(tidy) <= max_angle else rotation_now


static func _nearest_axis(vector: Vector3) -> Vector3:
	var axis: int = vector.abs().max_axis_index()
	var result := Vector3.ZERO
	result[axis] = signf(vector[axis])
	return result


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
	angular_velocity = (difference.get_axis() * angle / maxf(delta, 0.001)).limit_length(_tuning().hold_max_spin)


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


## Its real weight in kg (while it is lifted, the physics body weighs Config.feel.props.held_mass instead).
func get_true_mass() -> float:
	return _true_mass


## NEW 2026-10-29: how far it reaches from its centre along `direction` (metres), from its first
## collision shape as it is turned now. GrabController uses it to hold things just in front of you.
func get_depth_along(direction: Vector3) -> float:
	if _half_extents.x < 0.0:
		_half_extents = Vector3.ONE * 0.3
		for child: Node in get_children():
			var shape_node := child as CollisionShape3D
			if shape_node != null and shape_node.shape != null:
				_half_extents = shape_node.shape.get_debug_mesh().get_aabb().size / 2.0
				break
	var axes: Basis = global_basis.orthonormalized()
	return absf(direction.dot(axes.x)) * _half_extents.x + absf(direction.dot(axes.y)) * _half_extents.y \
		+ absf(direction.dot(axes.z)) * _half_extents.z


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
	angular_velocity += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _tuning().throw_spin


## For tests: pretend it weighs this much.
func set_true_mass(kilograms: float) -> void:
	_true_mass = kilograms
	mass = kilograms


func _config() -> GameConfig:
	return _spawner.get_config() if _spawner != null else Config.game


## NEW 2026-10-29: how holding, dropping, throwing and pushing feel (Config.feel.props).
func _tuning() -> PropTuning:
	return Config.feel.props


func _physics_process(delta: float) -> void:
	if _anchor != null:
		if is_instance_valid(_anchor):
			global_transform = _anchor.global_transform
		else:
			_anchor = null
			freeze = not is_simulated_here()
		return
	if is_simulated_here():
		_listen_for_hits(delta)
		_simulate(delta)
		_last_speed = linear_velocity.length()
		_velocity_after_step = linear_velocity
	else:
		_follow(delta)
	_update_scrape(delta)


## NEW 2026-10-29 (Half-Life 2 style): the PC running it hears its hits from how much speed the last physics
## step took away (beyond gravity), and tells the spawner, which plays the knock everywhere.
func _listen_for_hits(delta: float) -> void:
	if _impact_skip > 0 or is_held() or freeze or _spawner == null:
		_impact_skip = maxi(_impact_skip - 1, 0)
		return
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var expected: Vector3 = _velocity_after_step + Vector3.DOWN * gravity * gravity_scale * delta
	var lost: float = expected.length() - linear_velocity.length()
	var tuning: PropTuning = _tuning()
	if lost >= tuning.impact_damage_min_speed and _true_mass >= tuning.impact_min_mass and not own_hit_damage:
		_report_victim(expected - linear_velocity, lost)
	if lost >= tuning.impact_damage_min_speed and is_breakable():
		_spawner.report_wear(self, lost)
	if lost < tuning.impact_sound_min_speed:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_impact_msec < int(tuning.impact_sound_debounce * 1000.0):
		return
	_last_impact_msec = now
	_spawner.report_impact(self, global_position, lost)


## Owner (NEW 2026-10-29): it just lost `speed_lost` m/s in a hit (`change` is the speed taken away): if
## that hit was against an enemy or a player (it is touching one on the side it was slowed from), tell the
## host, which checks it and works out the damage.
func _report_victim(change: Vector3, speed_lost: float) -> void:
	var contact: Dictionary = _touch_info(PhysicsLayers.bit(PhysicsLayers.ENEMIES) | PhysicsLayers.bit(PhysicsLayers.PLAYERS))
	if contact.is_empty():
		return
	var victim := instance_from_id(contact["collider_id"]) as Node3D
	var toward: Vector3 = (contact["point"] as Vector3) - global_position
	if victim == null or toward.normalized().dot(change.normalized()) < HIT_DIRECTION_MIN_DOT:
		return
	var now: int = Time.get_ticks_msec()
	var key: int = victim.get_instance_id()
	if now - int(_hit_msec.get(key, -100000)) < int(_tuning().impact_report_cooldown * 1000.0):
		return
	_hit_msec[key] = now
	_spawner.report_hit(self, victim, speed_lost)


## The nearest contact (point, collider_id...) with a body on `mask` within a few centimetres, or {}.
func _touch_info(mask: int) -> Dictionary:
	if not is_inside_tree():
		return {}
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null or shape_node.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.margin = HIT_MARGIN
		query.collision_mask = mask
		query.exclude = [get_rid()]
		var info: Dictionary = get_world_3d().direct_space_state.get_rest_info(query)
		if not info.is_empty():
			return info
	return {}


## NEW 2026-10-29: the player who threw or dropped it in the last `seconds` (they get the credit for its
## hits), or 0.
func get_recent_thrower(seconds: float) -> int:
	if is_held():
		return 0
	return last_holder_id if Time.get_ticks_msec() - _released_msec <= int(seconds * 1000.0) else 0


## NEW 2026-10-29: what it is made of (PropData.surface; item pickups and props without data: wood).
func get_surface() -> SurfaceType:
	if data != null:
		return SurfaceType.find(data.surface)
	if has_meta(SurfaceType.META_KEY):
		return SurfaceType.of(self)
	return SurfaceType.find(&"wood")


## Every PC (NEW 2026-10-29): a looping scrape while it slides along the floor or something under it.
## Worked out on each PC from how its copy moves, so nothing extra is sent.
func _update_scrape(delta: float) -> void:
	var position_now: Vector3 = global_position
	var moved: Vector3 = position_now - _scrape_last_position if _scrape_last_position.is_finite() else Vector3.ZERO
	_scrape_last_position = position_now
	var tuning: PropTuning = _tuning()
	var flat_speed: float = Vector2(moved.x, moved.z).length() / maxf(delta, 0.001)
	# (Carts, the only keep_on_host props, roll on wheels: no scraping.)
	var sliding: bool = delta > 0.0 and not is_held() and _anchor == null and not keep_on_host \
		and flat_speed >= tuning.scrape_min_speed \
		and flat_speed < 30.0 and absf(moved.y / delta) < SCRAPE_MAX_VERTICAL_SPEED and _has_something_under()
	if sliding:
		_scrape_linger = SCRAPE_LINGER
		if _scrape_player == null:
			_scrape_player = AudioStreamPlayer3D.new()
			_scrape_player.bus = &"SFX"
			_scrape_player.stream = get_surface().scrape_sound()
			add_child(_scrape_player)
		var loudness: float = clampf(inverse_lerp(tuning.scrape_min_speed, tuning.scrape_full_speed, flat_speed), 0.0, 1.0)
		_scrape_player.volume_db = tuning.scrape_volume_db + linear_to_db(maxf(loudness, 0.05)) + get_surface().volume_db
		if not _scrape_player.playing:
			_scrape_player.play()
	elif _scrape_player != null and _scrape_player.playing:
		_scrape_linger -= delta
		if _scrape_linger <= 0.0:
			_scrape_player.stop()


## True while scraping (tests use it).
func is_scraping() -> bool:
	return _scrape_player != null and _scrape_player.playing


func _has_something_under() -> bool:
	if not is_inside_tree():
		return false
	var bottom: float = get_depth_along(Vector3.UP)
	var query := PhysicsRayQueryParameters3D.create(global_position,
		global_position + Vector3.DOWN * (bottom + SCRAPE_FLOOR_GAP), collision_mask)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Owner: pull a held prop toward its holders' hold point with a spring, and drop it if stuck.
## Heavy props that aren't fully lifted are pulled more weakly and more slowly (they drag).
func _simulate(delta: float) -> void:
	if not multiplayer.is_server():
		_claim_ahead(delta)
	_apply_pushes()
	# CHANGED 2026-10-29: no prop goes faster than prop_max_speed.
	var top_speed: float = _tuning().prop_max_speed
	if linear_velocity.length_squared() > top_speed * top_speed:
		linear_velocity = linear_velocity.limit_length(top_speed)
	var support: float = get_support()
	if support <= 0.0 or _hold_targets.is_empty():
		_hold_error = 0.0
		return
	var target := Vector3.ZERO
	for point: Vector3 in _hold_targets.values():
		target += point
	target /= float(_hold_targets.size())
	var tuning: PropTuning = _tuning()
	var offset: Vector3 = target - global_position
	var max_speed: float = tuning.held_prop_max_speed * support
	if support >= 1.0:
		# Half-Life 2's "shadow control": each physics step, set the speed that gets it exactly to
		# the hold point by the next step (capped). Tight, no spring wobble, and it still collides.
		var velocity: Vector3 = (offset / maxf(delta, 0.001)).limit_length(tuning.held_prop_track_speed)
		# CHANGED 2026-10-29 (Half-Life 2's touches): touching something, it slides along it instead of
		# pushing into it, and turns slower, so it doesn't jitter against walls.
		var touching: bool = is_touching_something()
		if touching:
			velocity = _slide_along_what_it_hits(velocity, delta)
		linear_velocity = velocity
		_steer_rotation(delta)
		var spin_goal: float = tuning.hold_contact_spin_min if touching else 1.0
		_contact_spin_scale = move_toward(_contact_spin_scale, spin_goal, tuning.hold_contact_spin_rate * delta)
		angular_velocity *= _contact_spin_scale
	else:
		# Not fully lifted (a heavy prop with too few helpers): a weaker pull, so it drags.
		apply_central_force((offset * tuning.hold_stiffness - linear_velocity * tuning.hold_damping) * mass * support)
		if linear_velocity.length() > max_speed:
			linear_velocity = linear_velocity.limit_length(max_speed)
	# CHANGED 2026-10-29: dropped when, on average, it is too far from where it should be (Half-Life 2),
	# after a grace period for flying to your hands. Only fully lifted props (heavy drags lag on purpose).
	if support >= 1.0:
		_hold_error = lerpf(_hold_error, offset.length(), 1.0 - exp(-delta / maxf(tuning.hold_error_smoothing, 0.001)))
		var grace_over: bool = Time.get_ticks_msec() - _held_since_msec > int(tuning.hold_error_grace * 1000.0)
		if grace_over and _hold_error > tuning.hold_error_drop and _spawner != null:
			_hold_error = 0.0
			# Let go here at once (it is pressed against something, so it stops dead), then tell the host.
			_hold_targets.clear()
			_release_here(false)
			_spawner.report_stuck(self)
			return
	else:
		_hold_error = 0.0


## Owner (NEW 2026-10-29): the part of `velocity` that doesn't push into what it would hit this step.
func _slide_along_what_it_hits(velocity: Vector3, delta: float) -> Vector3:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = global_transform
	params.motion = velocity * delta
	params.margin = TOUCH_MARGIN * 0.5
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return velocity
	var normal: Vector3 = result.get_collision_normal()
	var into: float = velocity.dot(normal)
	return velocity - normal * into if into < 0.0 else velocity


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
	var wanted: float = speed * _tuning().push_speed_factor * support_for(_pushes.size())
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
