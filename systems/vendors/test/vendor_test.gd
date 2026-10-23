extends Node3D
## Test scene for vendors (run alone with F6): one vending machine with the Zoology stock, 10 one-value
## gems and a 5-value gem on the floor. Pick gems up (E) and drop or throw them into the yellow coin slot:
## the gems count for whoever held them last. Then look at a green button and press E to buy; the change
## pops out as gems. The red lever (hold E) gives everyone's gems back. F4 drops 10 more gem value.
## Use 2 windows (Esc > Host local / Join local) to check two players' gems stay separate.

const VENDING_SCENE: PackedScene = preload("res://systems/vendors/vending_machine.tscn")

var _overview: Camera3D
var _prompt: Label


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
	box.size = Vector3(20, 1, 20)
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
	var vendor := VENDING_SCENE.instantiate() as Vendor
	vendor.name = "Vendor"
	vendor.stock_id = &"stock_zoology_vending"
	vendor.position = Vector3(0, 0, -4)
	add_child(vendor)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 6, 4)
	_overview.rotation_degrees = Vector3(-35, 0, 0)
	add_child(_overview)
	var layer := CanvasLayer.new()
	add_child(layer)
	var help := Label.new()
	help.position = Vector2(12, 12)
	help.text = "Pick gems up (E) and drop or throw them (left click) into the yellow slot. Green buttons buy (E).\n" \
		+ "Red lever: hold E for a refund. F4: more gems. Your gems in the machine show on its screen."
	layer.add_child(help)
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
	_drop_gems.call_deferred()


## Host: 10 plain gems and a large one on the floor.
func _drop_gems() -> void:
	if not multiplayer.is_server():
		return
	for index: int in 10:
		Props.spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, Vector3(-2.0 + 0.4 * float(index % 5), 0.3, -1.0 + 0.4 * floorf(float(index) / 5.0))))
	Props.spawn_prop(&"prop_gem_large", Transform3D(Basis.IDENTITY, Vector3(2, 0.3, -1)))


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F4:
		_more_gems_rpc.rpc_id(1)
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func _more_gems_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_drop_gems()
