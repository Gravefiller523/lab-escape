class_name Boss
extends Enemy
## A department boss (the root of a boss scene). It is an Enemy (movement, sight, health, syncing) with
## phases from its BossData: each phase lists which named BossAttack children it uses and which minions
## it summons. The phase changes when health drops past a threshold. Spec: docs/systems/bosses.md.
## The host decides everything; phases and attack wind-ups reach every PC by RPC.

signal phase_changed(phase_index: int)

const GROUP_BOSSES: StringName = &"bosses"
## Minions appear this far from the boss when the arena has no minion_spawn markers.
const MINION_RING: float = 4.0
## How close to the arena walls the boss can get (metres).
const ARENA_MARGIN: float = 1.5

## Walking speed between attacks (metres per second).
@export var boss_move_speed: float = 3.5
## Seconds between attacks.
@export var attack_gap: float = 1.2
@export var boss_sight_range: float = 60.0

var boss_data: BossData

var _phase: int = -1
var _fighting: bool = false
var _attacks: Dictionary[StringName, BossAttack] = {}
var _current_attack: BossAttack
var _next_attack_at: float = 0.0
var _wave_left: float = 0.0
var _health_label: Label3D


func _ready() -> void:
	add_to_group(GROUP_BOSSES)
	for child: Node in find_children("*", "", true, false):
		var attack := child as BossAttack
		if attack != null:
			_attacks[attack.attack_name] = attack
	super._ready()
	_health_label = get_node_or_null(^"HealthLabel") as Label3D
	var health: HealthComponent = get_health()
	if health != null:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.get_current(), health.get_max())
	died.connect(_on_boss_died)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_phase_rpc.rpc_id(1)


## Built from BossData: the numbers Enemy needs come from it and from this scene's exports.
func setup_from(content: ContentData, health_multiplier: float, rng_seed: int, rng_index: int) -> void:
	boss_data = content as BossData
	if boss_data == null:
		super.setup_from(content, health_multiplier, rng_seed, rng_index)
		return
	var numbers := EnemyData.new()
	numbers.id = boss_data.id
	numbers.display_name = boss_data.display_name
	numbers.max_health = boss_data.max_health
	numbers.move_speed = boss_move_speed
	numbers.sight_range = boss_sight_range
	numbers.loot_id = boss_data.loot_id
	numbers.impact_mass = boss_data.impact_mass
	setup(numbers, health_multiplier, rng_seed, rng_index)


## The boss in the game now, or null.
static func current() -> Boss:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP_BOSSES):
		var boss := node as Boss
		if boss != null and not boss.is_dead() and not boss.is_queued_for_deletion():
			return boss
	return null


func get_phase() -> int:
	return _phase


func is_fighting() -> bool:
	return _fighting


## An attack by its name (BossPhaseData.attack_names), or null.
func get_attack(attack_name: StringName) -> BossAttack:
	return _attacks.get(attack_name)


func get_current_attack() -> BossAttack:
	return _current_attack


## Host: the fight begins (the arena calls it when a player walks in; it also starts if the boss sees you).
func start_fight() -> void:
	if not multiplayer.is_server() or _fighting or is_dead():
		return
	_fighting = true
	_next_attack_at = _now() + attack_gap
	_set_phase(_phase_for(get_health().get_fraction()))


## Host, boss_fight state: pick an attack from this phase that can start now (null if none or too soon).
func choose_attack() -> BossAttack:
	if _now() < _next_attack_at or boss_data == null or _phase < 0 or _phase >= boss_data.phases.size():
		return null
	var ready_attacks: Array[BossAttack] = []
	for attack_name: String in boss_data.phases[_phase].attack_names:
		var attack: BossAttack = get_attack(StringName(attack_name))
		if attack != null and attack.can_start(self):
			ready_attacks.append(attack)
	if ready_attacks.is_empty():
		return null
	return ready_attacks[rng.randi_range(0, ready_attacks.size() - 1)]


## Host: the boss never leaves its arena (it would charge out of the open doorway otherwise).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var arena: BossArena = BossArena.current()
	if arena != null and multiplayer.is_server() and not is_dead():
		var inside: Vector3 = arena.clamp_inside(global_position, ARENA_MARGIN)
		if not inside.is_equal_approx(global_position):
			global_position = Vector3(inside.x, global_position.y, inside.z)


## Host: begin an attack; every PC sees its wind-up.
func begin_attack(attack: BossAttack) -> void:
	_current_attack = attack
	attack.start(self, get_target())
	_attack_effect_rpc.rpc(attack.attack_name)


