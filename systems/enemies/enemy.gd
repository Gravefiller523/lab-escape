class_name Enemy
extends CharacterBody3D
## One regular enemy (the root of every enemy scene). Spec: docs/systems/enemies.md.
## A scene is this body plus: a "States" node whose children are shared EnemyStates (idle, patrol, chase,
## swarm, attack_melee, flee, search; the child's name is the state's name), optional EnemyBehaviour
## children (a kangaroo's leap, a bat's swoop), a mesh and a collision shape. Numbers come from its EnemyData.
##
## The AI runs only on the host. The host sends position, facing and state ~20 times a second; other
## PCs slide their copy there. Health, statuses and the hurtbox come from damage (give_components).
##
## CHANGED 2026-10-30 (HL2 feel step 3): it notices players with a short delay and a squeak, chases to where
## it last saw you (not through walls), searches there, hears noises (EventBus.noise_made), tells its pack,
## takes attack tickets (AttackTickets) and winds up before it strikes, steers around other enemies, dodges
## heavy thrown props, and leaves a tumbling body when it dies.
## NEW 2026-10-30 (doors): it paths through doorways with doors it can open, and a door it walks into
## swings open for it (WorldDoor watches get_walk_intent()).

signal state_changed(state: StringName)
## NEW 2026-10-23 (bosses branch): it died (every PC, once), after it fell over.
signal died(info: DamageInfo)
## NEW 2026-10-30 (step 3.2): host: it noticed a player (it was calm before). Every PC hears its squeak.
signal noticed(player: PlayerCharacter)

const GROUP: StringName = &"enemies"
const SYNC_INTERVAL: float = 0.05
## NEW 2026-10-30: this close (m, flat) to where it's going counts as "got there".
const ARRIVE_DISTANCE: float = 1.0
## NEW 2026-10-30: the states in which it's calm (it listens for noises and can be startled).
const CALM_STATES: Array[StringName] = [&"idle", &"patrol", &"search"]
## NEW 2026-10-30: how long (s) a jump aside lasts.
const DODGE_SECONDS: float = 0.4
## NEW 2026-10-30 (punt): how long a shove lasts, and how fast it slows down meanwhile (m/s per second).
const KNOCK_SECONDS: float = 0.6
const KNOCK_FRICTION: float = 12.0
## CHANGED 2026-10-29: turn speed, target memory, repath time, client smoothing and corpse time moved to
## Config.feel.ai (AiTuning, res://config/feel_tuning.tres).

## Flies instead of walking (bats, flies): no gravity, steers through the air (along the ground's
## navigation path when there is one).
@export var flying: bool = false
## Height above the ground it flies at (flying only).
@export var hover_height: float = 2.2
## Push given to a player it hits (metres per second).
@export var attack_knockback: float = 2.0
## Size of its hurtbox capsule.
@export var hurtbox_radius: float = 0.35
@export var hurtbox_height: float = 0.6
## The first state.
@export var start_state: StringName = &"idle"
## NEW 2026-10-30 (step 3.5): how firmly it keeps its way when walking enemies make room for each other
## (0 to 1). Bigger enemies get more, so rats make way for a kangaroo.
@export_range(0.0, 1.0) var avoidance_priority: float = 0.5

var data: EnemyData
## Shared state machine data the states may use.
var home: Vector3 = Vector3.ZERO
## Flying: when >= 0, fly at this height above the ground instead of hover_height (a bat's dive).
var altitude_override: float = -1.0
## Where it last saw its target.
var last_known_position: Vector3 = Vector3.ZERO
## NEW 2026-10-30: where the "search" state looks around (a noise, or where it lost you).
var search_point: Vector3 = Vector3.ZERO
## NEW 2026-10-20: it already ran away once (enemies flee only once, then fight to the end).
var has_fled: bool = false
## Host: this enemy's own random numbers (wandering, swarm angles). Seeded per run and enemy (SeededRng).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Bodies of dead enemies on this PC, oldest first (weak references), for Config.feel.ai.max_corpses.
static var _corpses: Array[WeakRef] = []

