extends GutTest
## Tests for death_respawn (docs/systems/death_respawn.md). Solo: this PC is the host and the only player,
## so dying is the solo case unless solo free reprints are 0. Every test starts a fresh "run" (run_started)
## so nobody is still dead from the test before.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const PRINTER_SCENE: PackedScene = preload("res://systems/death_respawn/printer_3d.tscn")
const WAIT: float = 5.0

var _world: Node3D
var _body: PlayerCharacter
var _saved_free: int = 0
var _saved_wait: float = 0.0
var _saved_cost: int = 0
var _saved_growth: int = 0


func before_each() -> void:
	var game: GameConfig = Config.game
	_saved_free = game.solo_free_reprints_per_floor
	_saved_wait = game.reprint_min_wait
	_saved_cost = game.meat_per_reprint
	_saved_growth = game.meat_cost_growth_per_reprint
	game.reprint_min_wait = 0.0
	EventBus.run_started.emit(1)
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	var props := PropSpawner.new()
	props.name = "Props"
	_world.add_child(props)
	_body = PLAYER_SCENE.instantiate() as PlayerCharacter
	_body.player_id = Net.local_player_id()
	_body.name = str(_body.player_id)
	_world.add_child(_body)
	_body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(3)


func after_each() -> void:
	var game: GameConfig = Config.game
	game.solo_free_reprints_per_floor = _saved_free
	game.reprint_min_wait = _saved_wait
	game.meat_per_reprint = _saved_cost
	game.meat_cost_growth_per_reprint = _saved_growth
	EventBus.run_ended.emit(&"abandoned")
	await wait_process_frames(2)


func _no_free_reprints() -> void:
	Config.game.solo_free_reprints_per_floor = 0
	EventBus.run_started.emit(1)


func _printer(at: Vector3 = Vector3(0, 0, -4)) -> Printer3D:
	var printer := PRINTER_SCENE.instantiate() as Printer3D
	printer.position = at
	_world.add_child(printer)
	return printer


func test_death_drops_all_items() -> void:
	_no_free_reprints()
	var inventory: InventoryComponent = InventoryComponent.of(_body)
	inventory.add_item(&"item_crowbar")
	inventory.add_item(&"item_energy_drink", 1)
	Death.kill(_body.player_id)
	assert_true(Death.is_dead(_body.player_id))
	assert_true(_body.is_ghost(), "a ghost now")
	assert_null(inventory.get_slot(0))
	assert_null(inventory.get_slot(1))
	assert_eq(Props.get_props(&"item_crowbar").size(), 1, "the crowbar lies where they died")
	assert_eq(Props.get_props(&"item_energy_drink").size(), 1)


func test_death_emits_player_died() -> void:
	_no_free_reprints()
	watch_signals(EventBus)
	Death.kill(_body.player_id)
	assert_signal_emitted(EventBus, "player_died")


func test_death_releases_held_prop() -> void:
	_no_free_reprints()
	var crate: NetProp = Props.spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(0, 0.4, -1.2)))
	await wait_physics_frames(2)
	PropsService.grab_of(_body).try_grab(crate)
	await wait_until(func() -> bool: return crate.is_held(), WAIT)
	assert_true(crate.is_held())
	Death.kill(_body.player_id)
	await wait_physics_frames(2)
	assert_false(crate.is_held(), "dead hands let go")


func test_printer_needs_meat() -> void:
	_no_free_reprints()
	var printer := _printer()
	Death.kill(_body.player_id)
	assert_false(printer.print_now(_body.player_id), "no meat yet")
	assert_true(Death.is_dead(_body.player_id))
	printer.add_meat(1)
	assert_true(printer.print_now(_body.player_id))
	assert_false(Death.is_dead(_body.player_id), "reprinted")
	assert_false(_body.is_ghost())
	assert_eq(HealthComponent.of(_body).get_current(), Config.game.player_max_health, "full health")
	assert_eq(printer.get_meat_inserted(), 0, "the meat was used")
	assert_lt(_body.global_position.distance_to(printer.get_output_transform().origin), 1.0, "out of the printer")


