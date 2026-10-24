extends GutTest
## Tests for upgrades (docs/systems/upgrades.md). Solo: this PC is the host and the player (the record is
## the local player's). A PropSpawner is in the test world for DNA vials and data drives; upgrades are applied
## by the mutation machine (Zachary, 2026-10-23).

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 5.0

var _world: Node3D
var _body: PlayerCharacter
var _me: int = 0


func before_each() -> void:
	EventBus.run_started.emit(1)
	_me = Net.local_player_id()
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
	_body.player_id = _me
	_body.name = str(_me)
	_world.add_child(_body)
	_body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(3)


func after_each() -> void:
	EventBus.run_ended.emit(&"abandoned")
	await wait_process_frames(2)


func _register(upgrade: UpgradeData) -> void:
	if not ContentRegistry.has_content(upgrade.id):
		ContentRegistry.register_content(upgrade)


func _stacking(id: StringName, max_stacks: int) -> MutationData:
	var upgrade := MutationData.new()
	upgrade.id = id
	upgrade.display_name = String(id)
	upgrade.stack_rule = UpgradeData.StackRule.STACKS
	upgrade.max_stacks = max_stacks
	var stat := StatEffectData.new()
	stat.stat = &"melee_damage"
	stat.add = 1.0
	upgrade.effects = [stat]
	_register(upgrade)
	return upgrade


func test_grant_applies_every_effect_piece() -> void:
	assert_true(Upgrades.grant(_me, &"mutation_octo"))
	assert_true(Upgrades.has_upgrade(_me, &"mutation_octo"))
	assert_false(_body.get_movement().can_jump(), "movement piece: no jumping")
	assert_eq(_body.get_movement().get_wanted_mode(), &"wall_climb")
	assert_eq(InventoryComponent.of(_body).get_slot_count(), Config.game.base_inventory_slots + 1, "slot piece: +1 slot")
	assert_not_null(_body.get_attach_point(&"legs").get_node_or_null("Upgrade_mutation_octo_1"), "visual piece: tentacles")


func test_fly_changes_voice_and_looks() -> void:
	watch_signals(EventBus)
	Upgrades.grant(_me, &"mutation_fly")
	assert_signal_emitted_with_parameters(EventBus, "upgrade_gained", [_me, &"mutation_fly"])
	assert_lt(_body.get_movement().get_gravity_multiplier(), 1.0, "floaty")
	assert_not_null(_body.get_attach_point(&"back").get_node_or_null("Upgrade_mutation_fly_1"), "wings")


func test_stat_piece() -> void:
	Upgrades.grant(_me, &"mutation_slug")
	assert_eq(HealthComponent.of(_body).get_max(), Config.game.player_max_health + 40.0, "Slug is tougher")
	assert_eq(Upgrades.get_hidden_cosmetic_slots(_me), PackedStringArray(["shoes"]), "and hides shoes")


func test_unique_does_not_stack() -> void:
	assert_true(Upgrades.grant(_me, &"mutation_giraffe"))
	assert_false(Upgrades.grant(_me, &"mutation_giraffe"), "the second one does nothing")
	assert_eq(Upgrades.get_stack_count(_me, &"mutation_giraffe"), 1)


func test_stacks_up_to_max() -> void:
	_stacking(&"mutation_test_strong", 2)
	assert_true(Upgrades.grant(_me, &"mutation_test_strong"))
	assert_true(Upgrades.grant(_me, &"mutation_test_strong"))
	assert_false(Upgrades.grant(_me, &"mutation_test_strong"), "max 2")
	assert_eq(StatsComponent.of(_body).get_value(&"melee_damage"), 2.0, "both stacks count")
	Upgrades.remove(_me, &"mutation_test_strong")
	assert_eq(StatsComponent.of(_body).get_value(&"melee_damage"), 1.0, "each stack comes off on its own")


