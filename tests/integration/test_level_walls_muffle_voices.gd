extends GutTest
## Voices on a real level_gen floor: walls between rooms muffle them, open doorways and the same room don't.

const HEAD: Vector3 = Vector3(0, 1.6, 0)


func test_walls_between_rooms_muffle_voices() -> void:
	var cell: float = Config.game.room_cell_size
	# The lift room at (0, 0) has one doorway (north). A hall to its east only touches its wall;
	# a hall to its north joins it through the doorway.
	var layout := FloorLayout.new()
	layout.placements.append(RoomPlacement.make(&"room_lift_grey", Vector3i(0, 0, 0), 0))
	layout.placements.append(RoomPlacement.make(&"room_hall_grey", Vector3i(1, 0, 0), 0))
	layout.placements.append(RoomPlacement.make(&"room_hall_grey", Vector3i(0, 0, -1), 0))
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	Level.build(layout, root)
	await wait_physics_frames(3)
	var world: World3D = root.get_world_3d()

	var lift_middle := Vector3(cell * 0.5, 0, cell * 0.5) + HEAD
	var east_hall := Vector3(cell * 1.5, 0, cell * 0.5) + HEAD
	var north_hall := Vector3(cell * 0.5, 0, -cell * 0.5) + HEAD
	var same_room := Vector3(cell * 0.8, 0, cell * 0.3) + HEAD

	var through_wall := VoiceHearing.compute(east_hall, lift_middle, world, Config.game)
	assert_gt(through_wall.muffle, 0.5, "a wall between the rooms muffles the voice")
	var through_doorway := VoiceHearing.compute(north_hall, lift_middle, world, Config.game)
	assert_eq(through_doorway.muffle, 0.0, "through the open doorway: clear")
	var nearby := VoiceHearing.compute(same_room, lift_middle, world, Config.game)
	assert_eq(nearby.muffle, 0.0, "same room: clear")
	assert_lt(VoiceService.hearing_gain(through_wall.distance, through_wall.muffle, Config.game),
		VoiceService.hearing_gain(through_doorway.distance, through_doorway.muffle, Config.game),
		"and it is quieter than the same distance through a doorway")
	Level.clear()
