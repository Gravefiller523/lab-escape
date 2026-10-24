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


func _describe(drops: Array[LootDrop]) -> String:
	var parts: PackedStringArray = []
	for drop: LootDrop in drops:
		parts.append("%s%s x%d %s" % [drop.prop_id, drop.item_id, drop.count, drop.upgrade_id])
	return ", ".join(parts)


func test_same_seed_same_drops() -> void:
	var first: String = _describe(Loot.roll(&"loot_zoology_medium", SeededRng.make(11, &"loot", 3)))
	var second: String = _describe(Loot.roll(&"loot_zoology_medium", SeededRng.make(11, &"loot", 3)))
	assert_eq(first, second)


func test_weights_respected_over_many_rolls() -> void:
	var gems: int = 0
	var meat: int = 0
	var rng := SeededRng.make(5, &"loot", 0)
	for index: int in 2000:
		for drop: LootDrop in Loot.roll(&"loot_zoology_small", rng):
			if drop.prop_id == &"prop_gem":
				gems += 1
			elif drop.prop_id == &"prop_meat":
				meat += 1
	# Small table: nothing 1, gem 3, meat 2 -> gem drops ~1.5x as often as meat.
	assert_between(float(gems) / float(meat), 1.2, 1.8, "gems ~1.5x meat")


## Playtest 2026-10-24: "only the rat was dropping meat". Every enemy's table should drop meat often.
func test_every_enemy_drops_meat_often() -> void:
	for content: ContentData in ContentRegistry.get_all(&"enemy"):
		var enemy := content as EnemyData
		# Only real enemy files (other tests register made-up enemies in code).
		if not enemy.resource_path.begins_with("res://content/"):
			continue
		var kills_with_meat: int = 0
		var rng := SeededRng.make(9, &"loot", 0)
		for index: int in 400:
			for drop: LootDrop in Loot.roll(enemy.loot_id, rng):
				if drop.prop_id == &"prop_meat":
					kills_with_meat += 1
					break
		gut.p("%s (%s): meat on %d of 400 kills" % [enemy.id, enemy.loot_id, kills_with_meat])
		assert_gt(kills_with_meat, 400 / 5, "%s drops meat on over 1 in 5 kills" % enemy.id)


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


func test_killing_a_rat_spawns_its_drops() -> void:
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
