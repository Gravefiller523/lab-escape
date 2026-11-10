class_name FloorMapView
extends Control
## NEW 2026-10-31 (floor generation step 3): draws a floor layout from above, from the plan (not a camera):
## main hallways dark and thick, secondary hallways lighter, rooms coloured by wing, the elevator yellow,
## the welcome center teal, loops as magenta lines, wing names, and players as arrows. NEW 2026-11-09: broken
## lift parts as numbered orange diamonds with their carry paths back to the elevator. Used by the F3
## overlay and the floorgen viewer test scene. Mouse wheel (or zoom_by) zooms.

const ELEVATOR_COLOR: Color = Color(0.95, 0.8, 0.2)
const WELCOME_COLOR: Color = Color(0.25, 0.65, 0.65)
const MAIN_HALL_COLOR: Color = Color(0.32, 0.36, 0.45)
const SECONDARY_HALL_COLOR: Color = Color(0.5, 0.54, 0.62)
const LOOP_COLOR: Color = Color(1.0, 0.3, 0.85)
const OUTLINE_COLOR: Color = Color(0.08, 0.08, 0.1)
const PLAYER_COLOR: Color = Color(1.0, 1.0, 1.0)
## NEW 2026-10-31 (step 4b): rooms filled by damage level (pristine, light, heavy, destroyed); the incident star.
const DAMAGE_COLORS: Array[Color] = [Color(0.35, 0.62, 0.4), Color(0.85, 0.8, 0.3), Color(0.92, 0.5, 0.18), Color(0.85, 0.15, 0.12)]
const ORIGIN_COLOR: Color = Color(1.0, 0.95, 0.4)
## NEW 2026-10-31: the smaller incidents' stars.
const MINOR_ORIGIN_COLOR: Color = Color(1.0, 0.65, 0.3)
## NEW 2026-11-09 (step 4d): broken lift parts (numbered diamonds) and their carry paths.
const PART_COLOR: Color = Color(1.0, 0.55, 0.1)
const PART_PATH_COLOR: Color = Color(1.0, 0.6, 0.2, 0.7)
## NEW 2026-11-10 (step 4e): the map styles, the security style's colours, and camera icons.
const STYLE_DEBUG: StringName = &"debug"
const STYLE_SECURITY: StringName = &"security"
const SECURITY_BACKGROUND: Color = Color(0.02, 0.04, 0.05)
const SECURITY_ROOM_FILL: Color = Color(0.04, 0.08, 0.09)
const CAMERA_COLOR: Color = Color(0.85, 0.9, 1.0)

var layout: FloorLayout:
	set(value):
		layout = value
		queue_redraw()
## Players to draw: {"position": Vector3 in the floor's own space (metres), "facing": Vector3, "color": Color}.
var players: Array[Dictionary] = []:
	set(value):
		players = value
		queue_redraw()
## NEW 2026-11-10 (step 4e): "debug" (the F3 view) or "security" (the security room's map table: a dark screen,
## rooms outlined in accent_color, small room names, the elevator, locked and blocked doors; no damage, parts,
## key spots or players: the security system draws its own dots and blinking wings on top).
var style: StringName = STYLE_DEBUG:
	set(value):
		style = value
		queue_redraw()
var accent_color: Color = Color(0.3, 0.9, 0.75):
	set(value):
		accent_color = value
		queue_redraw()
## NEW 2026-11-10 (step 4e): security cameras to draw (F3 view): {"position": Vector3 in the floor's own space
## (metres), "broken": bool}.
var cameras: Array[Dictionary] = []:
	set(value):
		cameras = value
		queue_redraw()
var zoom: float = 1.0:
	set(value):
		zoom = clampf(value, 0.3, 6.0)
		queue_redraw()


func zoom_by(factor: float) -> void:
	zoom *= factor


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15)
			accept_event()


