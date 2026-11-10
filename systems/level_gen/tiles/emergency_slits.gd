class_name EmergencySlits
extends RefCounted
## NEW 2026-10-31 (Zachary): the red emergency lights of a 3 m tile are small glowing slits low on its walls,
## each with one small red light. A BlockoutTile builds them (node "EmergencySlits"); the light is in group
## "tile_emergency_light" and starts off, so an unlit slit is a dark groove. TileLightFlicker switches them on
## in heavily damaged rooms (steady) and destroyed ones (a share dead, the rest flickering). Looks only: no
## collision, nothing sent over the network. Numbers: Config.floor_gen, "Emergency slits".
##
## Where they go depends on the tile's `emergency_slits` style:
## - "room": the inside corners get L-shaped slits (2 opposite corners in small rooms, all 4 in big ones),
##   skipping corners next to a door, an open edge, furniture or a marker; walls longer than
##   emergency_long_wall also get straight slits. A room with none gets one straight slit somewhere.
## - "hall": worked out from the open sides. A straight piece lights every emergency_hall_lit_every units
##   (0, 2, 4...) with a pair of slits facing each other; a corner gets an L in its outside corner; an end
##   gets an L in both corners of its end wall (an arm that would run into a doorway is left off); T and
##   crossing pieces stay dark.
## - "none": no slits (the dark hallway filler).
## Doorways that were sealed (BlockoutTile.seal_socket) count as plain wall.
##
## A planned slit is a Dictionary: {"edge": int, "at": float} for a straight slit (metres along the edge
## from its start), or {"corner": Vector2i(north/south edge, west/east edge), "arms": Vector2i(1, 1)} for an
## L (an arm set to 0 is left off). Edges: 0 = north (z = 0), 1 = south, 2 = west (x = 0), 3 = east.
## By hand: a RoomMarker of kind "emergency_slit" on a wall face (+Z out of the wall, +X along it) is a straight
## slit; with params {"corner": true} it is an L in an inside corner, its arms along +X and +Z ({"marker":
## Transform3D, "l": bool}). The tile's `emergency_keep_out` areas (e.g. a room inside the room) get no
## slits from the rules above.

const NODE_NAME: String = "EmergencySlits"
## A RoomMarker kind: a slit placed by hand.
const MARKER_KIND: StringName = &"emergency_slit"
const STYLE_ROOM: StringName = &"room"
const STYLE_HALL: StringName = &"hall"
const STYLE_NONE: StringName = &"none"
const DEFAULT_COLOR: Color = Color(1.0, 0.15, 0.1)
const GROOVE_COLOR: Color = Color(0.04, 0.04, 0.04)
## How far the groove stands out of the wall face, so it never flickers against the wall (metres).
const PROUD: float = 0.002
## Furniture taller than this off the floor doesn't block a slit (metres).
const LOW_FURNITURE: float = 0.5
## Straight slits keep this far from the ends of their wall (metres), besides the door and corner rules.
const END_MARGIN: float = 0.5
## Search step when a straight slit slides out of the way (metres).
const SLIDE_STEP: float = 0.25


## Builds (or rebuilds) the tile's slits. Returns the node holding them.
static func build(tile: BlockoutTile, tuning: FloorGenTuning, color: Color = DEFAULT_COLOR) -> Node3D:
	var old: Node = tile.get_node_or_null(NODE_NAME)
	if old != null:
		tile.remove_child(old)
		old.queue_free()
	var holder := Node3D.new()
	holder.name = NODE_NAME
	tile.add_child(holder)
	var walls := _Walls.new(tile, tuning)
	var groove := StandardMaterial3D.new()
	groove.albedo_color = GROOVE_COLOR
	groove.roughness = 1.0
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = tuning.emergency_slit_glow
	var slits: Array[Dictionary] = plan(tile, tuning)
	for index: int in slits.size():
		_build_slit(holder, "Slit%d" % index, slits[index], walls, tuning, color, groove, glow)
	return holder


