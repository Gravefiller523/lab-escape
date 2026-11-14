extends SceneTree

var _frames: int = 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var car_park: Node3D = (load("res://systems/game_flow/ending/car_park.tscn") as PackedScene).instantiate()
		root.add_child(car_park)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.55, 0.75, 0.95)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.8, 0.82, 0.85)
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-60, 25, 0)
		sun.light_energy = 1.6
		sun.shadow_enabled = true
		root.add_child(sun)
		var cage := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(5, 3.2, 5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.78, 0.12)
		box.material = mat
		cage.mesh = box
		cage.position = Vector3(0, 1.6, 0)
		root.add_child(cage)
		var cam := Camera3D.new()
		cam.position = Vector3(9, 4.5, 14)
		root.add_child(cam)
		cam.look_at(Vector3(0, 1.5, -4))
		cam.current = true
	if _frames == 30:
		root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
		quit()
	return false
