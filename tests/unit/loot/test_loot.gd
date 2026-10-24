extends GutTest
## Tests for loot (docs/systems/loot.md). Solo: this PC is the host. Pure rolls use roll(); spawning
## tests use a PropSpawner in a test world. Test mutations / tables are registered in code.

const WAIT: float = 5.0

var _world: Node3D


func before_all() -> void:
	_mutation(&"mutation_test_any", 1.0, [])
	_mutation(&"mutation_test_zoo_only", 1.0, [&"department_test_zoo"])
	if not ContentRegistry.has_content(&"loot_test_gems"):
		var table := LootTableData.new()
		table.id = &"loot_test_gems"
		table.rolls = 1
		var entry := LootEntryData.new()
		entry.prop_id = &"prop_gem"
		entry.min_count = 1
		entry.max_count = 1
		table.entries = [entry]
		ContentRegistry.register_content(table)


func _mutation(id: StringName, weight: float, departments: Array[StringName]) -> void:
	if ContentRegistry.has_content(id):
		return
	var data := MutationData.new()
	data.id = id
	data.display_name = String(id)
	data.drop_weight = weight
	data.department_ids = departments
	ContentRegistry.register_content(data)


func before_each() -> void:
	Loot.reset_pity()
	Loot.use_department(null)
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


func after_each() -> void:
	Loot.clear_department_override()
	Loot.reset_pity()
	var game: GameConfig = Config.game
	game.gem_glow_chance = 0.15
	game.gem_glow_pity_step = 0.03
	game.gem_glow_chance_max = 0.6


func _describe(drops: Array[LootDrop]) -> String:
	var parts: PackedStringArray = []
	for drop: LootDrop in drops:
		parts.append("%s%s x%d %s" % [drop.prop_id, drop.item_id, drop.count, drop.upgrade_id])
	return ", ".join(parts)


func test_same_seed_same_drops() -> void:
	Loot.reset_pity()
	var first: String = _describe(Loot.roll(&"loot_zoology_medium", SeededRng.make(11, &"loot", 3)))
	Loot.reset_pity()
	var second: String = _describe(Loot.roll(&"loot_zoology_medium", SeededRng.make(11, &"loot", 3)))
	assert_eq(first, second)


func test_weights_respected_over_many_rolls() -> void:
	Config.game.gem_glow_chance = 0.0
	Config.game.gem_glow_pity_step = 0.0
	var gems: int = 0
	var meat: int = 0
	var rng := SeededRng.make(5, &"loot", 0)
	for index: int in 2000:
		for drop: LootDrop in Loot.roll(&"loot_zoology_small", rng):
			if drop.prop_id == &"prop_gem":
				gems += 1
			elif drop.prop_id == &"prop_meat":
				meat += 1
	# Small table: nothing 1, gem 3, meat 1 -> gem drops ~3x as often as meat.
	assert_between(float(gems) / float(meat), 2.5, 3.5, "gems ~3x meat")


func test_pity_raises_chance_until_glow() -> void:
	Config.game.gem_glow_chance = 0.0
	Config.game.gem_glow_pity_step = 0.25
	Config.game.gem_glow_chance_max = 1.0
	var rng := SeededRng.make(1, &"loot", 0)
	assert_eq(Loot.get_glow_chance(), 0.0)
	var glowed_after: int = -1
	for index: int in 10:
		if Loot.roll_glow(rng):
			glowed_after = index
			break
	assert_between(glowed_after, 1, 4, "the chance climbs (0, 25%, 50%...) until one glows")
	assert_eq(Loot.get_glow_chance(), 0.0, "and resets after it glows")


func test_pity_can_be_turned_off() -> void:
	Config.game.gem_glow_chance = 0.0
	Config.game.gem_glow_pity_step = 0.0
	var rng := SeededRng.make(1, &"loot", 0)
	for index: int in 50:
		assert_false(Loot.roll_glow(rng))
	assert_eq(Loot.get_glow_chance(), 0.0, "pity off: never glows at 0%")


func test_chance_never_above_max() -> void:
	Config.game.gem_glow_chance = 0.1
	Config.game.gem_glow_pity_step = 0.5
	Config.game.gem_glow_chance_max = 0.3
	var rng := SeededRng.make(2, &"loot", 0)
	for index: int in 30:
		Loot.roll_glow(rng)
		assert_lte(Loot.get_glow_chance(), 0.3)