## Where the tile's slits go (see the class notes), without building anything. For tests too.
static func plan(tile: BlockoutTile, tuning: FloorGenTuning) -> Array[Dictionary]:
	var walls := _Walls.new(tile, tuning)
	var slits: Array[Dictionary] = []
	# Slits the designer placed by hand come first (e.g. inside the welcome center's security room).
	for marker: RoomMarker in walls.slit_markers:
		slits.append({"marker": walls.in_tile(marker), "l": bool(marker.params.get("corner", false))})
	match tile.emergency_slits:
		STYLE_ROOM:
			slits.append_array(_plan_room(walls, tuning))
		STYLE_HALL:
			slits.append_array(_plan_hall(walls, tuning))
	if slits.size() > tuning.emergency_max_lights_per_tile:
		slits.resize(maxi(tuning.emergency_max_lights_per_tile, 0))
	return slits


## Where a planned slit is on the floor plan (x, z in metres, tile space): the middle of a straight slit, or
## the inside corner of an L.
static func slit_point(tile: BlockoutTile, tuning: FloorGenTuning, slit: Dictionary) -> Vector2:
	return _Walls.new(tile, tuning).point_of(slit)


# --- Rooms ----------------------------------------------------------------------------------------------

static func _plan_room(walls: _Walls, tuning: FloorGenTuning) -> Array[Dictionary]:
	var corners: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(1, 2)]
	var free: Array[Vector2i] = []
	for corner: Vector2i in corners:
		if walls.corner_free(corner):
			free.append(corner)
	var chosen: Array[Vector2i] = []
	if walls.size.x <= tuning.emergency_small_room + 0.01 and walls.size.y <= tuning.emergency_small_room + 0.01:
		# Small room: one pair of opposite corners (north-west + south-east, or north-east + south-west),
		# whichever has more free corners.
		var pairs: Array[Array] = [[corners[0], corners[2]], [corners[1], corners[3]]]
		var best: Array = pairs[0]
		var best_count: int = -1
		for pair: Array in pairs:
			var count: int = 0
			for corner: Vector2i in pair:
				if free.has(corner):
					count += 1
			if count > best_count:
				best = pair
				best_count = count
		for corner: Vector2i in best:
			if free.has(corner):
				chosen.append(corner)
	else:
		chosen = free
	var slits: Array[Dictionary] = []
	for corner: Vector2i in chosen:
		slits.append({"corner": corner, "arms": Vector2i(1, 1)})
	# Long walls: straight slits as well, evenly spaced, sliding out of the way when they must.
	for edge: int in 4:
		var length: float = walls.edge_length(edge)
		if length <= tuning.emergency_long_wall:
			continue
		var count: int = roundi(length / tuning.emergency_room_spacing) - 1
		for index: int in count:
			var target: float = length * float(index + 1) / float(count + 1)
			var at: float = _slide(walls, edge, target, tuning.emergency_slit_slide, slits, tuning)
			if not is_nan(at):
				slits.append({"edge": edge, "at": at})
	if slits.is_empty():
		# Nothing fitted: one straight slit on the first wall with room for it.
		for edge: int in 4:
			var length: float = walls.edge_length(edge)
			var at: float = _slide(walls, edge, length / 2.0, length / 2.0, slits, tuning)
			if not is_nan(at):
				slits.append({"edge": edge, "at": at})
				break
	return slits


## The nearest spot to `target` (within `reach` metres along the wall) where a straight slit fits, or NAN.
static func _slide(walls: _Walls, edge: int, target: float, reach: float, others: Array[Dictionary],
		tuning: FloorGenTuning) -> float:
	var steps: int = floori(reach / SLIDE_STEP)
	for step: int in steps + 1:
		for side: float in [1.0, -1.0]:
			if step == 0 and side < 0.0:
				continue
			var at: float = target + side * float(step) * SLIDE_STEP
			if walls.straight_free(edge, at, true) and walls.far_from(edge, at, others, tuning.emergency_slit_min_gap):
				return at
	return NAN


