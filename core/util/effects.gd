class_name Effects
## Small one-shot visual effects any system can drop into the world (NEW 2026-11-11, roadmap WP7): a burst of little
## cubes or sparks, and a bit of text that floats up and fades. Local only (each PC makes its own); they free
## themselves when done. Grey-box looks until the art pass.


## A burst of `count` little cubes flying out from `at` for `seconds`.
static func burst(parent: Node, at: Vector3, color: Color, count: int, speed: float, size: float,
		seconds: float) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree() or count <= 0:
		return null
	var particles := CPUParticles3D.new()
	particles.name = "Burst"
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = seconds
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	cube.material = material
	particles.mesh = cube
	parent.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.get_tree().create_timer(seconds + 0.2).timeout.connect(particles.queue_free)
	return particles


## Text (e.g. "+5") that rises `rise` metres from `at` and fades out over `seconds`, always facing the camera.
static func float_text(parent: Node, at: Vector3, text: String, color: Color, rise: float, seconds: float) -> Label3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var label := Label3D.new()
	label.name = "FloatText"
	label.text = text
	label.modulate = color
	label.outline_modulate = Color.BLACK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 0.004
	parent.add_child(label)
	label.global_position = at
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", at + Vector3.UP * rise, seconds)
	tween.tween_property(label, "modulate:a", 0.0, seconds)
	tween.chain().tween_callback(label.queue_free)
	return label