var _target: PlayerCharacter
var _target_lost_at: float = -1.0
var _target_since: float = 0.0
var _states: Dictionary[StringName, EnemyState] = {}
var _state: EnemyState
var _state_name: StringName = &""
var _behaviours: Array[EnemyBehaviour] = []
var _perception: Perception
var _agent: NavigationAgent3D
var _attack_ready_at: float = 0.0
var _sync_left: float = 0.0
var _synced_position: Vector3 = Vector3.ZERO
var _synced_yaw: float = 0.0
var _has_sync: bool = false
var _repath_left: float = 0.0
var _dead: bool = false
## Spacing: the push away from nearby enemies, worked out every spacing_check_seconds.
var _spacing_push: Vector3 = Vector3.ZERO
var _spacing_left: float = 0.0
## Flying: the ground path it follows at its height.
var _flyer_path: PackedVector3Array = PackedVector3Array()
var _flyer_index: int = 0
var _flyer_goal: Vector3 = Vector3.INF
## Circling while waiting for an attack ticket: which way round (+1 or -1).
var _circle_side: float = 1.0
## Dodging: seconds left of the jump aside, when it may dodge again, and props it already decided about.
var _dodge_left: float = 0.0
var _dodge_ready_at: float = 0.0
var _dodge_decided: Dictionary[int, bool] = {}
## NEW 2026-10-30 (punt): seconds left of being shoved (no thinking, it just slides).
var _knock_left: float = 0.0
## NEW 2026-10-30 (doors): the way move_towards last wanted to go, and on which physics frame.
var _walk_intent: Vector3 = Vector3.ZERO
var _walk_intent_frame: int = -100


## The enemy a node belongs to (a hitbox, a mesh), or null.
static func of(node: Node) -> Enemy:
	var current: Node = node
	while current != null:
		var enemy := current as Enemy
		if enemy != null:
			return enemy
		current = current.get_parent()
	return null


## NEW 2026-10-30 (step 3.3): host: a noise at `at` that carries `radius` metres. Calm enemies in range in
## the same world come to look. EnemiesService calls it for EventBus.noise_made.
static func hear_noise(tree: SceneTree, at: Vector3, radius: float) -> void:
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		var enemy := node as Enemy
		if enemy != null:
			enemy.hear(at, radius)


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS) \
		| PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	home = global_position
	search_point = global_position
	_synced_position = global_position
	_synced_yaw = rotation.y
	_perception = Perception.new()
	add_child(_perception)
	_agent = NavigationAgent3D.new()
	_agent.name = "Agent"
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.6
	add_child(_agent)
	var tuning: AiTuning = Config.feel.ai
	_repath_left = randf() * tuning.repath_seconds
	_spacing_left = randf() * tuning.spacing_check_seconds
	_circle_side = 1.0 if randf() < 0.5 else -1.0
	var states_node: Node = get_node_or_null(^"States")
	if states_node != null:
		for child: Node in states_node.get_children():
			var state := child as EnemyState
			if state != null:
				_states[StringName(child.name)] = state
	for child: Node in get_children():
		var behaviour := child as EnemyBehaviour
		if behaviour != null:
			_behaviours.append(behaviour)
	var health: HealthComponent = get_health()
	if health != null:
		health.died.connect(_on_died)
	if multiplayer.is_server():
		var first: StringName = start_state
		if not _states.has(first) and not _states.is_empty():
			first = _states.keys()[0]
		_change_state(first)
	elif multiplayer.has_multiplayer_peer():
		_request_state_rpc.rpc_id(1)


func _exit_tree() -> void:
	AttackTickets.release(self)


## NEW 2026-10-23 (bosses branch): EnemySpawner calls this with the content it spawns. Enemies use their
## EnemyData; a Boss overrides it to build its numbers from BossData.
func setup_from(content: ContentData, health_multiplier: float, rng_seed: int, rng_index: int) -> void:
	setup(content as EnemyData, health_multiplier, rng_seed, rng_index)


## Host (EnemySpawner): the numbers and the damage components. Called before it enters the tree.
func setup(enemy_data: EnemyData, health_multiplier: float, rng_seed: int = 0, rng_index: int = 0) -> void:
	data = enemy_data
	rng = SeededRng.make(rng_seed, &"enemy_ai", rng_index)
	DamageService.give_components(self, data.max_health * health_multiplier, hurtbox_radius, hurtbox_height)


