class_name CarPark
extends Node3D
## The ending (NEW 2026-11-13, roadmap WP19, mock-up approved by Zachary): the lab's car park in daylight, where the
## cargo lift bursts up through the tarmac after the last boss. game_flow loads it like the Break Room, lined up with
## the lift (LiftSpot), and everyone can walk around until the credits. Grey box, built in code: tarmac with
## painted bays, a few parked cars, broken tarmac round the lift, the lab building behind, and a fence. It turns the
## game world's light to daylight while it is loaded.

const SIZE: float = 60.0
const GROUND_COLOR: Color = Color(0.22, 0.23, 0.25)
const LINE_COLOR: Color = Color(0.85, 0.85, 0.8)
const BUILDING_COLOR: Color = Color(0.62, 0.64, 0.68)
const WINDOW_COLOR: Color = Color(0.35, 0.5, 0.6)
const RUBBLE_COLOR: Color = Color(0.3, 0.3, 0.32)
const CAR_COLORS: Array[Color] = [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.6), Color(0.85, 0.85, 0.82),
	Color(0.2, 0.45, 0.25), Color(0.8, 0.65, 0.1), Color(0.3, 0.3, 0.32)]
## Where the cars stand (x, z, turned), in metres from the lift.
const CAR_SPOTS: Array[Vector3] = [Vector3(-12, 10, 0), Vector3(-8.5, 10, 0), Vector3(-1.5, 10, 0), Vector3(9, 10, 0),
	Vector3(-12, -10, 1), Vector3(5.5, -10, 1)]
## Spots players step out to (around the lift, outside its cage).
const SPAWN_RING: float = 5.5
const SPAWN_COUNT: int = 8

var _lift_spot: Marker3D
var _spawns: Node3D


func _ready() -> void:
	_lift_spot = Marker3D.new()
	_lift_spot.name = "LiftSpot"
	add_child(_lift_spot)
	_spawns = Node3D.new()
	_spawns.name = "Spawns"
	add_child(_spawns)
	for index: int in SPAWN_COUNT:
		var spot := Marker3D.new()
		var angle: float = TAU * float(index) / float(SPAWN_COUNT)
		spot.position = Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RING
		_spawns.add_child(spot)
	_build()
	var world: GameWorld = GameWorld.current()
	if world != null:
		world.set_daylight(true)


func _exit_tree() -> void:
	var world: GameWorld = GameWorld.current()
	if world != null:
		world.set_daylight(false)


## Where the lift stands (game_flow lines this up with the cargo lift).
func get_lift_spot() -> Node3D:
	return _lift_spot


func get_spawn_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for child: Node in _spawns.get_children():
		points.append(child as Node3D)
	return points


func _build() -> void:
	_solid(Vector3(SIZE, 1.0, SIZE), Vector3(0, -0.5, 0), GROUND_COLOR)
	# Painted bays on both sides of the lane the lift came up in.
	for side: float in [-1.0, 1.0]:
		for index: int in 9:
			var x: float = -16.0 + float(index) * 3.5
			_mesh(Vector3(0.12, 0.01, 5.0), Vector3(x, 0.005, 10.0 * side), LINE_COLOR)
	for index: int in CAR_SPOTS.size():
		var spot: Vector3 = CAR_SPOTS[index]
		_car(Vector3(spot.x + 1.75, 0, spot.y), spot.z > 0.5, CAR_COLORS[index % CAR_COLORS.size()])
	# Broken tarmac pushed up round the lift.
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	for index: int in 10:
		var angle: float = TAU * float(index) / 10.0 + rng.randf_range(-0.2, 0.2)
		var at := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(3.6, 4.4)
		var chunk: MeshInstance3D = _mesh(Vector3(rng.randf_range(0.6, 1.2), 0.25, rng.randf_range(0.5, 0.9)),
			at + Vector3.UP * 0.1, RUBBLE_COLOR)
		chunk.rotation = Vector3(rng.randf_range(-0.4, 0.4), angle, rng.randf_range(-0.3, 0.3))
	# The lab behind, with rows of windows, and a fence round the rest.
	_solid(Vector3(SIZE, 12.0, 6.0), Vector3(0, 6.0, -SIZE * 0.5 + 3.0), BUILDING_COLOR)
	for row: int in 3:
		for column: int in 12:
			_mesh(Vector3(2.2, 1.4, 0.05), Vector3(-24.0 + float(column) * 4.4, 2.5 + float(row) * 3.2, -SIZE * 0.5 + 6.03),
				WINDOW_COLOR)
	_solid(Vector3(SIZE, 2.0, 0.2), Vector3(0, 1.0, SIZE * 0.5), BUILDING_COLOR.darkened(0.3))
	_solid(Vector3(0.2, 2.0, SIZE), Vector3(-SIZE * 0.5, 1.0, 0), BUILDING_COLOR.darkened(0.3))
	_solid(Vector3(0.2, 2.0, SIZE), Vector3(SIZE * 0.5, 1.0, 0), BUILDING_COLOR.darkened(0.3))


func _car(at: Vector3, turned: bool, color: Color) -> void:
	var car := StaticBody3D.new()
	car.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	car.position = at
	car.rotation.y = PI if turned else 0.0
	add_child(car)
	var body_size := Vector3(1.8, 0.8, 4.2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = body_size + Vector3(0, 0.6, 0)
	shape.shape = box
	shape.position.y = box.size.y * 0.5 + 0.2
	car.add_child(shape)
	car.add_child(_plain(body_size, Vector3(0, 0.6, 0), color))
	car.add_child(_plain(Vector3(1.6, 0.6, 2.2), Vector3(0, 1.3, 0.3), color.lightened(0.15)))
	for wheel: Vector3 in [Vector3(-0.85, 0.3, -1.3), Vector3(0.85, 0.3, -1.3), Vector3(-0.85, 0.3, 1.3),
			Vector3(0.85, 0.3, 1.3)]:
		car.add_child(_plain(Vector3(0.25, 0.6, 0.6), wheel, Color(0.08, 0.08, 0.08)))


func _solid(box_size: Vector3, at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	body.add_child(_plain(box_size, Vector3.ZERO, color))
	add_child(body)
	return body


func _mesh(box_size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = _plain(box_size, at, color)
	add_child(mesh_instance)
	return mesh_instance


func _plain(box_size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = at
	return mesh_instance
