extends GutTest
## Tests for damage (docs/systems/damage.md). Solo tests: this PC is the host. The network tests use two
## "PCs" (SubViewports with their own multiplayer) over real ENet, each with the same target node.

const PORT: int = 18120
const WAIT: float = 5.0
const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

var _pcs: Array[Node] = []


## A target with Stats, Health (100), Statuses and a Hurtbox, like the Damage autoload gives players.
func _target(parent: Node = null, max_health: float = 100.0) -> Node3D:
	var target := Node3D.new()
	target.name = "Target"
	(parent if parent != null else self).add_child(target)
	DamageService.give_components(target, max_health)
	if parent == null:
		autofree(target)
	return target


## A status effect that isn't in a file (registered once per test run).
func _status(id: StringName, duration: float, tick_damage: float = 0.0, refresh: bool = true,
		modifiers: Array[StatEffectData] = []) -> StatusEffectData:
	if ContentRegistry.has_content(id):
		return ContentRegistry.get_content(id) as StatusEffectData
	var data := StatusEffectData.new()
	data.id = id
	data.duration = duration
	data.tick_damage = tick_damage
	data.tick_interval = 0.1
	data.damage_type = &"fire"
	data.refresh_on_reapply = refresh
	data.stat_modifiers = modifiers
	ContentRegistry.register_content(data)
	return data


func _stat(stat: StringName, add: float, multiply: float) -> StatEffectData:
	var modifier := StatEffectData.new()
	modifier.stat = stat
	modifier.add = add
	modifier.multiply = multiply
	return modifier


func _pc(hosting: bool) -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var peer := ENetMultiplayerPeer.new()
	if hosting:
		assert_eq(peer.create_server(PORT, 32), OK)
	else:
		peer.create_client("127.0.0.1", PORT)
	pc.multiplayer.multiplayer_peer = peer
	_pcs.append(pc)
	return pc


func after_each() -> void:
	var paths: Array[NodePath] = []
	var peers: Array[MultiplayerPeer] = []
	for pc: Node in _pcs:
		paths.append(pc.get_path())
		peers.append(pc.multiplayer.multiplayer_peer)
		pc.free()
	for index: int in paths.size():
		if peers[index] != null:
			peers[index].close()
		get_tree().set_multiplayer(null, paths[index])
	_pcs.clear()


func test_damage_reduces_health() -> void:
	var health: HealthComponent = HealthComponent.of(_target())
	health.apply_damage(DamageInfo.make(30.0, &"blunt"))
	assert_eq(health.get_current(), 70.0)
	assert_eq(health.get_max(), 100.0)
	health.heal(10.0)
	assert_eq(health.get_current(), 80.0)
	health.heal(500.0)
	assert_eq(health.get_current(), 100.0, "never above max")


func test_damage_dealt_event_on_host() -> void:
	var target := _target()
	watch_signals(EventBus)
	HealthComponent.of(target).apply_damage(DamageInfo.make(5.0, &"sharp"))
	assert_signal_emitted_with_parameters(EventBus, "damage_dealt", [target, 5.0, &"sharp", null])


func test_multiplier_by_type() -> void:
	var health: HealthComponent = HealthComponent.of(_target())
	health.damage_multipliers = {"fire": 2.0}
	health.apply_damage(DamageInfo.make(10.0, &"fire"))
	assert_eq(health.get_current(), 80.0, "fire does double")
	health.apply_damage(DamageInfo.make(10.0, &"blunt"))
	assert_eq(health.get_current(), 70.0, "other types do normal damage")


func test_died_emitted_once() -> void:
	var health: HealthComponent = HealthComponent.of(_target())
	watch_signals(health)
	health.apply_damage(DamageInfo.make(80.0, &"blunt"))
	health.apply_damage(DamageInfo.make(80.0, &"blunt"))
	health.apply_damage(DamageInfo.make(80.0, &"blunt"))
	assert_true(health.is_dead())
	assert_eq(health.get_current(), 0.0)
	assert_signal_emit_count(health, "died", 1)
	health.revive(0.5)
	assert_false(health.is_dead())
	assert_eq(health.get_current(), 50.0)
	assert_signal_emit_count(health, "revived", 1)


func test_invulnerable_ignores_damage() -> void:
	var health: HealthComponent = HealthComponent.of(_target())
	health.invulnerable = true
	health.apply_damage(DamageInfo.make(500.0, &"blunt"))
	assert_eq(health.get_current(), 100.0)
	assert_false(health.is_dead())


