extends GutTest
## Tests for the punt (NEW 2026-10-30, HL2 feel step 4.3; docs/systems/physics_props.md, "Punt"), the pull and
## punting enemies (NEW 2026-10-30, Zachary's ideas). Each "PC"
## is a SubViewport with its own physics, multiplayer, Net, player spawner and prop spawner, as in
## test_props.gd, so two can talk over real ENet. The punt arm is added straight to the body here; the
## upgrades tests check that the cybernetic adds it.

const PORT: int = 18050
const WAIT: float = 5.0

var _pcs: Array[Node] = []


func _make_pc() -> Node:
	var config := GameConfig.new()
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	var level := Node3D.new()
	level.name = "Level"
	pc.add_child(level)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var players := Node3D.new()
	players.name = "Players"
	level.add_child(players)
	var player_spawner := PlayerSpawner.new()
	player_spawner.name = "PlayerSpawner"
	player_spawner.use_net(net)
	players.add_child(player_spawner)
	var props := PropSpawner.new()
	props.name = "Props"
	props.use_net(net, config)
	level.add_child(props)
	var enemies := EnemySpawner.new()
	enemies.name = "Enemies"
	level.add_child(enemies)
	_pcs.append(pc)
	return pc


func _props(pc: Node) -> PropSpawner:
	return pc.get_node("Level/Props") as PropSpawner


func _net(pc: Node) -> NetService:
	return pc.get_node("Net") as NetService


func _body(pc: Node, player_id: int) -> PlayerCharacter:
	return pc.get_node_or_null("Level/Players/%d" % player_id) as PlayerCharacter


func _my_body(pc: Node) -> PlayerCharacter:
	return _body(pc, _net(pc).local_player_id())


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


## Our body on this PC, keeping still, with a punt arm unless `with_arm` is false.
func _puncher(pc: Node, with_arm: bool = true) -> PlayerCharacter:
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var body: PlayerCharacter = _my_body(pc)
	body.set_input_override(PlayerInputState.new())
	if with_arm:
		body.add_child(PropPunter.new())
	await wait_physics_frames(5)
	return body


## A crate resting on the floor this far in front of the body (along -Z), and `aside` metres to the right.
func _crate_ahead(pc: Node, body: PlayerCharacter, distance: float, aside: float = 0.0) -> NetProp:
	var spot: Vector3 = body.global_position + Vector3(aside, 0.4, -distance)
	return _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, spot))


## Turns the body and tilts its head so it looks straight at `point`.
func _look_at(body: PlayerCharacter, point: Vector3) -> void:
	var to: Vector3 = point - body.get_aim_origin()
	body.rotation.y = atan2(-to.x, -to.z)
	body.set_look_pitch(asin(clampf(to.normalized().y, -1.0, 1.0)))


func _flat_speed(prop: NetProp) -> float:
	return Vector3(prop.linear_velocity.x, 0.0, prop.linear_velocity.z).length()


func _add_wall(pc: Node, center: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	pc.get_node("Level").add_child(wall)
	wall.global_position = center


func test_light_things_fly_faster_and_heavy_things_barely_move() -> void:
	var pc := _make_pc()
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(0, 1, -3)))
	var gem: NetProp = _props(pc).spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, Vector3(1, 1, -3)))
	var heavy: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(3, 1, -3)))
	var speed_of := func(prop: NetProp) -> float: return _props(pc).punt_strength(prop) / prop.get_true_mass()
	var crate_speed: float = speed_of.call(crate)
	assert_almost_eq(crate_speed, Config.feel.props.punt_speed, 0.01, "a 10 kg crate flies at punt_speed")
	assert_between(speed_of.call(gem) as float, crate_speed + 0.5,
		Config.feel.props.punt_speed + Config.feel.props.punt_light_bonus, "a gem flies faster, up to the bonus")
	assert_almost_eq(speed_of.call(heavy) as float, Config.feel.props.punt_max_impulse / heavy.get_true_mass(), 0.01,
		"the heavy crate only gets punt_max_impulse")
	assert_lt(speed_of.call(heavy) as float, crate_speed * 0.6, "so it moves much slower")


