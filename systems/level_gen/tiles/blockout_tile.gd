@tool
class_name BlockoutTile
extends Node3D
## NEW 2026-10-30 (floor generation, step 2): a plain grey tile on the 3 m grid, built from CSG boxes.
## Put this script on a tile scene's root, set size_units, and add RoomDoorway sockets on the footprint
## edge (see docs/systems/level_gen.md, "Tile standards"). When the tile loads it builds:
## - the floor and the ceiling (ceiling_height high, group "tile_ceiling"),
## - walls on the edge (wall_thickness thick, centred on it) with a doorway-sized hole for every door
##   socket and a frame around it, and no wall at all where a socket is an open_edge (hallway ends),
## - ceiling lights (group "tile_light"),
## - placeholder coloured boxes in empty damage overlays (Damage/Light, Damage/Heavy, Damage/Destroyed).
## Everything solid uses CSG with collision on the WORLD layer, so players, voices (muffling) and the
## enemies' navigation bake all see it. Nothing it builds is saved in the scene: move a socket, then tick
## "rebuild". Furniture and other pieces you add to the scene yourself stay as they are.
## Real art replaces these later; the generator doesn't care which kind a tile is.

## Footprint in grid units (x, z). Must match the tile's RoomData.size_cells (x and z).
@export var size_units: Vector2i = Vector2i.ONE
## Add ceiling lights (one per 2 x 2 grid units).
@export var auto_lights: bool = true
## A hole in the floor (x, z, width, depth in metres), e.g. where the cargo lift's own floor stands, so
## the two floors don't flicker against each other. Zero size = no hole.
@export var floor_hole: Rect2 = Rect2()
## Editor helper: tick it to build the geometry again.
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if is_inside_tree():
			_build()

const GENERATED_NAME: String = "Generated"
const PLACEHOLDER_NAME: String = "Placeholder"
const TUNING_PATH: String = "res://config/floor_gen_tuning.tres"
## Floor and ceiling slab thickness (metres).
const SLAB: float = 0.3
## Door frame thickness (metres).
const FRAME: float = 0.1
const MATERIALS_PATH: String = "res://systems/level_gen/tiles/materials/blockout_%s.tres"
const OVERLAY_COLORS: Dictionary[StringName, Color] = {
	&"light": Color(0.85, 0.75, 0.25), &"heavy": Color(0.9, 0.45, 0.15), &"destroyed": Color(0.75, 0.12, 0.1)}


func _ready() -> void:
	_build()


## The material a slot uses before a department palette replaces it.
static func slot_material(slot: StringName) -> Material:
	return load(MATERIALS_PATH % slot) as Material


func _tuning() -> FloorGenTuning:
	if Engine.is_editor_hint():
		var tuning := load(TUNING_PATH) as FloorGenTuning
		return tuning if tuning != null else FloorGenTuning.new()
	return Config.floor_gen


func _build() -> void:
	var old: Node = get_node_or_null(GENERATED_NAME)
	if old != null:
		remove_child(old)
		old.queue_free()
	var tuning: FloorGenTuning = _tuning()
	var unit: float = tuning.grid_unit
	var height: float = tuning.ceiling_height
	var length := Vector2(float(size_units.x) * unit, float(size_units.y) * unit)
	var generated := Node3D.new()
	generated.name = GENERATED_NAME
	add_child(generated)

	var shell := _csg_root("Shell")
	generated.add_child(shell)
	var sockets: Array[RoomDoorway] = _sockets()
	# Walls first, then the doorway holes cut out of them, then everything added on top.
	for edge: int in 4:
		_build_edge_walls(shell, edge, sockets, tuning)
	for socket: RoomDoorway in sockets:
		if not socket.open_edge:
			_cut_doorway(shell, socket, tuning)
	for socket: RoomDoorway in sockets:
		if not socket.open_edge:
			_add_frame(shell, socket, tuning)
	_box(shell, "Floor", Vector3(length.x / 2.0, -SLAB / 2.0, length.y / 2.0), Vector3(length.x, SLAB, length.y), &"floor")
	if floor_hole.has_area():
		var middle: Vector2 = floor_hole.get_center()
		var hole := _box(shell, "FloorHole", Vector3(middle.x, -SLAB / 2.0, middle.y),
			Vector3(floor_hole.size.x, SLAB + 0.2, floor_hole.size.y), &"floor")
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION

	var ceiling := _csg_root("Ceiling")
	ceiling.add_to_group(TileStandards.CEILING_GROUP)
	generated.add_child(ceiling)
	_box(ceiling, "Slab", Vector3(length.x / 2.0, height + SLAB / 2.0, length.y / 2.0), Vector3(length.x, SLAB, length.y), &"wall")

	if auto_lights:
		_add_lights(generated, tuning)
	_fill_overlays(tuning)


