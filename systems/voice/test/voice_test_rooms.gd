class_name VoiceTestRooms
extends RefCounted
## Builds the voice test layout: two rooms side by side with a solid wall between them, joined by a
## hallway along their north side. Room A's doorway into the hallway has a door (a stub of the
## doors system) that can open and close. Used by the voice proof scene and the GUT tests.
##
##   z=7  +--------- hallway ---------+
##        |  [door]            open   |
##   z=4  +---+   +---+wall+---+   +---+
##        | Room A    | wall |  Room B |
##   z=-4 +-----------+------+---------+
##       x=-10      x=-1   x=1      x=10

const WALL_HEIGHT: float = 3.0
const ROOM_A_CENTER: Vector3 = Vector3(-6, 0, 0)
const ROOM_B_CENTER: Vector3 = Vector3(6, 0, 0)
const DOOR_CENTER: Vector3 = Vector3(-2.5, 0, 4)
## Length of the optional field south of Room B (metres).
const FIELD_LENGTH: float = 60.0


## Builds the rooms under `parent`. With `navmesh`, the walkable floor is baked so voices can go the
## long way round. Returns the door's SoundDoor (open to start with).
static func build(parent: Node3D, navmesh: bool, long_field: bool = false) -> SoundDoor:
	var holder: Node3D
	var region: NavigationRegion3D
	if navmesh:
		region = NavigationRegion3D.new()
		region.name = "Navigation"
		var mesh := NavigationMesh.new()
		mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		mesh.geometry_collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD)
		# Multiples of the navmesh cell size (0.25 m), or Godot warns.
		mesh.agent_radius = 0.5
		mesh.agent_height = 2.0
		region.navigation_mesh = mesh
		parent.add_child(region)
		holder = region
	else:
		holder = Node3D.new()
		holder.name = "Rooms"
		parent.add_child(holder)

	_box(holder, Vector3(0, -0.25, 1.5), Vector3(20, 0.5, 11), Color(0.45, 0.46, 0.5))
	_box(holder, Vector3(0, WALL_HEIGHT / 2.0, 0), Vector3(2, WALL_HEIGHT, 8), Color(0.6, 0.6, 0.64))
	_box(holder, Vector3(-7, WALL_HEIGHT / 2.0, 4.2), Vector3(6, WALL_HEIGHT, 0.4), Color(0.6, 0.6, 0.64))
	_box(holder, Vector3(7, WALL_HEIGHT / 2.0, 4.2), Vector3(6, WALL_HEIGHT, 0.4), Color(0.6, 0.6, 0.64))
	_box(holder, Vector3(0, WALL_HEIGHT / 2.0, 7.2), Vector3(20, WALL_HEIGHT, 0.4), Color(0.6, 0.6, 0.64))
	if long_field:
		# Room B gets an opening in its south wall onto a long field, for the distance fade test.
		_box(holder, Vector3(-3, WALL_HEIGHT / 2.0, -4.2), Vector3(14, WALL_HEIGHT, 0.4), Color(0.6, 0.6, 0.64))
		_box(holder, Vector3(9, WALL_HEIGHT / 2.0, -4.2), Vector3(2, WALL_HEIGHT, 0.4), Color(0.6, 0.6, 0.64))
		_box(holder, Vector3(6, -0.25, -FIELD_LENGTH / 2.0 - 4.0), Vector3(8, 0.5, FIELD_LENGTH), Color(0.5, 0.52, 0.48))
	else:
		_box(holder, Vector3(0, WALL_HEIGHT / 2.0, -4.2), Vector3(20, WALL_HEIGHT, 0.4), Color(0.6, 0.6, 0.64))
	_box(holder, Vector3(-10.2, WALL_HEIGHT / 2.0, 1.5), Vector3(0.4, WALL_HEIGHT, 11), Color(0.6, 0.6, 0.64))
	_box(holder, Vector3(10.2, WALL_HEIGHT / 2.0, 1.5), Vector3(0.4, WALL_HEIGHT, 11), Color(0.6, 0.6, 0.64))
	if region != null:
		# Baked while the door is open, so the route through the doorway exists.
		region.bake_navigation_mesh(false)

	var door := SoundDoor.new()
	door.name = "Door"
	door.position = DOOR_CENTER + Vector3(0, WALL_HEIGHT / 2.0, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, WALL_HEIGHT, 0.6)
	shape.shape = box
	door.add_child(shape)
	parent.add_child(door)
	return door


static func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	parent.add_child(body)
	return body
