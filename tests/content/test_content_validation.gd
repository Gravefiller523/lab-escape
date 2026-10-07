extends GutTest
## Loads every content file and checks it for mistakes.
## Run this after adding or changing ANY content file (see CLAUDE.md, "Testing").
## Each failure message names the file and the field to fix.


func test_content_loaded_without_errors() -> void:
	var errors: PackedStringArray = ContentRegistry.load_errors
	assert_eq(errors.size(), 0, "Content loading problems:\n" + "\n".join(errors))


func test_all_content_is_valid() -> void:
	ContentRegistry.reload()
	var problems: PackedStringArray = ContentValidator.validate_all(
		ContentRegistry.get_everything(), ContentRegistry.get_type_keys())
	assert_eq(problems.size(), 0, "Content problems:\n" + "\n".join(problems))


func test_every_department_has_a_boss_and_rooms() -> void:
	for data: ContentData in ContentRegistry.get_all(&"department"):
		var department: DepartmentData = data as DepartmentData
		assert_true(ContentRegistry.has_content(department.boss_id),
			"%s needs a boss that exists." % department.id)
		assert_gt(department.room_ids.size(), 0, "%s needs at least one room." % department.id)
