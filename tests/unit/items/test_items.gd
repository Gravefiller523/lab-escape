extends GutTest
## Tests for items (docs/systems/items.md). Solo: this PC is the host and owns the body, which stands at
## the origin looking down -Z. A PropSpawner is in the world so item pickups can be spawned.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const PLANT_SCENE: PackedScene = preload("res://systems/items/world/mutated_plant.tscn")
const WAIT: float = 5.0
const PRIMARY: int = ItemBehaviourData.Trigger.PRIMARY
const SECONDARY: int = ItemBehaviourData.Trigger.SECONDARY

var _world: Node3D
var _body: PlayerCharacter


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
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


func _held() -> HeldItemController:
	return ItemsService.held_of(_body)


func _inventory() -> InventoryComponent:
	return InventoryComponent.of(_body)


## A target with 100 health (and a hurtbox) standing `distance` metres in front of the player.
func _dummy(distance: float, height: float = 0.0) -> Node3D:
	var dummy := Node3D.new()
	dummy.name = "Dummy%d" % int(distance * 10.0)
	dummy.position = Vector3(0.0, height, -distance)
	_world.add_child(dummy)
	DamageService.give_components(dummy, 100.0)
	return dummy


func _hold(item_id: StringName) -> void:
	var data := ContentRegistry.get_content(item_id) as ItemData
	assert_true(_inventory().add_item(item_id, data.uses))
	_inventory().request_select(_inventory().find_item(item_id))


func _health(node: Node) -> float:
	return HealthComponent.of(node).get_current()


func test_fists_when_slot_empty() -> void:
	assert_not_null(_held(), "the Items autoload gave the body a HeldItemController")
	assert_eq(_held().get_active_item().id, &"item_fists")
	_hold(&"item_crowbar")
	assert_eq(_held().get_active_item().id, &"item_crowbar")
	_inventory().request_holster_toggle()
	assert_eq(_held().get_active_item().id, &"item_fists", "holstered: fists")


func test_melee_hits_in_reach_only() -> void:
	var near := _dummy(1.5)
	var far := _dummy(5.0)
	_hold(&"item_crowbar")
	_held().use(PRIMARY)
	assert_eq(_health(near), 85.0, "the crowbar does 15 blunt")
	assert_eq(_health(far), 100.0, "out of reach")


func test_fists_do_damage_too() -> void:
	var near := _dummy(1.2)
	_held().use(PRIMARY)
	assert_eq(_health(near), 95.0, "fists do 5")


func test_cooldown_blocks_spam() -> void:
	var near := _dummy(1.5)
	_hold(&"item_crowbar")
	_held().use(PRIMARY)
	_held().use(PRIMARY)
	_held().use(PRIMARY)
	assert_eq(_health(near), 85.0, "only the first swing counts")
	assert_true(_held().is_on_cooldown(PRIMARY))
	await wait_seconds(0.75)
	_held().use(PRIMARY)
	assert_eq(_health(near), 70.0, "after the cooldown it hits again")


func test_melee_does_not_hurt_teammates() -> void:
	var friend := PLAYER_SCENE.instantiate() as PlayerCharacter
	friend.player_id = 5150
	friend.position = Vector3(0, 0, -1.3)
	_world.add_child(friend)
	await wait_physics_frames(2)
	_hold(&"item_knife")
	_held().use(PRIMARY)
	assert_eq(_health(friend), Config.game.player_max_health, "no friendly fire from melee")


func test_throw_spawns_prop_and_removes_item() -> void:
	_hold(&"item_potted_plant")
	var before: int = Props.get_props(&"item_potted_plant").size()
	_held().use(PRIMARY)
	assert_eq(_inventory().find_item(&"item_potted_plant"), -1, "it left the inventory")
	assert_eq(Props.get_props(&"item_potted_plant").size(), before + 1, "it flies as a pickup")


func test_thrown_plant_hurts_what_it_hits() -> void:
	var target := _dummy(3.0)
	_hold(&"item_potted_plant")
	_held().use(PRIMARY)
	await wait_until(func() -> bool: return _health(target) < 100.0, WAIT)
	assert_eq(_health(target), 85.0, "15 blunt")
	await wait_physics_frames(10)
	assert_eq(Props.get_props(&"item_potted_plant").size(), 1, "the plant didn't break")