func test_hurtbox_weak_spot_multiplies() -> void:
	var target := _target()
	var hurtbox := target.get_node("Hurtbox") as Hurtbox
	assert_eq(hurtbox.collision_layer, PhysicsLayers.bit(PhysicsLayers.HITBOXES))
	hurtbox.multiplier = 2.0
	assert_true(Damage.hit(hurtbox, DamageInfo.make(10.0, &"sharp")))
	assert_eq(HealthComponent.of(target).get_current(), 80.0, "a weak spot does double")
	assert_true(Damage.hit(target, DamageInfo.make(10.0, &"sharp")), "hitting the node itself works too")
	assert_eq(HealthComponent.of(target).get_current(), 70.0)
	assert_false(Damage.hit(Node3D.new(), DamageInfo.make(10.0, &"sharp")), "nothing to hurt")


func test_stats_add_then_multiply() -> void:
	var stats := StatsComponent.new()
	add_child_autofree(stats)
	stats.set_base(&"melee_damage", 10.0)
	stats.add_modifier(&"mutation_a", _stat(&"melee_damage", 5.0, 1.0))
	stats.add_modifier(&"mutation_b", _stat(&"melee_damage", 0.0, 2.0))
	assert_eq(stats.get_value(&"melee_damage"), 30.0, "(10 + 5) x 2")
	assert_eq(stats.get_value(&"unknown_stat"), 0.0, "unknown stats are 0")
	assert_eq(stats.get_value(&"damage_taken", 1.0), 1.0, "or the default you pass")


func test_remove_modifiers_by_source() -> void:
	var stats := StatsComponent.new()
	add_child_autofree(stats)
	stats.set_base(&"move_speed", 4.0)
	stats.add_modifier(&"status_x", _stat(&"move_speed", 0.0, 1.5))
	stats.add_modifier(&"status_x", _stat(&"carry_strength", 20.0, 1.0))
	stats.add_modifier(&"upgrade_y", _stat(&"move_speed", 1.0, 1.0))
	watch_signals(stats)
	stats.remove_modifiers(&"status_x")
	assert_eq(stats.get_value(&"move_speed"), 5.0, "only status_x's modifiers are gone")
	assert_eq(stats.get_value(&"carry_strength"), 0.0)
	assert_signal_emitted(stats, "stat_changed")


func test_max_health_stat_keeps_the_fraction() -> void:
	var target := _target()
	var health: HealthComponent = HealthComponent.of(target)
	health.apply_damage(DamageInfo.make(50.0, &"blunt"))
	StatsComponent.of(target).add_modifier(&"mutation_tough", _stat(&"max_health", 100.0, 1.0))
	assert_eq(health.get_max(), 200.0)
	assert_eq(health.get_current(), 100.0, "still half health")


func test_damage_taken_stat_multiplies_damage() -> void:
	var target := _target()
	StatsComponent.of(target).add_modifier(&"armour", _stat(&"damage_taken", 0.0, 0.5))
	HealthComponent.of(target).apply_damage(DamageInfo.make(40.0, &"blunt"))
	assert_eq(HealthComponent.of(target).get_current(), 80.0)


func test_status_ticks_damage_then_expires() -> void:
	_status(&"status_test_tick", 0.35, 10.0)
	var target := _target()
	var statuses: StatusEffectComponent = StatusEffectComponent.of(target)
	watch_signals(statuses)
	statuses.apply(&"status_test_tick")
	assert_true(statuses.has_status(&"status_test_tick"))
	assert_signal_emitted(statuses, "status_added")
	await wait_until(func() -> bool: return not statuses.has_status(&"status_test_tick"), WAIT)
	assert_false(statuses.has_status(&"status_test_tick"), "expired")
	assert_signal_emitted(statuses, "status_removed")
	var lost: float = 100.0 - HealthComponent.of(target).get_current()
	assert_between(lost, 20.0, 40.0, "ticked about 3 times (every 0.1 s for 0.35 s)")


func test_reapply_refreshes_timer() -> void:
	_status(&"status_test_refresh", 1.0, 0.0, true)
	_status(&"status_test_no_refresh", 1.0, 0.0, false)
	var statuses: StatusEffectComponent = StatusEffectComponent.of(_target())
	statuses.apply(&"status_test_refresh")
	statuses.apply(&"status_test_no_refresh")
	await wait_seconds(0.5)
	statuses.apply(&"status_test_refresh")
	statuses.apply(&"status_test_no_refresh")
	assert_almost_eq(statuses.get_time_left(&"status_test_refresh"), 1.0, 0.05, "restarted")
	assert_almost_eq(statuses.get_time_left(&"status_test_no_refresh"), 0.5, 0.1, "kept going")