func test_glowing_gem_holds_a_mutation() -> void:
	Config.game.gem_glow_chance = 1.0
	Config.game.gem_glow_chance_max = 1.0
	var drops: Array[LootDrop] = Loot.roll(&"loot_test_gems", SeededRng.make(3, &"loot", 0))
	assert_eq(drops.size(), 1)
	assert_eq(drops[0].prop_id, &"prop_gem_glowing")
	assert_true(ContentRegistry.get_content(drops[0].upgrade_id) is MutationData, "it holds a mutation")


func test_upgrade_pick_respects_department_filter() -> void:
	var zoo := DepartmentData.new()
	zoo.id = &"department_test_zoo"
	var other := DepartmentData.new()
	other.id = &"department_test_other"
	var rng := SeededRng.make(4, &"loot", 0)
	Loot.use_department(other)
	for index: int in 50:
		assert_ne(Loot.pick_upgrade(&"mutation", rng), &"mutation_test_zoo_only", "not outside its department")
	Loot.use_department(zoo)
	var seen: bool = false
	for index: int in 50:
		seen = seen or Loot.pick_upgrade(&"mutation", rng) == &"mutation_test_zoo_only"
	assert_true(seen, "rolled in its own department")


func test_new_mutation_joins_pool() -> void:
	_mutation(&"mutation_test_brand_new", 1000.0, [])
	var rng := SeededRng.make(6, &"loot", 0)
	var seen: bool = false
	for index: int in 20:
		seen = seen or Loot.pick_upgrade(&"mutation", rng) == &"mutation_test_brand_new"
	assert_true(seen, "a new mutation file drops with no code changes")


func test_robot_part_always_has_cybernetic() -> void:
	var part := PropData.new()
	part.id = &"prop_test_robot_part"
	part.tags = PackedStringArray(["robot_part"])
	if not ContentRegistry.has_content(part.id):
		ContentRegistry.register_content(part)
	var cyber := CyberneticData.new()
	cyber.id = &"cybernetic_test_arm"
	if not ContentRegistry.has_content(cyber.id):
		ContentRegistry.register_content(cyber)
	var table := LootTableData.new()
	table.id = &"loot_test_parts"
	var entry := LootEntryData.new()
	entry.prop_id = part.id
	entry.min_count = 3
	entry.max_count = 3
	table.entries = [entry]
	if not ContentRegistry.has_content(table.id):
		ContentRegistry.register_content(table)
	var drops: Array[LootDrop] = Loot.roll(&"loot_test_parts", SeededRng.make(7, &"loot", 0))
	assert_eq(drops.size(), 3)
	for drop: LootDrop in drops:
		assert_true(ContentRegistry.get_content(drop.upgrade_id) is CyberneticData)


func test_killing_a_rat_spawns_its_drops() -> void:
	Config.game.gem_glow_chance = 0.0
	Config.game.gem_glow_pity_step = 0.0
	var before: int = Props.get_props().size()
	var spawned: int = 0
	for index: int in 10:
		EventBus.enemy_killed.emit(&"enemy_rat", Vector3(0, 0.5, 0), 0)
	await wait_physics_frames(2)
	spawned = Props.get_props().size() - before
	assert_gt(spawned, 0, "rats drop gems and meat")
	for prop: NetProp in Props.get_props():
		assert_true(prop.content_id in [&"prop_gem", &"prop_meat"], "from the small Zoology table")


func test_gems_for_value_adds_up() -> void:
	var gems: Array[StringName] = LootService.gems_for_value(13)
	var total: int = 0
	for id: StringName in gems:
		total += (ContentRegistry.get_content(id) as PropData).gem_value
	assert_eq(total, 13)
	assert_eq(gems.size(), 5, "two large (5) and three plain (1)")


func test_merge_keeps_total_value() -> void:
	for index: int in 8:
		Props.spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, Vector3(0.1 * float(index), 0.2, 0)))
	await wait_physics_frames(30)
	for prop: NetProp in Props.get_props():
		prop.sleeping = true
	var removed: int = Loot.merge_gems(3)
	await wait_physics_frames(2)
	assert_gt(removed, 0, "they merged")
	var total: int = 0
	for prop: NetProp in Props.get_props():
		total += prop.data.gem_value
	assert_eq(total, 8, "no value lost")
	assert_lte(Props.get_props().size(), 4)
