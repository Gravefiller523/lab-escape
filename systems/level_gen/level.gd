class_name LevelService
extends Node
## Autoload "Level". Builds the floor in a FloorLayout on this PC (every PC builds the same one from
## the layout the host sends), fills unused doorways with wall plugs, and finds the rooms' markers.
## game_flow calls build() into the game world (and lines the lift room up with the cargo lift).
## Spec: docs/systems/level_gen.md.

## Every PC has finished building the floor in build().
signal floor_built()

const ROOMS_NODE: String = "Rooms"
const PLUG_THICKNESS: float = 0.35
const PLUG_COLOR: Color = Color(0.5, 0.5, 0.53)

var _config: GameConfig
var _layout: FloorLayout
var _rooms_root: Node3D
var _room_nodes: Array[Node3D] = []
var _markers: Array[RoomMarker] = []
## NEW 2026-10-31: each marker's key (FloorLayout.marker_key), the same order as _markers.
var _marker_keys: PackedStringArray = []
var _overlay: FloorgenOverlay


## For tests only: a different config.
func use_config(config: GameConfig) -> void:
	_config = config


func _ready() -> void:
	if _config == null:
		_config = Config.game
	# NEW 2026-10-31 (floor generation step 3): the F8 debug view, F9 and the floorgen console commands.
	_overlay = FloorgenOverlay.new()
	_overlay.name = "FloorgenOverlay"
	_overlay.seed_entered.connect(func(floor_seed: int) -> void: _regenerate(floor_seed))
	add_child(_overlay)
	DebugConsole.register_command(&"floorgen", _cmd_floorgen,
		"floorgen <seed> | floorgen floor <n> | floorgen dept <department_id> | floorgen log | floorgen map")


## NEW 2026-10-31: F8 shows the floor from above (cheats only), F9 makes a new floor (host, cheats only).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not DebugConsole.cheats_allowed():
		return
	if key.keycode == KEY_F8:
		_overlay.toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F9:
		var result: String = _regenerate(0)
		EventBus.toast_requested.emit(result)
		get_viewport().set_input_as_handled()


## Host: builds the current floor again with this floor seed (0 = a new random one). Everyone is brought
## into the lift and it rides there, so every PC gets the new floor.
func _regenerate(floor_seed: int) -> String:
	var run: RunState = GameFlow.get_run()
	if run == null:
		return "Start a run first (floor generation needs a floor to replace)."
	if run.is_boss_floor:
		return "Boss floors aren't generated."
	var new_seed: int = floor_seed if floor_seed != 0 else randi_range(1, 2147483646)
	FloorGenerator.set_next_seed(new_seed)
	var result: String = GameFlow.debug_go_to_floor(run.floor_number)
	if not result.begins_with("Going"):
		FloorGenerator.set_next_seed(0)
		return result
	return "New floor: seed %d. %s" % [new_seed, result]


func _cmd_floorgen(args: PackedStringArray, _player_id: int) -> String:
	if args.is_empty():
		return "Usage: floorgen <seed> | floorgen floor <n> | floorgen dept <department_id> | floorgen log | floorgen map"
	match args[0]:
		"log":
			var layout: FloorLayout = FloorGenerator.last_layout if FloorGenerator.last_layout != null else _layout
			if layout == null or layout.log_lines.is_empty():
				return "No generation log here (it is on the host)."
			return "\n".join(layout.log_lines) + "\n(saved to %s)" % FloorGenerator.LOG_PATH
		"map":
			_overlay.toggle()
			return "Floor map %s." % ("shown" if _overlay.visible else "hidden")
		"floor":
			if args.size() < 2 or not args[1].is_valid_int():
				return "Usage: floorgen floor <n>"
			return GameFlow.debug_go_to_floor(args[1].to_int())
		"dept":
			if args.size() < 2:
				return "Usage: floorgen dept <department_id>"
			var run: RunState = GameFlow.get_run()
			return GameFlow.debug_go_to_floor(run.floor_in_department if run != null else 1, StringName(args[1]))
	if args[0].is_valid_int() and args[0].to_int() != 0:
		return _regenerate(args[0].to_int())
	return "Usage: floorgen <seed> | floorgen floor <n> | floorgen dept <department_id> | floorgen log | floorgen map"


## Builds the floor: every room in its place, plugs in doorways that lead nowhere. Clears the old
## floor first. parent: where the rooms go (default: the current scene).
func build(layout: FloorLayout, parent: Node = null) -> void:
	clear()
	if parent == null:
		parent = get_tree().current_scene
	_layout = layout
	_rooms_root = Node3D.new()
	_rooms_root.name = ROOMS_NODE
	parent.add_child(_rooms_root)
	var cell: float = _cell_size(layout)
	for index: int in layout.placements.size():
		var placement: RoomPlacement = layout.placements[index]
		var room := ContentRegistry.get_content(placement.room_id) as RoomData
		if room == null or room.scene == null:
			push_error("Level.build: no room called '%s' (or it has no scene)." % placement.room_id)
			continue
		var node := room.scene.instantiate() as Node3D
		node.name = "Room%d" % index
		node.transform = RoomShape.of(room, cell).placement_transform(placement, cell)
		_rooms_root.add_child(node)
		_room_nodes.append(node)
		for marker: RoomMarker in _markers_in(node):
			_markers.append(marker)
			_marker_keys.append(FloorLayout.marker_key(index, String(node.get_path_to(marker))))
	for link: Dictionary in LevelGenerator.doorway_links(layout, cell):
		var connected: bool = link["connected"]
		if connected:
			continue
		if link.get("open_edge", false):
			_add_cap(link, cell)
		else:
			_add_plug(link, cell)
	if _overlay != null and _overlay.visible:
		_overlay.refresh()
	floor_built.emit()


