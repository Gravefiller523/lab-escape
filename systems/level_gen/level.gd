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


## For tests only: a different config.
func use_config(config: GameConfig) -> void:
	_config = config


func _ready() -> void:
	if _config == null:
		_config = Config.game


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
	var cell: float = _config.room_cell_size
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
		_markers.append_array(_markers_in(node))
	for link: Dictionary in LevelGenerator.doorway_links(layout, cell):
		var connected: bool = link["connected"]
		if not connected:
			_add_plug(link, cell)
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
	_layout = null


func get_layout() -> FloorLayout:
	return _layout


## Markers of one kind, in room order then by name inside each room (the same order on every PC).
func get_markers(kind: StringName) -> Array[RoomMarker]:
	var found: Array[RoomMarker] = []
	for marker: RoomMarker in _markers:
		if is_instance_valid(marker) and marker.kind == kind:
			found.append(marker)
	return found


## The room a point is in, or null.
func get_room_for_position(point: Vector3) -> RoomData:
	if _layout == null:
		return null
	var cell_size: float = _config.room_cell_size
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
