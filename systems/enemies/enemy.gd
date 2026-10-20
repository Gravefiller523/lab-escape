class_name Enemy
extends CharacterBody3D
## One regular enemy (the root of every enemy scene). Spec: docs/systems/enemies.md.
## A scene is this body plus: a "States" node whose children are shared EnemyStates (idle, patrol, chase,
## swarm, attack_melee, flee; the child's name is the state's name), optional EnemyBehaviour children
## (a kangaroo's leap, a bat's swoop), a mesh and a collision shape. Numbers come from its EnemyData.
##
## The AI runs only on the host. The host sends position, facing and state ~20 times a second; other
## PCs slide their copy there. Health, statuses and the hurtbox come from damage (give_components).

signal state_changed(state: StringName)

const GROUP: StringName = &"enemies"
const SYNC_INTERVAL: float = 0.05
const CLIENT_SMOOTHING: float = 15.0
const TURN_SPEED: float = 8.0
## Seconds it remembers a player it can no longer see (it goes to where they were last).
const TARGET_MEMORY: float = 3.0
## Seconds a dead enemy lies there before it's removed.
const CORPSE_SECONDS: float = 2.0
## How often the path is worked out again (seconds).
const REPATH_SECONDS: float = 0.25

## Flies instead of walking (bats, flies): no gravity, steers straight through the air.
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

var data: EnemyData
## Shared state machine data the states may use.
var home: Vector3 = Vector3.ZERO
## Flying: when >= 0, fly at this height above the ground instead of hover_height (a bat's dive).
var altitude_override: float = -1.0
var last_known_position: Vector3 = Vector3.ZERO
## NEW 2026-10-20: it already ran away once (enemies flee only once, then fight to the end).
var has_fled: bool = false
## Host: this enemy's own random numbers (wandering, swarm angles). Seeded per run and enemy (SeededRng).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _target: PlayerCharacter
var _target_lost_at: float = -1.0
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


## The enemy a node belongs to (a hitbox, a mesh), or null.
static func of(node: Node) -> Enemy:
	var current: Node = node
	while current != null:
		var enemy := current as Enemy
		if enemy != null:
			return enemy
		current = current.get_parent()
	return null


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS) \
		| PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	home = global_position
	_synced_position = global_position
	_synced_yaw = rotation.y
	_perception = Perception.new()
	add_child(_perception)
	_agent = NavigationAgent3D.new()
	_agent.name = "Agent"
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.6
	add_child(_agent)
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


## Host (EnemySpawner): the numbers and the damage components. Called before it enters the tree.
func setup(enemy_data: EnemyData, health_multiplier: float, rng_seed: int = 0, rng_index: int = 0) -> void:
	data = enemy_data
	rng = SeededRng.make(rng_seed, &"enemy_ai", rng_index)
	DamageService.give_components(self, data.max_health * health_multiplier, hurtbox_radius, hurtbox_height)


func get_health() -> HealthComponent:
	return HealthComponent.of(self)


func get_target() -> PlayerCharacter:
	return _target if is_instance_valid(_target) else null


func set_target(player: PlayerCharacter) -> void:
	_target = player
	if player != null:
		last_known_position = player.global_position
		_target_lost_at = -1.0


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


## Host: a player it noticed (or still remembers). Updates the target from Perception.
func update_target() -> PlayerCharacter:
	var seen: PlayerCharacter = _perception.get_nearest_visible_player()
	if seen != null:
		set_target(seen)
	elif get_target() != null:
		if _target_lost_at < 0.0:
			_target_lost_at = _now()
		elif _now() - _target_lost_at > TARGET_MEMORY or not _perception.is_valid_target(_target):
			_target = null
	return get_target()


func distance_to_target() -> float:
	var target: PlayerCharacter = get_target()
	return global_position.distance_to(target.global_position) if target != null else INF


## Horizontal distance to the target (ignores how high a flying enemy is).
func flat_distance_to_target() -> float:
	var target: PlayerCharacter = get_target()
	if target == null:
		return INF
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	return offset.length()


func move_speed() -> float:
	var base: float = data.move_speed if data != null else 3.0
	var stats: StatsComponent = StatsComponent.of(self)
	return base * (stats.get_value(&"move_speed_multiplier", 1.0) if stats != null else 1.0)


## Host, states: walk (or fly) towards a point at speed x `speed_scale`. Uses the navigation mesh when
## there is one (paths through doorways), otherwise heads straight there.
func move_towards(point: Vector3, speed_scale: float, delta: float) -> void:
	var next_point: Vector3 = point
	if not flying and _nav_ready():
		_repath_left -= delta
		if _repath_left <= 0.0 or _agent.target_position.distance_to(point) > 1.0:
			_repath_left = REPATH_SECONDS
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
	velocity.x = wanted.x
	velocity.z = wanted.z
	if flying:
		velocity.y = wanted.y
	face(point, delta)


## Host, states: stand still (flying enemies hover at their height).
func stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if flying:
		var altitude: float = altitude_override if altitude_override >= 0.0 else hover_height
		velocity.y = clampf((_ground_height(global_position) + altitude - global_position.y) * 2.0, -3.0, 3.0)


## Turn to look at a point (around the up axis).
func face(point: Vector3, delta: float) -> void:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	if offset.length() < 0.05:
		return
	var wanted: float = atan2(-offset.x, -offset.z)
	rotation.y = lerp_angle(rotation.y, wanted, clampf(TURN_SPEED * delta, 0.0, 1.0))


func attack_ready() -> bool:
	return _now() >= _attack_ready_at


## Host, attack states: hit the target if it's in range. True if it hit.
func try_attack() -> bool:
	var target: PlayerCharacter = get_target()
	if target == null or data == null or not attack_ready():
		return false
	_attack_ready_at = _now() + data.attack_cooldown
	# Measured to the player's chest, so flying enemies count too; a little extra for a lunge.
	if global_position.distance_to(target.global_position + Vector3.UP) > data.attack_range + 0.8:
		return false
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
	if _state != null:
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


## Every PC: it died. Falls over; the host tells EventBus and removes it after a moment.
func _on_died(info: DamageInfo) -> void:
	if _dead:
		return
	_dead = true
	collision_layer = 0
	var hurtbox := get_node_or_null(NodePath(Hurtbox.NODE_NAME)) as Area3D
	if hurtbox != null:
		hurtbox.set_deferred(&"monitorable", false)
		hurtbox.collision_layer = 0
	create_tween().tween_property(self, "rotation:z", deg_to_rad(90.0), 0.4)
	if flying:
		flying = false
	if multiplayer.is_server():
		_state_name = &"dead"
		EventBus.enemy_killed.emit(data.id if data != null else &"", global_position, info.source_player_id)
		get_tree().create_timer(CORPSE_SECONDS).timeout.connect(queue_free)


func _follow_sync(delta: float) -> void:
	if not _has_sync:
		return
	var blend: float = 1.0 - exp(-CLIENT_SMOOTHING * delta)
	global_position = global_position.lerp(_synced_position, blend)
	rotation.y = lerp_angle(rotation.y, _synced_yaw, blend)


func _nav_ready() -> bool:
	return is_inside_tree() and NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0 \
		and not NavigationServer3D.map_get_regions(get_world_3d().navigation_map).is_empty()


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


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_sync_rpc.rpc_id(multiplayer.get_remote_sender_id(), global_position, rotation.y, _state_name)
