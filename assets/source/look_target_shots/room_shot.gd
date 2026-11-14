extends SceneTree
# SHOT_MODE=final: the look-target room with warm light and fog. SHOT_MODE=grey: the grey-box tile, plain light.

var _frames: int = 0


func _add(path: String, at: Vector3, turn: float = 0.0) -> Node3D:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.position = at
	model.rotation.y = turn
	root.add_child(model)
	return model


func _process(_delta: float) -> bool:
	_frames += 1
	var final: bool = OS.get_environment("SHOT_MODE") == "final"
	if _frames == 2:
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.05, 0.05, 0.05)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		root.add_child(env)
		if final:
			env.environment.ambient_light_color = Color(0.55, 0.47, 0.36)
			env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.environment.tonemap_exposure = 1.3
			env.environment.ssao_enabled = true
			env.environment.glow_enabled = true
			env.environment.fog_enabled = true
			env.environment.fog_density = 0.008
			env.environment.fog_light_color = Color(0.4, 0.33, 0.22)
			env.environment.volumetric_fog_enabled = true
			env.environment.volumetric_fog_density = 0.012
			env.environment.volumetric_fog_albedo = Color(1.0, 0.9, 0.7)
			_add("res://assets/models/zoology/room_zoology_animal_holding.glb", Vector3.ZERO)
			for spot: Vector3 in [Vector3(4.5, 3.5, 4.5), Vector3(13.5, 3.5, 4.5), Vector3(4.5, 3.5, 13.5)]:
				var beam := SpotLight3D.new()
				beam.position = spot
				beam.rotation_degrees = Vector3(-90, 0, 0)
				beam.light_color = Color(1.0, 0.92, 0.75)
				beam.light_energy = 9.0
				beam.spot_range = 6.0
				beam.spot_angle = 35.0
				beam.shadow_enabled = true
				beam.light_volumetric_fog_energy = 2.0
				root.add_child(beam)
			for lamp_at: Vector3 in [Vector3(9, 3.0, 9), Vector3(9, 3.0, 3)]:
				var lamp := OmniLight3D.new()
				lamp.position = lamp_at
				lamp.light_color = Color(1.0, 0.75, 0.45)
				lamp.light_energy = 2.6
				lamp.omni_range = 9.0
				root.add_child(lamp)
			_add("res://assets/models/zoology/enemy_rat.glb", Vector3(9.0, 0.0, 12.5), 2.8)
			_add("res://assets/models/zoology/enemy_rat.glb", Vector3(10.2, 0.0, 13.6), 3.6)
			_add("res://assets/models/shared/prop_crate.glb", Vector3(6.5, 0.3, 15.5), 0.3)
			_add("res://assets/models/shared/prop_gem.glb", Vector3(9.5, 0.09, 6.5))
			_add("res://assets/models/shared/prop_meat.glb", Vector3(11.0, 0.08, 9.0), 0.8)
		else:
			env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-60, 25, 0)
			root.add_child(sun)
			_add("res://systems/level_gen/tiles/tile_zoology_animal_holding.tscn", Vector3.ZERO)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(9, 3.0, 9)
			lamp.omni_range = 14.0
			root.add_child(lamp)
		var cam := Camera3D.new()
		cam.position = Vector3(10.5, 1.7, 17.3)
		cam.fov = 70.0
		root.add_child(cam)
		cam.look_at(Vector3(7.5, 1.1, 4.0))
		cam.current = true
	if _frames == 40:
		root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
		quit()
	return false