func _draw() -> void:
	if layout == null or layout.placements.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(20, 40), "No floor to show.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		return
	var unit: float = layout.cell_size()
	var rects: Array[Rect2] = []
	for index: int in layout.placements.size():
		rects.append(_cell_rect(index, unit))
	var fit: Array = _fit()
	var scale_fit: float = fit[0]
	var offset: Vector2 = fit[1]
	var to_screen := func(cells: Vector2) -> Vector2: return offset + cells * scale_fit
	if style == STYLE_SECURITY:
		_draw_security(rects, to_screen, scale_fit, unit)
		return
	for index: int in rects.size():
		var screen := Rect2(to_screen.call(rects[index].position), rects[index].size * scale_fit)
		draw_rect(screen, _color_of(index))
		draw_rect(screen, OUTLINE_COLOR, false, 1.0)
	_draw_room_names(rects, to_screen, scale_fit)
	for pair: Vector2i in layout.loops:
		if pair.x < rects.size() and pair.y < rects.size():
			draw_line(to_screen.call(rects[pair.x].get_center()), to_screen.call(rects[pair.y].get_center()), LOOP_COLOR, 3.0)
	_draw_wing_names(rects, to_screen)
	_draw_damage_marks(rects, to_screen, scale_fit)
	_draw_doors(rects, to_screen, unit)
	_draw_parts(rects, to_screen)
	_draw_cameras(to_screen, unit)
	for player: Dictionary in players:
		var at: Vector3 = player["position"]
		var facing: Vector3 = player["facing"]
		var tip: Vector2 = to_screen.call(Vector2(at.x, at.z) / unit)
		var forward := Vector2(facing.x, facing.z).normalized()
		if forward == Vector2.ZERO:
			forward = Vector2.UP
		var side := Vector2(-forward.y, forward.x)
		var color: Color = player.get("color", PLAYER_COLOR)
		draw_colored_polygon(PackedVector2Array([tip + forward * 10.0, tip - forward * 6.0 + side * 6.0,
			tip - forward * 6.0 - side * 6.0]), color)



## NEW 2026-10-31 (step 4a): each room's name (its room type in the department) in rooms big enough to hold it.
func _draw_room_names(rects: Array[Rect2], to_screen: Callable, scale_fit: float) -> void:
	var department := ContentRegistry.get_content(layout.department_id) as DepartmentData
	var font: Font = ThemeDB.fallback_font
	for index: int in rects.size():
		var room := ContentRegistry.get_content(layout.placements[index].room_id) as RoomData
		if room == null or room.tile_role != TileStandards.ROLE_ROOM or rects[index].size.x * scale_fit < 50.0:
			continue
		var text: String = LevelService.room_display_name(room, department)
		var at: Vector2 = to_screen.call(rects[index].get_center()) - Vector2(rects[index].size.x * scale_fit / 2.0 - 4.0, 0)
		var width: float = rects[index].size.x * scale_fit - 8.0
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 11, OUTLINE_COLOR)

## A placement's footprint in grid cells (x, z), as a rectangle.
func _cell_rect(index: int, unit: float) -> Rect2:
	var placement: RoomPlacement = layout.placements[index]
	var room := ContentRegistry.get_content(placement.room_id) as RoomData
	var footprint := Vector2i.ONE
	if room != null:
		footprint = RoomShape.of(room, unit).rotated_size(placement.rotation_steps)
	return Rect2(Vector2(placement.cell.x, placement.cell.z), Vector2(footprint))


func _color_of(index: int) -> Color:
	var placement: RoomPlacement = layout.placements[index]
	var room := ContentRegistry.get_content(placement.room_id) as RoomData
	if room == null:
		return Color.MAGENTA
	if room.room_kind == &"lift":
		return ELEVATOR_COLOR
	var damaged: bool = index < layout.damage.size()
	var damage_color: Color = DAMAGE_COLORS[mini(layout.damage[index], 3)] if damaged else Color.WHITE
	match room.tile_role:
		TileStandards.ROLE_TEMPLATE:
			return WELCOME_COLOR.lerp(damage_color, 0.35) if damaged else WELCOME_COLOR
		TileStandards.ROLE_MAIN_HALL:
			return MAIN_HALL_COLOR.lerp(damage_color, 0.35) if damaged else MAIN_HALL_COLOR
		TileStandards.ROLE_SECONDARY_HALL:
			if damaged:
				return SECONDARY_HALL_COLOR.lerp(damage_color, 0.45)
			return SECONDARY_HALL_COLOR.lerp(_wing_color(placement.wing), 0.25)
	return damage_color if damaged else _wing_color(placement.wing)


func _wing_color(wing: int) -> Color:
	if wing < 0:
		return Color(0.6, 0.6, 0.6)
	return Color.from_hsv(fmod(float(wing) * 0.618034, 1.0), 0.55, 0.85)