## NEW 2026-10-29: how heavy it counts as when a thrown prop hits it (EnemyData.impact_mass).
func get_impact_mass() -> float:
	return data.impact_mass if data != null else 20.0


func get_health() -> HealthComponent:
	return HealthComponent.of(self)


func get_target() -> PlayerCharacter:
	return _target if is_instance_valid(_target) else null


func set_target(player: PlayerCharacter) -> void:
	_target = player
	if player != null:
		last_known_position = player.global_position
		_target_lost_at = -1.0
		_target_since = _now()
		_perception.know(player)


func get_state() -> StringName:
	return _state_name


func is_dead() -> bool:
	return _dead


func get_perception() -> Perception:
	return _perception


func has_state(state: StringName) -> bool:
	return _states.has(state)


## The state used to go after a player: "swarm" if this enemy has it, else "chase".
func pursuit_state() -> StringName:
	return &"swarm" if _states.has(&"swarm") else &"chase"


## Host: the player it's after, from Perception (whom it noticed, spread over the team, see
## Perception.choose_target). A player it can't see any more is remembered for target_memory_seconds.
## CHANGED 2026-10-30: noticing someone while calm squeaks and alerts its pack.
func update_target() -> PlayerCharacter:
	var current: PlayerCharacter = get_target()
	var chosen: PlayerCharacter = _perception.choose_target(current, _target_since)
	if chosen != null:
		if chosen != current:
			set_target(chosen)
			if current == null:
				_on_noticed(chosen)
		else:
			# Where it SAW them at its last look (not where they are now, which it may not see).
			last_known_position = _perception.last_seen_position(chosen)
			_target_lost_at = -1.0
	elif current != null:
		if not _perception.is_valid_target(current):
			_target = null
		elif _target_lost_at < 0.0:
			_target_lost_at = _now()
		elif _now() - _target_lost_at > Config.feel.ai.target_memory_seconds:
			_target = null
	return get_target()


## NEW 2026-10-30 (step 3.1): can it see its target right now (as of its last look)?
func can_see_target() -> bool:
	return _perception.can_see(get_target())


## NEW 2026-10-30 (step 3.1): where to run to: the target if it can see them, otherwise where it last saw
## them (so it doesn't track you through walls).
func chase_point() -> Vector3:
	var target: PlayerCharacter = get_target()
	return target.global_position if target != null and can_see_target() else last_known_position


## NEW 2026-10-30 (step 3.2): it got to where it last saw its target and they're gone: stop chasing and look
## around there. Returns the state to switch to ("search", or "idle" if it has none).
func lose_target() -> StringName:
	search_point = last_known_position
	_target = null
	return &"search" if _states.has(&"search") else &"idle"


## NEW 2026-10-30 (step 3.3): host: it heard a noise at `at` that carries `radius` m. A calm enemy in range
## goes to look ("search"); one that is already after someone ignores it.
func hear(at: Vector3, radius: float) -> void:
	if _dead or not is_inside_tree() or not multiplayer.is_server() or get_target() != null:
		return
	if _state_name not in CALM_STATES or global_position.distance_to(at) > radius:
		return
	search_point = at
	if _states.has(&"search"):
		_change_state(&"search")


## NEW 2026-10-30 (step 3.3): host: a packmate spotted `player`: go after them too (no squeak, no chain).
func alert_to(player: PlayerCharacter) -> void:
	if _dead or player == null or get_target() != null:
		return
	set_target(player)
	interrupt(pursuit_state())


## NEW 2026-10-30 (step 3.3): host: `player` hurt it. It remembers them; a calm enemy turns on them at once.
func on_hurt_by(player: PlayerCharacter) -> void:
	if _dead or not _perception.is_valid_target(player):
		return
	_perception.remember_hurt_by(player)
	if get_target() == null:
		set_target(player)
		_on_noticed(player)
		interrupt(pursuit_state())


