extends Node3D
## Physics props proof scene (run alone with F6, then with 2 windows). A grey room with a table,
## four light crates, one heavy crate (needs two people), a lift part (key object) and a pit.
##
## Look at a crate and press E to pick it up, E again (or Q) to drop it, left click to throw.
## Things to try: pass a crate between two windows, stack crates on the table, lift the heavy crate
## together, throw the lift part into the pit (it comes back), throw a crate into the pit (it's gone).
## Launch options after "--": "host", "join", "port=7790". R (host) puts all the props back.

const PIT_CENTER: Vector3 = Vector3(5, 0, -6)
const PIT_SIZE: float = 3.0
const ROOM_HALF: float = 10.0

var _props: PropSpawner
var _overview: Camera3D
var _prompt: Label
var _status: Label


func _ready() -> void:
	_build_world()
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_props = PropSpawner.new()
	_props.name = "Props"
	add_child(_props)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 14, 10)
	_overview.rotation_degrees = Vector3(-55, 0, 0)
	add_child(_overview)
	_build_ui()
	_spawn_layout.call_deferred()
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


## Host: the test props. (A client gets the host's props automatically.)
func _spawn_layout() -> void:
	if not multiplayer.is_server():
		return
	for prop: NetProp in _props.get_props():
		_props.despawn(prop)
	for index: int in 4:
		_props.spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(-3.0 + float(index) * 0.9, 0.35, -3)))
	_props.spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(0, 0.45, -6)))
	_props.spawn_prop(&"prop_lift_part_zoology", Transform3D(Basis.IDENTITY, Vector3(3, 0.4, -3)))


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	# STUB (ui HUD): the prompt and crosshair, drawn here until the HUD exists.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var held: String = "nothing"
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if body != null and PropsService.grab_of(body) != null and PropsService.grab_of(body).get_held() != null:
		var prop: NetProp = PropsService.grab_of(body).get_held()
		held = "%s (%d kg)%s" % [prop.data.display_name, int(prop.mass),
			"  - waiting for a second person" if prop.needs_two_people() and not prop.is_lifted() else ""]
	_status.text = "%s | players: %d | props: %d | holding: %s" % ["HOST" if Net.is_host() else "CLIENT",
		Net.get_player_count(), _props.get_props().size(), held]


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		_spawn_layout()


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.34, 0.38)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var grey := Color(0.48, 0.49, 0.52)
	# Floor in four pieces around the pit.
	var pit_min: Vector2 = Vector2(PIT_CENTER.x, PIT_CENTER.z) - Vector2.ONE * PIT_SIZE / 2.0
	var pit_max: Vector2 = Vector2(PIT_CENTER.x, PIT_CENTER.z) + Vector2.ONE * PIT_SIZE / 2.0
	_floor_piece(Vector2(-ROOM_HALF, -ROOM_HALF), Vector2(pit_min.x, ROOM_HALF), grey)
	_floor_piece(Vector2(pit_max.x, -ROOM_HALF), Vector2(ROOM_HALF, ROOM_HALF), grey)
	_floor_piece(Vector2(pit_min.x, -ROOM_HALF), Vector2(pit_max.x, pit_min.y), grey)
	_floor_piece(Vector2(pit_min.x, pit_max.y), Vector2(pit_max.x, ROOM_HALF), grey)
	var wall := Color(0.58, 0.58, 0.62)
	_box(Vector3(0, 2, -ROOM_HALF - 0.2), Vector3(ROOM_HALF * 2, 4, 0.4), wall)
	_box(Vector3(0, 2, ROOM_HALF + 0.2), Vector3(ROOM_HALF * 2, 4, 0.4), wall)
	_box(Vector3(-ROOM_HALF - 0.2, 2, 0), Vector3(0.4, 4, ROOM_HALF * 2), wall)
	_box(Vector3(ROOM_HALF + 0.2, 2, 0), Vector3(0.4, 4, ROOM_HALF * 2), wall)
	# A table to stack crates on.
	_box(Vector3(-4, 0.45, -7), Vector3(2.4, 0.9, 1.2), Color(0.5, 0.36, 0.24))
	_label(PIT_CENTER + Vector3(0, 1.2, 0), "Pit")
	_label(Vector3(-4, 1.6, -7), "Table")


func _floor_piece(corner_a: Vector2, corner_b: Vector2, color: Color) -> void:
	var size := Vector2(absf(corner_b.x - corner_a.x), absf(corner_b.y - corner_a.y))
	if size.x <= 0.01 or size.y <= 0.01:
		return
	var center: Vector2 = (corner_a + corner_b) / 2.0
	_box(Vector3(center.x, -0.5, center.y), Vector3(size.x, 1, size.y), color)


func _box(center: Vector3, size: Vector3, color: Color) -> void:
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


func _label(where: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
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
	_status = Label.new()
	column.add_child(_status)
	var help := Label.new()
	help.text = "E pick up / drop | left click throw | Q drop | R (host) reset the props"
	column.add_child(help)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(300, 80)
	center.add_child(middle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	middle.add_child(_prompt)
