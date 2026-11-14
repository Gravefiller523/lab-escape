extends SceneTree

var _frames: int = 0


func _add(path: String, at: Vector3, turn: float = 0.0) -> Node3D:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.position = at
	model.rotation.y = turn
	root.add_child(model)
	return model


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.06, 0.06, 0.07)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.3, 0.3, 0.33)
		env.environment.ssao_enabled = true
		env.environment.fog_enabled = true
		env.environment.fog_density = 0.02
		env.environment.fog_light_color = Color(0.25, 0.22, 0.18)
		root.add_child(env)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, 3.0, 0)
		lamp.light_color = Color(1.0, 0.9, 0.75)
		lamp.light_energy = 2.0
		lamp.omni_range = 9.0
		lamp.shadow_enabled = true
		root.add_child(lamp)
		_add("res://assets/models/shared/lift_cage.glb", Vector3.ZERO)
		_add("res://assets/models/shared/lift_door.glb", Vector3(-3.4, 1.5, -2.6))
		_add("res://assets/models/shared/lift_door.glb", Vector3(3.4, 1.5, -2.6))
		_add("res://assets/models/shared/prop_crate.glb", Vector3(-1.4, 0.3, 1.2), 0.4)
		_add("res://assets/models/zoology/enemy_rat.glb", Vector3(1.0, 0.0, -1.0), 2.4)
		var cam := Camera3D.new()
		cam.position = Vector3(1.8, 1.7, -4.8)
		cam.fov = 65.0
		root.add_child(cam)
		cam.look_at(Vector3(-0.3, 1.2, 1.5))
		cam.current = true
	if _frames == 30:
		root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
		quit()
	return false