## NEW 2026-10-30 (step 3.3): host: switch state now because something happened (a noise, a hit), unless the
## current state can't be cut short (mid-attack). True if it switched.
func interrupt(next: StringName) -> bool:
	if _state != null and not _state.can_interrupt(self):
		return false
	if next == _state_name or not _states.has(next) or not _states[next].can_enter(self):
		return false
	_change_state(next)
	return true


func distance_to_target() -> float:
	var target: PlayerCharacter = get_target()
	return global_position.distance_to(target.global_position) if target != null else INF


## Horizontal distance to the target (ignores how high a flying enemy is).
func flat_distance_to_target() -> float:
	var target: PlayerCharacter = get_target()
	if target == null:
		return INF
	return flat_distance_to(target.global_position)


## NEW 2026-10-30: horizontal distance to a point.
func flat_distance_to(point: Vector3) -> float:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	return offset.length()


func move_speed() -> float:
	var base: float = data.move_speed if data != null else 3.0
	var stats: StatsComponent = StatsComponent.of(self)
	return base * (stats.get_value(&"move_speed_multiplier", 1.0) if stats != null else 1.0)


## Host, states: walk (or fly) towards a point at speed x `speed_scale`. Uses the navigation mesh when
## there is one (paths through doorways; flyers follow it at their height), otherwise heads straight there.
## Walking enemies make room for each other.
func move_towards(point: Vector3, speed_scale: float, delta: float) -> void:
	var next_point: Vector3 = point
	if _nav_ready():
		if flying:
			next_point = _next_flyer_point(point, delta)
		else:
			_repath_left -= delta
			if _repath_left <= 0.0 or _agent.target_position.distance_to(point) > 1.0:
				_repath_left = Config.feel.ai.repath_seconds
				_agent.target_position = point
			if not _agent.is_navigation_finished():
				next_point = _agent.get_next_path_position()
	var direction: Vector3 = next_point - global_position
	if flying:
		var ground: float = _ground_height(point)
		var altitude: float = altitude_override if altitude_override >= 0.0 else hover_height
		direction.y = (ground + altitude) - global_position.y
	else:
		direction.y = 0.0
	var speed: float = move_speed() * speed_scale
	var wanted: Vector3 = direction.normalized() * speed if direction.length() > 0.05 else Vector3.ZERO
	_walk_intent = wanted
	_walk_intent_frame = Engine.get_physics_frames()
	if flying:
		velocity = wanted
	else:
		var steered: Vector3 = _with_spacing(wanted, speed, delta)
		velocity.x = steered.x
		velocity.z = steered.z
	face(point, delta)


## Host, states: stand still (flying enemies hover at their height).
func stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if flying:
		var altitude: float = altitude_override if altitude_override >= 0.0 else hover_height
		velocity.y = clampf((_ground_height(global_position) + altitude - global_position.y) * 2.0, -3.0, 3.0)


## NEW 2026-10-30 (step 3.4): host: no attack ticket yet: walk round `player` at circle_distance, facing them.
func circle(player: PlayerCharacter, delta: float) -> void:
	var away: Vector3 = global_position - player.global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = global_basis.z
	var angle: float = atan2(away.z, away.x) + _circle_side * 0.6
	var spot: Vector3 = player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * Config.feel.ai.circle_distance
	move_towards(spot, 0.6, delta)
	face(player.global_position, delta)


## Turn to look at a point (around the up axis).
func face(point: Vector3, delta: float) -> void:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	if offset.length() < 0.05:
		return
	var wanted: float = atan2(-offset.x, -offset.z)
	rotation.y = lerp_angle(rotation.y, wanted, clampf(Config.feel.ai.turn_speed * delta, 0.0, 1.0))


func attack_ready() -> bool:
	return _now() >= _attack_ready_at


## NEW 2026-10-30 (step 3.4): host: take attack tickets for its target (true if it holds them now).
func claim_attack_ticket() -> bool:
	var target: PlayerCharacter = get_target()
	return target != null and attack_ready() and AttackTickets.claim(self, target)


## NEW 2026-10-30 (step 3.4): host: the wind-up everyone sees and hears before an attack.
func begin_windup() -> void:
	_windup_rpc.rpc(Config.feel.ai.attack_windup)


