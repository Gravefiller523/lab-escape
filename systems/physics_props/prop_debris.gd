class_name PropDebris
extends RigidBody3D
## A piece of a broken prop (NEW 2026-10-29, HL2 feel step 2.6). Cosmetic: each PC makes its own pieces
## when the host says a prop broke, they only hit the world (PhysicsLayers.DEBRIS), and they shrink away
## after Config.feel.props.gib_lifetime seconds. At most max_gibs exist; the oldest go first.

static var _alive: Array[PropDebris] = []

var _age: float = 0.0


## Breaks a box-ish prop of `half_extents` (its own axes) at `xform` into `count` pieces of `color`,
## flying apart from `velocity`. Pieces become children of `parent`. Returns them.
static func burst(parent: Node, xform: Transform3D, half_extents: Vector3, color: Color, velocity: Vector3,
		count: int) -> Array[PropDebris]:
	var pieces: Array[PropDebris] = []
	if parent == null or count <= 0:
		return pieces
	# Not gameplay: looks only, so its own random numbers.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var piece_size: Vector3 = (half_extents * 2.0 / maxf(pow(float(count), 1.0 / 3.0), 1.0)).max(Vector3.ONE * 0.05)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	for index: int in count:
		var piece := PropDebris.new()
		var offset := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * half_extents * 0.6
		piece.transform = Transform3D(xform.basis, xform * offset)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = piece_size
		shape.shape = box
		piece.add_child(shape)
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = piece_size
		box_mesh.material = material
		mesh.mesh = box_mesh
		piece.add_child(mesh)
		piece.mass = 0.3
		piece.linear_velocity = velocity * 0.5 + offset.normalized() * rng.randf_range(1.0, 3.0) + Vector3.UP * 1.5
		piece.angular_velocity = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		parent.add_child(piece)
		pieces.append(piece)
	return pieces


## How many pieces exist right now (all games on this PC).
static func count_alive() -> int:
	_alive = _alive.filter(func(piece: PropDebris) -> bool: return is_instance_valid(piece))
	return _alive.size()


func _ready() -> void:
	collision_layer = PhysicsLayers.bit(PhysicsLayers.DEBRIS)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD)
	count_alive()
	_alive.append(self)
	var limit: int = maxi(Config.feel.props.max_gibs, 1)
	while _alive.size() > limit:
		var oldest: PropDebris = _alive.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _exit_tree() -> void:
	_alive.erase(self)


func _process(delta: float) -> void:
	_age += delta
	var tuning: PropTuning = Config.feel.props
	var fade_left: float = tuning.gib_lifetime + tuning.gib_fade_seconds - _age
	if fade_left <= 0.0:
		queue_free()
	elif fade_left < tuning.gib_fade_seconds:
		var shrink: float = maxf(fade_left / maxf(tuning.gib_fade_seconds, 0.01), 0.01)
		for child: Node in get_children():
			var mesh := child as MeshInstance3D
			if mesh != null:
				mesh.scale = Vector3.ONE * shrink