func test_clash_replaces_old() -> void:
	Upgrades.grant(_me, &"mutation_octo")
	assert_eq(Upgrades.preview_clash(_me, &"mutation_frog"), [&"mutation_octo"] as Array[StringName])
	assert_true(Upgrades.grant(_me, &"mutation_frog"))
	assert_false(Upgrades.has_upgrade(_me, &"mutation_octo"), "Frog legs replaced the tentacles")
	assert_true(_body.get_movement().can_jump(), "Octo's no-jump is gone")
	assert_eq(_body.get_movement().get_jump_multiplier(), 1.8)


func test_remove_reverts_effects() -> void:
	Upgrades.grant(_me, &"mutation_octo")
	Upgrades.remove(_me, &"mutation_octo")
	assert_false(Upgrades.has_upgrade(_me, &"mutation_octo"))
	assert_true(_body.get_movement().can_jump())
	assert_eq(InventoryComponent.of(_body).get_slot_count(), Config.game.base_inventory_slots)
	await wait_process_frames(2)
	assert_null(_body.get_attach_point(&"legs").get_node_or_null("Upgrade_mutation_octo_1"))


func test_reapply_after_reprint_matches() -> void:
	Config.game.solo_free_reprints_per_floor = 0
	EventBus.run_started.emit(1)
	Upgrades.grant(_me, &"mutation_frog")
	Death.kill(_me)
	Death.reprint(_me, Transform3D.IDENTITY)
	assert_true(Upgrades.has_upgrade(_me, &"mutation_frog"), "kept through death")
	assert_eq(_body.get_movement().get_jump_multiplier(), 1.8, "and still working")
	Config.game.solo_free_reprints_per_floor = 1


func test_new_body_gets_upgrades_from_the_record() -> void:
	Upgrades.grant(_me, &"mutation_frog")
	_body.free()
	var again := PLAYER_SCENE.instantiate() as PlayerCharacter
	again.player_id = _me
	again.name = str(_me)
	_world.add_child(again)
	assert_eq(again.get_movement().get_jump_multiplier(), 1.8, "a reconnect's new body gets Frog back")
	_body = again


func _machine(at: Vector3 = Vector3(0, 0, -4)) -> UpgradeMachine:
	var machine := (load("res://systems/upgrades/upgrade_machine.tscn") as PackedScene).instantiate() as UpgradeMachine
	machine.position = at
	_world.add_child(machine)
	return machine


func test_machine_applies_the_loaded_mutation_when_you_step_in() -> void:
	var machine := _machine()
	machine.load_upgrade(&"mutation_frog")
	assert_eq(machine.get_loaded(), [&"mutation_frog"] as Array[StringName])
	_body.teleport(Transform3D(Basis.IDENTITY, machine.global_position + Vector3.UP * 0.1))
	await wait_until(func() -> bool: return Upgrades.has_upgrade(_me, &"mutation_frog"), WAIT)
	assert_true(Upgrades.has_upgrade(_me, &"mutation_frog"), "stood in the booth: Frog")
	assert_true(machine.get_loaded().is_empty(), "the vial is used up")


func test_vial_dropped_in_the_hopper_loads_the_machine() -> void:
	var machine := _machine()
	Props.spawn_prop(&"prop_dna_vial", Transform3D(Basis.IDENTITY, machine.global_transform * UpgradeMachine.HOPPER_OFFSET + Vector3.UP * 0.6),
		{"upgrade_id": "mutation_octo"})
	await wait_until(func() -> bool: return not machine.get_loaded().is_empty(), WAIT)
	assert_eq(machine.get_loaded(), [&"mutation_octo"] as Array[StringName])
	assert_eq(Props.get_props(&"prop_dna_vial").size(), 0, "the vial went in")


func test_e_at_the_machine_while_holding_a_vial_puts_it_in() -> void:
	var machine := _machine(Vector3(0, 0, -2.5))
	var vial: NetProp = Props.spawn_prop(&"prop_dna_vial", Transform3D(Basis.IDENTITY, Vector3(0.8, 0.3, 0)),
		{"upgrade_id": "mutation_giraffe"})
	await wait_physics_frames(2)
	PropsService.grab_of(_body).try_grab(vial)
	await wait_until(func() -> bool: return vial.is_held(), WAIT)
	var controller: InteractionController = InteractionService.controller_of(_body)
	assert_true(controller.press_use(machine.get_node("Back")), "E on the machine")
	# Zachary's bug (2026-10-24): right after it goes in, the prompt and E must not touch the freed vial.
	await wait_process_frames(1)
	controller.get_prompt()
	controller.press_use(machine.get_node("Back"))
	await wait_physics_frames(2)
	assert_eq(machine.get_loaded(), [&"mutation_giraffe"] as Array[StringName])
	assert_false(Upgrades.has_upgrade(_me, &"mutation_giraffe"), "loading isn't getting it: you step in for that")