func _draw_wing_names(rects: Array[Rect2], to_screen: Callable) -> void:
	var sums: Dictionary[int, Vector2] = {}
	var counts: Dictionary[int, int] = {}
	for index: int in rects.size():
		var wing: int = layout.placements[index].wing
		if wing < 0:
			continue
		sums[wing] = sums.get(wing, Vector2.ZERO) + rects[index].get_center()
		counts[wing] = counts.get(wing, 0) + 1
	var font: Font = ThemeDB.fallback_font
	for wing: int in sums:
		if wing >= layout.wings.size():
			continue
		var at: Vector2 = to_screen.call(sums[wing] / float(counts[wing]))
		var text: String = layout.wings[wing]
		draw_string_outline(font, at - Vector2(40, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, OUTLINE_COLOR)
		draw_string(font, at - Vector2(40, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## NEW 2026-10-31 (step 4b): a star where the incident started (smaller orange stars for the smaller incidents)
## and an X over collapsed hallway pieces.
func _draw_damage_marks(rects: Array[Rect2], to_screen: Callable, scale_fit: float) -> void:
	for index: int in layout.collapsed:
		if index < rects.size():
			var screen := Rect2(to_screen.call(rects[index].position), rects[index].size * scale_fit)
			draw_line(screen.position, screen.end, OUTLINE_COLOR, 3.0)
			draw_line(Vector2(screen.end.x, screen.position.y), Vector2(screen.position.x, screen.end.y), OUTLINE_COLOR, 3.0)
	for index: int in layout.minor_origins:
		if index < rects.size():
			_draw_star(to_screen.call(rects[index].get_center()), 9.0, MINOR_ORIGIN_COLOR)
	if layout.origin >= 0 and layout.origin < rects.size():
		_draw_star(to_screen.call(rects[layout.origin].get_center()), 14.0, ORIGIN_COLOR)


func _draw_star(centre: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for point: int in 10:
		var reach: float = radius if point % 2 == 0 else radius * 0.43
		var angle: float = -PI / 2.0 + float(point) * PI / 5.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * reach)
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, OUTLINE_COLOR, 1.5)


## NEW 2026-10-31 (step 4c): locked and blocked doors as small squares (keycard doors in their card's colour,
## grey = pry with a crowbar, cyan = power, brown = debris), each with a line to what opens it.
## CHANGED 2026-11-10: show_items false (the security map) leaves out the lines to where keys and tools are.
func _draw_doors(rects: Array[Rect2], to_screen: Callable, unit: float, show_items: bool = true) -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	var colours: Array[StringName] = tuning.keycard_colours.keys()
	var spots: Array[Vector2] = []
	for index: int in layout.doors.size():
		var door: Array = layout.doors[index]
		var at: Vector2 = _door_cells(door, unit)
		spots.append(at)
		var type: int = door[3]
		var color := Color.TRANSPARENT
		match type:
			FloorGenerator.DOOR_KEYCARD:
				color = tuning.keycard_colours[colours[clampi(door[4], 0, colours.size() - 1)]]
			FloorGenerator.DOOR_PRY:
				color = Color(0.7, 0.7, 0.72)
			FloorGenerator.DOOR_POWER:
				color = Color(0.3, 0.85, 1.0)
			FloorGenerator.DOOR_DEBRIS:
				color = Color(0.55, 0.4, 0.25)
		if color.a == 0.0:
			continue
		var screen: Vector2 = to_screen.call(at)
		draw_rect(Rect2(screen - Vector2(5, 5), Vector2(10, 10)), color)
		draw_rect(Rect2(screen - Vector2(5, 5), Vector2(10, 10)), OUTLINE_COLOR, false, 1.0)
	if not show_items:
		return
	for item: Array in layout.door_items:
		var door_index: int = item[2]
		var room: int = str(item[1]).get_slice("/", 0).to_int()
		if door_index >= spots.size() or room >= rects.size():
			continue
		var line_color := Color(0.85, 0.85, 0.85, 0.8)
		if str(item[0]).begins_with("keycard_"):
			line_color = tuning.keycard_colours.get(StringName(str(item[0]).trim_prefix("keycard_")), line_color)
		draw_line(to_screen.call(rects[room].get_center()), to_screen.call(spots[door_index]), line_color, 2.0)
		draw_circle(to_screen.call(rects[room].get_center()), 4.0, line_color)


## Where a door is, in grid cells (the middle of its doorway).
func _door_cells(door: Array, unit: float) -> Vector2:
	var placement: RoomPlacement = layout.placements[door[0]]
	var room := ContentRegistry.get_content(placement.room_id) as RoomData
	for doorway: Dictionary in RoomShape.of(room, unit).rotated_doorways(placement.rotation_steps):
		if doorway["name"] == str(door[1]):
			var cell: Vector2i = doorway["cell"]
			var dir: Vector2i = doorway["dir"]
			return Vector2(placement.cell.x, placement.cell.z) + Vector2(cell) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
	return Vector2(placement.cell.x, placement.cell.z)


## NEW 2026-11-09 (step 4d): the broken lift parts as numbered diamonds in their rooms, each with its carry
## path back to the elevator.
func _draw_parts(rects: Array[Rect2], to_screen: Callable) -> void:
	for index: int in layout.lift_parts.size():
		var room: int = layout.lift_parts[index][2]
		if room >= rects.size():
			continue
		if index < layout.lift_part_paths.size():
			var points := PackedVector2Array()
			for step: int in layout.lift_part_paths[index]:
				if step < rects.size():
					points.append(to_screen.call(rects[step].get_center()))
			if points.size() >= 2:
				draw_polyline(points, PART_PATH_COLOR, 2.0)
		var at: Vector2 = to_screen.call(rects[room].get_center())
		var diamond := PackedVector2Array([at + Vector2(0, -9), at + Vector2(9, 0), at + Vector2(0, 9), at + Vector2(-9, 0)])
		draw_colored_polygon(diamond, PART_COLOR)
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), OUTLINE_COLOR, 1.5)
		draw_string(ThemeDB.fallback_font, at + Vector2(-4, 5), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			OUTLINE_COLOR)


