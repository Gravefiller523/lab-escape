extends Node3D
## level_gen test scene (run with F6): builds a floor from a seed and shows it from above, with the
## markers as coloured balls (green = player spawn, yellow = props, red = enemies, blue = lift,
## purple = boss). Type a seed or press "Next seed". "Boss floor" shows the arena.
## Launch option after "--": "seed=123".

const MARKER_COLORS: Dictionary[StringName, Color] = {
	&"player_spawn": Color(0.2, 0.9, 0.3),
	&"prop_spawn": Color(0.95, 0.85, 0.2),
	&"enemy_spawn": Color(0.9, 0.2, 0.2),
	&"lift": Color(0.2, 0.5, 1.0),
	&"boss_spawn": Color(0.7, 0.2, 0.9),
}
const OTHER_MARKER_COLOR: Color = Color(1, 1, 1)
const CAMERA_HEIGHT: float = 90.0

var _seed_edit: SpinBox
var _info: Label
var _camera: Camera3D
var _gizmos: Node3D
var _boss: bool = false


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.1, 0.1, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 30, 0)
	add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 120.0
	_camera.rotation_degrees = Vector3(-90, 0, 0)
	add_child(_camera)
	_gizmos = Node3D.new()
	_gizmos.name = "Gizmos"
	add_child(_gizmos)
	_build_ui()
	var start_seed: int = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seed=") and arg.trim_prefix("seed=").is_valid_int():
			start_seed = arg.trim_prefix("seed=").to_int()
	_seed_edit.value = start_seed
	_generate.call_deferred()


func _generate() -> void:
	var department: DepartmentData = GameFlow.get_department(GameFlowService.PLACEHOLDER_DEPARTMENT_ID)
	var run_seed: int = int(_seed_edit.value)
	var layout: FloorLayout = LevelGenerator.generate_boss_floor(department, 6, run_seed) if _boss \
		else LevelGenerator.generate(department, 1, 1, run_seed, 1)
	Level.build(layout, self)
	for child: Node in _gizmos.get_children():
		child.queue_free()
	var counts: Dictionary[StringName, int] = {}
	for kind: StringName in MARKER_COLORS.keys():
		for marker: RoomMarker in Level.get_markers(kind):
			_ball(marker.global_position, MARKER_COLORS[kind])
			counts[kind] = counts.get(kind, 0) + 1
	# Centre the camera over the rooms.
	var cell_size: float = Config.game.room_cell_size
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for placement: RoomPlacement in layout.placements:
		var room := ContentRegistry.get_content(placement.room_id) as RoomData
		var size: Vector2i = RoomShape.of(room, cell_size).rotated_size(placement.rotation_steps)
		var corner := Vector2(placement.cell.x, placement.cell.z)
		low = Vector2(minf(low.x, corner.x), minf(low.y, corner.y))
		high = Vector2(maxf(high.x, corner.x + float(size.x)), maxf(high.y, corner.y + float(size.y)))
	var middle: Vector2 = (low + high) / 2.0 * cell_size
	_camera.position = Vector3(middle.x, CAMERA_HEIGHT, middle.y)
	_camera.size = maxf(high.x - low.x, high.y - low.y) * cell_size * 1.3
	var kinds: PackedStringArray = []
	for placement: RoomPlacement in layout.placements:
		kinds.append(String((ContentRegistry.get_content(placement.room_id) as RoomData).room_kind))
	_info.text = "Seed %d: %d rooms (%s) | markers: %s" % [run_seed, layout.placements.size(), ", ".join(kinds), str(counts)]


func _ball(at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material
	mesh.mesh = sphere
	mesh.position = at + Vector3.UP * 4.0
	_gizmos.add_child(mesh)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := Label.new()
	label.text = "Seed"
	row.add_child(label)
	_seed_edit = SpinBox.new()
	_seed_edit.min_value = 0
	_seed_edit.max_value = 999999
	_seed_edit.value_changed.connect(func(_value: float) -> void: _generate())
	row.add_child(_seed_edit)
	var next := Button.new()
	next.text = "Next seed"
	next.pressed.connect(func() -> void: _seed_edit.value += 1)
	row.add_child(next)
	var boss := CheckBox.new()
	boss.text = "Boss floor"
	boss.toggled.connect(func(on: bool) -> void:
		_boss = on
		_generate())
	row.add_child(boss)
	_info = Label.new()
	column.add_child(_info)
