extends Node3D
## Test scene for carts (run alone with F6): a cart, 20 gems, a doorway at the narrowest width rooms may
## have (cart width + 0.4 m), a ramp, and a lift-sized box to park in.
## Pick gems up (E) and drop or throw them into the basket. Look at the cart and press E to push it,
## E again to let go. Look at a gem in the cart and press E to take it out. F1 more gems.
## Use 2 windows (Esc > Host local / Join local): only one player can push at a time.

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
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var grey := Color(0.55, 0.55, 0.6)
	_add_box(Vector3(0, -0.5, -8), Vector3(16, 1, 36), Color(0.45, 0.46, 0.5))
	# A wall across with the narrowest doorway allowed.
	var door: float = Config.game.cart_width + 0.4
	var side: float = (16.0 - door) / 2.0
	_add_box(Vector3(-8.0 + side / 2.0, 1.5, -6), Vector3(side, 3, 0.3), grey)
	_add_box(Vector3(8.0 - side / 2.0, 1.5, -6), Vector3(side, 3, 0.3), grey)
	# A ramp up to a platform.
	var ramp := _add_box(Vector3(0, 0.45, -11), Vector3(3, 0.2, 5), grey)
	ramp.rotation_degrees = Vector3(10, 0, 0)
	_add_box(Vector3(0, 0.4, -16), Vector3(6, 0.8, 5), grey)
	# The lift's floor size (5 x 5 m), as an outline.
	_add_box(Vector3(5, 0.01, 3), Vector3(5, 0.02, 5), Color(0.75, 0.6, 0.2))
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 12, 8)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var help := Label.new()
	help.text = "E on the cart: push / let go.  Drop or throw gems into the basket.  E on a gem in the cart: take it out.  F1 more gems.\n" \
		+ "Through the doorway and up the ramp; the yellow square is the cargo lift's floor size."
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
	_start.call_deferred()


func _start() -> void:
	if not multiplayer.is_server():
		return
	Props.spawn_prop(&"prop_cart_standard", Transform3D(Basis.IDENTITY, Vector3(0, 0.2, -2)))
	_drop_gems()


func _drop_gems() -> void:
	for index: int in 20:
		Props.spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, Vector3(-4.0 + 0.4 * float(index % 5), 0.3, 1.0 + 0.4 * floorf(float(index) / 5.0))))


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var parts: PackedStringArray = []
	for node: Node in get_tree().get_nodes_in_group(&"carts"):
		var cart := node as Cart
		parts.append("cart: %d / %d, pushed by %s" % [cart.get_contents().size(), cart.get_capacity(),
			Net.get_display_name(cart.get_pusher_id()) if cart.get_pusher_id() != 0 else "nobody"])
	_info.text = "  ".join(parts)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		_more_rpc.rpc_id(1)
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func _more_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_drop_gems()


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
