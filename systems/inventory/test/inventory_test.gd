extends Node3D
## Test scene for inventory (run alone with F6). Test items are made in code (the real crowbar and drinks
## come with the items system): a crowbar, an energy drink (1 per slot) and bolts (stack 3).
##   F1 crowbar, F2 energy drink, F3 bolt (all as picking up: swaps with the selected item when full)
##   F4 one more bonus slot, F7 remove the bonus slots, F8 empty everything (like dying)
##   1-9 / mouse wheel pick a slot, Alt holsters (fists out), Q drops the selected item
## The slot bar is at the bottom (the real one comes with the ui HUD). Use 2 windows (Esc > Host local /
## Join local) to check every PC sees the same slots. Launch options after "--": "host", "join", "port=7790".

const TEST_ITEMS: Array[Array] = [
	[&"item_test_crowbar", "Crowbar", 1, -1],
	[&"item_test_energy_drink", "Energy drink", 1, 1],
	[&"item_test_bolt", "Bolt", 3, 1],
]

var _overview: Camera3D
var _bar: HBoxContainer
var _hand: Label
var _log: Label
## player_id -> extra slots given with F4.
var _bonus: Dictionary[int, int] = {}


func _ready() -> void:
	for entry: Array in TEST_ITEMS:
		var id: StringName = entry[0]
		if ContentRegistry.has_content(id):
			continue
		var data := ItemData.new()
		data.id = id
		data.display_name = entry[1]
		data.max_stack = entry[2]
		data.uses = entry[3]
		ContentRegistry.register_content(data)
	_build_world()
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 12, 10)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	_build_ui()
	EventBus.player_spawned.connect(func(_player_id: int, body: Node3D) -> void:
		var inventory: InventoryComponent = InventoryComponent.of(body)
		if inventory != null and multiplayer.is_server():
			inventory.item_dropped.connect(func(slot: InventorySlot, _at: Transform3D) -> void:
				_announce.rpc("%s dropped %s" % [Net.get_display_name((body as PlayerCharacter).player_id), slot.item_id])))
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


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var actions: Dictionary[Key, StringName] = {
		KEY_F1: &"item_test_crowbar", KEY_F2: &"item_test_energy_drink", KEY_F3: &"item_test_bolt",
		KEY_F4: &"bonus_add", KEY_F7: &"bonus_clear", KEY_F8: &"take_all",
	}
	if actions.has(key.keycode):
		_request_rpc.rpc_id(1, actions[key.keycode])
		get_viewport().set_input_as_handled()


## Anyone -> host: do a test action to the sender's inventory.
@rpc("any_peer", "call_local", "reliable")
func _request_rpc(action: StringName) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var player_id: int = Net.get_player_id_for_peer(sender) if sender != 0 and sender != 1 else Net.local_player_id()
	var inventory: InventoryComponent = InventoryComponent.of(PlayerCharacter.find(player_id))
	if inventory == null:
		return
	match action:
		&"bonus_add":
			_bonus[player_id] = _bonus.get(player_id, 0) + 1
			inventory.set_bonus_slots(&"test", _bonus[player_id])
		&"bonus_clear":
			_bonus.erase(player_id)
			inventory.clear_bonus_slots(&"test")
		&"take_all":
			_announce.rpc("%s lost everything (%d items)" % [Net.get_display_name(player_id), inventory.take_all().size()])
		_:
			var data := ContentRegistry.get_content(action) as ItemData
			inventory.pick_up(action, data.uses if data != null else -1)


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	if not is_inside_tree():
		return
	_log.text = "%s\n%s" % [text, _log.text.left(300)]


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	_draw_bar(Inventory.get_local())


## STUB (ui HUD's inventory bar): one box per slot, the selected one highlighted.
func _draw_bar(inventory: InventoryComponent) -> void:
	var count: int = inventory.get_slot_count() if inventory != null else 0
	while _bar.get_child_count() < count:
		var box := Label.new()
		box.custom_minimum_size = Vector2(130, 56)
		box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_theme_stylebox_override("normal", StyleBoxFlat.new())
		_bar.add_child(box)
	while _bar.get_child_count() > count:
		var extra: Node = _bar.get_child(_bar.get_child_count() - 1)
		_bar.remove_child(extra)
		extra.queue_free()
	for index: int in count:
		var box := _bar.get_child(index) as Label
		var slot: InventorySlot = inventory.get_slot(index)
		var name_text: String = "(fists)"
		if slot != null:
			var data := ContentRegistry.get_content(slot.item_id) as ItemData
			name_text = data.display_name if data != null else String(slot.item_id)
			if slot.count > 1:
				name_text += " x%d" % slot.count
		box.text = "%d\n%s" % [index + 1, name_text]
		var style := box.get_theme_stylebox("normal") as StyleBoxFlat
		var selected: bool = index == inventory.get_active_index()
		style.bg_color = Color(0.9, 0.75, 0.2, 0.85) if selected else Color(0.1, 0.1, 0.12, 0.7)
		box.add_theme_color_override("font_color", Color.BLACK if selected else Color.WHITE)
	_hand.text = "" if inventory == null else "In your hand: %s%s" % [
		"fists" if inventory.is_using_fists() else String(inventory.get_active_item_id()),
		" (holstered: Alt to take it out)" if inventory.is_holstered() else ""]


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.32, 0.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(environment)
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.5, -2)
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, 1, 16)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	floor_body.add_child(mesh)
	add_child(floor_body)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var help := Label.new()
	help.position = Vector2(12, 12)
	help.text = "F1 crowbar  F2 energy drink  F3 bolt  F4 +1 slot  F7 remove extra slots  F8 empty all\n" \
		+ "1-9 / wheel: pick a slot   Alt: holster   Q: drop"
	layer.add_child(help)
	_log = Label.new()
	_log.position = Vector2(12, 70)
	layer.add_child(_log)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -16
	bottom.offset_top = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(bottom)
	_hand = Label.new()
	_hand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_hand)
	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_bar)