func test_status_stat_modifiers_and_visual_come_and_go() -> void:
	var modifiers: Array[StatEffectData] = [_stat(&"move_speed", 0.0, 1.5)]
	_status(&"status_test_fast", 0.3, 0.0, true, modifiers)
	var target := _target()
	var stats: StatsComponent = StatsComponent.of(target)
	stats.set_base(&"move_speed", 4.0)
	var statuses: StatusEffectComponent = StatusEffectComponent.of(target)
	statuses.apply(&"status_test_fast")
	assert_eq(stats.get_value(&"move_speed"), 6.0, "x1.5 while active")
	await wait_until(func() -> bool: return not statuses.has_status(&"status_test_fast"), WAIT)
	assert_eq(stats.get_value(&"move_speed"), 4.0, "back to normal")


func test_burning_content_shows_its_fire() -> void:
	var target := _target()
	StatusEffectComponent.of(target).apply(&"status_burning")
	assert_not_null(target.get_node_or_null("StatusVisual_status_burning"), "the burning particles are on the target")
	StatusEffectComponent.of(target).remove(&"status_burning")
	await wait_process_frames(2)
	assert_null(target.get_node_or_null("StatusVisual_status_burning"))


func test_dead_targets_lose_their_statuses() -> void:
	_status(&"status_test_long", 10.0)
	var target := _target()
	var statuses: StatusEffectComponent = StatusEffectComponent.of(target)
	statuses.apply(&"status_test_long")
	HealthComponent.of(target).apply_damage(DamageInfo.make(500.0, &"blunt"))
	await wait_process_frames(2)
	assert_false(statuses.has_status(&"status_test_long"))


func test_player_bodies_get_damage_components() -> void:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 4242
	add_child_autofree(body)
	assert_not_null(HealthComponent.of(body))
	assert_eq(HealthComponent.of(body).get_max(), Config.game.player_max_health)
	assert_not_null(StatsComponent.of(body))
	assert_not_null(StatusEffectComponent.of(body))
	assert_not_null(body.get_node_or_null("Hurtbox"))


func test_health_is_the_same_on_host_and_client() -> void:
	var host := _pc(true)
	var client := _pc(false)
	await wait_until(func() -> bool: return client.multiplayer.get_unique_id() > 1 \
		and host.multiplayer.get_peers().size() == 1, WAIT)
	var on_host := _target(host)
	var on_client := _target(client)
	var host_health: HealthComponent = HealthComponent.of(on_host)
	var client_health: HealthComponent = HealthComponent.of(on_client)
	host_health.apply_damage(DamageInfo.make(35.0, &"blunt"))
	await wait_until(func() -> bool: return is_equal_approx(client_health.get_current(), 65.0), WAIT)
	assert_eq(client_health.get_current(), 65.0, "the client sees the host's health")
	watch_signals(client_health)
	host_health.apply_damage(DamageInfo.make(100.0, &"fire"))
	await wait_until(func() -> bool: return client_health.is_dead(), WAIT)
	await wait_process_frames(2)
	assert_signal_emit_count(client_health, "died", 1, "died fires on the client too")
	host_health.revive()
	StatusEffectComponent.of(on_host).apply(&"status_burning")
	await wait_until(func() -> bool: return StatusEffectComponent.of(on_client).has_status(&"status_burning"), WAIT)
	assert_true(StatusEffectComponent.of(on_client).has_status(&"status_burning"), "statuses reach the client")


func test_client_cannot_apply_damage() -> void:
	var host := _pc(true)
	var client := _pc(false)
	await wait_until(func() -> bool: return client.multiplayer.get_unique_id() > 1 \
		and host.multiplayer.get_peers().size() == 1, WAIT)
	var on_host := _target(host)
	var on_client := _target(client)
	await wait_process_frames(5)
	HealthComponent.of(on_client).apply_damage(DamageInfo.make(50.0, &"blunt"))
	StatusEffectComponent.of(on_client).apply(&"status_burning")
	await wait_process_frames(10)
	assert_eq(HealthComponent.of(on_client).get_current(), 100.0, "nothing changed on the client")
	assert_eq(HealthComponent.of(on_host).get_current(), 100.0, "or on the host")
	assert_false(StatusEffectComponent.of(on_host).has_status(&"status_burning"))


func test_late_client_copy_asks_for_the_health() -> void:
	var host := _pc(true)
	var on_host := _target(host)
	HealthComponent.of(on_host).apply_damage(DamageInfo.make(60.0, &"blunt"))
	var client := _pc(false)
	await wait_until(func() -> bool: return client.multiplayer.get_unique_id() > 1 \
		and host.multiplayer.get_peers().size() == 1, WAIT)
	var on_client := _target(client)
	await wait_until(func() -> bool: return is_equal_approx(HealthComponent.of(on_client).get_current(), 40.0), WAIT)
	assert_eq(HealthComponent.of(on_client).get_current(), 40.0, "a copy made after the hit gets the right health")
