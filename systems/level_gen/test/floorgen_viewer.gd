extends Node3D
## Floor generation viewer (floor generation step 3; run alone with F6). Makes floors without playing:
## type a floor seed and a floor number, press Generate (or Next seed). Tab switches between the map from
## above and the 3D floor (ceilings off). In 3D: hold the right mouse button to look around, WASD to fly,
## Q/E down/up, Shift faster. "Bake navigation" bakes the enemies' navigation mesh and shows how long it took.
## The generation log is printed to the Output panel and shown at the bottom.
##
## Benchmark: run with the launch option "benchmark" (after "--") to build and bake the biggest floors and
## print the times, then quit.

const BENCHMARK_FLOOR: int = 18
const BENCHMARK_SEEDS: Array[int] = [11, 222, 3333]
const FLY_SPEED: float = 12.0
const LOOK_SPEED: float = 0.004

var _floor_root: Node3D
var _camera: Camera3D
var _map: FloorMapView
var _seed_box: LineEdit
var _floor_box: SpinBox
var _info: Label
var _log: Label
var _layout: FloorLayout
var _show_3d: bool = false
var _looking: bool = false


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.13, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	add_child(sun)
	_floor_root = Node3D.new()
	_floor_root.name = "Floor"
	add_child(_floor_root)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 80, 40)
	_camera.rotation_degrees = Vector3(-70, 0, 0)
	_camera.far = 800.0
	add_child(_camera)
	_build_ui()
	if OS.get_cmdline_user_args().has("benchmark"):
		_benchmark.call_deferred()
	else:
		_generate.call_deferred(1234, 1)


func _process(delta: float) -> void:
	if not _show_3d or not _looking:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= _camera.global_basis.z
	if Input.is_key_pressed(KEY_S):
		move += _camera.global_basis.z
	if Input.is_key_pressed(KEY_A):
		move -= _camera.global_basis.x
	if Input.is_key_pressed(KEY_D):
		move += _camera.global_basis.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	var speed: float = FLY_SPEED * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_camera.global_position += move.normalized() * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_RIGHT:
		_looking = button.pressed and _show_3d
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	var motion := event as InputEventMouseMotion
	if motion != null and _looking:
		_camera.rotation.y -= motion.relative.x * LOOK_SPEED
		_camera.rotation.x = clampf(_camera.rotation.x - motion.relative.y * LOOK_SPEED, -1.5, 1.5)
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_TAB:
		_show_3d = not _show_3d
		_map.visible = not _show_3d
		get_viewport().set_input_as_handled()


func _generate(floor_seed: int, floor_number: int) -> void:
	var started: int = Time.get_ticks_usec()
	_layout = FloorGenerator.generate_from_seed(_department(), floor_number, floor_seed, Config.floor_gen)
	var generate_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	FloorGenerator.report(_layout)
	started = Time.get_ticks_usec()
	Level.build(_layout, _floor_root)
	var build_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	for node: Node in get_tree().get_nodes_in_group(TileStandards.CEILING_GROUP):
		(node as Node3D).visible = false
	_map.layout = _layout
	_seed_box.text = str(floor_seed)
	_floor_box.value = floor_number
	_info.text = "seed %d / attempt %d / floor %d: %d tiles, %d wings, %d loops%s.  Generated in %.1f ms, built in %.1f ms." % [
		_layout.floor_seed, _layout.attempt, floor_number, _layout.placements.size(), _layout.wings.size(),
		_layout.loops.size(), "  FALLBACK" if _layout.is_fallback else "", generate_ms, build_ms]
	_log.text = "\n".join(_layout.log_lines.slice(maxi(_layout.log_lines.size() - 10, 0)))


func _bake() -> void:
	if _layout == null:
		return
	# CSG walls make their collision a frame after they are built.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var started: int = Time.get_ticks_usec()
	var region: NavigationRegion3D = Enemies.bake_navigation(_floor_root.get_node(LevelService.ROOMS_NODE) as Node3D, true)
	var bake_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var polygons: int = region.navigation_mesh.get_polygon_count() if region != null and region.navigation_mesh != null else 0
	var line: String = "Navigation baked in %.0f ms (%d polygons, %d tiles)." % [bake_ms, polygons, _layout.placements.size()]
	print("[floorgen_viewer] %s" % line)
	_info.text += "\n" + line


## Builds and bakes the biggest floors and prints the times (launch option "benchmark").
func _benchmark() -> void:
	for floor_seed: int in BENCHMARK_SEEDS:
		_generate(floor_seed, BENCHMARK_FLOOR)
		print("[floorgen_viewer] %s" % _info.text)
		await _bake()
	get_tree().quit()


func _department() -> DepartmentData:
	var department := DepartmentData.new()
	department.id = &"department_viewer"
	return department


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_map = FloorMapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.offset_top = 90
	_map.offset_bottom = -170
	layer.add_child(_map)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 8)
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var seed_label := Label.new()
	seed_label.text = "Floor seed"
	row.add_child(seed_label)
	_seed_box = LineEdit.new()
	_seed_box.custom_minimum_size = Vector2(140, 0)
	row.add_child(_seed_box)
	var floor_label := Label.new()
	floor_label.text = "Floor"
	row.add_child(floor_label)
	_floor_box = SpinBox.new()
	_floor_box.min_value = 1
	_floor_box.max_value = 30
	row.add_child(_floor_box)
	var generate := Button.new()
	generate.text = "Generate"
	generate.pressed.connect(func() -> void:
		_generate(_seed_box.text.to_int() if _seed_box.text.is_valid_int() else 1, int(_floor_box.value)))
	row.add_child(generate)
	var next := Button.new()
	next.text = "Next seed"
	next.pressed.connect(func() -> void: _generate(randi_range(1, 2147483646), int(_floor_box.value)))
	row.add_child(next)
	var bake := Button.new()
	bake.text = "Bake navigation"
	bake.pressed.connect(_bake)
	row.add_child(bake)
	var help := Label.new()
	help.text = "Tab: map / 3D floor. 3D: hold right mouse to look, WASD fly, Q/E down/up, Shift faster. Wheel on the map zooms."
	column.add_child(help)
	_info = Label.new()
	column.add_child(_info)
	_log = Label.new()
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_log.add_theme_font_size_override("font_size", 12)
	layer.add_child(_log)
