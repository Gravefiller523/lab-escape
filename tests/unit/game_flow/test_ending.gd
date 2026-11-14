extends GutTest
## The ending (NEW 2026-11-13, roadmap WP19): the car park, the light and "YOU ESCAPED", the escape PA line, and the
## credits roll. The whole sequence on 3 PCs is in the full-run test.


func test_the_car_park_has_ground_cars_and_a_spot_for_the_lift() -> void:
	var car_park := (load(GameFlowService.CAR_PARK_SCENE) as PackedScene).instantiate() as CarPark
	add_child_autofree(car_park)
	await wait_physics_frames(2)
	assert_not_null(car_park.get_lift_spot())
	assert_gte(car_park.get_spawn_points().size(), 4, "room for the team to step out")
	var query := PhysicsRayQueryParameters3D.create(Vector3(3, 2, 3), Vector3(3, -2, 3), PhysicsLayers.bit(PhysicsLayers.WORLD))
	assert_false(car_park.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "solid ground to walk on")


func test_the_light_fills_the_screen_then_you_escaped_shows() -> void:
	var banner := EscapeBanner.new()
	add_child_autofree(banner)
	await wait_process_frames(1)
	assert_eq(banner.get_whiteness(), 0.0)
	EventBus.run_ended.emit(GameFlowService.RESULT_ESCAPED)
	await wait_seconds(Config.game.lift_ride_seconds * 0.5)
	assert_gt(banner.get_whiteness(), 0.3, "halfway up, the screen is getting white")
	assert_true(banner.is_busy())
	EventBus.surface_reached.emit()
	await wait_process_frames(2)
	assert_eq(banner.get_text(), "YOU ESCAPED")
	await wait_seconds(Config.game.escape_banner_seconds + 0.6)
	assert_eq(banner.get_text(), "", "then it goes")
	assert_eq(banner.get_whiteness(), 0.0, "and so does the light")
	assert_false(banner.is_busy(), "and the run summary may show")


func test_a_wipe_is_not_an_escape() -> void:
	var banner := EscapeBanner.new()
	add_child_autofree(banner)
	await wait_process_frames(1)
	EventBus.run_ended.emit(&"wiped")
	await wait_seconds(0.5)
	assert_eq(banner.get_whiteness(), 0.0, "no light for a wipe")


func test_the_last_ride_has_its_own_pa_lines() -> void:
	var line: String = Announcer.pick(42, 13, &"", &"escape_ride")
	assert_false(line.is_empty(), "there is a line for the ride up")
	var escape_lines: Array[String] = []
	for content: ContentData in ContentRegistry.get_all(&"announcement"):
		var data := content as AnnouncementData
		if data.moment == &"escape_ride":
			escape_lines.append(data.text)
	assert_has(escape_lines, line)
	for floor_number: int in range(1, 20):
		assert_does_not_have(escape_lines, Announcer.pick(42, floor_number, &"department_zoology"),
			"floors never read an escape line (floor %d)" % floor_number)


func test_the_credits_roll_shows_the_names_and_the_licences() -> void:
	UI.show_screen(UIService.SCREEN_CREDITS)
	await wait_process_frames(2)
	var screen: Node = UI.get_child(UI.get_child_count() - 2)
	assert_eq(UI.get_open_screen(), UIService.SCREEN_CREDITS)
	screen.call("keep_rolling")
	var lines: PackedStringArray = screen.call("get_lines")
	assert_has(lines, "Made by Zachary")
	assert_has(lines, "LAB ESCAPE")
	assert_has(lines, "Godot Engine licence", "Godot's own licence notice is included")
	assert_gt(lines.size(), 30, "and its third-party notices")
	Input.parse_input_event(_key(KEY_ESCAPE))
	await wait_process_frames(3)
	assert_ne(UI.get_open_screen(), UIService.SCREEN_CREDITS, "Esc skips it")


func test_the_lift_waits_in_the_car_park() -> void:
	var lift := (load("res://systems/cargo_lift/cargo_lift.tscn") as PackedScene).instantiate() as CargoLift
	add_child_autofree(lift)
	await wait_process_frames(2)
	lift.set_hold_note(GameFlowService.CAR_PARK_HOLD_NOTE)
	assert_false(lift.is_ready(), "Go doesn't work while it waits")
	assert_eq(lift.depart_blocker(), GameFlowService.CAR_PARK_HOLD_NOTE, "and it says why")
	lift.set_hold_note("")
	assert_eq(lift.get_hold_note(), "")


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event
