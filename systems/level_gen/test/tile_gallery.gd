extends Node3D
## Tile gallery (floor generation step 2; run alone with F6). Two things to look at:
## - A small JOINED SAMPLE near where you spawn: the elevator, the welcome center, both main hallways
##   (3-long and 5-long walled pieces), two side hallways and an office, placed by hand the way the
##   generator will join them (step 3).
## - Every 3 m tile ON ITS OWN, in rows behind the elevator (south), with gaps between them.
## Sockets are arrows pointing out (green = doorway, cyan = open edge). Markers are coloured balls with
## their kind written above. You start inside the elevator (the yellow square is the cargo lift's floor;
## its gate faces the welcome center). A cart waits in the welcome center: look at it and press E.
##
## Keys: 1 pristine, 2 light, 3 heavy, 4 destroyed (damage overlays and lights on every tile: light =
## some lights blink, heavy = dim and mostly dark with flickers, destroyed = dark, rare faint flickers, red
## emergency light that sometimes flickers).
## C ceilings on/off, M arrows and markers on/off, O overview camera on/off (use with C),
## T jump to the next tile, Y back to the elevator, P test palette on/off (material slots).

## The joined sample: [room id, cell x, cell z, quarter turns]. Cells are 3 m grid units.
const SAMPLE: Array = [
	[&"room_tile_elevator", 0, 0, 0],
	[&"room_tile_welcome_center", -3, -6, 0],
	# West main hallway: a 3-long piece, a 5-long piece, an end.
	[&"room_tile_main_straight", -6, -4, 1],
	[&"room_tile_main_straight_long", -11, -4, 1],
	[&"room_tile_main_end", -12, -4, 1],
	# A side hallway from the 3-long piece's doorway, ending at an office.
	[&"room_tile_hall_straight", -5, -7, 0],
	[&"room_tile_hall_end", -5, -8, 0],
	[&"room_tile_office", -6, -12, 0],
	# A long side hallway from the 5-long piece's second doorway.
	[&"room_tile_hall_straight_long", -8, -9, 0],
	[&"room_tile_hall_end", -8, -10, 0],
	# East main hallway: a 3-long piece, a corner, another 3-long piece, an end.
	[&"room_tile_main_straight", 5, -4, 1],
	[&"room_tile_main_corner", 8, -4, 3],
	[&"room_tile_main_straight", 8, -2, 0],
	[&"room_tile_main_end", 8, 1, 2],
]
## Where the rows of single tiles start (grid units) and how wide a row may get.
const ROWS_START: Vector2i = Vector2i(0, 12)
const ROW_WIDTH: int = 40
const GAP: int = 2
const ROLE_ORDER: Array[StringName] = [&"template", &"main_hall", &"secondary_hall", &"room"]
const DOOR_COLOR: Color = Color(0.3, 0.9, 0.35)
const OPEN_COLOR: Color = Color(0.3, 0.85, 0.95)
const LIFT_GATE_COLOR: Color = Color(0.95, 0.75, 0.2)
const TEST_PALETTE_COLORS: Dictionary[String, Color] = {
	"wall": Color(0.85, 0.82, 0.7), "floor": Color(0.25, 0.3, 0.35), "trim": Color(0.95, 0.75, 0.1), "accent": Color(0.2, 0.45, 0.6)}

var _unit: float = 3.0
var _tiles: Array[Node3D] = []
var _tile_names: PackedStringArray = []
var _tiles_root: Node3D
var _debug_root: Node3D
var _overview: Camera3D
var _status: Label
var _prompt: Label
var _start_spot: Transform3D
var _cart_spot: Transform3D
var _damage: StringName = &"pristine"
var _ceilings_on: bool = true
var _palette_on: bool = false
var _next_tile: int = 0
var _flickers: Array[TileLightFlicker] = []


