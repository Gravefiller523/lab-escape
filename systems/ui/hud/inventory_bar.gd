class_name InventoryBar
extends VBoxContainer
## Your inventory slots (bottom middle of the HUD), one box per slot the inventory has (2 to start, more from
## upgrades), with what's in your hands named above them. NEW 2026-11-11 (roadmap WP5). Reads the local body's
## InventoryComponent (inventory). Spec: docs/systems/ui.md.

const SLOT_SIZE: Vector2 = Vector2(78, 64)

var _held: Label
var _slots: HBoxContainer
## What the bar shows now, so it's only rebuilt when something changes.
var _shown: String = ""
var _body: Node
var _use_test_body: bool = false


## For tests only: show this body's inventory instead of the local player's.
func use_body(body: Node) -> void:
	_body = body
	_use_test_body = true


## The name above the slots ("Crowbar", "Fists", "Energy drink (2 uses)").
func get_held_text() -> String:
	return _held.text if visible else ""


## One text per slot box, e.g. ["1\nCrowbar", "2\n"]. The selected one starts with ">".
func get_slot_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for box: Node in _slots.get_children():
		var text: String = (box.get_node(^"Text") as Label).text
		texts.append((">" if box.has_meta(&"selected") else "") + text)
	return texts


func _ready() -> void:
	name = "InventoryBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_held = HudStyle.label("Held")
	_held.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_held)
	_slots = HBoxContainer.new()
	_slots.name = "Slots"
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 6)
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots)


func _process(_delta: float) -> void:
	var body: Node = _body if _use_test_body else PlayerCharacter.find(Net.local_player_id())
	var inventory: InventoryComponent = InventoryComponent.of(body) if body != null and is_instance_valid(body) else null
	var health: HealthComponent = HealthComponent.of(body) if inventory != null else null
	visible = inventory != null and (health == null or not health.is_dead())
	if not visible:
		return
	var texts := PackedStringArray()
	for index: int in inventory.get_slot_count():
		texts.append(_slot_text(index, inventory.get_slot(index)))
	var selected: int = -1 if inventory.is_holstered() else inventory.get_active_index()
	var held: String = _held_text(inventory)
	var shown: String = "%s|%d|%s" % ["/".join(texts), selected, held]
	if shown == _shown:
		return
	_shown = shown
	_held.text = held
	for child: Node in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	for index: int in texts.size():
		_slots.add_child(_slot_box(texts[index], index == selected))


static func _item_name(item_id: StringName) -> String:
	var data: ContentData = ContentRegistry.get_content(item_id)
	return data.display_name if data != null and not data.display_name.is_empty() else String(item_id).capitalize()


static func _slot_text(index: int, slot: InventorySlot) -> String:
	if slot == null:
		return "%d\n" % (index + 1)
	var text: String = "%d\n%s" % [index + 1, _item_name(slot.item_id)]
	if slot.count > 1:
		text += " x%d" % slot.count
	return text


static func _held_text(inventory: InventoryComponent) -> String:
	var item_id: StringName = inventory.get_active_item_id()
	var text: String = _item_name(item_id)
	var slot: InventorySlot = null if inventory.is_using_fists() else inventory.get_slot(inventory.get_active_index())
	if slot != null and slot.uses_left > 0:
		text += " (%d %s)" % [slot.uses_left, "use" if slot.uses_left == 1 else "uses"]
	return text


func _slot_box(text: String, selected: bool) -> PanelContainer:
	var box: PanelContainer = HudStyle.panel("Slot")
	box.custom_minimum_size = SLOT_SIZE
	if selected:
		box.add_theme_stylebox_override("panel", HudStyle.panel_box(HudStyle.ACCENT, 3))
		box.set_meta(&"selected", true)
	var label: Label = HudStyle.label("Text", HudStyle.SMALL_FONT_SIZE)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = SLOT_SIZE - Vector2(16, 16)
	box.add_child(label)
	return box
