extends GutTest
## Checks that the content validator itself catches the mistakes it should.
## Uses content made in code, so it doesn't depend on real content files.

var _types: Array[StringName] = [&"mutation", &"boss", &"department", &"room", &"enemy", &"loot"]


func _make_mutation(id: StringName) -> MutationData:
	var mutation: MutationData = MutationData.new()
	mutation.id = id
	mutation.display_name = "Test"
	return mutation


func test_valid_content_has_no_problems() -> void:
	var problems: PackedStringArray = ContentValidator.validate_all(
		[_make_mutation(&"mutation_fly")] as Array[ContentData], _types)
	assert_eq(problems.size(), 0, "\n".join(problems))


func test_duplicate_ids_are_caught() -> void:
	var problems: PackedStringArray = ContentValidator.validate_all(
		[_make_mutation(&"mutation_fly"), _make_mutation(&"mutation_fly")] as Array[ContentData], _types)
	assert_gt(problems.size(), 0)


func test_wrong_prefix_is_caught() -> void:
	var problems: PackedStringArray = ContentValidator.validate_all(
		[_make_mutation(&"fly")] as Array[ContentData], _types)
	assert_gt(problems.size(), 0)


func test_missing_required_field_is_caught() -> void:
	var mutation: MutationData = _make_mutation(&"mutation_fly")
	mutation.display_name = ""
	var problems: PackedStringArray = ContentValidator.validate_all([mutation] as Array[ContentData], _types)
	assert_gt(problems.size(), 0)


func test_missing_reference_is_caught() -> void:
	var department: DepartmentData = DepartmentData.new()
	department.id = &"department_test"
	department.display_name = "Test"
	department.boss_id = &"boss_does_not_exist"
	var problems: PackedStringArray = ContentValidator.validate_all([department] as Array[ContentData], _types)
	var joined: String = "\n".join(problems)
	assert_string_contains(joined, "boss_does_not_exist")


func test_reference_to_wrong_type_is_caught() -> void:
	var department: DepartmentData = DepartmentData.new()
	department.id = &"department_test"
	department.display_name = "Test"
	department.boss_id = &"mutation_fly"
	var problems: PackedStringArray = ContentValidator.validate_all(
		[department, _make_mutation(&"mutation_fly")] as Array[ContentData], _types)
	assert_string_contains("\n".join(problems), "should point to a 'boss'")


func test_references_inside_sub_resources_are_checked() -> void:
	var boss: BossData = BossData.new()
	boss.id = &"boss_test"
	boss.display_name = "Test"
	var phase: BossPhaseData = BossPhaseData.new()
	phase.minion_enemy_ids = [&"enemy_missing"]
	boss.phases = [phase]
	var problems: PackedStringArray = ContentValidator.validate_all([boss] as Array[ContentData], _types)
	assert_string_contains("\n".join(problems), "enemy_missing")


func test_seeded_rng_is_repeatable() -> void:
	var a: RandomNumberGenerator = SeededRng.make(1234, &"loot", 2)
	var b: RandomNumberGenerator = SeededRng.make(1234, &"loot", 2)
	assert_eq(a.randi(), b.randi())