## NEW 2026-10-30 (step 3.4): host: the wind-up is over, the attack starts (a kangaroo leaps now).
func strike() -> void:
	for behaviour: EnemyBehaviour in _behaviours:
		behaviour.on_strike(self)


## NEW 2026-10-30 (step 3.4): host: the attack is over (hit or miss): hand the tickets back. A miss still
## costs half a cooldown, so it doesn't grab the tickets straight back.
func end_attack() -> void:
	AttackTickets.release(self)
	if data != null:
		_attack_ready_at = maxf(_attack_ready_at, _now() + data.attack_cooldown * 0.5)


## Host, attack states: hit the target if it's in range. True if it hit.
## CHANGED 2026-10-30 (step 3.1): an attempt out of range no longer uses up the cooldown.
func try_attack() -> bool:
	var target: PlayerCharacter = get_target()
	if target == null or data == null or not attack_ready():
		return false
	# Measured to the player's chest, so flying enemies count too; a little extra for a lunge.
	if global_position.distance_to(target.global_position + Vector3.UP) > data.attack_range + 0.8:
		return false
	_attack_ready_at = _now() + data.attack_cooldown
	var info := DamageInfo.make(data.attack_damage, data.attack_damage_type, self)
	var push: Vector3 = target.global_position - global_position
	push.y = 0.0
	info.knockback = push.normalized() * attack_knockback + Vector3.UP * attack_knockback * 0.3
	info.hit_position = target.global_position
	for behaviour: EnemyBehaviour in _behaviours:
		behaviour.on_attack(self, info)
	var hurtbox: Node = target.get_node_or_null(NodePath(Hurtbox.NODE_NAME))
	Damage.hit(hurtbox if hurtbox != null else target, info)
	_attacked_rpc.rpc()
	return true


## NEW 2026-10-30 (step 3.6): host: a prop is flying at `prop_velocity` from `prop_position`. If it's heavy
## enough (the caller checks) and will pass close, this enemy may jump aside (EnemyData.dodge_chance, rolled
## once per prop). True if it dodged.
func consider_dodge(prop_id: int, prop_position: Vector3, prop_velocity: Vector3) -> bool:
	if _dead or flying or data == null or data.dodge_chance <= 0.0 or _dodge_left > 0.0 or _now() < _dodge_ready_at:
		return false
	if not is_on_floor() or (_state != null and not _state.can_interrupt(self)) or _dodge_decided.has(prop_id):
		return false
	var tuning: AiTuning = Config.feel.ai
	var speed: float = prop_velocity.length()
	if speed < tuning.dodge_min_speed:
		return false
	var heading: Vector3 = prop_velocity / speed
	var offset: Vector3 = (global_position + Vector3.UP * hurtbox_height * 0.5) - prop_position
	var ahead: float = offset.dot(heading)
	if ahead <= 0.0 or ahead > tuning.dodge_look_distance:
		return false
	var beside: Vector3 = offset - heading * ahead
	if beside.length() > tuning.dodge_miss_distance + hurtbox_radius:
		return false
	if _dodge_decided.size() > 32:
		_dodge_decided.clear()
	_dodge_decided[prop_id] = true
	if rng.randf() > data.dodge_chance:
		return false
	var side: Vector3 = heading.cross(Vector3.UP)
	side.y = 0.0
	if side.length() < 0.01:
		side = global_basis.x
	side = side.normalized()
	beside.y = 0.0
	if beside.length() > 0.05 and side.dot(beside) < 0.0:
		side = -side
	velocity = side * tuning.dodge_speed + Vector3.UP * 3.0
	_dodge_left = DODGE_SECONDS
	_dodge_ready_at = _now() + tuning.dodge_cooldown
	return true


## NEW 2026-10-30 (punt): host: shove it at `push` m/s. For KNOCK_SECONDS it doesn't think, it just slides
## (and falls), slowing down. No damage: whoever shoves it decides that.
func knock_back(push: Vector3) -> void:
	if _dead:
		return
	velocity = push
	_knock_left = KNOCK_SECONDS