func _ready() -> void:
	_unit = Config.floor_gen.grid_unit
	_build_environment()
	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)
	_debug_root = Node3D.new()
	_debug_root.name = "Debug"
	add_child(_debug_root)
	for entry: Array in SAMPLE:
		var x: int = entry[1]
		var z: int = entry[2]
		var turns: int = entry[3]
		_place(StringName(str(entry[0])), Vector2i(x, z), turns, false)
	_place_rows()
	for tile: Node3D in _tiles:
		_draw_sockets(tile)
		_draw_markers(tile)
	_find_start()

	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	var spot := Marker3D.new()
	spot.name = "StartSpot"
	spot.transform = _start_spot
	add_child(spot)
	spawner.spawn_points = [spot] as Array[Node3D]
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.name = "Overview"
	_overview.position = Vector3(30, 90, 30)
	_overview.rotation_degrees = Vector3(-75, 0, 0)
	_overview.far = 600.0
	add_child(_overview)
	_build_ui()
	_start.call_deferred()


func _start() -> void:
	if multiplayer.is_server():
		Props.spawn_prop(&"prop_cart_standard", _cart_spot)


func _process(_delta: float) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if body == null and not _overview.current:
		_overview.make_current()
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var where: String = ""
	if body != null:
		where = _tile_at(body.global_position)
	_status.text = "damage: %s | ceilings %s | palette %s | in: %s" % [_damage, "on" if _ceilings_on else "off",
		"test" if _palette_on else "grey", where if not where.is_empty() else "outside"]


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_set_damage(&"pristine")
		KEY_2:
			_set_damage(&"light")
		KEY_3:
			_set_damage(&"heavy")
		KEY_4:
			_set_damage(&"destroyed")
		KEY_C:
			_ceilings_on = not _ceilings_on
			for node: Node in get_tree().get_nodes_in_group(TileStandards.CEILING_GROUP):
				(node as Node3D).visible = _ceilings_on
		KEY_M:
			_debug_root.visible = not _debug_root.visible
		KEY_O:
			_toggle_overview()
		KEY_T:
			_jump_to_tile(_next_tile)
			_next_tile = (_next_tile + 1) % _tiles.size()
		KEY_Y:
			_teleport(_start_spot)
		KEY_P:
			_palette_on = not _palette_on
			_apply_palette()
		_:
			return
	get_viewport().set_input_as_handled()


# --- Laying out tiles --------------------------------------------------------------------------------

func _place(room_id: StringName, cell: Vector2i, turns: int, single: bool) -> void:
	var room := ContentRegistry.get_content(room_id) as RoomData
	if room == null or room.scene == null:
		push_error("tile_gallery: no tile called '%s'." % room_id)
		return
	var tile := room.scene.instantiate() as Node3D
	tile.name = "%s_%d" % [String(room_id).trim_prefix("room_tile_"), _tiles.size()]
	var placement := RoomPlacement.make(room_id, Vector3i(cell.x, 0, cell.y), turns)
	tile.transform = RoomShape.of(room, _unit).placement_transform(placement, _unit)
	_tiles_root.add_child(tile)
	_tiles.append(tile)
	# Damage lighting: flicker, dim, dead lights and the red emergency light (Config.floor_gen).
	var flicker := TileLightFlicker.new()
	flicker.name = "LightFlicker"
	tile.add_child(flicker)
	flicker.setup(tile, _damage)
	_flickers.append(flicker)
	_tile_names.append(String(room_id))
	if single:
		var size: Vector2i = RoomShape.of(room, _unit).rotated_size(turns)
		var label := _label("%s\n%dx%d %s %s" % [room_id, room.size_cells.x, room.size_cells.z, room.tile_role,
			room.size_category], Color.WHITE, 64)
		label.position = Vector3((float(cell.x) + float(size.x) / 2.0) * _unit, Config.floor_gen.ceiling_height + 1.5,
			(float(cell.y) + float(size.y) / 2.0) * _unit)
		_debug_root.add_child(label)


