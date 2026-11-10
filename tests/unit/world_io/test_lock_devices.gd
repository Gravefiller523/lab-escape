extends GutTest
## Tests for the floor generation lock devices in world_io (docs/systems/world_io.md): WorldPryPoint,
## WorldKeycardReader and WorldBreaker (NEW 2026-10-31).


func _add(device: WorldDevice) -> WorldDevice:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	viewport.add_child(device)
	return device


func test_breaker_lever_opens_its_door() -> void:
	var door := _add(WorldDoor.new()) as WorldDoor
	door.locked = true
	var breaker := WorldBreaker.new()
	door.get_parent().add_child(breaker)
	breaker.wire(&"pulled", door, &"unlock")
	assert_true(breaker.has_power(), "no cell needed")
	breaker.get_interactable().used.emit(1)
	assert_true(breaker.is_pulled(), "the lever is down")
	assert_false(door.is_locked(), "and the door is unlocked")


func test_breaker_without_its_cell_does_nothing() -> void:
	var breaker := _add(WorldBreaker.new()) as WorldBreaker
	breaker.needs_cell = true
	assert_false(breaker.has_power(), "the cell is missing")
	assert_false(breaker.get_interactable().allows(1), "the lever gives the can't-use buzz")
	breaker.get_interactable().used.emit(1)
	assert_false(breaker.is_pulled())


func test_keycard_reader_says_which_card() -> void:
	var reader := WorldKeycardReader.new()
	reader.keycard_prop_id = &"prop_keycard_blue"
	reader.card_name = "blue keycard"
	_add(reader)
	assert_false(reader.is_accepted())
	assert_eq(reader.get_interactable().prompt_text, "Needs the blue keycard")


func test_pry_point_needs_a_crowbar() -> void:
	var pry := _add(WorldPryPoint.new()) as WorldPryPoint
	assert_false(pry.has_tool(12345), "nobody there holds a crowbar")
	assert_false(pry.get_interactable().allows(12345), "so it can't be pried")
	assert_eq(pry.get_progress(), 0.0)