## NEW 2026-11-10 (step 4e): where a point of the floor (in grid cells) is drawn on this control.
func cells_to_screen(cells: Vector2) -> Vector2:
	var fit: Array = _fit()
	return (fit[1] as Vector2) + cells * float(fit[0])


## NEW 2026-11-10 (step 4e): where a placement (FloorLayout.placements index) is drawn on this control.
func room_screen_rect(index: int) -> Rect2:
	if layout == null or index < 0 or index >= layout.placements.size():
		return Rect2()
	var rect: Rect2 = _cell_rect(index, layout.cell_size())
	var fit: Array = _fit()
	return Rect2(cells_to_screen(rect.position), rect.size * float(fit[0]))


## [scale (pixels per cell), offset (pixels)] that fit the whole floor in the control (with zoom).
func _fit() -> Array:
	var unit: float = layout.cell_size()
	var bounds := Rect2()
	for index: int in layout.placements.size():
		var rect: Rect2 = _cell_rect(index, unit)
		bounds = rect if index == 0 else bounds.merge(rect)
	var scale_fit: float = minf(size.x / maxf(bounds.size.x, 1.0), size.y / maxf(bounds.size.y, 1.0)) * 0.9 * zoom
	return [scale_fit, size / 2.0 - (bounds.position + bounds.size / 2.0) * scale_fit]


## NEW 2026-11-10 (step 4e): the security room's map: a dark screen, rooms outlined in the accent colour
## (hallways filled a little), the elevator, small room names and the locked and blocked doors.
func _draw_security(rects: Array[Rect2], to_screen: Callable, scale_fit: float, unit: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SECURITY_BACKGROUND)
	for index: int in rects.size():
		var screen := Rect2(to_screen.call(rects[index].position), rects[index].size * scale_fit)
		var room := ContentRegistry.get_content(layout.placements[index].room_id) as RoomData
		var fill: Color = SECURITY_ROOM_FILL
		if room != null and room.room_kind == &"lift":
			fill = ELEVATOR_COLOR.darkened(0.3)
		elif room != null and room.tile_role != TileStandards.ROLE_ROOM:
			fill = SECURITY_ROOM_FILL.lerp(accent_color, 0.12)
		draw_rect(screen.grow(-1.0), fill)
		draw_rect(screen.grow(-1.0), accent_color.darkened(0.2), false, 1.5)
	var department := ContentRegistry.get_content(layout.department_id) as DepartmentData
	var font: Font = ThemeDB.fallback_font
	for index: int in rects.size():
		var room := ContentRegistry.get_content(layout.placements[index].room_id) as RoomData
		if room == null or room.tile_role != TileStandards.ROLE_ROOM or rects[index].size.x * scale_fit < 40.0:
			continue
		var width: float = rects[index].size.x * scale_fit - 6.0
		var at: Vector2 = to_screen.call(rects[index].get_center()) - Vector2(width / 2.0, -4.0)
		draw_string(font, at, LevelService.room_display_name(room, department).to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
			width, 10, accent_color.lightened(0.3))
	_draw_doors(rects, to_screen, unit, false)


## NEW 2026-11-10 (step 4e): security cameras as small squares with a lens (red cross when broken).
func _draw_cameras(to_screen: Callable, unit: float) -> void:
	for camera: Dictionary in cameras:
		var at3: Vector3 = camera["position"]
		var at: Vector2 = to_screen.call(Vector2(at3.x, at3.z) / unit)
		draw_rect(Rect2(at - Vector2(5, 4), Vector2(10, 8)), CAMERA_COLOR)
		draw_circle(at + Vector2(6, 0), 2.5, CAMERA_COLOR)
		if camera.get("broken", false):
			draw_line(at - Vector2(6, 6), at + Vector2(6, 6), Color(1, 0.2, 0.15), 2.0)
			draw_line(at + Vector2(-6, 6), at + Vector2(6, -6), Color(1, 0.2, 0.15), 2.0)
