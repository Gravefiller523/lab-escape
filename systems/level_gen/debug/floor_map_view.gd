class_name FloorMapView
extends Control
## NEW 2026-10-31 (floor generation step 3): draws a floor layout from above, from the plan (not a camera):
## main hallways dark and thick, secondary hallways lighter, rooms coloured by wing, the elevator yellow,
## the welcome center teal, loops as magenta lines, wing names, and players as arrows. Used by the F8
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

var layout: FloorLayout:
	set(value):
		layout = value
		queue_redraw()
## Players to draw: {"position": Vector3 in the floor's own space (metres), "facing": Vector3, "color": Color}.
var players: Array[Dictionary] = []:
	set(value):
		players = value
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
	var bounds := Rect2()
	for index: int in layout.placements.size():
		var rect: Rect2 = _cell_rect(index, unit)
		rects.append(rect)
		bounds = rect if index == 0 else bounds.merge(rect)
	var scale_fit: float = minf(size.x / maxf(bounds.size.x, 1.0), size.y / maxf(bounds.size.y, 1.0)) * 0.9 * zoom
	var offset: Vector2 = size / 2.0 - (bounds.position + bounds.size / 2.0) * scale_fit
	var to_screen := func(cells: Vector2) -> Vector2: return offset + cells * scale_fit
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


## NEW 2026-10-31 (step 4b): a star where the incident started and an X over collapsed hallway pieces.
func _draw_damage_marks(rects: Array[Rect2], to_screen: Callable, scale_fit: float) -> void:
	for index: int in layout.collapsed:
		if index < rects.size():
			var screen := Rect2(to_screen.call(rects[index].position), rects[index].size * scale_fit)
			draw_line(screen.position, screen.end, OUTLINE_COLOR, 3.0)
			draw_line(Vector2(screen.end.x, screen.position.y), Vector2(screen.position.x, screen.end.y), OUTLINE_COLOR, 3.0)
	if layout.origin < 0 or layout.origin >= rects.size():
		return
	var centre: Vector2 = to_screen.call(rects[layout.origin].get_center())
	var points := PackedVector2Array()
	for point: int in 10:
		var radius: float = 14.0 if point % 2 == 0 else 6.0
		var angle: float = -PI / 2.0 + float(point) * PI / 5.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, ORIGIN_COLOR)
	points.append(points[0])
	draw_polyline(points, OUTLINE_COLOR, 1.5)
