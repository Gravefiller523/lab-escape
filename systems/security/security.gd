class_name SecurityService
extends Node
## Autoload "Security". NEW 2026-11-10 (floor generation step 4e, plan section 7): the welcome center's
## security room. When a generated floor is built (on every PC, while the lift rides), it puts the map table on
## the security_map marker and a monitor with Prev and Next buttons on each security_monitor marker (up to
## Config.floor_gen.security_monitors). Then, while the local player is within feed_active_radius of the room,
## it moves the map's dots and blinking part wings map_updates_per_second times a second and redraws the camera
## feeds feed_updates_per_second times a second; otherwise nothing redraws. The cameras come from the floor plan
## (FloorLayout.cameras), so every PC shows the same ones. Spec: docs/systems/security.md.

var _table: SecurityMapTable
var _monitors: Array[SecurityMonitor] = []
var _anchor: Node3D
var _map_left: float = 0.0
var _feed_left: float = 0.0
var _map_elapsed: float = 0.0
var _near: bool = false


func _ready() -> void:
	Level.floor_built.connect(_on_floor_built)


## The map table on this floor, or null.
func get_map_table() -> SecurityMapTable:
	return _table if _table != null and is_instance_valid(_table) else null


## The monitors on this floor, in marker order.
func get_monitors() -> Array[SecurityMonitor]:
	var found: Array[SecurityMonitor] = []
	for monitor: SecurityMonitor in _monitors:
		if is_instance_valid(monitor):
			found.append(monitor)
	return found


## Is the local player near enough to the security room for its screens to draw?
func is_anyone_near() -> bool:
	return _near


## Every PC: the floor's rooms (placement indexes) to blink on the map: the wing (or, outside the wings, the
## tile) each broken lift part is in now, so it follows a part someone carries off. Parts already slotted into
## the lift are gone, so their wings stop.
func part_highlight_rooms() -> Array[int]:
	var found: Array[int] = []
	var layout: FloorLayout = Level.get_layout()
	var lift: CargoLift = CargoLift.current()
	if layout == null or lift == null:
		return found
	var rooms: Dictionary[int, bool] = {}
	for slot: StringName in lift.get_broken_slots():
		var part: PropData = lift.get_slot_part(slot)
		if part == null:
			continue
		for prop: NetProp in Props.get_props(part.id):
			var index: int = Level.get_room_index_for_position(prop.global_position)
			if index < 0:
				continue
			var wing: int = layout.placements[index].wing
			if wing < 0:
				rooms[index] = true
				continue
			for other: int in layout.placements.size():
				if layout.placements[other].wing == wing:
					rooms[other] = true
	found.assign(rooms.keys())
	found.sort()
	return found


## Every PC: every player's dot for the map: {"cells": where (grid cells), "color"} (colours by join order).
func player_dots() -> Array[Dictionary]:
	var dots: Array[Dictionary] = []
	var layout: FloorLayout = Level.get_layout()
	if layout == null:
		return dots
	var tuning: FloorGenTuning = Config.floor_gen
	var ids: Array[int] = Net.get_player_ids()
	ids.sort()
	var to_floor: Transform3D = Level.get_floor_transform().affine_inverse()
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body == null or body.is_ghost():
			continue
		var at: Vector3 = to_floor * body.global_position
		var order: int = maxi(ids.find(body.player_id), 0)
		var color: Color = tuning.map_player_colors[order % tuning.map_player_colors.size()] \
			if not tuning.map_player_colors.is_empty() else Color.WHITE
		dots.append({"cells": Vector2(at.x, at.z) / layout.cell_size(), "color": color})
	return dots


func _process(delta: float) -> void:
	if _anchor == null or not is_instance_valid(_anchor) or not _anchor.is_inside_tree():
		return
	var tuning: FloorGenTuning = Config.floor_gen
	var near: bool = _local_player_near(tuning.feed_active_radius)
	if near != _near:
		_near = near
		for monitor: SecurityMonitor in get_monitors():
			monitor.set_feed_active(near)
	if not near:
		return
	_map_elapsed += delta
	_map_left -= delta
	if _map_left <= 0.0 and get_map_table() != null:
		_map_left = 1.0 / maxf(tuning.map_updates_per_second, 0.1)
		_table.refresh(part_highlight_rooms(), player_dots(), _map_elapsed)
		_map_elapsed = 0.0
	_feed_left -= delta
	if _feed_left <= 0.0:
		_feed_left = 1.0 / maxf(tuning.feed_updates_per_second, 0.1)
		for monitor: SecurityMonitor in get_monitors():
			monitor.render_once()


func _local_player_near(radius: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body != null and body.is_local() and body.global_position.distance_to(_anchor.global_position) <= radius:
			return true
	return false


## Every PC: a floor was built. On a generated floor with a security room, put in the table and the monitors
## (the same names everywhere, so the monitors' state reaches every PC).
func _on_floor_built() -> void:
	_table = null
	_monitors.clear()
	_anchor = null
	_near = false
	var layout: FloorLayout = Level.get_layout()
	if layout == null or layout.grid != RoomData.GRID_TILE:
		return
	var spots: Array[RoomMarker] = Level.get_markers(&"security_map")
	if spots.is_empty():
		return
	_anchor = spots[0]
	var department := ContentRegistry.get_content(layout.department_id) as DepartmentData
	_table = SecurityMapTable.new()
	_table.name = "MapTable"
	_anchor.add_child(_table)
	_table.show_layout(layout, department.accent_color if department != null else Color(0.3, 0.9, 0.75))
	var screens: Array[RoomMarker] = Level.get_markers(&"security_monitor")
	for index: int in mini(screens.size(), Config.floor_gen.security_monitors):
		var monitor := SecurityMonitor.new()
		monitor.name = "Monitor"
		monitor.cameras = layout.cameras
		monitor.start_index = index
		monitor.position = Vector3(0, 0, -0.09)
		screens[index].add_child(monitor)
		monitor.set_feed_active(false)
		var buttons: Array[WorldButton] = []
		for side: int in 2:
			var button := WorldButton.new()
			button.name = "Prev" if side == 0 else "Next"
			button.prompt = "Previous camera" if side == 0 else "Next camera"
			button.size = Vector3(0.14, 0.1, 0.06)
			button.color = Color(0.3, 0.32, 0.36)
			button.reset_seconds = 0.3
			button.position = Vector3(-0.2 if side == 0 else 0.2, -0.42, -0.15)
			screens[index].add_child(button)
			buttons.append(button)
		buttons[0].wire(&"pressed", monitor, &"prev")
		buttons[1].wire(&"pressed", monitor, &"next")
		_monitors.append(monitor)
