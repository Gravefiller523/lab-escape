extends GutTest
## A tile's finished model (NEW 2026-11-14, roadmap WP22 art rollout): BlockoutTile.art_mesh shows the model and hides
## the grey CSG, which still blocks movement.

const TILE: PackedScene = preload("res://systems/level_gen/tiles/tile_zoology_animal_holding.tscn")


func test_the_animal_holding_room_shows_its_model_and_keeps_its_walls() -> void:
	var tile := TILE.instantiate() as Node3D
	add_child_autofree(tile)
	await wait_physics_frames(3)
	var art := tile.find_child(BlockoutTile.ART_NAME, true, false) as MeshInstance3D
	assert_not_null(art, "the finished model is there")
	assert_not_null(art.mesh)
	var hidden: int = 0
	for csg: Node in tile.find_children("*", "CSGCombiner3D", true, false):
		if not (csg as CSGCombiner3D).visible:
			hidden += 1
	assert_gt(hidden, 0, "the grey CSG is hidden")
	# The floor still holds you up and a pen side still blocks the way, though both are invisible now.
	var space: PhysicsDirectSpaceState3D = tile.get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(Vector3(9, 2, 9), Vector3(9, -2, 9))
	assert_false(space.intersect_ray(down).is_empty(), "the floor is solid")
	var across := PhysicsRayQueryParameters3D.create(Vector3(4, 1, 2), Vector3(6, 1, 2))
	assert_false(space.intersect_ray(across).is_empty(), "the pen side between x 4 and 6 still blocks")


func test_a_tile_without_a_model_is_unchanged() -> void:
	# A plain tile made here, so this test never depends on which rooms have models yet.
	var tile := BlockoutTile.new()
	tile.size_units = Vector2i(2, 2)
	add_child_autofree(tile)
	await wait_physics_frames(2)
	assert_null(tile.find_child(BlockoutTile.ART_NAME, true, false))
	for csg: Node in tile.find_children("*", "CSGCombiner3D", true, false):
		assert_true((csg as CSGCombiner3D).visible, "%s still shows" % csg.name)
