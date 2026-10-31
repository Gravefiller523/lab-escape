class_name FloorgenOverlay
extends CanvasLayer
## NEW 2026-10-31 (floor generation step 3): the F8 debug view. The floor from above (FloorMapView) with
## your position, the seed in the corner ("seed 1837261 / attempt 2 / floor 4 department_robotics"), a seed
## box (host: type a seed, press Go, the same floor comes back), and the end of the generation log.
## Level owns it: F8 shows and hides it, F9 (host) makes a new floor. Esc frees the mouse to click the box.

## Asks Level to rebuild this floor with a seed (host only).
signal seed_entered(floor_seed: int)

const LOG_LINES_SHOWN: int = 14

var _map: FloorMapView
var _title: Label
var _seed_box: LineEdit
var _log: Label
var _refresh_left: float = 0.0


func _ready() -> void:
	layer = 60
	visible = false
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.06, 0.08, 0.88)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_map = FloorMapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.offset_left = 20
	_map.offset_top = 60
	_map.offset_right = -20
	_map.offset_bottom = -20
	add_child(_map)
	var column := VBoxContainer.new()
	column.position = Vector2(16, 10)
	add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	column.add_child(_title)
	var row := HBoxContainer.new()
	column.add_child(row)
	var hint := Label.new()
	hint.text = "F8 close   F9 new floor (host)   wheel zoom   seed:"
	row.add_child(hint)
	_seed_box = LineEdit.new()
	_seed_box.custom_minimum_size = Vector2(140, 0)
	_seed_box.placeholder_text = "floor seed"
	_seed_box.text_submitted.connect(func(_text: String) -> void: _submit())
	row.add_child(_seed_box)
	var go := Button.new()
	go.text = "Go"
	go.pressed.connect(_submit)
	row.add_child(go)
	_log = Label.new()
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	_log.add_theme_font_size_override("font_size", 12)
	_log.modulate = Color(0.8, 0.85, 0.9)
	add_child(_log)


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


## Draws the current floor again (and your position).
func refresh() -> void:
	var layout: FloorLayout = Level.get_layout()
	_map.layout = layout
	if layout == null:
		_title.text = "No floor (start a run)."
		_log.text = ""
		return
	_title.text = "seed %d / attempt %d / floor %d %s%s   (%d tiles, %d wings, %d loops)" % [layout.floor_seed,
		layout.attempt, layout.floor_number, layout.department_id, "  FALLBACK FLOOR" if layout.is_fallback else "",
		layout.placements.size(), layout.wings.size(), layout.loops.size()]
	var lines: PackedStringArray = layout.log_lines
	if lines.is_empty():
		_log.text = "(the generation log is on the host; `floorgen log` in the console)"
	else:
		var start: int = maxi(lines.size() - LOG_LINES_SHOWN, 0)
		_log.text = "\n".join(lines.slice(start))
	_map.players = _player_arrows()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.2
		_map.players = _player_arrows()


func _input(event: InputEvent) -> void:
	# Zoom with the wheel even while the mouse is captured by the player.
	var button := event as InputEventMouseButton
	if visible and button != null and button.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_map.zoom_by(1.15)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_map.zoom_by(1.0 / 1.15)
			get_viewport().set_input_as_handled()


func _submit() -> void:
	var text: String = _seed_box.text.strip_edges()
	if text.is_valid_int() and text.to_int() != 0:
		seed_entered.emit(text.to_int())
		_seed_box.release_focus()


## Every player body as an arrow, in the floor's own space.
func _player_arrows() -> Array[Dictionary]:
	var arrows: Array[Dictionary] = []
	var to_floor: Transform3D = Level.get_floor_transform().affine_inverse()
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body == null:
			continue
		var facing: Vector3 = to_floor.basis * body.get_aim_direction()
		arrows.append({"position": to_floor * body.global_position, "facing": facing,
			"color": Color(0.4, 1.0, 0.5) if body.is_local() else Color.WHITE})
	return arrows
