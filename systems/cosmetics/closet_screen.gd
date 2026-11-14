class_name ClosetScreen
extends Control
## The jacket closet (NEW 2026-11-13, roadmap WP17, mock-up approved by Zachary): press E on the closet in the Break
## Room. Slots on the left, that slot's cosmetics in the middle (worn, yours, or locked with how to unlock it), and
## your body on the right, slowly turning, trying on whatever you pick (with your mutations' models too). Wear puts
## it on for everyone; Take off empties the slot. Esc or Close shuts it. Spec: docs/systems/cosmetics.md.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const PREVIEW_SIZE: Vector2i = Vector2i(300, 420)
const TURN_SPEED: float = 0.6
const ITEM_SIZE: Vector2 = Vector2(150, 70)
const SLOT_TITLES: Dictionary[StringName, String] = {&"hat": "Hat", &"glasses": "Glasses", &"coat": "Coat",
	&"gloves": "Gloves", &"shoes": "Shoes"}

var _slot: StringName = &"hat"
var _selected: StringName = &""
var _grid: GridContainer
var _info: Label
var _wear: Button
var _slot_buttons: Dictionary[StringName, Button] = {}
var _turntable: Node3D
var _points: Dictionary[StringName, Node3D] = {}


## For tests: which slot is showing, and what is picked.
func get_slot() -> StringName:
	return _slot


func get_selected() -> StringName:
	return _selected


## The item buttons' texts in the middle (tests).
func get_item_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for child: Node in _grid.get_children():
		texts.append((child as Button).text)
	return texts


func get_info() -> String:
	return _info.text


## Shows a slot's cosmetics.
func show_slot(slot: StringName) -> void:
	_slot = slot
	_selected = StringName(str(Cosmetics.get_loadout(Net.local_player_id()).get(String(slot), "")))
	for key: StringName in _slot_buttons:
		_slot_buttons[key].button_pressed = key == slot
	_rebuild_items()
	_rebuild_preview()


## Picks an item (shows it on the body and says what it is).
func pick(cosmetic_id: StringName) -> void:
	_selected = cosmetic_id
	_rebuild_items()
	_rebuild_preview()


## Wear (or take off) the picked item.
func press_wear() -> void:
	if _selected == &"" or not Cosmetics.is_unlocked(_selected):
		return
	if _worn() == _selected:
		Cosmetics.request_unequip(_slot)
	else:
		Cosmetics.request_equip(_selected)
	_rebuild_items()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.06, 0.07, 0.09, 0.92)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	center.add_child(outer)
	var title := HudStyle.label("Title", 32)
	title.text = "Jacket closet"
	outer.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	outer.add_child(row)
	var slots := VBoxContainer.new()
	slots.custom_minimum_size = Vector2(150, 0)
	row.add_child(slots)
	for slot: StringName in CosmeticsService.SLOTS:
		var button := Button.new()
		button.name = "Slot_%s" % slot
		button.text = SLOT_TITLES.get(slot, String(slot).capitalize())
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 40)
		button.pressed.connect(show_slot.bind(slot))
		slots.add_child(button)
		_slot_buttons[slot] = button
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(ITEM_SIZE.x * 3 + 24, 0)
	row.add_child(middle)
	_grid = GridContainer.new()
	_grid.columns = 3
	middle.add_child(_grid)
	_info = HudStyle.label("Info", HudStyle.SMALL_FONT_SIZE)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(ITEM_SIZE.x * 3, 60)
	middle.add_child(_info)
	var right := VBoxContainer.new()
	row.add_child(right)
	right.add_child(_make_preview())
	_wear = Button.new()
	_wear.name = "Wear"
	_wear.custom_minimum_size = Vector2(0, 40)
	_wear.pressed.connect(press_wear)
	right.add_child(_wear)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(UI.close_screen)
	right.add_child(close)
	EventBus.cosmetics_changed.connect(func(player_id: int) -> void:
		if player_id == Net.local_player_id() and is_inside_tree():
			_rebuild_items()
			_rebuild_preview())
	show_slot(_slot)