## Host: the current attack is over.
func end_attack() -> void:
	_current_attack = null
	_next_attack_at = _now() + attack_gap


## Host, boss_fight state: minion waves on a timer (minion_wave_interval).
func update_waves(delta: float) -> void:
	if not _fighting or boss_data == null or _phase < 0:
		return
	var phase: BossPhaseData = boss_data.phases[_phase]
	if phase.minion_wave_interval <= 0.0:
		return
	_wave_left -= delta
	if _wave_left <= 0.0:
		_wave_left = phase.minion_wave_interval
		spawn_wave()


## Host: one wave of this phase's minions (more with more players).
func spawn_wave() -> Array[Enemy]:
	var spawned: Array[Enemy] = []
	if boss_data == null or _phase < 0:
		return spawned
	var phase: BossPhaseData = boss_data.phases[_phase]
	if phase.minion_enemy_ids.is_empty() or phase.minions_per_wave <= 0:
		return spawned
	var count: int = minions_for_players(phase.minions_per_wave, Net.get_player_count())
	var points: Array[Node3D] = []
	var arena: BossArena = BossArena.current()
	if arena != null:
		points = arena.get_minion_spawn_points()
	for index: int in count:
		var minion_id: StringName = phase.minion_enemy_ids[index % phase.minion_enemy_ids.size()]
		var where: Vector3
		if not points.is_empty():
			where = points[index % points.size()].global_position + Vector3(rng.randf_range(-1.0, 1.0), 0.3, rng.randf_range(-1.0, 1.0))
		else:
			var angle: float = TAU * float(index) / float(count)
			where = global_position + Vector3(cos(angle) * MINION_RING, 0.3, sin(angle) * MINION_RING)
		var minion: Enemy = Enemies.spawn(minion_id, Transform3D(Basis.IDENTITY, where))
		if minion != null:
			spawned.append(minion)
	return spawned


## Minions per wave for this many players: base x (1 + boss_minions_per_extra_player per extra player).
static func minions_for_players(base: int, player_count: int, config: GameConfig = null) -> int:
	var game: GameConfig = config if config != null else Config.game
	return roundi(float(base) * (1.0 + game.boss_minions_per_extra_player * float(maxi(player_count, 1) - 1)))


## Which phase a health fraction is in: the last phase whose threshold it has dropped to.
func _phase_for(fraction: float) -> int:
	if boss_data == null:
		return -1
	var found: int = 0
	for index: int in boss_data.phases.size():
		if fraction <= boss_data.phases[index].starts_at_health_fraction + 0.0001:
			found = index
	return found


func _on_health_changed(health_now: float, maximum: float) -> void:
	if _health_label != null:
		var title: String = boss_data.display_name if boss_data != null else "Boss"
		_health_label.text = "%s  %d / %d" % [title.to_upper(), roundi(health_now), roundi(maximum)]
	if not multiplayer.is_server() or not _fighting or is_dead():
		return
	var phase: int = _phase_for(health_now / maximum if maximum > 0.0 else 0.0)
	if phase > _phase:
		_set_phase(phase)


func _set_phase(phase: int) -> void:
	_phase_rpc.rpc(phase)
	if boss_data == null or phase < 0 or phase >= boss_data.phases.size():
		return
	_wave_left = boss_data.phases[phase].minion_wave_interval
	spawn_wave()


func _on_boss_died(_info: DamageInfo) -> void:
	_current_attack = null
	EventBus.boss_defeated.emit(boss_data.id if boss_data != null else &"")
	if not multiplayer.is_server():
		return
	# The fight is over: the minions go too.
	for enemy: Enemy in Enemies.get_alive():
		if enemy != self and not enemy is Boss:
			enemy.queue_free()


## Host -> everyone: the phase changed.
@rpc("authority", "call_local", "reliable")
func _phase_rpc(phase: int) -> void:
	if not is_inside_tree() or phase == _phase:
		return
	_phase = phase
	_fighting = true
	phase_changed.emit(phase)
	EventBus.boss_phase_changed.emit(boss_data.id if boss_data != null else &"", phase)


## Host -> everyone: an attack is winding up (everyone sees it coming).
@rpc("authority", "call_local", "reliable")
func _attack_effect_rpc(attack_name: StringName) -> void:
	if not is_inside_tree():
		return
	var attack: BossAttack = get_attack(attack_name)
	if attack != null:
		attack.play_effect(self)


@rpc("any_peer", "call_remote", "reliable")
func _request_phase_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server() and _phase >= 0:
		_phase_rpc.rpc_id(multiplayer.get_remote_sender_id(), _phase)