## Removes the floor (rooms and plugs).
func clear() -> void:
	if _rooms_root != null and is_instance_valid(_rooms_root):
		var parent: Node = _rooms_root.get_parent()
		if parent != null:
			parent.remove_child(_rooms_root)
		# Out of the tree already, so it can go right away (queue_free would leave it lying around a frame).
		_rooms_root.free()
	_rooms_root = null
	_room_nodes.clear()
	_markers.clear()
	_marker_keys.clear()
	_layout = null


func get_layout() -> FloorLayout:
	return _layout


## Markers of one kind, in room order then by name inside each room (the same order on every PC).
## CHANGED 2026-10-31: on a floor whose layout switched only some markers of this kind on
## (FloorLayout.active_markers), only those.
func get_markers(kind: StringName) -> Array[RoomMarker]:
	var found: Array[RoomMarker] = []
	var active: PackedStringArray = PackedStringArray()
	var filtered: bool = _layout != null and _layout.active_markers.has(kind)
	if filtered:
		active = _layout.active_markers[kind]
	for index: int in _markers.size():
		var marker: RoomMarker = _markers[index]
		if is_instance_valid(marker) and marker.kind == kind and (not filtered or active.has(_marker_keys[index])):
			found.append(marker)
	return found


## The room a point is in, or null.
func get_room_for_position(point: Vector3) -> RoomData:
	if _layout == null:
		return null
	var cell_size: float = _cell_size(_layout)
	# The floor may be moved and turned (game_flow lines its lift room up with the cargo lift).
	var local: Vector3 = point
	if _rooms_root != null and is_instance_valid(_rooms_root) and _rooms_root.is_inside_tree():
		local = _rooms_root.global_transform.affine_inverse() * point
	var cell := Vector2i(floori(local.x / cell_size), floori(local.z / cell_size))
	for placement: RoomPlacement in _layout.placements:
		var room := ContentRegistry.get_content(placement.room_id) as RoomData
		if room == null:
			continue
		var size: Vector2i = RoomShape.of(room, cell_size).rotated_size(placement.rotation_steps)
		var corner := Vector2i(placement.cell.x, placement.cell.z)
		if cell.x >= corner.x and cell.x < corner.x + size.x and cell.y >= corner.y and cell.y < corner.y + size.y:
			return room
	return null


## The room nodes in placement order (for test scenes and debug drawing).
func get_room_nodes() -> Array[Node3D]:
	return _room_nodes.duplicate()


## NEW 2026-10-31: where the floor is (game_flow moves and turns it to line its lift up with the cargo lift).
## Turns a point in the floor's own grid space into the world, and back with affine_inverse().
func get_floor_transform() -> Transform3D:
	if _rooms_root != null and is_instance_valid(_rooms_root) and _rooms_root.is_inside_tree():
		return _rooms_root.global_transform
	return Transform3D.IDENTITY


## NEW 2026-10-31: metres per grid cell on this floor (3 m tiles or 12 m grey-box rooms).
func _cell_size(layout: FloorLayout) -> float:
	if layout != null and layout.grid == RoomData.GRID_TILE:
		return Config.floor_gen.grid_unit
	return _config.room_cell_size


func _markers_in(room_node: Node) -> Array[RoomMarker]:
	var found: Array[RoomMarker] = []
	for node: Node in RoomShape.all_children(room_node):
		var marker := node as RoomMarker
		if marker != null:
			found.append(marker)
	found.sort_custom(func(a: RoomMarker, b: RoomMarker) -> bool:
		return String(room_node.get_path_to(a)) < String(room_node.get_path_to(b)))
	return found


## A wall piece that fills a doorway nothing joins, on the edge between its cell and the next.
func _add_plug(link: Dictionary, cell_size: float) -> void:
	var cell: Vector2i = link["cell"]
	var dir: Vector2i = link["dir"]
	var door_width: float = link["width"]
	var width: float = door_width + 0.1
	var height: float = link["height"]
	var center := (Vector2(cell) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5) * cell_size
	var body := StaticBody3D.new()
	body.name = "Plug%s_%s" % [str(link["placement"]), str(link["name"])]
	body.position = Vector3(center.x, height / 2.0, center.y)
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	body.collision_mask = 0
	var size := Vector3(PLUG_THICKNESS, height, width) if dir.x != 0 else Vector3(width, height, PLUG_THICKNESS)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = PLUG_COLOR
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	_rooms_root.add_child(body)


## NEW 2026-10-31: a wall that closes an open edge nothing joins (a hallway end): as wide as the grid unit
## and as tall as the ceiling, in the tiles' wall material.
func _add_cap(link: Dictionary, cell_size: float) -> void:
	var cell: Vector2i = link["cell"]
	var dir: Vector2i = link["dir"]
	var tuning: FloorGenTuning = Config.floor_gen
	var height: float = tuning.ceiling_height
	var center := (Vector2(cell) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5) * cell_size
	var body := StaticBody3D.new()
	body.name = "Cap%s_%s" % [str(link["placement"]), str(link["name"])]
	body.position = Vector3(center.x, height / 2.0, center.y)
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	body.collision_mask = 0
	var size := Vector3(tuning.wall_thickness, height, cell_size) if dir.x != 0 \
		else Vector3(cell_size, height, tuning.wall_thickness)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = BlockoutTile.slot_material(&"wall")
	mesh.mesh = box_mesh
	mesh.set_meta(TileStandards.MATERIAL_SLOT_META, &"wall")
	body.add_child(mesh)
	_rooms_root.add_child(body)
