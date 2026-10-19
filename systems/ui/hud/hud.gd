class_name Hud
extends Control
## The HUD (heads-up display): what's drawn over the game while you play. Built in code with fixed
## node names. Shown only in the game world (game_flow) while you have a body.
##   Crosshair       a dot in the middle of the screen
##   Prompt          "E: Pick up crate" for whatever you look at (InteractionController.get_prompt())
##   HoldBar         fills up while you hold E on a hold-to-use object
##   LiftPanel       what the cargo lift still needs this floor (top right)
##   HealthSlot / InventorySlot   empty spots for the health bar (damage) and inventory bar (inventory)
## Local only: it reads other systems' public APIs. Spec: docs/systems/ui.md.

const LIFT_REFRESH_SECONDS: float = 0.2
const FONT_SIZE: int = 22
const MARGIN: float = 16.0

var _crosshair: ColorRect
var _prompt: Label
var _hold_bar: ProgressBar
var _lift_panel: PanelContainer
var _lift_label: Label
var _lift_left: float = 0.0
## For tests: the controller and lift to read (null = the local player's, CargoLift.current()).
var _controller: InteractionController
var _lift: CargoLift
var _use_test_sources: bool = false


## For tests only: read this controller and this lift instead of the game's.
func use_sources(controller: InteractionController, lift: CargoLift) -> void:
	_controller = controller
	_lift = lift
	_use_test_sources = true


## The prompt on screen now ("" for none).
func get_prompt_text() -> String:
	return _prompt.text


## The lift panel's text ("" when hidden).
func get_lift_text() -> String:
	return _lift_label.text if _lift_panel.visible else ""


## What the lift panel says, from the lift's state. "" = hide the panel.
## `missing` are the display names of the parts still needed.
static func lift_text(needed: int, fixed: int, missing: Array[String], waiting_for_boss: bool, riding: bool,
		in_break_room: bool) -> String:
	if riding or in_break_room:
		return ""
	if waiting_for_boss:
		return "LIFT\nBeat the boss to fix the lift."
	if needed <= 0 or missing.is_empty():
		return "LIFT FIXED\nEveryone in, then press Go."
	var lines: Array[String] = ["LIFT PARTS %d/%d" % [fixed, needed]]
	for part_name: String in missing:
		lines.append("- %s" % part_name)
	return "\n".join(lines)


func _ready() -> void:
	name = "Hud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_crosshair = ColorRect.new()
	_crosshair.name = "Crosshair"
	_crosshair.color = Color(1, 1, 1, 0.8)
	_crosshair.size = Vector2(6, 6)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-3, -3)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_prompt = _outlined_label("Prompt")
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-300, 30)
	_prompt.size = Vector2(600, 32)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)

	_hold_bar = ProgressBar.new()
	_hold_bar.name = "HoldBar"
	_hold_bar.set_anchors_preset(Control.PRESET_CENTER)
	_hold_bar.position = Vector2(-60, 66)
	_hold_bar.size = Vector2(120, 8)
	_hold_bar.max_value = 1.0
	_hold_bar.show_percentage = false
	_hold_bar.visible = false
	_hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hold_bar)

	_lift_panel = PanelContainer.new()
	_lift_panel.name = "LiftPanel"
	# Pinned to the top-right corner; it grows to the left and down to fit its text.
	_lift_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lift_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_lift_panel.offset_left = -MARGIN
	_lift_panel.offset_right = -MARGIN
	_lift_panel.offset_top = MARGIN
	_lift_panel.offset_bottom = MARGIN
	_lift_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lift_panel.visible = false
	_lift_label = _outlined_label("LiftLabel")
	_lift_panel.add_child(_lift_label)
	add_child(_lift_panel)

	# Empty spots, so damage and inventory only add their widget here.
	var spots: Dictionary[String, Control.LayoutPreset] = {
		"HealthSlot": Control.PRESET_BOTTOM_LEFT, "InventorySlot": Control.PRESET_CENTER_BOTTOM}
	for spot_name: String in spots:
		var spot := Control.new()
		spot.name = spot_name
		spot.set_anchors_preset(spots[spot_name])
		spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(spot)


func _process(delta: float) -> void:
	var controller: InteractionController = _controller if _use_test_sources else Interaction.get_local_controller()
	# Only in the game world: other systems' test scenes draw their own prompt.
	visible = _use_test_sources or (controller != null and GameWorld.current() != null)
	if not visible:
		return
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var hold: float = controller.get_hold_progress() if controller != null else 0.0
	_hold_bar.visible = hold > 0.0
	_hold_bar.value = hold

	_lift_left -= delta
	if _lift_left <= 0.0:
		_lift_left = LIFT_REFRESH_SECONDS
		_refresh_lift()


func _refresh_lift() -> void:
	var lift: CargoLift = _lift if _use_test_sources else CargoLift.current()
	var text: String = ""
	if lift != null:
		var missing: Array[String] = []
		for slot: StringName in lift.get_broken_slots():
			var part: PropData = lift.get_slot_part(slot)
			missing.append(part.display_name if part != null else String(slot))
		text = lift_text(lift.get_parts_needed(), lift.get_parts_delivered(), missing,
			lift.depart_blocker() == CargoLift.MSG_BOSS,  # the boss check comes first, so it works on every PC
			lift.is_riding(), lift.is_in_break_room())
	_lift_label.text = text
	_lift_panel.visible = not text.is_empty()


func _outlined_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
