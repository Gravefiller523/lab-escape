class_name RoomShape
extends RefCounted
## A room's footprint and doorways in grid cells, read once from its scene (and remembered).
## Internal to level_gen: the generator and Level use it to fit rooms together and turn them.
##
## Grid rules: a room scene's origin is the corner of its footprint with the smallest x and z, at
## floor height, and the footprint covers size cells along +x and +z. One cell is
## Config.game.room_cell_size metres. Doorways sit on the footprint's edge.

## How close (in cells) a doorway must be to an edge to count as on it.
const EDGE_TOLERANCE: float = 0.25

## Footprint in cells (x, z).
var size: Vector2i = Vector2i.ONE
## Each doorway: {"cell": Vector2i (the cell inside the room), "dir": Vector2i (which way it faces),
## "width": float, "height": float, "name": String}. In the room's own (unturned) frame.
var doorways: Array[Dictionary] = []
## Doorways that aren't on an edge (mistakes in the scene), by node name.
var bad_doorways: PackedStringArray = []

static var _cache: Dictionary[StringName, RoomShape] = {}


## The shape of a room (from its scene). Cached by room id.
static func of(room: RoomData, cell_size: float) -> RoomShape:
	if _cache.has(room.id):
		return _cache[room.id]
	var shape := RoomShape.new()
	shape.size = Vector2i(maxi(room.size_cells.x, 1), maxi(room.size_cells.z, 1))
	if room.scene != null:
		var root: Node = room.scene.instantiate()
		shape._read_doorways(root, cell_size)
		root.free()
	_cache[room.id] = shape
	return shape


## For tests that add rooms: forget remembered shapes.
static func clear_cache() -> void:
	_cache.clear()


## Footprint size after turning.
func rotated_size(steps: int) -> Vector2i:
	return size if posmod(steps, 2) == 0 else Vector2i(size.y, size.x)


## The doorways after turning: "cell" is relative to the turned footprint's corner.
func rotated_doorways(steps: int) -> Array[Dictionary]:
	var turned: Array[Dictionary] = []
	var corner: Vector2 = footprint_corner(steps)
	for doorway: Dictionary in doorways:
		var cell: Vector2i = doorway["cell"]
		var center: Vector2 = rotate_xz(Vector2(cell) + Vector2(0.5, 0.5), steps) - corner
		var entry: Dictionary = doorway.duplicate()
		entry["cell"] = Vector2i(floori(center.x), floori(center.y))
		entry["dir"] = Vector2i(rotate_xz(Vector2(doorway["dir"] as Vector2i), steps).round())
		turned.append(entry)
	return turned


## Where the turned footprint's smallest corner ends up (in cells, before moving it into place).
func footprint_corner(steps: int) -> Vector2:
	var corner := Vector2(INF, INF)
	for point: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), Vector2(size)]:
		var turned: Vector2 = rotate_xz(point, steps)
		corner = Vector2(minf(corner.x, turned.x), minf(corner.y, turned.y))
	return corner


## Where a room scene goes for a placement: turned, with its footprint starting at the placement's cell.
func placement_transform(placement: RoomPlacement, cell_size: float) -> Transform3D:
	var basis := Basis(Vector3.UP, float(placement.rotation_steps) * PI / 2.0)
	var corner: Vector2 = footprint_corner(placement.rotation_steps)
	var origin := Vector3((float(placement.cell.x) - corner.x) * cell_size, float(placement.cell.y) * cell_size,
		(float(placement.cell.z) - corner.y) * cell_size)
	return Transform3D(basis, origin)


## Turns a point on the x/z plane the same way a room node turned by steps * 90 degrees turns.
static func rotate_xz(point: Vector2, steps: int) -> Vector2:
	var turned: Vector3 = Basis(Vector3.UP, float(posmod(steps, 4)) * PI / 2.0) * Vector3(point.x, 0.0, point.y)
	return Vector2(turned.x, turned.z)


func _read_doorways(root: Node, cell_size: float) -> void:
	for node: Node in all_children(root):
		var doorway := node as RoomDoorway
		if doorway == null:
			continue
		var u: float = doorway.position.x / cell_size
		var w: float = doorway.position.z / cell_size
		var entry: Dictionary = {"width": doorway.width, "height": doorway.height, "name": String(doorway.name)}
		if absf(u) < EDGE_TOLERANCE:
			entry["dir"] = Vector2i(-1, 0)
			entry["cell"] = Vector2i(0, clampi(floori(w), 0, size.y - 1))
		elif absf(u - float(size.x)) < EDGE_TOLERANCE:
			entry["dir"] = Vector2i(1, 0)
			entry["cell"] = Vector2i(size.x - 1, clampi(floori(w), 0, size.y - 1))
		elif absf(w) < EDGE_TOLERANCE:
			entry["dir"] = Vector2i(0, -1)
			entry["cell"] = Vector2i(clampi(floori(u), 0, size.x - 1), 0)
		elif absf(w - float(size.y)) < EDGE_TOLERANCE:
			entry["dir"] = Vector2i(0, 1)
			entry["cell"] = Vector2i(clampi(floori(u), 0, size.x - 1), size.y - 1)
		else:
			bad_doorways.append(String(doorway.name))
			continue
		doorways.append(entry)


## Every node under root (children, grandchildren, ...).
static func all_children(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		found.append(child)
		found.append_array(all_children(child))
	return found
