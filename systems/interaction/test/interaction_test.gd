extends Node3D
## Test scene for interaction (run alone with F6). A room with:
##   a green button (press E), a red lever (hold E for 1 second), a grey disabled button,
##   and a blue button on the far wall (its prompt only appears when you walk up to it).
## Each use is checked by the host; the host then tells everyone, and the lamp changes colour.
## Launch options after "--": "host", "join", "port=7790".

const LAMP_COLORS: Array[Color] = [Color(1, 0.9, 0.5), Color(0.4, 1, 0.5), Color(0.5, 0.7, 1), Color(1, 0.4, 0.4)]

var _overview: Camera3D
var _prompt: Label
var _hold_bar: ProgressBar
var _log: Label
var _lamp: OmniLight3D
var _lamp_index: int = 0


func _ready() -> void:
	_build_world()
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 12, 10)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	_build_ui()
	_run_launch_options.call_deferred()


func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = 7777
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			port = arg.trim_prefix("port=").to_int()
	if args.has("host"):
		SteamSession.host_local(port)
	elif args.has("join"):
		SteamSession.join_local("127.0.0.1", port)


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	# STUB (ui HUD): the prompt and hold ring, drawn here until the HUD exists.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "Press E to %s" % prompt.to_lower()
	var progress: float = controller.get_hold_progress() if controller != null else 0.0
	_hold_bar.visible = progress > 0.0
	_hold_bar.value = progress


## Host only (Interactable.used fires on the host): tell everyone what happened.
func _on_used(player_id: int, what: String) -> void:
	_announce.rpc(Net.get_display_name(player_id), what)


@rpc("authority", "call_local", "reliable")
func _announce(player_name: String, what: String) -> void:
	if not is_inside_tree():
		return
	_lamp_index = (_lamp_index + 1) % LAMP_COLORS.size()
	_lamp.light_color = LAMP_COLORS[_lamp_index]
	_log.text = "%s used the %s (the host checked it)\n%s" % [player_name, what, _log.text]


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.32, 0.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, 3.5, -2)
	_lamp.omni_range = 14.0
	_lamp.light_energy = 2.0
	_lamp.light_color = LAMP_COLORS[0]
	add_child(_lamp)
	_add_box(Vector3(0, -0.5, -2), Vector3(16, 1, 16), Color(0.45, 0.46, 0.5), PhysicsLayers.WORLD)
	_add_box(Vector3(0, 2, -10.2), Vector3(16, 4, 0.4), Color(0.55, 0.55, 0.6), PhysicsLayers.WORLD)
	_add_box(Vector3(-8.2, 2, -2), Vector3(0.4, 4, 16), Color(0.55, 0.55, 0.6), PhysicsLayers.WORLD)
	_add_box(Vector3(8.2, 2, -2), Vector3(0.4, 4, 16), Color(0.55, 0.55, 0.6), PhysicsLayers.WORLD)

	var button := _add_usable("GreenButton", Vector3(-3, 1.3, -4), Color(0.2, 0.8, 0.3), "Press the button", 0.0)
	button.used.connect(_on_used.bind("green button"))
	var lever := _add_usable("RedLever", Vector3(0, 1.3, -4), Color(0.85, 0.2, 0.2), "Pull the lever (hold)", 1.0)
	lever.used.connect(_on_used.bind("red lever"))
	var disabled := _add_usable("GreyButton", Vector3(3, 1.3, -4), Color(0.45, 0.45, 0.45), "This shouldn't show", 0.0)
	disabled.enabled = false
	disabled.used.connect(_on_used.bind("grey button (this should never happen)"))
	var far := _add_usable("BlueButton", Vector3(0, 1.3, -9.8), Color(0.2, 0.4, 0.9), "Press the far button", 0.0)
	far.used.connect(_on_used.bind("blue button"))
	_add_label(Vector3(-3, 2.0, -4), "Button")
	_add_label(Vector3(0, 2.0, -4), "Lever (hold E)")
	_add_label(Vector3(3, 2.0, -4), "Disabled")
	_add_label(Vector3(0, 2.0, -9.8), "Walk up to me")


func _add_usable(node_name: String, where: Vector3, color: Color, prompt: String, hold: float) -> Interactable:
	var body := _add_box(where, Vector3(0.6, 0.6, 0.3), color, PhysicsLayers.INTERACTABLES)
	body.name = node_name
	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_text = prompt
	interactable.hold_seconds = hold
	body.add_child(interactable)
	return interactable


func _add_box(center: Vector3, size: Vector3, color: Color, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.bit(layer)
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


func _add_label(where: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = where
	add_child(label)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	for entry: Array in [["Host local", func() -> void: SteamSession.host_local()],
			["Join local", func() -> void: SteamSession.join_local()], ["Leave", SteamSession.leave_lobby]]:
		var button := Button.new()
		button.text = entry[0] as String
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1] as Callable)
		row.add_child(button)
	_log = Label.new()
	column.add_child(_log)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(300, 120)
	center.add_child(middle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	middle.add_child(_prompt)
	_hold_bar = ProgressBar.new()
	_hold_bar.max_value = 1.0
	_hold_bar.show_percentage = false
	_hold_bar.custom_minimum_size = Vector2(200, 10)
	_hold_bar.visible = false
	middle.add_child(_hold_bar)