func test_right_click_punts_the_crate_you_aim_at() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc)
	var crate: NetProp = _crate_ahead(pc, body, 4.0)
	await wait_physics_frames(30)
	_look_at(body, crate.global_position)
	await wait_physics_frames(2)
	var punter: PropPunter = PropPunter.of(body)
	watch_signals(punter)
	var click := InputEventAction.new()
	click.action = InputActions.SECONDARY
	click.pressed = true
	punter._unhandled_input(click)
	assert_signal_emitted(punter, "punted")
	await wait_physics_frames(3)
	assert_gt(-crate.linear_velocity.z, 8.0, "it flies off away from us (%.1f m/s)" % -crate.linear_velocity.z)
	assert_gt(crate.linear_velocity.y, 0.5, "aimed down at the floor, it still hops up (%.1f m/s)" % crate.linear_velocity.y)
	assert_eq(crate.get_recent_thrower(2.0), body.player_id, "the punter gets the credit for its hits")


func test_nothing_in_reach_leaves_the_click_to_the_item() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc)
	var punter: PropPunter = PropPunter.of(body)
	assert_false(punter.try_punt(), "nothing to punt")
	var far: NetProp = _crate_ahead(pc, body, 9.0)
	await wait_physics_frames(30)
	_look_at(body, far.global_position)
	await wait_physics_frames(2)
	assert_false(punter.try_punt(), "9 m is out of reach")
	var near: NetProp = _crate_ahead(pc, body, 3.0, 4.0)
	_add_wall(pc, body.global_position + Vector3(2.0, 1.0, -1.5), Vector3(0.3, 3.0, 4.0))
	await wait_physics_frames(30)
	_look_at(body, near.global_position)
	await wait_physics_frames(2)
	assert_false(punter.try_punt(), "never through a wall")
	assert_lt(near.linear_velocity.length(), 0.5, "and it stays put")


func test_a_held_crate_is_punted_out_of_your_hands_faster_than_a_throw() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc)
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate",
		Transform3D(Basis.IDENTITY, body.get_aim_origin() + body.get_aim_direction() * 1.4 + Vector3(0, -0.4, 0)))
	PropsService.grab_of(body).try_grab(crate)
	await wait_physics_frames(20)
	assert_true(PropPunter.of(body).try_punt())
	await wait_physics_frames(2)
	assert_false(crate.is_held(), "let go")
	var throw_speed: float = _props(pc).throw_strength(crate) / crate.get_true_mass()
	assert_gt(_flat_speed(crate), throw_speed * 1.5, "much faster than a throw (%.1f m/s)" % _flat_speed(crate))


func test_only_a_punt_arm_can_punt_and_not_too_often() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc, false)
	var first: NetProp = _crate_ahead(pc, body, 3.0)
	var second: NetProp = _crate_ahead(pc, body, 3.0, 1.0)
	await wait_physics_frames(30)
	assert_eq(_props(pc).decide_punt(body, first), PropSpawner.REFUSE_NO_PUNT_ARM, "no arm, no punt")
	var punter := PropPunter.new()
	body.add_child(punter)
	assert_eq(_props(pc).decide_punt(body, first), "", "with the arm it's fine")
	_look_at(body, first.global_position)
	await wait_physics_frames(2)
	assert_true(punter.try_punt())
	_look_at(body, second.global_position)
	await wait_physics_frames(2)
	assert_false(punter.try_punt(), "half a second between punts")
	assert_eq(_props(pc).decide_punt(body, second), PropSpawner.REFUSE_TOO_SOON, "the host checks it too")
	await wait_seconds(Config.feel.props.punt_cooldown + 0.05)
	assert_true(punter.try_punt(), "then it works again")


func test_a_punted_crate_kills_a_light_enemy_and_the_punter_gets_the_credit() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc)
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate",
		Transform3D(Basis.IDENTITY, body.get_aim_origin() + body.get_aim_direction() * 1.4 + Vector3(0, -0.4, 0)))
	PropsService.grab_of(body).try_grab(crate)
	var victim := CharacterBody3D.new()
	victim.collision_layer = PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	victim.set_meta(&"impact_mass", 5.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.4, 1.0)
	shape.shape = box
	shape.position.y = 1.2
	victim.add_child(shape)
	pc.get_node("Level").add_child(victim)
	victim.global_position = body.global_position + Vector3(0, 0, -5.0)
	DamageService.give_components(victim, 15.0, 0.0)
	var health: HealthComponent = HealthComponent.of(victim)
	var credit: Array[int] = []
	health.died.connect(func(info: DamageInfo) -> void: credit.append(info.source_player_id))
	await wait_physics_frames(20)
	PropPunter.of(body).try_punt()
	await wait_until(func() -> bool: return health.is_dead(), 2.0)
	assert_true(health.is_dead(), "a punted crate kills a 5 kg enemy")
	assert_eq(credit, [body.player_id] as Array[int], "the punter gets the kill")


