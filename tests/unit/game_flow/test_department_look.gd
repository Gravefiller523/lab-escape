extends GutTest
## A department's atmosphere (NEW 2026-11-14, art phase WP26): GameWorld.apply_look puts the department's
## LightingStyleData "Atmosphere" settings on the world, and the plain look and daylight still work.

const WORLD_SCENE: String = "res://systems/game_flow/game_world.tscn"

var _world: GameWorld


func before_each() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as GameWorld
	add_child_autofree(_world)
	await wait_process_frames(1)


func _environment() -> Environment:
	for child: Node in _world.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
	return null


func test_every_department_has_an_atmosphere() -> void:
	for id: StringName in [&"department_zoology", &"department_botany", &"department_robotics"]:
		var department := ContentRegistry.get_content(id) as DepartmentData
		assert_not_null(department.lighting, "%s has lighting" % id)
		assert_gt(department.lighting.fog_density, 0.0, "%s has a haze" % id)
		assert_gt(department.lighting.mote_amount, 0, "%s has floating specks" % id)
		assert_true(department.lighting.shadows, "%s lights cast shadows" % id)


func test_a_department_look_goes_on_and_comes_off() -> void:
	var zoology := ContentRegistry.get_content(&"department_zoology") as DepartmentData
	_world.apply_look(zoology.lighting)
	var environment: Environment = _environment()
	assert_eq(_world.get_look(), zoology.lighting)
	assert_true(environment.fog_enabled, "haze on")
	assert_eq(environment.fog_light_color, zoology.lighting.fog_color)
	assert_eq(environment.ambient_light_color, zoology.lighting.ambient_color)
	assert_eq(environment.tonemap_mode, Environment.TONE_MAPPER_FILMIC)
	assert_not_null(_world.find_child("Motes", false, false), "dust floats around")
	_world.apply_look(null)
	await wait_process_frames(1)
	assert_false(environment.fog_enabled, "the plain look has no haze")
	assert_null(_world.find_child("Motes", false, false), "and no dust")


func test_daylight_then_back_inside_keeps_the_department_look() -> void:
	var robotics := ContentRegistry.get_content(&"department_robotics") as DepartmentData
	_world.apply_look(robotics.lighting)
	_world.set_daylight(true)
	assert_true(_world.is_daylight())
	assert_false(_environment().fog_enabled, "no haze in daylight")
	_world.set_daylight(false)
	assert_false(_world.is_daylight())
	assert_eq(_world.get_look(), robotics.lighting, "back inside, the department look again")
	assert_eq(_environment().background_color, robotics.lighting.background_color)
