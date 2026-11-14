extends SceneTree

var _frames: int = 0


func _add(path: String, at: Vector3, turn: float = 0.0) -> void:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.position = at
	model.rotation.y = turn
	root.add_child(model)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.14, 0.12, 0.1)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.45, 0.4, 0.35)
		env.environment.ssao_enabled = true
		root.add_child(env)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.6, 1.6, 1.2)
		lamp.light_color = Color(1.0, 0.82, 0.6)
		lamp.light_energy = 2.2
		lamp.omni_range = 6.0
		lamp.shadow_enabled = true
		root.add_child(lamp)
		var table := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.6, 0.1, 1.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.36, 0.22)
		box.material = mat
		table.mesh = box
		table.position = Vector3(0, -0.05, 0)
		root.add_child(table)
		_add("res://assets/models/shared/prop_crate.glb", Vector3(-0.85, 0.3, -0.2), 0.3)
		_add("res://assets/models/zoology/enemy_rat.glb", Vector3(-0.05, 0.0, 0.15), 2.6)
		_add("res://assets/models/shared/prop_gem.glb", Vector3(0.45, 0.09, 0.35))
		_add("res://assets/models/shared/prop_gem_large.glb", Vector3(0.7, 0.15, 0.0), 0.5)
		_add("res://assets/models/shared/prop_meat.glb", Vector3(0.35, 0.08, -0.25), 0.8)
		_add("res://assets/models/shared/prop_dna_vial.glb", Vector3(1.0, 0.13, 0.3))
		_add("res://assets/models/shared/prop_dna_vial_glass.glb", Vector3(1.0, 0.13, 0.3))
		var cam := Camera3D.new()
		cam.position = Vector3(-0.42, 0.38, 0.9)
		cam.fov = 45.0
		root.add_child(cam)
		cam.look_at(Vector3(-0.05, 0.15, 0.15))
		cam.current = true
	if _frames == 30:
		root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
		quit()
	return false