## Every 3 m tile once, unturned, in rows: templates, main hallways, secondary hallways, then rooms.
func _place_rows() -> void:
	var rooms: Array[RoomData] = []
	for content: ContentData in ContentRegistry.get_all(&"room", true):
		var room := content as RoomData
		if room != null and room.grid == RoomData.GRID_TILE:
			rooms.append(room)
	rooms.sort_custom(func(a: RoomData, b: RoomData) -> bool:
		var role_a: int = ROLE_ORDER.find(a.tile_role)
		var role_b: int = ROLE_ORDER.find(b.tile_role)
		if role_a != role_b:
			return role_a < role_b
		return a.size_cells.x * a.size_cells.z < b.size_cells.x * b.size_cells.z)
	var cursor: Vector2i = ROWS_START
	var row_depth: int = 0
	for room: RoomData in rooms:
		if cursor.x > ROWS_START.x and cursor.x + room.size_cells.x > ROWS_START.x + ROW_WIDTH:
			cursor = Vector2i(ROWS_START.x, cursor.y + row_depth + GAP + 1)
			row_depth = 0
		_place(room.id, cursor, 0, true)
		cursor.x += room.size_cells.x + GAP
		row_depth = maxi(row_depth, room.size_cells.z)


## The elevator's lift marker (where you start) and the welcome center's cart marker.
func _find_start() -> void:
	_start_spot = Transform3D(Basis.IDENTITY, Vector3(4.5, 0.1, 4.5))
	_cart_spot = Transform3D(Basis.IDENTITY, Vector3(9, 0.2, -6))
	for tile: Node3D in [_tiles[0], _tiles[1]]:
		for node: Node in RoomShape.all_children(tile):
			var marker := node as RoomMarker
			if marker == null:
				continue
			if marker.kind == &"lift":
				_start_spot = Transform3D(marker.global_basis, marker.global_position + Vector3.UP * 0.1)
				_draw_lift_floor(marker)
			elif marker.kind == &"cart":
				_cart_spot = Transform3D(Basis.IDENTITY, marker.global_position + Vector3.UP * 0.2)


func _tile_at(point: Vector3) -> String:
	for index: int in _tiles.size():
		var room := ContentRegistry.get_content(StringName(_tile_names[index])) as RoomData
		var local: Vector3 = _tiles[index].global_transform.affine_inverse() * point
		if local.x >= 0.0 and local.z >= 0.0 and local.x <= float(room.size_cells.x) * _unit \
				and local.z <= float(room.size_cells.z) * _unit and local.y > -1.0 and local.y < 4.0:
			return _tile_names[index]
	return ""


# --- Keys --------------------------------------------------------------------------------------------

func _set_damage(level: StringName) -> void:
	_damage = level
	for index: int in _tiles.size():
		TileStandards.show_damage(_tiles[index], level)
		_flickers[index].setup(_tiles[index], level)


func _toggle_overview() -> void:
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if _overview.current and body != null:
		body.get_camera().make_current()
	else:
		_overview.make_current()


func _jump_to_tile(index: int) -> void:
	var tile: Node3D = _tiles[index]
	var room := ContentRegistry.get_content(StringName(_tile_names[index])) as RoomData
	var middle := Vector3(float(room.size_cells.x) * _unit / 2.0, 0.2, float(room.size_cells.z) * _unit / 2.0)
	_teleport(Transform3D(tile.global_basis, tile.global_transform * middle))
	print("[tile_gallery] %s" % _tile_names[index])


func _teleport(xform: Transform3D) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if body != null and multiplayer.is_server():
		body.teleport(xform)


func _apply_palette() -> void:
	var palette: Dictionary = {}
	for slot: StringName in TileStandards.MATERIAL_SLOTS:
		if not TEST_PALETTE_COLORS.has(String(slot)):
			continue
		if _palette_on:
			var material := StandardMaterial3D.new()
			material.albedo_color = TEST_PALETTE_COLORS[String(slot)]
			palette[String(slot)] = material
		else:
			palette[String(slot)] = BlockoutTile.slot_material(slot)
	for tile: Node3D in _tiles:
		TileStandards.apply_palette(tile, palette)