func test_a_client_punt_launches_the_crate_on_every_pc() -> void:
	var host := _make_pc()
	var client := _make_pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 4), OK)
	host.multiplayer.multiplayer_peer = server
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	client.multiplayer.multiplayer_peer = peer
	var body: PlayerCharacter = await _puncher(client)
	await wait_until(func() -> bool: return _body(host, body.player_id) != null, WAIT)
	# Upgrades add the arm on every PC; here we add the host's copy by hand.
	_body(host, body.player_id).add_child(PropPunter.new())
	var crate_on_host: NetProp = _crate_ahead(host, body, 4.0)
	await wait_until(func() -> bool: return _props(client).get_prop(crate_on_host.net_id) != null, WAIT)
	var crate: NetProp = _props(client).get_prop(crate_on_host.net_id)
	await wait_physics_frames(30)
	var start: Vector3 = crate_on_host.global_position
	_look_at(body, crate.global_position)
	await wait_physics_frames(5)
	watch_signals(_props(host))
	assert_true(PropPunter.of(body).try_punt(), "the client punts")
	await wait_until(func() -> bool: return get_signal_emit_count(_props(host), "prop_punted") > 0, WAIT)
	assert_signal_emitted_with_parameters(_props(host), "prop_punted", [crate_on_host, body.player_id])
	assert_eq(crate_on_host.get_recent_thrower(2.0), body.player_id, "the host gives the client the credit")
	await wait_until(func() -> bool: return crate_on_host.global_position.distance_to(start) > 3.0, WAIT)
	assert_gt(crate_on_host.global_position.distance_to(start), 3.0, "it flew on the host")
	await wait_until(func() -> bool: return crate.global_position.distance_to(start) > 3.0, WAIT)
	assert_gt(crate.global_position.distance_to(start), 3.0, "and the client sees it fly")


# --- Pull (NEW 2026-10-30, Zachary's idea) ------------------------------------------------------------------

func test_holding_e_pulls_a_far_crate_in_and_picks_it_up() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc)
	var crate: NetProp = _crate_ahead(pc, body, 7.0)
	await wait_physics_frames(30)
	_look_at(body, crate.global_position)
	await wait_physics_frames(2)
	var start: float = body.get_aim_origin().distance_to(crate.global_position)
	PropPunter.of(body).pull(crate)
	await wait_physics_frames(30)
	assert_lt(body.get_aim_origin().distance_to(crate.global_position), start - 1.0, "it comes towards us")
	assert_lt(crate.global_position.y, 0.8, "dragged along the floor, not floating (%.2f m up)" % crate.global_position.y)
	var grab: GrabController = PropsService.grab_of(body)
	await wait_until(func() -> bool: return grab.get_held() == crate, WAIT)
	assert_eq(grab.get_held(), crate, "and is picked up once it's in reach")
	assert_null(PropPunter.of(body).get_pulled(), "the pull is over")


func test_the_arm_lets_e_reach_a_bit_further_and_e_starts_a_pull() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc, false)
	var crate: NetProp = _crate_ahead(pc, body, 3.6)
	await wait_physics_frames(30)
	var interaction: InteractionController = InteractionService.controller_of(body)
	assert_false(interaction.press_use(null), "without the arm it's too far, and E doesn't pull")
	assert_false(crate.is_held())
	body.add_child(PropPunter.new())
	await wait_physics_frames(2)
	assert_true(interaction.press_use(null), "with the arm...")
	assert_true(crate.is_held(), "...it's close enough to pick up")
	PropsService.grab_of(body).drop()
	_props(pc).despawn(crate)
	var far: NetProp = _crate_ahead(pc, body, 7.0, 0.5)
	await wait_physics_frames(30)
	_look_at(body, far.global_position)
	await wait_physics_frames(2)
	assert_true(interaction.press_use(null), "E at a far prop takes the press (no buzz)")
	assert_eq(PropPunter.of(body).get_pulled(), far, "and starts pulling it")


