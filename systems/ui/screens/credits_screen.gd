extends Control
## The credits roll (NEW 2026-11-13, roadmap WP19, mock-up approved by Zachary): words from res://config/credits.tres
## scroll up over a dark screen, then Godot's own licence notices in small type. It scrolls so the whole roll
## takes Config.game.credits_seconds; Esc, Space or a click skips it (only on your PC: the lift still goes back down
## when the host's credits time is up). Spec: docs/systems/ui.md.

const CREDITS_PATH: String = "res://config/credits.tres"
const HEADING_SIZE: int = 40
const LINE_SIZE: int = 26
const SMALL_SIZE: int = 14
const TOP_GAP: float = 40.0

var _scroll: VBoxContainer
var _speed: float = 60.0
var _finished: bool = false
var _test_mode: bool = false
## Opened at the end of a run (it stops when the run summary is over).
var _from_summary: bool = false


## For tests only: keep rolling whatever game_flow's state.
func keep_rolling() -> void:
	_test_mode = true


## Every line the roll shows (tests).
func get_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for child: Node in _scroll.get_children():
		var label := child as Label
		if label != null:
			lines.append(label.text)
	return lines


func is_finished() -> bool:
	return _finished


func _ready() -> void:
	_from_summary = GameFlow.get_state() == GameFlowService.State.RUN_SUMMARY
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.03, 0.03, 0.05, 0.96)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_scroll = VBoxContainer.new()
	_scroll.name = "Roll"
	_scroll.add_theme_constant_override("separation", 6)
	add_child(_scroll)
	var credits := load(CREDITS_PATH) as CreditsData
	for line: String in (credits.text if credits != null else "LAB ESCAPE").split("\n"):
		if line.begins_with("# "):
			_add(line.trim_prefix("# "), HEADING_SIZE, HudStyle.ACCENT)
		else:
			_add(line, LINE_SIZE, Color.WHITE)
	_add("", LINE_SIZE, Color.WHITE)
	_add("Godot Engine licence", LINE_SIZE, HudStyle.MUTED)
	for line: String in Engine.get_license_text().split("\n"):
		_add(line, SMALL_SIZE, HudStyle.MUTED)
	_add("", LINE_SIZE, Color.WHITE)
	_add("Third-party parts of Godot", LINE_SIZE, HudStyle.MUTED)
	for info: Dictionary in Engine.get_copyright_info():
		_add(str(info.get("name", "")), SMALL_SIZE, HudStyle.MUTED)
	_layout.call_deferred()


func _layout() -> void:
	var view: Vector2 = get_viewport_rect().size
	_scroll.size = Vector2(view.x * 0.8, 0.0)
	_scroll.position = Vector2(view.x * 0.1, view.y + TOP_GAP)
	# The whole roll (its own height plus one screen) passes in credits_seconds.
	var height: float = _scroll.get_combined_minimum_size().y
	_speed = (height + view.y + TOP_GAP) / maxf(Config.game.credits_seconds, 1.0)


func _add(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(label)


func _process(delta: float) -> void:
	if _finished:
		return
	# The lift went back down (or the run is over some other way): the roll stops.
	if _from_summary and GameFlow.get_state() != GameFlowService.State.RUN_SUMMARY and not _test_mode:
		_finish()
		return
	_scroll.position.y -= _speed * delta
	if _scroll.position.y + _scroll.size.y < 0.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	var skip: bool = event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_accept")
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed:
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if UI.get_open_screen() == UIService.SCREEN_CREDITS:
		UI.close_screen()
