class_name Perception
extends Node
## Child "Perception" of every Enemy (added by Enemy). Which players it can see: alive, within
## EnemyData.sight_range, and with no wall in between. Host only (the AI runs there). Checked a few
## times a second, not every frame. Spec: docs/systems/enemies.md.
## CHANGED 2026-10-30 (HL2 feel step 3.2): it only sees inside its view cone (EnemyData.sight_cone_degrees)
## unless you're very close (Config.feel.ai.close_sense_range); it notices a player only after they've been
## in view for Config.feel.ai.notice_seconds (players it already knows about: at once); all enemies share
## Config.feel.ai.sight_rays_per_tick sight lines per tick; and choose_target() spreads enemies over the team.

const NODE_NAME: String = "Perception"
## CHANGED 2026-10-29: how often it looks, eye height and where it aims on a player moved to Config.feel.ai.

## Test scenes: enemies ignore every player while true.
static var players_invisible: bool = false

## Sight lines used this physics tick, by all enemies together.
static var _rays_frame: int = -1
static var _rays_used: int = 0

var _enemy: Enemy
## Plain array: a player in it may have left (been freed) since the last look.
var _visible: Array = []
var _check_left: float = 0.0
## Player instance id -> when (seconds) it came into view this time.
var _seen_since: Dictionary[int, float] = {}
## Player instance id -> until when (seconds) it is "known": noticed at once when seen (its target, a
## player that hurt it, one a packmate told it about).
var _known_until: Dictionary[int, float] = {}
## Player instance id -> when (seconds) they last hurt this enemy.
var _hurt_at: Dictionary[int, float] = {}
## Player instance id -> where they were at its last look that saw them.
var _seen_at: Dictionary[int, Vector3] = {}


func _ready() -> void:
	name = NODE_NAME
	_enemy = get_parent() as Enemy
	# Spread the first look out, so a room full of enemies doesn't look on the same tick.
	_check_left = randf() * Config.feel.ai.sight_check_seconds


func get_visible_players() -> Array[PlayerCharacter]:
	var alive: Array[PlayerCharacter] = []
	for entry: Variant in _visible:
		if is_valid_target(entry):
			alive.append(entry as PlayerCharacter)
	return alive


## Can it see this player right now (as of its last look)?
func can_see(player: PlayerCharacter) -> bool:
	return player != null and _visible.has(player) and is_valid_target(player)


## NEW 2026-10-30 (step 3.1): where `player` was when it last saw them (their position now if never).
func last_seen_position(player: PlayerCharacter) -> Vector3:
	if player == null:
		return Vector3.ZERO
	return _seen_at.get(player.get_instance_id(), player.global_position)


## NEW 2026-10-30: the players it can see AND has noticed (in view long enough, close, or already known).
func get_noticed_players() -> Array[PlayerCharacter]:
	var noticed: Array[PlayerCharacter] = []
	var now: float = _now()
	var tuning: AiTuning = Config.feel.ai
	for player: PlayerCharacter in get_visible_players():
		var key: int = player.get_instance_id()
		var close: bool = _flat_distance(player) <= tuning.close_sense_range
		if close or now - float(_seen_since.get(key, now)) >= tuning.notice_seconds \
				or float(_known_until.get(key, -1.0)) > now:
			noticed.append(player)
	return noticed