func test_heavy_props_are_not_pulled() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc)
	var heavy: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, body.global_position + Vector3(0, 0.5, -6)))
	var crate: NetProp = _crate_ahead(pc, body, 6.0, 2.0)
	await wait_physics_frames(30)
	assert_eq(_props(pc).decide_pull(body, heavy), PropSpawner.REFUSE_TOO_HEAVY)
	assert_false(PropPunter.of(body).can_pull(heavy))
	assert_eq(_props(pc).decide_pull(body, crate), "", "a normal crate is fine")


func test_a_client_pulls_a_crate_from_afar() -> void:
	var host := _make_pc()
	var client := _make_pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT + 1, 4), OK)
	host.multiplayer.multiplayer_peer = server
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT + 1)
	client.multiplayer.multiplayer_peer = peer
	var body: PlayerCharacter = await _puncher(client)
	await wait_until(func() -> bool: return _body(host, body.player_id) != null, WAIT)
	_body(host, body.player_id).add_child(PropPunter.new())
	var crate_on_host: NetProp = _crate_ahead(host, body, 7.0)
	await wait_until(func() -> bool: return _props(client).get_prop(crate_on_host.net_id) != null, WAIT)
	var crate: NetProp = _props(client).get_prop(crate_on_host.net_id)
	await wait_physics_frames(30)
	_look_at(body, crate.global_position)
	await wait_physics_frames(5)
	PropPunter.of(body).pull(crate)
	var grab: GrabController = PropsService.grab_of(body)
	await wait_until(func() -> bool: return grab.get_held() == crate and crate_on_host.is_held(), WAIT)
	assert_eq(grab.get_held(), crate, "the client pulled it in and picked it up")
	assert_eq(crate_on_host.get_holder_ids(), [body.player_id] as Array[int], "the host agrees")


# --- Punting enemies (NEW 2026-10-30, Zachary: a shove, never damage) --------------------------------------

func test_punting_an_enemy_shoves_it_but_never_hurts_it() -> void:
	var pc := _make_pc()
	var body: PlayerCharacter = await _puncher(pc)
	var enemies := pc.get_node("Level/Enemies") as EnemySpawner
	var rat: Enemy = enemies.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, body.global_position + Vector3(0, 0.1, -4)))
	await wait_physics_frames(20)
	var health: float = rat.get_health().get_current()
	var start: Vector3 = rat.global_position
	_look_at(body, rat.global_position + Vector3.UP * rat.hurtbox_height * 0.5)
	await wait_physics_frames(2)
	var punter: PropPunter = PropPunter.of(body)
	watch_signals(punter)
	assert_true(punter.try_punt())
	assert_signal_emitted(punter, "punted_enemy")
	assert_true(rat.is_knocked_back(), "it's shoved")
	await wait_seconds(0.25)
	assert_lt(rat.global_position.z, start.z - 1.0, "away from us (%.2f m)" % (start.z - rat.global_position.z))
	assert_eq(rat.get_health().get_current(), health, "and not hurt at all")
	assert_eq(rat.get_target(), body, "but it's angry with us now")


func test_heavy_enemies_are_shoved_less() -> void:
	var pc := _make_pc()
	var enemies := pc.get_node("Level/Enemies") as EnemySpawner
	var rat: Enemy = enemies.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -4)))
	var kangaroo: Enemy = enemies.spawn(&"enemy_kangaroo", Transform3D(Basis.IDENTITY, Vector3(4, 0.1, -4)))
	var rat_push: Vector3 = PropSpawner.punt_push_for(rat, Vector3.FORWARD)
	var kangaroo_push: Vector3 = PropSpawner.punt_push_for(kangaroo, Vector3.FORWARD)
	assert_gt(rat_push.length(), kangaroo_push.length() * 2.0, "a rat flies, a kangaroo stumbles")
	assert_gt(kangaroo_push.length(), 0.5, "but even a kangaroo moves")