## NEW 2026-10-30 (doors): host: the way it is trying to walk right now (m/s): what it asked move_towards for in
## the last couple of physics frames, even if a wall or a shut door stops it. Zero when it isn't walking.
func get_walk_intent() -> Vector3:
	if _dead or Engine.get_physics_frames() - _walk_intent_frame > 2:
		return Vector3.ZERO
	return _walk_intent


## NEW 2026-10-30 (punt): is it being shoved right now?
func is_knocked_back() -> bool:
	return _knock_left > 0.0


## NEW 2026-10-30: is it in the middle of jumping aside?
func is_dodging() -> bool:
	return _dodge_left > 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_follow_sync(delta)
		return
	if _dead:
		if not flying:
			velocity.y -= _gravity() * delta
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
		return
	if _dodge_left > 0.0:
		# Mid-jump aside: no thinking, just fly.
		_dodge_left -= delta
	elif _knock_left > 0.0:
		# NEW 2026-10-30: shoved (punt): no thinking, slide to a stop.
		_knock_left -= delta
		if flying or is_on_floor():
			var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, KNOCK_FRICTION * delta)
			velocity.x = flat.x
			velocity.z = flat.z
			if flying:
				velocity.y = move_toward(velocity.y, 0.0, KNOCK_FRICTION * delta)
	elif _state != null:
		var next: StringName = _state.physics_update(self, delta)
		if next != &"" and next != _state_name and _states.has(next) and _states[next].can_enter(self):
			_change_state(next)
	if not flying:
		velocity.y = 0.0 if is_on_floor() and velocity.y < 0.0 else velocity.y - _gravity() * delta
	move_and_slide()
	_sync_left -= delta
	if _sync_left <= 0.0 and multiplayer.has_multiplayer_peer():
		_sync_left = SYNC_INTERVAL
		_sync_rpc.rpc(global_position, rotation.y, _state_name)


func _change_state(next: StringName) -> void:
	if _state != null:
		_state.exit(self)
	_state_name = next
	_state = _states.get(next)
	if _state != null:
		_state.enter(self)
	for behaviour: EnemyBehaviour in _behaviours:
		behaviour.on_state_changed(self, next)
	state_changed.emit(next)


## Host: it just noticed `player` while calm: squeak (every PC hears it) and tell nearby enemies of its kind.
func _on_noticed(player: PlayerCharacter) -> void:
	noticed.emit(player)
	_noticed_rpc.rpc()
	if data == null:
		return
	var radius: float = Config.feel.ai.pack_alert_radius
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Enemy
		if other == null or other == self or other.is_dead() or other.data == null or other.data.id != data.id:
			continue
		if other.get_world_3d() == get_world_3d() and other.global_position.distance_to(global_position) <= radius:
			other.alert_to(player)


## Every PC: it died. It becomes a tumbling body; the host tells EventBus, squeals (a noise enemies hear) and
## removes it after a moment.
func _on_died(info: DamageInfo) -> void:
	if _dead:
		return
	_dead = true
	AttackTickets.release(self)
	collision_layer = 0
	var hurtbox := get_node_or_null(NodePath(Hurtbox.NODE_NAME)) as Area3D
	if hurtbox != null:
		hurtbox.set_deferred(&"monitorable", false)
		hurtbox.collision_layer = 0
	if not _spawn_corpse(info):
		create_tween().tween_property(self, "rotation:z", deg_to_rad(90.0), 0.4)
	if flying:
		flying = false
	died.emit(info)
	if multiplayer.is_server():
		_state_name = &"dead"
		EventBus.enemy_killed.emit(data.id if data != null else &"", global_position, info.source_player_id)
		EventBus.noise_made.emit(global_position, Config.feel.ai.noise_death, 0)
		get_tree().create_timer(Config.feel.ai.corpse_seconds).timeout.connect(queue_free)