func test_coffee_applies_burning() -> void:
	var target := _dummy(3.0)
	_hold(&"item_hot_coffee")
	_held().use(PRIMARY)
	await wait_until(func() -> bool: return StatusEffectComponent.of(target).has_status(&"status_burning"), WAIT)
	assert_true(StatusEffectComponent.of(target).has_status(&"status_burning"), "set on fire")
	await wait_physics_frames(5)
	assert_eq(Props.get_props(&"item_hot_coffee").size(), 0, "the pot smashed")


func test_drink_gives_speed_status_and_spends_use() -> void:
	_hold(&"item_energy_drink")
	_held().use(PRIMARY)
	assert_true(StatusEffectComponent.of(_body).has_status(&"status_speed_boost"))
	assert_eq(_inventory().find_item(&"item_energy_drink"), -1, "drunk: the can is gone")
	assert_eq(_held().get_active_item().id, &"item_fists")


func test_water_grows_plant_ladder() -> void:
	var plant := PLANT_SCENE.instantiate() as MutatedPlant
	plant.position = Vector3(0, 1.2, -1.2)
	_world.add_child(plant)
	_hold(&"item_energy_drink")
	_held().use(SECONDARY)
	assert_true(plant.is_grown(), "the vine grew")
	assert_eq(_inventory().find_item(&"item_energy_drink"), -1, "pouring used the drink")
	await wait_seconds(1.3)
	assert_not_null(plant.get_node_or_null("Vine/Step9"), "steps all the way up")


func test_crowbar_pries_but_stays() -> void:
	var boards := StaticBody3D.new()
	boards.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 0.2)
	shape.shape = box
	boards.add_child(shape)
	var target := UseTarget.new()
	target.name = UseTarget.NODE_NAME
	target.accepted_tags = PackedStringArray(["pry"])
	boards.add_child(target)
	boards.position = Vector3(0, 1.6, -1.5)
	_world.add_child(boards)
	watch_signals(target)
	_hold(&"item_crowbar")
	_held().use(SECONDARY)
	assert_true(target.is_used(), "pried open")
	assert_signal_emitted_with_parameters(target, "item_used_on", [&"pry", _body.player_id])
	assert_ne(_inventory().find_item(&"item_crowbar"), -1, "the crowbar isn't used up")


func test_take_a_pickup_with_e() -> void:
	var prop: NetProp = Props.spawn_item(&"item_knife", Transform3D(Basis.IDENTITY, Vector3(0, 0.2, -1.2)))
	assert_not_null(prop)
	await wait_physics_frames(2)
	var controller: InteractionController = InteractionService.controller_of(_body)
	assert_true(controller.press_use(prop))
	await wait_physics_frames(2)
	assert_ne(_inventory().find_item(&"item_knife"), -1, "the knife is in the inventory")
	assert_eq(Props.get_props(&"item_knife").size(), 0, "and gone from the floor")


func test_new_item_file_needs_no_code() -> void:
	var melee := MeleeBehaviourData.new()
	melee.damage = 40.0
	melee.damage_type = &"sharp"
	melee.reach = 2.0
	var item := ItemData.new()
	item.id = &"item_test_sword"
	item.display_name = "Test sword"
	item.behaviours = [melee]
	if not ContentRegistry.has_content(item.id):
		ContentRegistry.register_content(item)
	var near := _dummy(1.5)
	_hold(&"item_test_sword")
	_held().use(PRIMARY)
	assert_eq(_health(near), 60.0, "a new item made of existing pieces just works")


func test_held_model_shows_in_your_view() -> void:
	_hold(&"item_crowbar")
	await wait_process_frames(2)
	assert_not_null(_body.get_camera().get_node_or_null("HeldModel"), "the crowbar is in front of the camera")


func test_item_used_event() -> void:
	watch_signals(EventBus)
	_held().use(PRIMARY)
	assert_signal_emitted_with_parameters(EventBus, "item_used", [_body.player_id, &"item_fists"])
