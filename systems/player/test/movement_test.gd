extends Node3D
## Test scene for player (run alone with F6). A grey floor with boxes, a ramp, a low door and a wall.
## Run 2 or 3 instances (Debug > Customize Run Instances) and use Host local / Join local to see
## each other walk around. Launch options after "--": "host" or "join" start by themselves.
##
## Keys: WASD move, Shift sprint, Space jump, Ctrl crouch, Esc frees the mouse (click to look again).
## Test modifiers on your own body: 1 = double speed, 2 = no jumping, 3 = Giraffe height (x1.4).
## STUB buttons stand in for game_flow: "Start run" and "Next floor" (press them in the host window).

const FLOOR_SIZE: float = 40.0
const TEST_MODIFIERS: Dictionary[Key, StringName] = {KEY_1: &"test_fast", KEY_2: &"test_no_jump", KEY_3: &"test_giraffe"}

var _spawner: PlayerSpawner
var _overview: Camera3D
var _status: Label
var _floor_number: int = 0
var _active_test_sources: Array[StringName] = []
var _last_body_count: int = -1


func _ready() -> void:
	_build_world()
	_spawner = PlayerSpawner.new()
	_spawner.name = "PlayerSpawner"
	var points: Array[Node3D] = []
	for index: int in 8:
		var point := Marker3D.new()
		var angle: float = TAU * float(index) / 8.0
		point.position = Vector3(cos(angle) * 3.0, 0.1, sin(angle) * 3.0)
		add_child(point)
		points.append(point)
	_spawner.spawn_points = points
	add_child(_spawner)
	# Used while this window has no body of its own (e.g. joined mid-run, waiting for the next floor).
	# Your own body's first-person camera takes over as soon as it spawns.
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 18, 18)
	_overview.rotation_degrees = Vector3(-45, 0, 0)
	add_child(_overview)
	_build_ui()
	_run_launch_options.call_deferred()


## "port=7790" picks another port, so a second test group doesn't join the first one.
func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = 7777
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			port = arg.trim_prefix("port=").to_int()
	if args.has("host"):
		SteamSession.host_local(port)
		if args.has("start_run"):
			EventBus.run_started.emit(randi())
	elif args.has("join"):
		SteamSession.join_local("127.0.0.1", port)


func _process(_delta: float) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if body == null and not _overview.current:
		_overview.make_current()
	var lines: PackedStringArray = []
	lines.append("%s | me: %d | players: %d | bodies: %d" % ["HOST" if Net.is_host() else "CLIENT",
		Net.local_player_id(), Net.get_player_count(), get_tree().get_nodes_in_group(PlayerCharacter.GROUP).size()])
	if body != null:
		var movement: PlayerMovement = body.get_movement()
		lines.append("speed x%.1f | can jump: %s | height %.2f m | crouching: %s | grounded: %s" % [
			movement.get_speed_multiplier(), movement.can_jump(), movement.get_height(),
			movement.is_crouching(), movement.is_grounded()])
	elif Net.is_waiting_for_next_floor(Net.local_player_id()):
		lines.append("Joined mid-run: you'll spawn on the next floor.")
	_status.text = "\n".join(lines)
	var body_count: int = get_tree().get_nodes_in_group(PlayerCharacter.GROUP).size()
	if body_count != _last_body_count:
		_last_body_count = body_count
		print("[movement_test] bodies in the level: %d" % body_count)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not TEST_MODIFIERS.has(key.keycode):
		return
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if body == null:
		return
	# Only your own PC changes here; upgrades will set modifiers on every PC later.
	var source: StringName = TEST_MODIFIERS[key.keycode]
	var movement: PlayerMovement = body.get_movement()
	if _active_test_sources.has(source):
		movement.remove_modifier(source)
		_active_test_sources.erase(source)
	else:
		movement.set_modifier(source, _make_test_effect(source))
		_active_test_sources.append(source)


func _make_test_effect(source: StringName) -> MovementEffectData:
	var effect := MovementEffectData.new()
	match source:
		&"test_fast":
			effect.speed_multiplier = 2.0
		&"test_no_jump":
			effect.can_jump = false
		&"test_giraffe":
			effect.height_multiplier = 1.4
	return effect


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.62, 0.7)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	_add_box(Vector3(0, -0.5, 0), Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE), Color(0.5, 0.5, 0.52))
	# Some crates to walk around and jump on.
	_add_box(Vector3(6, 0.5, 2), Vector3(1, 1, 1), Color(0.6, 0.45, 0.3))
	_add_box(Vector3(7.5, 0.75, 4), Vector3(1.5, 1.5, 1.5), Color(0.6, 0.45, 0.3))
	_add_box(Vector3(-5, 0.4, -6), Vector3(2, 0.8, 2), Color(0.6, 0.45, 0.3))
	# A ramp.
	var ramp := _add_box(Vector3(-8, 1.0, 6), Vector3(3, 0.3, 8), Color(0.45, 0.5, 0.45))
	ramp.rotation_degrees.x = 15.0
	# A low door frame (1.5 m opening): Giraffe height (key 3) must crouch through it.
	_add_box(Vector3(0, 0.75, -10), Vector3(0.4, 1.5, 0.4), Color(0.4, 0.4, 0.5))
	_add_box(Vector3(1.6, 0.75, -10), Vector3(0.4, 1.5, 0.4), Color(0.4, 0.4, 0.5))
	_add_box(Vector3(0.8, 1.7, -10), Vector3(2.0, 0.4, 0.4), Color(0.4, 0.4, 0.5))
	# A tall wall (for wall climbing later).
	_add_box(Vector3(12, 2.5, -4), Vector3(0.5, 5, 6), Color(0.45, 0.45, 0.5))


func _add_box(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
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
	add_child(body)
	return body


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_button(row, "Host local", func() -> void: SteamSession.host_local())
	_add_button(row, "Join local", func() -> void: SteamSession.join_local())
	_add_button(row, "Leave", SteamSession.leave_lobby)
	_add_button(row, "Start run (stub)", func() -> void: EventBus.run_started.emit(randi()))
	_add_button(row, "Next floor (stub)", _on_next_floor)
	_status = Label.new()
	column.add_child(_status)
	var help := Label.new()
	help.text = "WASD move, Shift sprint, Space jump, Ctrl crouch, Esc frees the mouse.\n1 = fast, 2 = no jump, 3 = Giraffe height."
	column.add_child(help)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)


func _on_next_floor() -> void:
	_floor_number += 1
	EventBus.floor_loading.emit(_floor_number, &"department_zoology")
	EventBus.floor_ready.emit(_floor_number, &"department_zoology")