func _process(delta: float) -> void:
	if _turntable != null:
		_turntable.rotate_y(TURN_SPEED * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		UI.close_screen()


func _worn() -> StringName:
	return StringName(str(Cosmetics.get_loadout(Net.local_player_id()).get(String(_slot), "")))


func _rebuild_items() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var worn: StringName = _worn()
	for data: CosmeticData in Cosmetics.get_all_for_slot(_slot):
		var button := Button.new()
		button.name = String(data.id)
		button.custom_minimum_size = ITEM_SIZE
		var state: String = "worn" if data.id == worn else ("" if Cosmetics.is_unlocked(data.id) else "locked")
		button.text = data.display_name if state.is_empty() else "%s\n(%s)" % [data.display_name, state]
		button.toggle_mode = true
		button.button_pressed = data.id == _selected
		if not Cosmetics.is_unlocked(data.id):
			button.modulate = Color(1, 1, 1, 0.55)
		button.pressed.connect(pick.bind(data.id))
		_grid.add_child(button)
	var picked := ContentRegistry.get_content(_selected) as CosmeticData
	if picked == null:
		_info.text = "Pick something to try it on."
		_wear.text = "Wear"
		_wear.disabled = true
	elif not Cosmetics.is_unlocked(picked.id):
		_info.text = "Locked: %s\n%s" % [picked.display_name, CosmeticsService.describe_unlock(picked)]
		_wear.text = "Locked"
		_wear.disabled = true
	else:
		_info.text = "%s\n%s" % [picked.display_name, picked.description]
		_wear.text = "Take off" if picked.id == worn else "Wear"
		_wear.disabled = false


## A small 3D stage: a grey stand-in for your body on a turntable, lit from the front.
func _make_preview() -> Control:
	var container := SubViewportContainer.new()
	container.name = "Preview"
	container.custom_minimum_size = Vector2(PREVIEW_SIZE)
	container.stretch = true
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	container.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.2, 3.0)
	camera.rotation.x = deg_to_rad(-6.0)
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 20, 0)
	viewport.add_child(light)
	_turntable = Node3D.new()
	viewport.add_child(_turntable)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.72, 0.75)
	capsule.material = material
	body.mesh = capsule
	body.position.y = 0.9
	_turntable.add_child(body)
	# The real body's attach points, so things sit where they do in the game.
	var template := PLAYER_SCENE.instantiate()
	# CHANGED 2026-11-14 (art rollout): the stand-in is the real body model when the player scene has one.
	var real_body := template.get_node_or_null(^"BodyMesh") as MeshInstance3D
	if real_body != null and real_body.mesh != null and not (real_body.mesh is CapsuleMesh):
		body.mesh = real_body.mesh
		body.position.y = 0.0
	var points: Node = template.get_node_or_null(^"AttachPoints")
	if points != null:
		for marker: Node in points.get_children():
			var spot := Node3D.new()
			spot.name = marker.name
			spot.transform = (marker as Node3D).transform
			_turntable.add_child(spot)
			_points[StringName(marker.name)] = spot
	template.free()
	return container


## Dresses the stand-in: what you wear, with the picked item swapped in, plus your mutations' models.
func _rebuild_preview() -> void:
	for spot: Node3D in _points.values():
		for child: Node in spot.get_children():
			spot.remove_child(child)
			child.queue_free()
	var me: int = Net.local_player_id()
	var upgrades: Array[StringName] = Upgrades.get_upgrades(me)
	for upgrade_id: StringName in upgrades:
		var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
		if upgrade == null:
			continue
		for effect: UpgradeEffectData in upgrade.effects:
			var visual := effect as VisualAttachmentEffectData
			if visual != null and visual.scene != null and _points.has(visual.attach_point):
				_points[visual.attach_point].add_child(visual.scene.instantiate())
	var outfit: Dictionary = Cosmetics.get_loadout(me)
	var picked := ContentRegistry.get_content(_selected) as CosmeticData
	if picked != null:
		outfit[String(picked.slot)] = String(picked.id)
	var hidden: PackedStringArray = Upgrades.get_hidden_cosmetic_slots(me)
	for slot: Variant in outfit:
		var data := ContentRegistry.get_content(StringName(str(outfit[slot]))) as CosmeticData
		var point_name: StringName = CosmeticsService.ATTACH_POINTS.get(StringName(str(slot)), &"body")
		if data == null or hidden.has(str(slot)) or not _points.has(point_name):
			continue
		var scene: PackedScene = CosmeticDresser.model_for(data, upgrades)
		if scene != null:
			_points[point_name].add_child(scene.instantiate())