## NEW 2026-10-30 (step 3.6): every PC: a loose physics copy of its look and shape that tumbles away from the
## hit, then shrinks away. Only the world and props block it (it's on the debris layer). False if this enemy
## has no "Mesh" and "Shape" to copy.
func _spawn_corpse(info: DamageInfo) -> bool:
	var mesh := get_node_or_null(^"Mesh") as MeshInstance3D
	var shape_node := get_node_or_null(^"Shape") as CollisionShape3D
	if mesh == null or shape_node == null or shape_node.shape == null or not is_inside_tree() or get_parent() == null:
		return false
	var corpse := RigidBody3D.new()
	corpse.name = "%sBody" % name
	corpse.collision_layer = PhysicsLayers.bit(PhysicsLayers.DEBRIS)
	corpse.collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS)
	corpse.mass = clampf(get_impact_mass(), 0.5, 300.0)
	var shape := CollisionShape3D.new()
	shape.shape = shape_node.shape
	shape.transform = shape_node.transform
	corpse.add_child(shape)
	var look := mesh.duplicate() as MeshInstance3D
	look.visible = true
	corpse.add_child(look)
	corpse_parent().add_child(corpse)
	corpse.global_transform = global_transform
	var push: Vector3 = info.knockback if info != null else Vector3.ZERO
	if push.length() < 0.1 and info != null and info.hit_position != Vector3.ZERO:
		push = global_position - info.hit_position
	push.y = 0.0
	if push.length() < 0.1:
		push = global_basis.z
	var moving: Vector3 = velocity if multiplayer.is_server() else Vector3.ZERO
	corpse.linear_velocity = moving * 0.5 + push.normalized() * 2.5 + Vector3.UP * 2.0
	corpse.angular_velocity = Vector3(randf_range(-5.0, 5.0), randf_range(-2.0, 2.0), randf_range(-5.0, 5.0))
	mesh.visible = false
	var tween: Tween = corpse.create_tween()
	tween.tween_interval(Config.feel.ai.corpse_seconds + 1.0)
	tween.tween_property(look, "scale", Vector3.ONE * 0.01, 0.5)
	tween.tween_callback(corpse.queue_free)
	_corpses.append(weakref(corpse))
	_trim_corpses()
	return true


## NEW 2026-10-30: where its dead body goes: next to its spawner (not inside it, so it is never mistaken
## for a spawned enemy), or next to the enemy.
func corpse_parent() -> Node:
	var parent: Node = get_parent()
	if parent is EnemySpawner and parent.get_parent() != null:
		return parent.get_parent()
	return parent


## Keep at most Config.feel.ai.max_corpses bodies on this PC: the oldest go first.
static func _trim_corpses() -> void:
	var alive: Array[WeakRef] = []
	for entry: WeakRef in _corpses:
		var body := entry.get_ref() as Node
		if body != null and not body.is_queued_for_deletion():
			alive.append(entry)
	while alive.size() > Config.feel.ai.max_corpses:
		var first: WeakRef = alive.pop_front()
		var oldest := first.get_ref() as Node
		if oldest != null:
			oldest.queue_free()
	_corpses = alive


## NEW 2026-10-30: how many enemy bodies are lying around on this PC (tests).
static func count_corpses() -> int:
	_trim_corpses()
	return _corpses.size()


func _follow_sync(delta: float) -> void:
	if not _has_sync:
		return
	var blend: float = 1.0 - exp(-Config.feel.ai.client_smoothing * delta)
	global_position = global_position.lerp(_synced_position, blend)
	rotation.y = lerp_angle(rotation.y, _synced_yaw, blend)


func _nav_ready() -> bool:
	return is_inside_tree() and NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0 \
		and not NavigationServer3D.map_get_regions(get_world_3d().navigation_map).is_empty()


## Spacing (NEW 2026-10-30, step 3.5; replaces the swarm's every-rat-against-every-rat check each frame):
## walking enemies that are too close push each other apart, the smaller one more. The push is worked out a
## few times a second and added to where it wants to go.
func _with_spacing(wanted: Vector3, speed: float, delta: float) -> Vector3:
	_spacing_left -= delta
	if _spacing_left <= 0.0:
		_spacing_left = Config.feel.ai.spacing_check_seconds
		_spacing_push = _work_out_spacing()
	if _spacing_push.is_zero_approx() or wanted.length() < 0.01:
		return wanted
	return (wanted + _spacing_push * speed).limit_length(speed)


## NEW 2026-10-30: the push (length 0 to about 1) away from walking enemies whose bodies are too close.
func get_spacing_push() -> Vector3:
	return _spacing_push


