extends Node3D
## Test scene for items (run alone with F6). A range with:
##   a table of item pickups (look at one and press E to take it),
##   3 red dummies (100 health; their health floats above them),
##   a mutated plant (right click with an energy drink to water it: it grows steps),
##   boarded-up planks (right click with the crowbar to pry them off).
## Left click: use (swing, throw, drink). Right click: the item's second use. Alt holsters, Q drops.
## Keys: F1 crowbar, F2 knife, F3 potted plant, F4 energy drink, F7 hot coffee, F8 reset the range.
## Use 2 windows (Esc > Host local / Join local) to check everyone sees the same thing.
## Launch options after "--": "host", "join", "port=7790".

const PLANT_SCENE: PackedScene = preload("res://systems/items/world/mutated_plant.tscn")
const GIVE_KEYS: Dictionary[Key, StringName] = {
	KEY_F1: &"item_crowbar", KEY_F2: &"item_knife", KEY_F3: &"item_potted_plant",
	KEY_F4: &"item_energy_drink", KEY_F7: &"item_hot_coffee",
}
const TABLE_ITEMS: Array[StringName] = [&"item_crowbar", &"item_knife", &"item_potted_plant",
	&"item_energy_drink", &"item_hot_coffee"]

var _overview: Camera3D
var _prompt: Label
var _status: Label
var _dummies: Array[Node3D] = []
var _dummy_labels: Array[Label3D] = []
var _plant: MutatedPlant
var _boards: StaticBody3D


func _ready() -> void:
	_build_world()
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 12, 10)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	_build_ui()
	_fill_table.call_deferred()
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


## Host: one of each item on the table.
func _fill_table() -> void:
	if not multiplayer.is_server():
		return
	for index: int in TABLE_ITEMS.size():
		Props.spawn_item(TABLE_ITEMS[index], Transform3D(Basis.IDENTITY, Vector3(-3.0 + float(index) * 1.5, 1.2, 2.0)))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if GIVE_KEYS.has(key.keycode):
		_request_rpc.rpc_id(1, GIVE_KEYS[key.keycode])
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F8:
		_request_rpc.rpc_id(1, &"reset")
		get_viewport().set_input_as_handled()


## Anyone -> host: give the sender an item, or reset the range.
@rpc("any_peer", "call_local", "reliable")
func _request_rpc(what: StringName) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	if what == &"reset":
		for dummy: Node3D in _dummies:
			HealthComponent.of(dummy).revive()
		(_plant.get_node("UseTarget") as UseTarget).reset()
		(_boards.get_node("UseTarget") as UseTarget).reset()
		for prop: NetProp in Props.get_props():
			if prop.get_node_or_null(NodePath(ItemPickup.NODE_NAME)) != null:
				Props.despawn(prop)
		_fill_table()
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var player_id: int = Net.get_player_id_for_peer(sender) if sender > 1 else Net.local_player_id()
	var inventory: InventoryComponent = InventoryComponent.of(PlayerCharacter.find(player_id))
	var data := ContentRegistry.get_content(what) as ItemData
	if inventory != null and data != null:
		inventory.pick_up(what, data.uses)


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	# STUB (the ui HUD only shows prompts in the game world): the prompt.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var inventory: InventoryComponent = Inventory.get_local()
	var me: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	var parts: PackedStringArray = []
	if inventory != null:
		for index: int in inventory.get_slot_count():
			var slot: InventorySlot = inventory.get_slot(index)
			var item_name: String = "-" if slot == null else (ContentRegistry.get_content(slot.item_id) as ItemData).display_name
			parts.append("%s%d: %s" % [">" if index == inventory.get_active_index() else " ", index + 1, item_name])
		var health: HealthComponent = HealthComponent.of(me)
		_status.text = "In hand: %s    %s    Health %d" % [
			(ContentRegistry.get_content(inventory.get_active_item_id()) as ItemData).display_name, "   ".join(parts),
			roundi(health.get_current()) if health != null else 0]
	for index: int in _dummies.size():
		var health: HealthComponent = HealthComponent.of(_dummies[index])
		var statuses: StatusEffectComponent = StatusEffectComponent.of(_dummies[index])
		_dummy_labels[index].text = "%d%s" % [roundi(health.get_current()),
			" (burning)" if statuses.has_status(&"status_burning") else (" (down)" if health.is_dead() else "")]
	_boards.visible = not (_boards.get_node("UseTarget") as UseTarget).is_used()
	(_boards.get_node("Shape") as CollisionShape3D).disabled = not _boards.visible


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.32, 0.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	_add_box("Floor", Vector3(0, -0.5, -2), Vector3(20, 1, 20), Color(0.45, 0.46, 0.5))
	_add_box("Table", Vector3(0, 0.45, 2.0), Vector3(8, 0.9, 1.0), Color(0.5, 0.38, 0.25))
	for index: int in 3:
		var dummy := _add_box("Dummy%d" % index, Vector3(-3.0 + float(index) * 3.0, 0.9, -6), Vector3(0.7, 1.8, 0.7),
			Color(0.8, 0.25, 0.2))
		DamageService.give_components(dummy, 100.0, 0.5, 1.8)
		(dummy.get_node("Hurtbox") as Node3D).position.y = -0.9
		_dummies.append(dummy)
		var label := Label3D.new()
		label.font_size = 64
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 1.3, 0)
		dummy.add_child(label)
		_dummy_labels.append(label)
	_plant = PLANT_SCENE.instantiate() as MutatedPlant
	_plant.name = "MutatedPlant"
	_plant.position = Vector3(6, 0, -3)
	add_child(_plant)
	_boards = _add_box("Boards", Vector3(-6, 1.2, -3), Vector3(1.6, 1.4, 0.2), Color(0.6, 0.45, 0.3))
	var pry := UseTarget.new()
	pry.name = UseTarget.NODE_NAME
	pry.accepted_tags = PackedStringArray(["pry"])
	_boards.add_child(pry)
	_add_label(Vector3(6, 2.2, -3), "Mutated plant\n(energy drink, right click)")
	_add_label(Vector3(-6, 2.3, -3), "Boarded up\n(crowbar, right click)")
	_add_label(Vector3(0, 1.8, 2.0), "Take items (E)")


func _add_box(node_name: String, center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
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
	label.font_size = 36
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = where
	add_child(label)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var help := Label.new()
	help.position = Vector2(12, 12)
	help.text = "F1 crowbar  F2 knife  F3 potted plant  F4 energy drink  F7 hot coffee  F8 reset\n" \
		+ "Left click: use   Right click: second use   E: take   Alt: holster   Q: drop   1/2 or wheel: slots"
	layer.add_child(help)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.offset_top = -40
	_status.offset_bottom = -12
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	layer.add_child(_status)
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
