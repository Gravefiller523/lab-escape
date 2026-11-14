extends SceneTree
## Turns the Blender exports (assets/models/**/*.glb) into plain mesh files the game's scenes use
## (<name>.mesh next to each .glb), with every surface using the shared palette material
## (assets/materials/shared/palette_zoology.tres). Roadmap WP21 art rollout. Run after Blender has rebuilt the models
## and Godot has imported them:
##   godot --headless --path . --editor --quit
##   godot --headless --path . -s assets/source/extract_meshes.gd

const ROOT: String = "res://assets/models"
const PALETTE_MATERIAL: String = "res://assets/materials/shared/palette_zoology.tres"
const GLASS_MATERIAL: String = "res://assets/materials/shared/palette_zoology_glass.tres"

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var solid: Material = _palette_material(PALETTE_MATERIAL, false)
	var glass: Material = _palette_material(GLASS_MATERIAL, true)
	for folder: String in DirAccess.get_directories_at(ROOT):
		var path: String = ROOT.path_join(folder)
		for file: String in DirAccess.get_files_at(path):
			if not file.ends_with(".glb"):
				continue
			var scene := load(path.path_join(file)) as PackedScene
			var mesh: Mesh = _first_mesh(scene.instantiate())
			if mesh == null:
				continue
			var plain := mesh.duplicate() as Mesh
			for surface: int in plain.get_surface_count():
				plain.surface_set_material(surface, glass if file.contains("glass") else solid)
			var out: String = path.path_join(file.get_basename() + ".mesh")
			print("MESH %s %s" % [out, ResourceSaver.save(plain, out)])
	quit()
	return false


func _first_mesh(node: Node) -> Mesh:
	var instance := node as MeshInstance3D
	if instance != null:
		return instance.mesh
	for child: Node in node.get_children():
		var found: Mesh = _first_mesh(child)
		if found != null:
			return found
	return null


func _palette_material(path: String, see_through: bool) -> Material:
	if ResourceLoader.exists(path):
		return load(path) as Material
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/zoology/palette_zoology.png") as Texture2D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.8
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 1, 1, 0.45)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(material, path)
	return load(path) as Material
