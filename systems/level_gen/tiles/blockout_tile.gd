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
## NEW 2026-10-31 (step 4b): markers rubble keeps clear of, and how far (metres).
const KEEP_CLEAR_MARKERS: Dictionary[StringName, float] = {&"vendor": 1.0, &"printer": 1.6, &"upgrade_machine": 1.6,
	&"charger": 1.0, &"cart": 1.2, &"lift": 3.5, &"lift_part": 0.7, &"prop_spawn": 0.7, &"item_spawn": 0.6, &"keycard": 0.5,
	&"player_spawn": 0.6, &"security_map": 1.2, &"security_monitor": 0.5}


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


## Damage overlays the designer left empty get blockout debris (CHANGED 2026-10-31, step 4b: was coloured
## boxes). The worse the damage, the more there is:
## - solid rubble chunks (WORLD collision, so players, carts and the navigation bake go round them), always
##   hugging the walls, never in front of a doorway, in a hallway's cart lane or on a machine or spawn spot;
## - things you walk over or under (no collision): papers (light), fallen ceiling tiles and hanging cables
##   (heavy), scorch marks and ceiling panels (destroyed);
## - a red emergency light (heavy and destroyed, group "tile_emergency_light").
## The same tile always gets the same debris. The rubble is only solid while its overlay is shown
## (TileStandards.show_damage / keep_damage).
func _fill_overlays(tuning: FloorGenTuning) -> void:
	var unit: float = tuning.grid_unit
	var length := Vector2(float(size_units.x) * unit, float(size_units.y) * unit)
	var cells: int = size_units.x * size_units.y
	var keep_out: Array[Rect2] = _keep_out_zones(length)
	# How far from the walls rubble may reach: narrow tiles (hallways) keep their middle clear for carts.
	var band: float = 0.5 if mini(size_units.x, size_units.y) <= 2 else 1.0
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
		var rubble := _csg_root("Rubble")
		rubble.use_collision = overlay.visible
		placeholder.add_child(rubble)
		var rng: RandomNumberGenerator = SeededRng.make(size_units.x * 100 + size_units.y, &"blockout_overlay", level_index)
		var chunks: int = maxi(1, roundi(float(cells) * [0.0, 0.35, 0.7, 1.1][level_index]))
		var placed: int = 0
		for attempt: int in chunks * 8:
			if placed >= chunks:
				break
			var size := Vector3(rng.randf_range(0.3, 0.45 + 0.15 * float(level_index)), rng.randf_range(0.15, 0.2 + 0.2 * float(level_index)),
				rng.randf_range(0.3, 0.45 + 0.15 * float(level_index)))
			size.x = minf(size.x, band)
			size.z = minf(size.z, band)
			var spot: Vector2 = _spot_by_wall(rng, length, band, size)
			var footprint := Rect2(spot - Vector2(size.x, size.z) / 2.0, Vector2(size.x, size.z))
			if _hits_any(footprint, keep_out):
				continue
			_box(rubble, "Chunk%d" % placed, Vector3(spot.x, size.y / 2.0, spot.y), size, &"rubble")
			placed += 1
		_add_loose_debris(placeholder, level_index, length, rng, tuning)
		if level_index >= 2:
			var emergency := OmniLight3D.new()
			emergency.name = "EmergencyLight"
			emergency.light_color = Color(1.0, 0.15, 0.1)
			emergency.light_energy = 1.2
			emergency.omni_range = maxf(length.x, length.y) * 0.6
			emergency.position = Vector3(length.x / 2.0, tuning.ceiling_height - 0.5, length.y / 2.0)
			emergency.add_to_group(TileStandards.EMERGENCY_LIGHT_GROUP)
			placeholder.add_child(emergency)