func test_meat_in_the_hopper_counts() -> void:
	var printer := _printer()
	Props.spawn_prop(&"prop_meat", Transform3D(Basis.IDENTITY, printer.global_position + Vector3(0, 2.4, 0)))
	await wait_until(func() -> bool: return printer.get_meat_inserted() == 1, WAIT)
	assert_eq(printer.get_meat_inserted(), 1, "meat dropped on top goes in")
	assert_eq(Props.get_props(&"prop_meat").size(), 0)


## Playtest 2026-10-24: touching the hopper with meat in your hands is enough (no need to throw it in).
func test_held_meat_touching_the_hopper_counts() -> void:
	var printer := _printer()
	await wait_physics_frames(2)
	var hopper_shape := printer.get_node("Hopper").get_child(0) as CollisionShape3D
	var meat: NetProp = Props.spawn_prop(&"prop_meat", Transform3D(Basis.IDENTITY, hopper_shape.global_position))
	meat.freeze = true
	meat.apply_holders([7], 7)
	await wait_until(func() -> bool: return printer.get_meat_inserted() == 1, WAIT)
	assert_eq(printer.get_meat_inserted(), 1, "held against the hopper: it goes in")
	assert_eq(Props.get_props(&"prop_meat").size(), 0)


func test_reprint_keeps_upgrades_not_items() -> void:
	_no_free_reprints()
	var printer := _printer()
	printer.add_meat(1)
	var stats: StatsComponent = StatsComponent.of(_body)
	var tough := StatEffectData.new()
	tough.stat = &"max_health"
	tough.add = 50.0
	stats.add_modifier(&"mutation_test_tough", tough)
	InventoryComponent.of(_body).add_item(&"item_knife")
	Death.kill(_body.player_id)
	printer.print_now(_body.player_id)
	assert_true(stats.has_modifiers(&"mutation_test_tough"), "the mutation is still there")
	assert_eq(HealthComponent.of(_body).get_max(), Config.game.player_max_health + 50.0)
	assert_eq(InventoryComponent.of(_body).find_item(&"item_knife"), -1, "the knife stayed on the floor")


func test_cost_grows_if_configured() -> void:
	_no_free_reprints()
	Config.game.meat_cost_growth_per_reprint = 2
	var printer := _printer()
	assert_eq(Death.get_reprint_cost(), 1)
	printer.add_meat(1)
	Death.kill(_body.player_id)
	printer.print_now(_body.player_id)
	assert_eq(Death.get_reprint_cost(), 3, "1 + 2 per reprint done this floor")
	EventBus.floor_ready.emit(2, &"")
	assert_eq(Death.get_reprint_cost(), 1, "a new floor resets it")


func test_solo_free_reprint_then_run_ends() -> void:
	Config.game.solo_free_reprints_per_floor = 1
	EventBus.run_started.emit(1)
	var printer := _printer()
	watch_signals(EventBus)
	Death.kill(_body.player_id)
	await wait_until(func() -> bool: return not Death.is_dead(_body.player_id), WAIT)
	assert_false(Death.is_dead(_body.player_id), "the free reprint brought them back")
	assert_lt(_body.global_position.distance_to(printer.get_output_transform().origin), 1.0, "at the nearest printer")
	assert_eq(Death.get_free_reprints_left(), 0)
	assert_signal_not_emitted(EventBus, "team_wiped")
	Death.kill(_body.player_id)
	await wait_process_frames(2)
	assert_signal_emitted(EventBus, "team_wiped", "no free reprints left: the run ends")


func test_all_dead_emits_team_wiped_once() -> void:
	_no_free_reprints()
	watch_signals(EventBus)
	Death.kill(_body.player_id)
	Death.kill(_body.player_id)
	HealthComponent.of(_body).apply_damage(DamageInfo.make(500.0, &"blunt"))
	await wait_process_frames(2)
	assert_signal_emit_count(EventBus, "team_wiped", 1)


func test_ghosts_are_not_waited_for_by_the_lift() -> void:
	_no_free_reprints()
	Death.kill(_body.player_id)
	var record: PlayerRecord = Net.get_record(_body.player_id)
	assert_false(record.is_alive, "the record says dead")
	var zone := ElevatorZone.new()
	add_child_autofree(zone)
	assert_true(zone.contains_all_players(), "the lift doesn't wait for a ghost")
