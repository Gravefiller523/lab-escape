extends "res://systems/player/test/movement_test.gd"
## Playtest level for the HL2 feel work (NEW 2026-10-29). Claude opens it from the editor when a step needs
## a human to play it. The movement test level, plus a course for the feel steps (stairs, a block, a
## ledge) and an on-screen list of what to try, read from playtest_checklist.txt (rewritten for each step).
## F1 hides or shows the list. Everything else (keys, mutation keys 4 to 7, host and join) works as in
## the movement test.

const CHECKLIST_PATH: String = "res://systems/player/test/playtest_checklist.txt"
const COURSE_COLOR: Color = Color(0.5, 0.42, 0.55)

var _checklist: PanelContainer


func _build_world() -> void:
	super._build_world()
	# Stairs going up along +X: 0.2 m steps (walk up) and 0.4 m steps (walk up, just).
	_add_stairs(Vector3(-6, 0, 13), 0.2, 6, "0.2 m stairs")
	_add_stairs(Vector3(-6, 0, 17), 0.4, 4, "0.4 m stairs")
	# A 0.5 m block: too high to walk up, you must jump.
	_add_box(Vector3(6, 0.25, 13), Vector3(2, 0.5, 2), COURSE_COLOR)
	_add_label(Vector3(6, 1.2, 13), "0.5 m block")
	# A 1.4 m ledge: only a crouch-jump gets you up.
	_add_box(Vector3(6, 0.7, 17), Vector3(2, 1.4, 2), COURSE_COLOR)
	_add_label(Vector3(6, 2.1, 17), "1.4 m ledge")
	_add_label(Vector3(-12, 3.6, -4), "3 m drop")
	# A metal floor plate, to hear the footsteps change.
	var plate: StaticBody3D = _add_box(Vector3(0, 0.025, 15), Vector3(4, 0.05, 6), Color(0.55, 0.6, 0.68))
	plate.set_meta(SurfaceType.META_KEY, "metal")
	_add_label(Vector3(0, 1.2, 15), "metal floor")


func _build_ui() -> void:
	super._build_ui()
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_checklist = PanelContainer.new()
	_checklist.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_checklist)
	var text := Label.new()
	text.custom_minimum_size = Vector2(440, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = _read_checklist() + "\n\n(F1 hides this list)"
	_checklist.add_child(text)
	_checklist.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		_checklist.visible = not _checklist.visible
		return
	super._unhandled_key_input(event)


func _read_checklist() -> String:
	if not FileAccess.file_exists(CHECKLIST_PATH):
		return "No playtest checklist yet."
	return FileAccess.get_file_as_string(CHECKLIST_PATH).strip_edges()


## `count` steps of `rise` metres, each 0.5 m deep, going up along +X from `start`.
func _add_stairs(start: Vector3, rise: float, count: int, label: String) -> void:
	for index: int in count:
		var height: float = rise * float(index + 1)
		_add_box(start + Vector3(0.5 * index, height * 0.5, 0), Vector3(0.5, height, 2), COURSE_COLOR)
	_add_label(start + Vector3(0, rise + 0.8, 0), label)


func _add_label(where: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = where
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	add_child(label)