## The closest player it has noticed, or null.
func get_nearest_visible_player() -> PlayerCharacter:
	var best: PlayerCharacter = null
	var best_distance: float = INF
	for player: PlayerCharacter in get_noticed_players():
		var distance: float = player.global_position.distance_to(_enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## NEW 2026-10-30 (step 3.4): whom to go after among the players it has noticed. Closer is better; a player
## other enemies are already after counts as further away (so the pack spreads over the team); one who hurt
## it lately counts as closer; and it sticks to its current target (for at least target_min_hold seconds,
## then as if they were target_stickiness times closer). `held_since` is when it took its current target.
func choose_target(current: PlayerCharacter, held_since: float) -> PlayerCharacter:
	var noticed: Array[PlayerCharacter] = get_noticed_players()
	if noticed.is_empty():
		return null
	var tuning: AiTuning = Config.feel.ai
	var now: float = _now()
	if current != null and noticed.has(current) and now - held_since < tuning.target_min_hold:
		return current
	var best: PlayerCharacter = null
	var best_score: float = INF
	for player: PlayerCharacter in noticed:
		var score: float = maxf(player.global_position.distance_to(_enemy.global_position), 0.5)
		score *= 1.0 + tuning.target_crowd_penalty * float(_others_after(player))
		if player == current:
			score /= tuning.target_stickiness
		if now - float(_hurt_at.get(player.get_instance_id(), -1000.0)) < tuning.target_memory_seconds:
			score /= tuning.target_revenge
		if score < best_score:
			best_score = score
			best = player
	return best


## NEW 2026-10-30: from now on it notices this player at once (for a while): its target, a player who hurt
## it, or one a packmate spotted.
func know(player: PlayerCharacter) -> void:
	if player != null:
		_known_until[player.get_instance_id()] = _now() + Config.feel.ai.target_memory_seconds


## NEW 2026-10-30: this player hurt it (it remembers, and prefers going after them).
func remember_hurt_by(player: PlayerCharacter) -> void:
	if player != null:
		_hurt_at[player.get_instance_id()] = _now()
		know(player)


## A player worth chasing: still here (not freed: a player who left), alive, and not hidden by the
## test switch. Takes a Variant so a freed player can be checked safely.
func is_valid_target(candidate: Variant) -> bool:
	if players_invisible or not is_instance_valid(candidate):
		return false
	var player := candidate as PlayerCharacter
	if player == null or not player.is_inside_tree() or player.is_queued_for_deletion():
		return false
	var health: HealthComponent = HealthComponent.of(player)
	return health == null or not health.is_dead()


## Looks again now (tests; normally every Config.feel.ai.sight_check_seconds, within the shared budget).
func refresh() -> void:
	var was_visible: Array = _visible.duplicate()
	_visible.clear()
	if _enemy == null or not _enemy.is_inside_tree() or players_invisible:
		_seen_since.clear()
		return
	var tuning: AiTuning = Config.feel.ai
	var sight: float = _enemy.data.sight_range if _enemy.data != null else 15.0
	var cone: float = _enemy.data.sight_cone_degrees if _enemy.data != null else 360.0
	var eyes: Vector3 = _enemy.global_position + Vector3.UP * tuning.eye_height
	var forward: Vector3 = -_enemy.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var space: PhysicsDirectSpaceState3D = _enemy.get_world_3d().direct_space_state
	var now: float = _now()
	for player: PlayerCharacter in _candidates():
		var chest: Vector3 = player.global_position + Vector3.UP * tuning.player_chest_height
		if eyes.distance_to(chest) > sight:
			continue
		# Outside the view cone it can't see you, unless you're right next to it or it's already after you.
		if cone < 359.0 and player != _enemy.get_target() and _flat_distance(player) > tuning.close_sense_range:
			var toward: Vector3 = chest - eyes
			toward.y = 0.0
			if toward.length() > 0.01 and forward.dot(toward.normalized()) < cos(deg_to_rad(cone * 0.5)):
				continue
		var query := PhysicsRayQueryParameters3D.create(eyes, chest, PhysicsLayers.bit(PhysicsLayers.WORLD))
		if space.intersect_ray(query).is_empty():
			_visible.append(player)
			var key: int = player.get_instance_id()
			_seen_at[key] = player.global_position
			if not was_visible.has(player) or not _seen_since.has(key):
				_seen_since[key] = now
	for key: int in _seen_since.keys():
		var still: bool = false
		for entry: Variant in _visible:
			if is_instance_valid(entry) and (entry as Object).get_instance_id() == key:
				still = true
		if not still:
			_seen_since.erase(key)
	var target: PlayerCharacter = _enemy.get_target()
	if target != null and _visible.has(target):
		know(target)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	if not _take_rays(_candidates().size()):
		return
	_check_left = Config.feel.ai.sight_check_seconds
	refresh()


## Living players in the same world as the enemy.
func _candidates() -> Array[PlayerCharacter]:
	var found: Array[PlayerCharacter] = []
	if _enemy == null or not _enemy.is_inside_tree():
		return found
	for node: Node in _enemy.get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var player := node as PlayerCharacter
		if player != null and is_valid_target(player) and player.get_world_3d() == _enemy.get_world_3d():
			found.append(player)
	return found


## Shares Config.feel.ai.sight_rays_per_tick between all enemies: true if this look fits in this tick's
## budget (one ray per player). The first look of a tick always fits.
static func _take_rays(count: int) -> bool:
	var frame: int = Engine.get_physics_frames()
	if frame != _rays_frame:
		_rays_frame = frame
		_rays_used = 0
	if _rays_used > 0 and _rays_used + count > Config.feel.ai.sight_rays_per_tick:
		return false
	_rays_used += count
	return true


## How many other living enemies are after this player.
func _others_after(player: PlayerCharacter) -> int:
	var count: int = 0
	for node: Node in _enemy.get_tree().get_nodes_in_group(Enemy.GROUP):
		var other := node as Enemy
		if other != null and other != _enemy and not other.is_dead() and other.get_target() == player:
			count += 1
	return count


func _flat_distance(player: PlayerCharacter) -> float:
	var offset: Vector3 = player.global_position - _enemy.global_position
	offset.y = 0.0
	return offset.length()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