## The tile's sockets (RoomDoorway children, not inside the generated nodes).
func _sockets() -> Array[RoomDoorway]:
	var found: Array[RoomDoorway] = []
	for node: Node in RoomShape.all_children(self):
		var socket := node as RoomDoorway
		if socket != null:
			found.append(socket)
	return found


## Edge 0 = north (z = 0), 1 = south (z = far), 2 = west (x = 0), 3 = east (x = far).
## Returns [start corner, direction along the edge, number of grid units].
func _edge_info(edge: int, unit: float) -> Array:
	var length := Vector2(float(size_units.x) * unit, float(size_units.y) * unit)
	match edge:
		0:
			return [Vector3.ZERO, Vector3.RIGHT, size_units.x]
		1:
			return [Vector3(0, 0, length.y), Vector3.RIGHT, size_units.x]
		2:
			return [Vector3.ZERO, Vector3.BACK, size_units.y]
		_:
			return [Vector3(length.x, 0, 0), Vector3.BACK, size_units.y]


## Which edge a socket is on (see _edge_info), or -1, and its grid unit along that edge.
func _socket_place(socket: RoomDoorway, unit: float) -> Vector2i:
	var u: float = socket.position.x / unit
	var w: float = socket.position.z / unit
	var tolerance: float = RoomShape.EDGE_TOLERANCE
	if absf(w) < tolerance:
		return Vector2i(0, floori(u))
	if absf(w - float(size_units.y)) < tolerance:
		return Vector2i(1, floori(u))
	if absf(u) < tolerance:
		return Vector2i(2, floori(w))
	if absf(u - float(size_units.x)) < tolerance:
		return Vector2i(3, floori(w))
	return Vector2i(-1, 0)


## The walls along one edge: one box per run of grid units that are not open edges.
func _build_edge_walls(shell: CSGCombiner3D, edge: int, sockets: Array[RoomDoorway], tuning: FloorGenTuning) -> void:
	var unit: float = tuning.grid_unit
	var info: Array = _edge_info(edge, unit)
	var start: Vector3 = info[0]
	var along: Vector3 = info[1]
	var units: int = info[2]
	var open: Dictionary[int, bool] = {}
	for socket: RoomDoorway in sockets:
		var place: Vector2i = _socket_place(socket, unit)
		if place.x == edge and socket.open_edge:
			open[place.y] = true
	var run_start: int = -1
	for index: int in units + 1:
		var closed: bool = index < units and not open.has(index)
		if closed and run_start < 0:
			run_start = index
		elif not closed and run_start >= 0:
			# Runs that reach a corner go on by half a wall, so corners are closed.
			var from: float = float(run_start) * unit - (tuning.wall_thickness / 2.0 if run_start == 0 else 0.0)
			var to: float = float(index) * unit + (tuning.wall_thickness / 2.0 if index == units else 0.0)
			var middle: Vector3 = start + along * (from + to) / 2.0 + Vector3.UP * tuning.ceiling_height / 2.0
			var size: Vector3 = _along_size(along, to - from, tuning.ceiling_height, tuning.wall_thickness)
			_box(shell, "Wall%d_%d" % [edge, run_start], middle, size, &"wall")
			run_start = -1


## A box size for something lying along an edge direction: long along it, thick across it.
func _along_size(along: Vector3, length: float, box_height: float, thickness: float) -> Vector3:
	if absf(along.x) > 0.5:
		return Vector3(length, box_height, thickness)
	return Vector3(thickness, box_height, length)


func _socket_along(socket: RoomDoorway, unit: float) -> Vector3:
	var edge: int = _socket_place(socket, unit).x
	return Vector3.RIGHT if edge == 0 or edge == 1 else Vector3.BACK


func _cut_doorway(shell: CSGCombiner3D, socket: RoomDoorway, tuning: FloorGenTuning) -> void:
	var along: Vector3 = _socket_along(socket, tuning.grid_unit)
	var hole := _box(shell, "Hole_%s" % socket.name, socket.position + Vector3.UP * (socket.height / 2.0 - 0.05),
		_along_size(along, socket.width, socket.height + 0.1, tuning.wall_thickness + 0.2), &"wall")
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION


## A frame around a doorway (trim): two posts and a beam, standing a little out of the wall.
func _add_frame(shell: CSGCombiner3D, socket: RoomDoorway, tuning: FloorGenTuning) -> void:
	var along: Vector3 = _socket_along(socket, tuning.grid_unit)
	var depth: float = tuning.wall_thickness + FRAME
	for side: float in [-1.0, 1.0]:
		var post_middle: Vector3 = socket.position + along * side * (socket.width / 2.0 + FRAME / 2.0) \
			+ Vector3.UP * socket.height / 2.0
		_box(shell, "Frame_%s_%d" % [socket.name, int(side)], post_middle, _along_size(along, FRAME, socket.height, depth), &"trim")
	var beam_middle: Vector3 = socket.position + Vector3.UP * (socket.height + FRAME / 2.0)
	_box(shell, "Frame_%s_top" % socket.name, beam_middle, _along_size(along, socket.width + FRAME * 2.0, FRAME, depth), &"trim")


func _add_lights(parent: Node3D, tuning: FloorGenTuning) -> void:
	var unit: float = tuning.grid_unit
	var blocks := Vector2i(ceili(float(size_units.x) / 2.0), ceili(float(size_units.y) / 2.0))
	var length := Vector2(float(size_units.x) * unit, float(size_units.y) * unit)
	for x: int in blocks.x:
		for z: int in blocks.y:
			var light := OmniLight3D.new()
			light.name = "Light%d_%d" % [x, z]
			light.position = Vector3((float(x) + 0.5) * length.x / float(blocks.x), tuning.ceiling_height - 0.3,
				(float(z) + 0.5) * length.y / float(blocks.y))
			light.omni_range = unit * 2.6
			light.light_energy = 0.9
			light.add_to_group(TileStandards.LIGHT_GROUP)
			parent.add_child(light)


## Damage overlays the designer left empty get placeholder boxes (debris), more for worse damage.
## A heavy overlay also gets a red emergency light. The same tile always gets the same boxes.
func _fill_overlays(tuning: FloorGenTuning) -> void:
	var unit: float = tuning.grid_unit
	var length := Vector2(float(size_units.x) * unit, float(size_units.y) * unit)
	var cells: int = size_units.x * size_units.y
	for level_index: int in TileStandards.DAMAGE_LEVELS.size():
		var level: StringName = TileStandards.DAMAGE_LEVELS[level_index]
		var overlay: Node3D = TileStandards.overlay_of(self, level)
		if overlay == null:
			continue
		var old: Node = overlay.get_node_or_null(PLACEHOLDER_NAME)
		if old != null:
			overlay.remove_child(old)
			old.queue_free()
		if overlay.get_child_count() > 0:
			continue
		var placeholder := Node3D.new()
		placeholder.name = PLACEHOLDER_NAME
		overlay.add_child(placeholder)
		var rng: RandomNumberGenerator = SeededRng.make(size_units.x * 100 + size_units.y, &"blockout_overlay", level_index)
		var count: int = maxi(2, ceili(float(cells) * float(level_index) / 3.0))
		for index: int in count:
			var size := Vector3(rng.randf_range(0.3, 0.5 + 0.4 * float(level_index)), rng.randf_range(0.15, 0.3 * float(level_index) + 0.2),
				rng.randf_range(0.3, 0.5 + 0.4 * float(level_index)))
			var where := Vector3(rng.randf_range(0.6, length.x - 0.6), size.y / 2.0, rng.randf_range(0.6, length.y - 0.6))
			var mesh := _mesh_box(placeholder, "Debris%d" % index, where, size, OVERLAY_COLORS[level])
			mesh.rotation.y = rng.randf_range(0.0, TAU)
		if level == &"heavy":
			var emergency := OmniLight3D.new()
			emergency.name = "EmergencyLight"
			emergency.light_color = Color(1.0, 0.15, 0.1)
			emergency.light_energy = 1.2
			emergency.omni_range = maxf(length.x, length.y) * 0.6
			emergency.position = Vector3(length.x / 2.0, tuning.ceiling_height - 0.5, length.y / 2.0)
			placeholder.add_child(emergency)
		if level == &"destroyed":
			# A fallen ceiling panel.
			var panel := _mesh_box(placeholder, "FallenPanel", Vector3(length.x / 2.0, 0.6, length.y / 2.0),
				Vector3(minf(length.x, 2.8), 0.12, minf(length.y, 1.4)), OVERLAY_COLORS[level].darkened(0.3))
			panel.rotation.z = 0.35


func _csg_root(root_name: String) -> CSGCombiner3D:
	var root := CSGCombiner3D.new()
	root.name = root_name
	root.use_collision = true
	root.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	root.collision_mask = 0
	return root


func _box(parent: Node, box_name: String, center: Vector3, size: Vector3, slot: StringName) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = box_name
	box.position = center
	box.size = size
	box.material = slot_material(slot)
	box.set_meta(TileStandards.MATERIAL_SLOT_META, slot)
	parent.add_child(box)
	return box


## A plain coloured box with no collision (overlay placeholders).
func _mesh_box(parent: Node, box_name: String, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	mesh.position = center
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	parent.add_child(mesh)
	return mesh