# --- Drawing sockets and markers ---------------------------------------------------------------------

func _draw_sockets(tile: Node3D) -> void:
	var blockout := tile as BlockoutTile
	if blockout == null:
		return
	var length := Vector2(float(blockout.size_units.x) * _unit, float(blockout.size_units.y) * _unit)
	for node: Node in tile.get_children():
		var socket := node as RoomDoorway
		if socket == null:
			continue
		var outward := Vector3.RIGHT
		if absf(socket.position.z) < 0.1:
			outward = Vector3.FORWARD
		elif absf(socket.position.z - length.y) < 0.1:
			outward = Vector3.BACK
		elif absf(socket.position.x) < 0.1:
			outward = Vector3.LEFT
		var direction: Vector3 = (tile.global_basis * outward).normalized()
		var color: Color = OPEN_COLOR if socket.open_edge else DOOR_COLOR
		var arrow := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.3
		cone.height = 0.7
		cone.material = _flat_material(color)
		arrow.mesh = cone
		arrow.basis = Basis(Quaternion(Vector3.UP, direction))
		arrow.position = socket.global_position + Vector3.UP * 0.4 - direction * 0.6
		_debug_root.add_child(arrow)


func _draw_markers(tile: Node3D) -> void:
	for node: Node in RoomShape.all_children(tile):
		var marker := node as RoomMarker
		if marker == null:
			continue
		var color := Color.from_hsv(float(absi(hash(String(marker.kind))) % 360) / 360.0, 0.7, 1.0)
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		sphere.height = 0.36
		sphere.material = _flat_material(color)
		ball.mesh = sphere
		ball.position = marker.global_position + Vector3.UP * 0.18
		_debug_root.add_child(ball)
		var label := _label(String(marker.kind), color, 28)
		label.position = marker.global_position + Vector3.UP * 0.6
		_debug_root.add_child(label)


## The cargo lift's floor (5.4 x 5.4 m) as a yellow square, and an arrow from it out of its gate.
func _draw_lift_floor(marker: RoomMarker) -> void:
	var square := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(5.4, 0.02, 5.4)
	plate.material = _flat_material(LIFT_GATE_COLOR)
	square.mesh = plate
	square.transform = Transform3D(marker.global_basis, marker.global_position + Vector3.UP * 0.01)
	_debug_root.add_child(square)
	var gate: Vector3 = -marker.global_basis.z
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.4
	cone.height = 1.0
	cone.material = _flat_material(LIFT_GATE_COLOR)
	arrow.mesh = cone
	arrow.basis = Basis(Quaternion(Vector3.UP, gate))
	arrow.position = marker.global_position + gate * 3.2 + Vector3.UP * 0.5
	_debug_root.add_child(arrow)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _label(text: String, color: Color, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = font_size
	label.pixel_size = 0.006
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return label


# --- World and UI ------------------------------------------------------------------------------------

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.22, 0.24, 0.28)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.45, 0.46, 0.5)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.6
	add_child(sun)
	# Ground under everything, 1 cm below the tile floors, so you can walk out of a doorway.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	ground.collision_mask = 0
	ground.position = Vector3(60, -0.51, 55)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(220, 1, 230)
	shape.shape = box
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.32, 0.3)
	box_mesh.material = material
	mesh.mesh = box_mesh
	ground.add_child(mesh)
	add_child(ground)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var help := Label.new()
	help.text = "Tile gallery. 1-4 damage (pristine, light, heavy, destroyed)   C ceilings   M arrows/markers   " \
		+ "O overview camera   T next tile   Y back to the elevator   P test palette\n" \
		+ "Arrows: green = doorway, cyan = open edge (hallway ends). Yellow square = the lift's floor, arrow = its gate."
	column.add_child(help)
	_status = Label.new()
	column.add_child(_status)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var middle := VBoxContainer.new()
	center.add_child(middle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	middle.add_child(_prompt)