func _work_out_spacing() -> Vector3:
	var push := Vector3.ZERO
	var gap: float = Config.feel.ai.spacing_gap
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Enemy
		if other == null or other == self or other.is_dead() or other.flying or other.get_world_3d() != get_world_3d():
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var reach: float = hurtbox_radius + other.hurtbox_radius + gap
		var distance: float = offset.length()
		if distance >= reach:
			continue
		if distance < 0.01:
			offset = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		# The one with the lower priority makes more room.
		var share: float = clampf(0.5 + other.avoidance_priority - avoidance_priority, 0.1, 1.0)
		push += offset.normalized() * (reach - distance) / reach * share * 2.0
	return push.limit_length(1.0)


## Flying: the next point to head for along the ground's navigation path to `point` (its height is set by
## move_towards). Worked out again every repath_seconds or when the goal moves.
func _next_flyer_point(point: Vector3, delta: float) -> Vector3:
	_repath_left -= delta
	if _repath_left <= 0.0 or _flyer_goal.distance_to(point) > 1.0:
		_repath_left = Config.feel.ai.repath_seconds
		_flyer_goal = point
		var from := Vector3(global_position.x, _ground_height(global_position), global_position.z)
		var to := Vector3(point.x, _ground_height(point), point.z)
		_flyer_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)
		_flyer_index = 0
	while _flyer_index < _flyer_path.size() and flat_distance_to(_flyer_path[_flyer_index]) < 0.8:
		_flyer_index += 1
	if _flyer_index >= _flyer_path.size():
		return point
	var next: Vector3 = _flyer_path[_flyer_index]
	return Vector3(next.x, point.y, next.z)


func _ground_height(point: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = Vector3(point.x, maxf(point.y, global_position.y) + 1.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, PhysicsLayers.bit(PhysicsLayers.WORLD))
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return point.y
	var where: Vector3 = hit["position"]
	return where.y


func _gravity() -> float:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return gravity


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Host -> everyone else: where it is and what it's doing.
@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_rpc(where: Vector3, yaw: float, state: StringName) -> void:
	if not is_inside_tree():
		return
	if not _has_sync:
		global_position = where
		rotation.y = yaw
	_has_sync = true
	_synced_position = where
	_synced_yaw = yaw
	if state != _state_name:
		_state_name = state
		for behaviour: EnemyBehaviour in _behaviours:
			behaviour.on_state_changed(self, state)
		state_changed.emit(state)


## Host -> everyone: it attacked (a lunge everyone sees).
@rpc("authority", "call_local", "reliable")
func _attacked_rpc() -> void:
	if not is_inside_tree():
		return
	var mesh := get_node_or_null(^"Mesh") as Node3D
	if mesh == null:
		return
	var rest: Vector3 = mesh.position
	var tween: Tween = mesh.create_tween()
	tween.tween_property(mesh, "position", rest + Vector3(0, 0, -0.25), 0.08)
	tween.tween_property(mesh, "position", rest, 0.15)


## NEW 2026-10-30: host -> everyone: it noticed someone (a squeak).
@rpc("authority", "call_local", "reliable")
func _noticed_rpc() -> void:
	if is_inside_tree():
		Sound.play_3d(Sound.event_sound(&"enemy_notice"), global_position + Vector3.UP * 0.4, -4.0, 0.15)


## NEW 2026-10-30: host -> everyone: it winds up an attack (a growl, and it crouches back for `seconds`).
@rpc("authority", "call_local", "reliable")
func _windup_rpc(seconds: float) -> void:
	if not is_inside_tree():
		return
	Sound.play_3d(Sound.event_sound(&"enemy_windup"), global_position + Vector3.UP * 0.4, -2.0, 0.1)
	var mesh := get_node_or_null(^"Mesh") as Node3D
	if mesh == null:
		return
	var rest: Vector3 = mesh.position
	var tween: Tween = mesh.create_tween()
	tween.tween_property(mesh, "position", rest + Vector3(0, -0.05, 0.15), seconds * 0.8)
	tween.tween_property(mesh, "position", rest, seconds * 0.2)


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_sync_rpc.rpc_id(multiplayer.get_remote_sender_id(), global_position, rotation.y, _state_name)
