extends Node3D
## Test scene for death_respawn (run alone with F6): a 3D printer, a pile of meat and a kill button.
##   F1 die   F2 a crowbar for you   F3 more meat
## Die (F1 or the red button): your crowbar drops, you become a ghost watching a teammate (left / right
## click to switch). A teammate carries meat (E) onto the printer's red tray and presses its green button.
## Alone you get a free reprint after a few seconds (once per floor); the second death ends the "run".
## Use 2 windows (Esc > Host local / Join local) for the real thing.

const PRINTER_SCENE: PackedScene = preload("res://systems/death_respawn/printer_3d.tscn")

var _overview: Camera3D
var _prompt: Label
var _info: Label


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.32, 0.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(environment)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 1, 24)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	floor_body.add_child(mesh)
	floor_body.position.y = -0.5
	add_child(floor_body)
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var printer := PRINTER_SCENE.instantiate() as Printer3D
	printer.name = "Printer"
	printer.position = Vector3(0, 0, -6)
	add_child(printer)
	var button := StaticBody3D.new()
	button.name = "KillButton"
	button.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	var button_shape := CollisionShape3D.new()
	var button_box := BoxShape3D.new()
	button_box.size = Vector3(0.5, 0.5, 0.5)
	button_shape.shape = button_box
	button.add_child(button_shape)
	var button_mesh := MeshInstance3D.new()
	var red := BoxMesh.new()
	red.size = button_box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.15, 0.15)
	red.material = material
	button_mesh.mesh = red
	button.add_child(button_mesh)
	button.position = Vector3(4, 1.0, -3)
	var use := Interactable.new()
	use.prompt_text = "Die (test)"
	use.used.connect(func(player_id: int) -> void: Death.kill(player_id))
	button.add_child(use)
	add_child(button)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 10, 8)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var help := Label.new()
	help.text = "F1 die   F2 a crowbar   F3 more meat   Carry meat (E) onto the printer's red tray, then press its green button."
	column.add_child(help)
	_info = Label.new()
	column.add_child(_info)
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
	_drop_meat.call_deferred()


func _drop_meat() -> void:
	if not multiplayer.is_server():
		return
	for index: int in 3:
		Props.spawn_prop(&"prop_meat", Transform3D(Basis.IDENTITY, Vector3(-3.0 + 0.5 * float(index), 0.3, -2)))


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var names: PackedStringArray = []
	for player_id: int in Death.get_dead_players():
		names.append(Net.get_display_name(player_id))
	_info.text = "Dead: %s   Reprint cost: %d meat   Free solo reprints left: %d" % [
		", ".join(names) if not names.is_empty() else "nobody", Death.get_reprint_cost(), Death.get_free_reprints_left()]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var actions: Dictionary[Key, StringName] = {KEY_F1: &"die", KEY_F2: &"crowbar", KEY_F3: &"meat"}
	if actions.has(key.keycode):
		_request_rpc.rpc_id(1, actions[key.keycode])
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func _request_rpc(action: StringName) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var player_id: int = Net.get_player_id_for_peer(sender) if sender > 1 else Net.local_player_id()
	match action:
		&"die":
			Death.kill(player_id)
		&"crowbar":
			var inventory: InventoryComponent = InventoryComponent.of(PlayerCharacter.find(player_id))
			if inventory != null:
				inventory.pick_up(&"item_crowbar")
		&"meat":
			_drop_meat()