## Things with no collision: papers (light and worse), fallen ceiling tiles and hanging cables (heavy and
## worse), scorch marks and a fallen ceiling panel (destroyed).
func _add_loose_debris(parent: Node3D, level_index: int, length: Vector2, rng: RandomNumberGenerator,
		tuning: FloorGenTuning) -> void:
	var cells: int = size_units.x * size_units.y
	for index: int in maxi(1, cells / 3):
		var paper := _mesh_box(parent, "Paper%d" % index, Vector3(rng.randf_range(0.5, length.x - 0.5), 0.005,
			rng.randf_range(0.5, length.y - 0.5)), Vector3(0.3, 0.01, 0.42), Color(0.85, 0.84, 0.78))
		paper.rotation.y = rng.randf_range(0.0, TAU)
	if level_index >= 2:
		for index: int in maxi(1, cells / 4):
			var tile_piece := _mesh_box(parent, "CeilingTile%d" % index, Vector3(rng.randf_range(0.6, length.x - 0.6), 0.03,
				rng.randf_range(0.6, length.y - 0.6)), Vector3(0.6, 0.03, 0.6), Color(0.7, 0.7, 0.68))
			tile_piece.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.0, TAU), rng.randf_range(-0.05, 0.05))
			var cable := _mesh_box(parent, "Cable%d" % index, Vector3(rng.randf_range(0.5, length.x - 0.5),
				tuning.ceiling_height - 0.6, rng.randf_range(0.5, length.y - 0.5)), Vector3(0.04, 1.2, 0.04), Color(0.1, 0.1, 0.1))
			cable.rotation.z = rng.randf_range(-0.4, 0.4)
	if level_index >= 3:
		for index: int in maxi(1, cells / 3):
			var scorch := MeshInstance3D.new()
			scorch.name = "Scorch%d" % index
			var plane := PlaneMesh.new()
			var size: float = rng.randf_range(1.0, 2.2)
			plane.size = Vector2(size, size * rng.randf_range(0.6, 1.0))
			plane.material = slot_material(&"scorch")
			scorch.mesh = plane
			scorch.position = Vector3(rng.randf_range(0.8, length.x - 0.8), 0.006, rng.randf_range(0.8, length.y - 0.8))
			scorch.rotation.y = rng.randf_range(0.0, TAU)
			parent.add_child(scorch)
		var panel := _mesh_box(parent, "FallenPanel", Vector3(length.x / 2.0, tuning.ceiling_height - 0.9, length.y / 2.0),
			Vector3(minf(length.x * 0.5, 2.4), 0.06, minf(length.y * 0.5, 1.2)), Color(0.55, 0.55, 0.55))
		panel.rotation.z = 0.5


## Where rubble may not go (x/z rectangles, metres): in front of every doorway (its width plus 0.6 m each
## side, 1.8 m deep), and around every machine and spawn spot.
func _keep_out_zones(length: Vector2) -> Array[Rect2]:
	var zones: Array[Rect2] = []
	var unit: float = length.x / float(maxi(size_units.x, 1))
	for socket: RoomDoorway in _sockets():
		var place: Vector2i = _socket_place(socket, unit)
		var p := Vector2(socket.position.x, socket.position.z)
		var reach: float = socket.width / 2.0 + 0.6
		match place.x:
			0:
				zones.append(Rect2(p.x - reach, 0.0, reach * 2.0, 1.8))
			1:
				zones.append(Rect2(p.x - reach, length.y - 1.8, reach * 2.0, 1.8))
			2:
				zones.append(Rect2(0.0, p.y - reach, 1.8, reach * 2.0))
			3:
				zones.append(Rect2(length.x - 1.8, p.y - reach, 1.8, reach * 2.0))
	for node: Node in RoomShape.all_children(self):
		var marker := node as RoomMarker
		if marker == null or not KEEP_CLEAR_MARKERS.has(marker.kind):
			continue
		var at: Vector3 = (marker.get_parent() as Node3D).transform * marker.position if marker.get_parent() != self \
			else marker.position
		var radius: float = KEEP_CLEAR_MARKERS[marker.kind]
		zones.append(Rect2(Vector2(at.x, at.z) - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
	return zones


## A random spot within `band` metres of one of the walls (not counting where the box would poke out).
func _spot_by_wall(rng: RandomNumberGenerator, length: Vector2, band: float, size: Vector3) -> Vector2:
	var inner: float = 0.15
	var edge: int = rng.randi_range(0, 3)
	# How far the box reaches out from that wall: its z size on the north and south walls, x on the others.
	var across: float = size.z if edge <= 1 else size.x
	var depth: float = inner + across / 2.0 + rng.randf() * maxf(band - across, 0.0)
	match edge:
		0:
			return Vector2(rng.randf_range(0.5, length.x - 0.5), depth)
		1:
			return Vector2(rng.randf_range(0.5, length.x - 0.5), length.y - depth)
		2:
			return Vector2(depth, rng.randf_range(0.5, length.y - 0.5))
	return Vector2(length.x - depth, rng.randf_range(0.5, length.y - 0.5))


func _hits_any(rect: Rect2, zones: Array[Rect2]) -> bool:
	for zone: Rect2 in zones:
		if rect.intersects(zone):
			return true
	return false


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
