class_name HamsterWheelTask
extends FloorTask
## The hamster wheel (NEW 2026-11-13, roadmap WP15): a giant running wheel left over from a lab experiment. Its floor
## is a belt that carries you out of the back, so you have to keep running forward (towards -Z) to stay on it; a
## panel across the front (the wheel's far side) stops you running off the front. Every
## second each runner spends on it counts as a second of work; more runners fill it faster (up to the task's
## max_participants). Full, it pays out its reward (FloorTaskData.reward_loot_id).
## Numbers: FloorTaskData.work_seconds, params "belt_speed" (m/s, below walking speed). Grey box until the art pass.
## The belt pushes only the body this PC owns (each player's movement is decided on their own PC); the host counts
## the runners from everyone's synced positions.

const DEFAULT_BELT_SPEED: float = 3.2
const RING_RADIUS: float = 1.6
const RING_THICKNESS: float = 0.12
const PLATFORM_HEIGHT: float = 0.15
## The panel across the front: you run against it.
const FRONT_HEIGHT: float = 1.4
const FRONT_THICKNESS: float = 0.12
const STRIPES: int = 6
## How fast the ring turns (radians a second) for each runner.
const SPIN_PER_RUNNER: float = 1.6
const COLOR_FRAME: Color = Color(0.55, 0.57, 0.6)
const COLOR_BELT: Color = Color(0.2, 0.2, 0.22)
const COLOR_STRIPE: Color = Color(0.95, 0.78, 0.12)

var _belt: TaskStation
var _ring: Node3D
var _stripes: Array[MeshInstance3D] = []
var _label: Label3D
var _stripe_offset: float = 0.0


func _ready() -> void:
	super._ready()
	_belt = get_node_or_null(^"Belt") as TaskStation
	_build_look()
	progress_changed.connect(func(_progress: float) -> void: _update_label())
	completed.connect(_update_label)
	_update_label()


## m/s the belt carries you backwards.
func get_belt_speed() -> float:
	if task_data == null:
		return DEFAULT_BELT_SPEED
	var value: Variant = task_data.params.get("belt_speed", DEFAULT_BELT_SPEED)
	return (value as float) if value is float or value is int else DEFAULT_BELT_SPEED


## The players running on it now (at most max_participants of them).
func get_runners() -> Array[PlayerCharacter]:
	if _belt == null:
		return []
	var runners: Array[PlayerCharacter] = _belt.get_occupants()
	var limit: int = task_data.max_participants if task_data != null else 0
	if limit > 0 and runners.size() > limit:
		runners = runners.slice(0, limit)
	return runners


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _belt == null:
		return
	var runners: Array[PlayerCharacter] = get_runners()
	if not is_done():
		var backwards: Vector3 = _belt.global_basis.z.normalized()
		for player: PlayerCharacter in _belt.get_occupants():
			if player.is_local():
				player.global_position += backwards * get_belt_speed() * delta
		if multiplayer.is_server() and not runners.is_empty():
			var ids: Array[int] = []
			for player: PlayerCharacter in runners:
				ids.append(player.player_id)
			add_work(ids, delta)
	_animate(runners.size(), delta)


func _animate(runner_count: int, delta: float) -> void:
	if is_done():
		return
	if _ring != null:
		_ring.rotate_object_local(Vector3.RIGHT, -SPIN_PER_RUNNER * float(runner_count) * delta)
	var length: float = _belt.size.z
	_stripe_offset = fposmod(_stripe_offset + get_belt_speed() * delta, length / float(STRIPES))
	for index: int in _stripes.size():
		var z: float = -length * 0.5 + float(index) * length / float(STRIPES) + _stripe_offset
		_stripes[index].position.z = z


func _update_label() -> void:
	if _label == null:
		return
	if is_done():
		_label.text = "WHEEL FULL"
		_label.modulate = Color(0.5, 1.0, 0.5)
	else:
		_label.text = "RUN!  %d%%" % roundi(get_progress() * 100.0)


## Grey box: a dark belt with moving yellow stripes on a low platform, a big ring around it, and a sign.
func _build_look() -> void:
	var size: Vector3 = _belt.size if _belt != null else Vector3(2.4, 2.0, 3.2)
	var platform := StaticBody3D.new()
	platform.name = "Platform"
	platform.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, PLATFORM_HEIGHT, size.z)
	shape.shape = box
	shape.position.y = PLATFORM_HEIGHT * 0.5
	platform.add_child(shape)
	platform.add_child(_box_mesh(Vector3(size.x, PLATFORM_HEIGHT, size.z), Vector3(0, PLATFORM_HEIGHT * 0.5, 0), COLOR_BELT))
	add_child(platform)
	var front := StaticBody3D.new()
	front.name = "Front"
	front.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var front_shape := CollisionShape3D.new()
	var front_box := BoxShape3D.new()
	front_box.size = Vector3(size.x, FRONT_HEIGHT, FRONT_THICKNESS)
	front_shape.shape = front_box
	front_shape.position = Vector3(0, FRONT_HEIGHT * 0.5, -size.z * 0.5 - FRONT_THICKNESS * 0.5)
	front.add_child(front_shape)
	front.add_child(_box_mesh(front_box.size, front_shape.position, COLOR_FRAME))
	add_child(front)
	for index: int in STRIPES:
		var stripe: MeshInstance3D = _box_mesh(Vector3(size.x * 0.9, 0.01, 0.12), Vector3(0, PLATFORM_HEIGHT + 0.005, 0),
			COLOR_STRIPE)
		add_child(stripe)
		_stripes.append(stripe)
	_ring = Node3D.new()
	_ring.name = "Ring"
	_ring.position = Vector3(0, RING_RADIUS + PLATFORM_HEIGHT * 0.3, 0)
	var ring_mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - RING_THICKNESS
	torus.outer_radius = RING_RADIUS
	torus.rings = 32
	torus.ring_segments = 6
	torus.material = _material(COLOR_FRAME)
	ring_mesh.mesh = torus
	# A torus lies flat; stand it up so its hole faces along x (you run through it front to back).
	ring_mesh.rotation = Vector3(0, 0, PI * 0.5)
	_ring.add_child(ring_mesh)
	for spoke: int in 4:
		var bar: MeshInstance3D = _box_mesh(Vector3(0.06, RING_RADIUS * 2.0, 0.06), Vector3(size.x * 0.5, 0, 0), COLOR_FRAME)
		bar.rotation.x = float(spoke) * PI * 0.25
		_ring.add_child(bar)
	add_child(_ring)
	_label = Label3D.new()
	_label.name = "Sign"
	_label.position = Vector3(0, RING_RADIUS * 2.0 + 0.6, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.outline_size = 12
	add_child(_label)


func _box_mesh(box_size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = _material(color)
	mesh_instance.mesh = mesh
	mesh_instance.position = at
	return mesh_instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