# --- Hallways -------------------------------------------------------------------------------------------

static func _plan_hall(walls: _Walls, tuning: FloorGenTuning) -> Array[Dictionary]:
	var slits: Array[Dictionary] = []
	var open: Array[int] = walls.open_edges()
	if open.size() == 2 and open.has(0) == open.has(1):
		# Straight: lit units along the length, a slit on each side wall.
		var sides: Array[int] = [0, 1]
		if open.has(0):
			sides = [2, 3]
		var units: int = walls.tile.size_units.y if open.has(0) else walls.tile.size_units.x
		var every: int = maxi(tuning.emergency_hall_lit_every, 1)
		for unit_index: int in units:
			if unit_index % every != 0:
				continue
			for edge: int in sides:
				var at: float = (float(unit_index) + 0.5) * walls.unit
				if walls.straight_free(edge, at, false):
					slits.append({"edge": edge, "at": at})
	elif open.size() == 2:
		# Corner: an L where the two closed walls meet (the outside of the turn).
		var closed_ns: int = 1 if open.has(0) else 0
		var closed_we: int = 3 if open.has(2) else 2
		_add_hall_corner(walls, Vector2i(closed_ns, closed_we), slits)
	elif open.size() == 1:
		# End: an L in both corners of the end wall (the one facing the open side).
		var end: int = [1, 0, 3, 2][open[0]]
		if end <= 1:
			_add_hall_corner(walls, Vector2i(end, 2), slits)
			_add_hall_corner(walls, Vector2i(end, 3), slits)
		else:
			_add_hall_corner(walls, Vector2i(0, end), slits)
			_add_hall_corner(walls, Vector2i(1, end), slits)
	return slits


static func _add_hall_corner(walls: _Walls, corner: Vector2i, slits: Array[Dictionary]) -> void:
	var arms := Vector2i(1 if walls.arm_free(corner, 0) else 0, 1 if walls.arm_free(corner, 1) else 0)
	if arms != Vector2i.ZERO:
		slits.append({"corner": corner, "arms": arms})


# --- Building --------------------------------------------------------------------------------------------

static func _build_slit(holder: Node3D, slit_name: String, slit: Dictionary, walls: _Walls, tuning: FloorGenTuning,
		color: Color, groove: Material, glow: Material) -> void:
	var node := Node3D.new()
	node.name = slit_name
	holder.add_child(node)
	var pieces: Array[Array] = walls.pieces_of(slit)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = walls.light_spot(slit)
	light.light_color = color
	light.light_energy = tuning.emergency_slit_light_energy
	light.omni_range = tuning.emergency_slit_light_range
	light.shadow_enabled = false
	light.visible = false
	light.add_to_group(TileStandards.EMERGENCY_LIGHT_GROUP)
	node.add_child(light)
	for piece_index: int in pieces.size():
		var piece: Array = pieces[piece_index]
		var centre: Vector3 = piece[0]
		var size: Vector3 = piece[1]
		var normal: Vector3 = piece[2]
		# The groove is as deep as the recess; the glow is a thin plate on its front.
		var groove_size: Vector3 = size + normal.abs() * (tuning.emergency_slit_recess - size.dot(normal.abs()))
		var groove_mesh := _mesh("Groove%d" % piece_index, groove_size, groove)
		groove_mesh.position = centre + normal * (PROUD - tuning.emergency_slit_recess / 2.0)
		groove_mesh.visible = tuning.emergency_slit_groove
		node.add_child(groove_mesh)
		# The glow hangs under the light, so it goes dark whenever the light is off.
		var glow_mesh := _mesh("Glow%d" % piece_index, size, glow)
		glow_mesh.position = centre + normal * (PROUD + size.dot(normal.abs()) / 2.0) - light.position
		light.add_child(glow_mesh)