func test_machine_keeps_a_unique_mutation_you_already_have() -> void:
	var machine := _machine()
	Upgrades.grant(_me, &"mutation_giraffe")
	machine.load_upgrade(&"mutation_giraffe")
	assert_false(machine.apply_to(_me), "you have it already")
	assert_eq(machine.get_loaded().size(), 1, "it stays loaded for someone else")


func test_data_drive_gives_a_cybernetic_the_same_way() -> void:
	var machine := _machine()
	var drive: NetProp = Props.spawn_prop(&"prop_data_drive", Transform3D(Basis.IDENTITY, Vector3(5, 0.3, 5)),
		{"upgrade_id": "cybernetic_test_arm"})
	await wait_physics_frames(2)
	assert_true(machine.insert_prop(drive))
	assert_true(machine.apply_to(_me))
	assert_true(Upgrades.has_upgrade(_me, &"cybernetic_test_arm"))
	assert_eq(StatsComponent.of(_body).get_value(&"carry_strength"), 30.0)


func test_carrier_prop_matches_the_kind_of_upgrade() -> void:
	assert_eq(UpgradesService.carrier_prop_for(&"mutation_fly"), &"prop_dna_vial")
	assert_eq(UpgradesService.carrier_prop_for(&"cybernetic_test_arm"), &"prop_data_drive")



func test_vial_name_unknown_until_someone_has_it() -> void:
	assert_false(Upgrades.is_known(&"mutation_fly"), "a new run: nobody has eaten one")
	Upgrades.grant(_me, &"mutation_fly")
	assert_true(Upgrades.is_known(&"mutation_fly"))


func test_run_end_clears_upgrades() -> void:
	Upgrades.grant(_me, &"mutation_octo")
	EventBus.run_ended.emit(&"escaped")
	assert_false(Upgrades.has_upgrade(_me, &"mutation_octo"))
	assert_true(_body.get_movement().can_jump(), "the effects are gone too")


func test_new_mutation_file_needs_no_code() -> void:
	var upgrade := MutationData.new()
	upgrade.id = &"mutation_test_speedy"
	upgrade.display_name = "Speedy"
	var move := MovementEffectData.new()
	move.speed_multiplier = 2.0
	upgrade.effects = [move]
	_register(upgrade)
	assert_true(Upgrades.grant(_me, &"mutation_test_speedy"))
	assert_eq(_body.get_movement().get_speed_multiplier(), 2.0)


func test_energy_drink_speed_boost_makes_you_faster() -> void:
	StatusEffectComponent.of(_body).apply(&"status_speed_boost")
	assert_almost_eq(_body.get_movement().get_speed_multiplier(), 1.5, 0.001, "movement reads the move_speed stat")


func test_prompt_and_e_survive_a_held_vial_vanishing() -> void:
	# Zachary's bug (2026-10-24): the vial you hold disappears (put in the machine) and the prompt / E
	# looked at the freed vial before the grab noticed.
	var vial: NetProp = Props.spawn_prop(&"prop_dna_vial", Transform3D(Basis.IDENTITY, Vector3(0.8, 0.3, 0)),
		{"upgrade_id": "mutation_frog"})
	await wait_physics_frames(2)
	PropsService.grab_of(_body).try_grab(vial)
	await wait_until(func() -> bool: return vial.is_held(), WAIT)
	vial.free()
	var controller: InteractionController = InteractionService.controller_of(_body)
	assert_eq(_held_prompt(controller), "", "no prompt, no error")
	controller.press_use(null)
	assert_null(PropsService.grab_of(_body).get_held())


func _held_prompt(controller: InteractionController) -> String:
	return controller.get_prompt()
