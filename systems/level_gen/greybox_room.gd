@tool
class_name GreyboxRoom
extends Node3D
## A quick grey-box room for testing layouts: put this script on a room scene's root, set size_cells,
## and add RoomDoorway and RoomMarker children. It builds a floor and walls around the footprint and
## leaves a gap for every doorway on an edge. Move a doorway, then tick "rebuild" to see the change.
## (Real rooms with art replace these later; the generator doesn't care which kind a room is.)

## Footprint in grid cells (x, z). Must match the room's RoomData.size_cells.
@export var size_cells: Vector2i = Vector2i.ONE
@export var wall_height: float = 3.5
@export var wall_thickness: float = 0.3
@export var floor_color: Color = Color(0.42, 0.43, 0.46)
@export var wall_color: Color = Color(0.58, 0.59, 0.62)
## Editor helper: tick it to build the geometry again.
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if is_inside_tree():
			_build()

const GENERATED_NAME: String = "Generated"
const FLOOR_THICKNESS: float = 0.3


func _ready() -> void:
	_build()


func _cell_size() -> float:
	if Engine.is_editor_hint():
		var config := load("res://config/game_config.tres") as GameConfig
		return config.room_cell_size if config != null else 12.0
	return Config.game.room_cell_size


func _build() -> void:
	var old: Node = get_node_or_null(GENERATED_NAME)
	if old != null:
		remove_child(old)
		old.queue_free()
	var generated := Node3D.new()
	generated.name = GENERATED_NAME
	add_child(generated)
	var cell: float = _cell_size()
	var length := Vector2(float(size_cells.x) * cell, float(size_cells.y) * cell)
	_box(generated, Vector3(length.x / 2.0, -FLOOR_THICKNESS / 2.0, length.y / 2.0),
		Vector3(length.x, FLOOR_THICKNESS, length.y), floor_color)
	# The four edges: (start, end, which axis runs along it).
	_wall_line(generated, Vector3(0, 0, 0), Vector3(length.x, 0, 0), _gaps(true, 0.0, length.x))
	_wall_line(generated, Vector3(0, 0, length.y), Vector3(length.x, 0, length.y), _gaps(true, length.y, length.x))
	_wall_line(generated, Vector3(0, 0, 0), Vector3(0, 0, length.y), _gaps(false, 0.0, length.y))
	_wall_line(generated, Vector3(length.x, 0, 0), Vector3(length.x, 0, length.y), _gaps(false, length.x, length.y))


## The doorways on one edge, as [from, to, height] along it. along_x: the edge runs along x at z = line.
func _gaps(along_x: bool, line: float, edge_length: float) -> Array[Vector3]:
	var gaps: Array[Vector3] = []
	for child: Node in get_children():
		var doorway := child as RoomDoorway
		if doorway == null:
			continue
		var across: float = doorway.position.z if along_x else doorway.position.x
		var along: float = doorway.position.x if along_x else doorway.position.z
		if absf(across - line) > 0.5 or along < 0.0 or along > edge_length:
			continue
		gaps.append(Vector3(along - doorway.width / 2.0, along + doorway.width / 2.0, doorway.height))
	gaps.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	return gaps


## Builds wall pieces from `from` to `to`, leaving the gaps (with a piece above each).
func _wall_line(parent: Node3D, from: Vector3, to: Vector3, gaps: Array[Vector3]) -> void:
	var direction: Vector3 = (to - from).normalized()
	var total: float = from.distance_to(to)
	var cursor: float = 0.0
	for gap: Vector3 in gaps:
		_wall_piece(parent, from, direction, cursor, gap.x, 0.0, wall_height)
		_wall_piece(parent, from, direction, gap.x, gap.y, gap.z, wall_height)
		cursor = gap.y
	_wall_piece(parent, from, direction, cursor, total, 0.0, wall_height)


func _wall_piece(parent: Node3D, from: Vector3, direction: Vector3, start: float, end: float,
		bottom: float, top: float) -> void:
	if end - start < 0.01 or top - bottom < 0.01:
		return
	var middle: Vector3 = from + direction * (start + end) / 2.0 + Vector3.UP * (bottom + top) / 2.0
	var size := Vector3(end - start, top - bottom, wall_thickness) if absf(direction.x) > 0.5 \
		else Vector3(wall_thickness, top - bottom, end - start)
	_box(parent, middle, size, wall_color)


func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	body.collision_mask = 0
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
