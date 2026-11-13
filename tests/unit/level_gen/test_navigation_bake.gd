extends GutTest
## NEW 2026-11-13 (floor generation step 6b): the enemies' navigation bake reads the blockout rooms from their
## collision faces, not their visual meshes. Godot warns that reading visual meshes is slow (it copies them back
## from the graphics card). This checks the bake of a damaged floor in every department gives no such warning,
## and that it finds the same walkable floor the slow way does (so walls still block where they did).

const DEPARTMENTS: Array[StringName] = [&"department_robotics", &"department_botany", &"department_zoology"]
const FLOOR: int = 7
## How much the two ways' walkable areas may differ (a share of the area).
const AREA_TOLERANCE: float = 0.02


func after_each() -> void:
	FloorGenerator.debug_damage = &""
	Level.clear()


func test_a_damaged_floor_bakes_without_reading_visual_meshes_and_finds_the_same_floor() -> void:
	for department_id: StringName in DEPARTMENTS:
		var department := ContentRegistry.get_content(department_id) as DepartmentData
		assert_not_null(department, "%s exists" % department_id)
		var root := Node3D.new()
		add_child_autofree(root)
		FloorGenerator.debug_damage = &"heavy"
		var layout: FloorLayout = FloorGenerator.generate_from_seed(department, FLOOR, 4249, Config.floor_gen)
		FloorGenerator.debug_damage = &""
		Level.build(layout, root)
		await wait_physics_frames(3)
		var rooms := root.get_node(LevelService.ROOMS_NODE) as Node3D
		var region: NavigationRegion3D = Enemies.bake_navigation(rooms, true)
		assert_not_null(region.navigation_mesh, "%s: the floor's navigation is baked" % department_id)
		for error: GutTrackedError in get_errors():
			assert_false(not error.handled and error.contains_text("Source geometry"),
				"%s: the bake didn't read visual meshes" % department_id)
		var slow: NavigationMesh = _bake_the_slow_way(region.navigation_mesh, rooms)
		var area: float = _walkable_area(region.navigation_mesh)
		var slow_area: float = _walkable_area(slow)
		assert_gt(area, 0.0, "%s: there is walkable floor" % department_id)
		assert_almost_eq(area, slow_area, slow_area * AREA_TOLERANCE,
			"%s: the same walkable floor as reading the visual meshes" % department_id)
		Level.clear()
		await wait_physics_frames(2)


## Bake the same rooms the way Godot does on its own (it reads the rooms' visual meshes, and warns).
func _bake_the_slow_way(like: NavigationMesh, rooms: Node3D) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = like.geometry_parsed_geometry_type
	mesh.geometry_collision_mask = like.geometry_collision_mask
	mesh.geometry_source_geometry_mode = like.geometry_source_geometry_mode
	mesh.agent_radius = like.agent_radius
	mesh.agent_height = like.agent_height
	mesh.cell_size = like.cell_size
	mesh.cell_height = like.cell_height
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, rooms)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	for error: GutTrackedError in get_errors():
		if error.contains_text("Source geometry"):
			error.handled = true
	return mesh


## The navigation mesh's total polygon area (square metres).
func _walkable_area(mesh: NavigationMesh) -> float:
	var vertices: PackedVector3Array = mesh.get_vertices()
	var total: float = 0.0
	for index: int in mesh.get_polygon_count():
		var polygon: PackedInt32Array = mesh.get_polygon(index)
		for corner: int in range(1, polygon.size() - 1):
			var a: Vector3 = vertices[polygon[corner]] - vertices[polygon[0]]
			var b: Vector3 = vertices[polygon[corner + 1]] - vertices[polygon[0]]
			total += a.cross(b).length() / 2.0
	return total