static func _mesh(mesh_name: String, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = mesh_name
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## A tile's walls as seen by the slit rules: lengths, open spans, door frames, furniture and markers.
class _Walls:
	extends RefCounted

	var tile: BlockoutTile
	var tuning: FloorGenTuning
	var unit: float
	var size: Vector2
	var half_wall: float
	## Per edge: spans (Vector2 from, to along the edge) where there is no wall, and door frames.
	var open_spans: Array[Array] = [[], [], [], []]
	var door_spans: Array[Array] = [[], [], [], []]
	## Low furniture footprints and marker spots (x, z rectangles in tile space).
	var blockers: Array[Rect2] = []
	## Hand-placed "emergency_slit" markers, and areas the rules keep out of (tile.emergency_keep_out).
	var slit_markers: Array[RoomMarker] = []
	var keep_out: Array[Rect2] = []

	func _init(for_tile: BlockoutTile, numbers: FloorGenTuning) -> void:
		tile = for_tile
		tuning = numbers
		unit = numbers.grid_unit
		keep_out = tile.emergency_keep_out
		size = Vector2(tile.size_units) * unit
		half_wall = numbers.wall_thickness / 2.0
		for socket: RoomDoorway in tile.get_sockets():
			var place: Vector2i = tile.socket_place(socket)
			if place.x < 0:
				continue
			if socket.open_edge:
				open_spans[place.x].append(Vector2(float(place.y) * unit, float(place.y + 1) * unit))
			elif not tile.is_socket_sealed(str(socket.name)):
				var middle: float = socket.position.x if place.x <= 1 else socket.position.z
				var reach: float = socket.width / 2.0 + BlockoutTile.FRAME
				door_spans[place.x].append(Vector2(middle - reach, middle + reach))
		_find_blockers()

	func edge_length(edge: int) -> float:
		return size.x if edge <= 1 else size.y

	func open_edges() -> Array[int]:
		var found: Array[int] = []
		for edge: int in 4:
			if not open_spans[edge].is_empty():
				found.append(edge)
		return found

	## Where the wall face is across the edge (z for north/south, x for west/east), and which way is in.
	func face(edge: int) -> float:
		match edge:
			0:
				return half_wall
			1:
				return size.y - half_wall
			2:
				return half_wall
		return size.x - half_wall

	func normal(edge: int) -> Vector3:
		return [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT][edge]

	## How far a span is from the nearest span in a list (0 = touching or overlapping), or INF.
	func gap_to(spans: Array, from: float, to: float) -> float:
		var best: float = INF
		for span: Vector2 in spans:
			best = minf(best, maxf(maxf(span.x - to, from - span.y), 0.0))
		return best

	## Is the inside corner there (both walls), with no door frame near it and nothing standing in it?
	func corner_free(corner: Vector2i) -> bool:
		for which: int in 2:
			var edge: int = corner[which]
			var at: float = corner_at(corner, which)
			if gap_to(open_spans[edge], at, at) <= 0.01:
				return false
			if gap_to(door_spans[edge], at, at) < tuning.emergency_door_corner_clearance:
				return false
		if kept_out(point_of({"corner": corner})):
			return false
		var point: Vector2 = point_of({"corner": corner})
		var reach: float = tuning.emergency_furniture_clearance
		var inward := Vector2(1.0 if corner.y == 2 else -1.0, 1.0 if corner.x == 0 else -1.0)
		var zone := Rect2(point, inward * reach).abs()
		return not _blocked(zone)

	## Hallway corners: can the L's arm along this wall (0 = the north/south one) go there?
	func arm_free(corner: Vector2i, which: int) -> bool:
		var edge: int = corner[which]
		var at: float = corner_at(corner, which)
		var inward: float = 1.0 if at < edge_length(edge) / 2.0 else -1.0
		var tip: float = at + inward * tuning.emergency_slit_corner_arm
		var from: float = minf(at, tip)
		var to: float = maxf(at, tip)
		return gap_to(open_spans[edge], from, to) > 0.01 and gap_to(door_spans[edge], from, to) > 0.05

	## How far along the given wall of the corner (0 = its north/south wall) the inside corner is.
	func corner_at(corner: Vector2i, which: int) -> float:
		if which == 0:
			return half_wall if corner.y == 2 else size.x - half_wall
		return half_wall if corner.x == 0 else size.y - half_wall

	## Can a straight slit go `at` metres along this edge? (Rooms also keep their furniture clearance.)
	func straight_free(edge: int, at: float, check_furniture: bool) -> bool:
		var half: float = tuning.emergency_slit_size.x / 2.0
		var from: float = at - half
		var to: float = at + half
		if from < half_wall + END_MARGIN or to > edge_length(edge) - half_wall - END_MARGIN:
			return false
		if gap_to(open_spans[edge], from, to) <= 0.01:
			return false
		if gap_to(door_spans[edge], from, to) < tuning.emergency_door_clearance:
			return false
		if kept_out(point_of({"edge": edge, "at": at})):
			return false
		if not check_furniture:
			return true
		var depth: float = tuning.emergency_furniture_clearance
		var zone: Rect2
		match edge:
			0:
				zone = Rect2(from - 0.1, half_wall, to - from + 0.2, depth)
			1:
				zone = Rect2(from - 0.1, size.y - half_wall - depth, to - from + 0.2, depth)
			2:
				zone = Rect2(half_wall, from - 0.1, depth, to - from + 0.2)
			_:
				zone = Rect2(size.x - half_wall - depth, from - 0.1, depth, to - from + 0.2)
		return not _blocked(zone)

	## Is a straight slit at `at` on `edge` at least `gap` metres from every slit in the list?
	func far_from(edge: int, at: float, others: Array[Dictionary], gap: float) -> bool:
		var here: Vector2 = point_of({"edge": edge, "at": at})
		for other: Dictionary in others:
			if here.distance_to(point_of(other)) < gap:
				return false
		return true

	## Inside one of the tile's keep-out areas (emergency_keep_out)?
	func kept_out(point: Vector2) -> bool:
		for area: Rect2 in keep_out:
			if area.grow(0.05).has_point(point):
				return true
		return false

	func point_of(slit: Dictionary) -> Vector2:
		if slit.has("marker"):
			var origin: Vector3 = (slit["marker"] as Transform3D).origin
			return Vector2(origin.x, origin.z)
		if slit.has("corner"):
			var corner: Vector2i = slit["corner"]
			return Vector2(corner_at(corner, 0), corner_at(corner, 1))
		var edge: int = slit["edge"]
		var at: float = slit["at"]
		if edge <= 1:
			return Vector2(at, face(edge))
		return Vector2(face(edge), at)

	## Where the slit's light goes (tile space): up and out from the wall (both walls for an L).
	func light_spot(slit: Dictionary) -> Vector3:
		var point: Vector2 = point_of(slit)
		var out: Vector3 = Vector3.ZERO
		if slit.has("marker"):
			var basis: Basis = (slit["marker"] as Transform3D).basis.orthonormalized()
			out = basis.z + basis.x if slit["l"] else basis.z
		elif slit.has("corner"):
			var corner: Vector2i = slit["corner"]
			out = normal(corner.x) + normal(corner.y)
		else:
			out = normal(slit["edge"])
		return Vector3(point.x, tuning.emergency_slit_light_offset.x, point.y) + out * tuning.emergency_slit_light_offset.y

	## The slit's glowing pieces: [centre on the wall face, size (thin across the wall), normal into the room].
	func pieces_of(slit: Dictionary) -> Array[Array]:
		var pieces: Array[Array] = []
		var height: float = tuning.emergency_slit_size.y
		var y: float = tuning.emergency_slit_height + height / 2.0
		var thin: float = 0.004
		if slit.has("marker"):
			var xform: Transform3D = slit["marker"]
			var along: Vector3 = xform.basis.x.normalized()
			var out: Vector3 = xform.basis.z.normalized()
			var base: Vector3 = Vector3(xform.origin.x, y, xform.origin.z)
			if not slit["l"]:
				pieces.append([base, _axis_size(along, tuning.emergency_slit_size.x, height, thin), out])
			else:
				var arm_length: float = tuning.emergency_slit_corner_arm
				pieces.append([base + along * arm_length / 2.0, _axis_size(along, arm_length, height, thin), out])
				pieces.append([base + out * arm_length / 2.0, _axis_size(out, arm_length, height, thin), along])
			return pieces
		if not slit.has("corner"):
			var edge: int = slit["edge"]
			var point: Vector2 = point_of(slit)
			pieces.append([Vector3(point.x, y, point.y), _along_size(edge, tuning.emergency_slit_size.x, height, thin),
				normal(edge)])
			return pieces
		var corner: Vector2i = slit["corner"]
		var arms: Vector2i = slit.get("arms", Vector2i(1, 1))
		var arm: float = tuning.emergency_slit_corner_arm
		var inner: Vector2 = point_of(slit)
		for which: int in 2:
			if arms[which] == 0:
				continue
			var edge: int = corner[which]
			var at: float = corner_at(corner, which)
			var inward: float = 1.0 if at < edge_length(edge) / 2.0 else -1.0
			var middle: float = at + inward * arm / 2.0
			var centre := Vector3(middle, y, inner.y) if edge <= 1 else Vector3(inner.x, y, middle)
			pieces.append([centre, _along_size(edge, arm, height, thin), normal(edge)])
		return pieces

	func _along_size(edge: int, length: float, height: float, thin: float) -> Vector3:
		return Vector3(length, height, thin) if edge <= 1 else Vector3(thin, height, length)

	## A size for a piece lying along a direction (the tile's x or z): long along it, thin across it.
	func _axis_size(direction: Vector3, length: float, height: float, thin: float) -> Vector3:
		return Vector3(length, height, thin) if absf(direction.x) > 0.5 else Vector3(thin, height, length)

	func _blocked(zone: Rect2) -> bool:
		for blocker: Rect2 in blockers:
			if zone.intersects(blocker, true):
				return true
		return false

	## Low furniture the designer put in the tile (CSG boxes and meshes outside the generated nodes) and
	## every marker.
	func _find_blockers() -> void:
		for child: Node in tile.get_children():
			if child.name in [BlockoutTile.GENERATED_NAME, NODE_NAME, TileStandards.DAMAGE_NODE] or child is RoomDoorway:
				continue
			for node: Node in [child] + RoomShape.all_children(child):
				var marker := node as RoomMarker
				if marker != null:
					if marker.kind == MARKER_KIND:
						slit_markers.append(marker)
						continue
					var at: Vector3 = in_tile(marker).origin
					blockers.append(Rect2(at.x - 0.05, at.z - 0.05, 0.1, 0.1))
					continue
				var box: AABB = _box_of(node)
				if box.size == Vector3.ZERO or box.position.y > LOW_FURNITURE:
					continue
				blockers.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))

	## A furniture piece's box in tile space (zero size = not furniture).
	func _box_of(node: Node) -> AABB:
		var local: AABB
		var csg := node as CSGBox3D
		if csg != null:
			if csg.operation != CSGShape3D.OPERATION_UNION:
				return AABB()
			local = AABB(-csg.size / 2.0, csg.size)
		elif node is MeshInstance3D:
			local = (node as MeshInstance3D).get_aabb()
		else:
			return AABB()
		return in_tile(node as Node3D) * local

	## A node's transform relative to the tile (works before the tile is in the tree).
	func in_tile(node: Node3D) -> Transform3D:
		var xform: Transform3D = Transform3D.IDENTITY
		var at: Node = node
		while at != null and at != tile:
			var spatial := at as Node3D
			if spatial != null:
				xform = spatial.transform * xform
			at = at.get_parent()
		return xform
