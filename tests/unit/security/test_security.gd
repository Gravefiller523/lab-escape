extends GutTest
## NEW 2026-11-10 (floor generation step 4e): the security room (docs/systems/security.md): the plan's cameras,
## the map table's blinking part wings, feeds that only draw while someone is near, and monitors that keep
## every PC on the same camera.

const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 5.0
const PORT: int = 18044


func _tuning() -> FloorGenTuning:
	return Config.floor_gen


func _robotics() -> DepartmentData:
	return ContentRegistry.get_content(&"department_robotics") as DepartmentData


func _joins(layout: FloorLayout) -> Dictionary[int, Array]:
	var links: Array[Dictionary] = LevelGenerator.doorway_links(layout, _tuning().grid_unit)
	var joins: Dictionary[int, Array] = {}
	for link: Dictionary in links:
		if not link["connected"]:
			continue
		var next: Vector2i = (link["cell"] as Vector2i) + (link["dir"] as Vector2i)
		for other: Dictionary in links:
			if other["cell"] == next and other["dir"] == -(link["dir"] as Vector2i):
				var from: int = link["placement"]
				if not joins.has(from):
					joins[from] = []
				joins[from].append((other["placement"] as int))
	return joins


func test_cameras_are_picked_by_the_rules_and_match_on_every_pc() -> void:
	var tuning: FloorGenTuning = _tuning()
	for floor_number: int in [1, 3, 6, 9, 11, 12]:
		for attempt: int in 3:
			var floor_seed: int = 3100 + floor_number * 17 + attempt
			var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, floor_seed, tuning)
			var again: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, floor_seed, tuning)
			var label: String = "floor %d seed %d" % [floor_number, floor_seed]
			assert_eq(again.cameras, layout.cameras, "%s: the same seed picks the same cameras" % label)
			assert_eq(FloorLayout.from_dict(layout.to_dict()).cameras, layout.cameras, "%s: other PCs get them" % label)
			var most: int = tuning.cameras_per_main_hall * layout.main_halls.size() \
				+ tuning.cameras_per_part_room * layout.lift_parts.size() + tuning.cameras_random
			assert_between(layout.cameras.size(), 1, most, "%s: camera count" % label)
			var rooms: Dictionary[int, bool] = {}
			var keys: Dictionary[String, bool] = {}
			for index: int in layout.cameras.size():
				var camera: Array = layout.cameras[index]
				var key: String = camera[0]
				assert_false(keys.has(key), "%s: each camera spot once" % label)
				keys[key] = true
				var room: int = key.get_slice("/", 0).to_int()
				rooms[room] = true
				assert_true(str(camera[1]).begins_with("CAM %02d " % (index + 1)), "%s: labelled %s" % [label, camera[1]])
				var level: int = layout.damage[room] if room < layout.damage.size() else 0
				if camera[2]:
					assert_gte(level, 2, "%s: only cameras in heavy or destroyed tiles are broken" % label)
				if level >= 3:
					assert_true(camera[2], "%s: every camera in a destroyed tile is broken" % label)
			for hall: PackedInt32Array in layout.main_halls:
				var spots: int = 0
				var picked: int = 0
				for piece: int in hall:
					var room := ContentRegistry.get_content(layout.placements[piece].room_id) as RoomData
					for marker: Dictionary in RoomShape.of(room, tuning.grid_unit).markers:
						if marker["kind"] == &"camera" and not layout.collapsed.has(piece):
							spots += 1
					if rooms.has(piece):
						picked += 1
				assert_gte(picked, mini(1, spots), "%s: each main hallway is watched" % label)
			var joins: Dictionary[int, Array] = _joins(layout)
			for part: Array in layout.lift_parts:
				var room: int = part[2]
				var watched: bool = rooms.has(room)
				for next: int in joins.get(room, []):
					watched = watched or rooms.has(next)
				var could: bool = _has_camera_spot(layout, room)
				for next: int in joins.get(room, []):
					could = could or _has_camera_spot(layout, next)
				if could:
					assert_true(watched, "%s: a camera in or next to the %s's room" % [label, part[0]])


func _has_camera_spot(layout: FloorLayout, index: int) -> bool:
	if layout.collapsed.has(index):
		return false
	var room := ContentRegistry.get_content(layout.placements[index].room_id) as RoomData
	for marker: Dictionary in RoomShape.of(room, _tuning().grid_unit).markers:
		if marker["kind"] == &"camera":
			return true
	return false


## A generated floor with the cargo lift and props, as in the game. Returns [root, lift, props, layout].
func _floor_with_lift(floor_number: int, floor_seed: int) -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var props := PropSpawner.new()
	props.name = "Props"
	root.add_child(props)
	var lift := LIFT_SCENE.instantiate() as CargoLift
	root.add_child(lift)
	var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, floor_seed, _tuning())
	EventBus.floor_loading.emit(floor_number, layout.department_id)
	Level.build(layout, root)
	await wait_physics_frames(3)
	return [root, lift, props, layout]


func test_the_security_room_is_built_with_its_table_and_monitors() -> void:
	var made: Array = await _floor_with_lift(2, 8080)
	assert_not_null(Security.get_map_table(), "the map table is on the security_map marker")
	assert_eq(Security.get_monitors().size(), _tuning().security_monitors, "4 monitors")
	var labels: Dictionary[String, bool] = {}
	for monitor: SecurityMonitor in Security.get_monitors():
		labels[monitor.get_camera_label()] = true
		assert_not_null(monitor.get_parent().get_node_or_null("Prev"), "a Prev button")
		assert_not_null(monitor.get_parent().get_node_or_null("Next"), "a Next button")
	assert_gt(labels.size(), 1, "the monitors start on different cameras")
	Level.clear()
	assert_eq(made.size(), 4)


func test_part_wings_blink_follow_a_moved_part_and_stop_when_it_is_delivered() -> void:
	var made: Array = await _floor_with_lift(9, 5151)
	var lift: CargoLift = made[1]
	var props: PropSpawner = made[2]
	var layout: FloorLayout = made[3]
	lift.arrive(1, false)
	EventBus.floor_ready.emit(9, layout.department_id)
	await wait_physics_frames(3)
	_allow_navigation_warning()
	# A part that needs no charging.
	var part: Array = []
	for planned: Array in layout.lift_parts:
		var data := ContentRegistry.get_content(StringName(str(planned[0]))) as PropData
		if data.needs_charge_seconds <= 0.0 and data.mass < 30.0:
			part = planned
			break
	assert_false(part.is_empty(), "a part to carry")
	var prop: NetProp = props.get_props(StringName(str(part[0])))[0]
	var room: int = part[2]
	var wing: int = layout.placements[room].wing
	var lit: Array[int] = Security.part_highlight_rooms()
	assert_true(lit.has(room), "the part's room blinks")
	for index: int in layout.placements.size():
		if wing >= 0 and layout.placements[index].wing == wing:
			assert_true(lit.has(index), "its whole wing blinks (not just the room)")
	# Carry it into another wing.
	var other_room: int = -1
	for index: int in layout.placements.size():
		var other_wing: int = layout.placements[index].wing
		if other_wing >= 0 and other_wing != wing and not lit.has(index):
			other_room = index
			break
	assert_gt(other_room, -1, "another wing to carry it to")
	var tile := Level.get_room_nodes()[other_room] as BlockoutTile
	var middle := Vector3(tile.size_units.x, 0, tile.size_units.y) * _tuning().grid_unit / 2.0
	prop.freeze = true
	prop.global_position = tile.global_transform * (middle + Vector3.UP * 0.5)
	await wait_physics_frames(2)
	lit = Security.part_highlight_rooms()
	assert_true(lit.has(other_room), "the blinking follows the part into its new wing")
	assert_false(wing >= 0 and lit.has(room) and not _other_part_in(layout, room, part), "and leaves the old wing")
	# Deliver it.
	var slot: StringName = (ContentRegistry.get_content(StringName(str(part[0]))) as PropData).lift_slot
	var socket := lift.get_node("Slot_%s/Socket" % slot) as Area3D
	prop.freeze = false
	prop.global_position = socket.global_position + Vector3.UP * 0.2
	await wait_until(func() -> bool: return not lift.get_broken_slots().has(slot), WAIT)
	assert_false(lift.get_broken_slots().has(slot), "the part went into its slot")
	await wait_physics_frames(2)
	assert_false(Security.part_highlight_rooms().has(other_room) and not _other_part_in(layout, other_room, part),
		"a delivered part's wing stops blinking")
	# floor_ready started the enemies' navigation bake on a background thread: let it finish before the floor goes.
	await wait_until(func() -> bool: return not Enemies.is_baking_navigation(), WAIT)
	Level.clear()


## Does another planned part sit in the same wing as this room (so that wing blinks anyway)?
func _other_part_in(layout: FloorLayout, room: int, part: Array) -> bool:
	var wing: int = layout.placements[room].wing
	for other: Array in layout.lift_parts:
		if other == part:
			continue
		var other_room: int = other[2]
		if other_room == room or (wing >= 0 and layout.placements[other_room].wing == wing):
			return true
	return false


func test_feeds_only_draw_while_someone_is_near() -> void:
	var made: Array = await _floor_with_lift(2, 8080)
	var root: Node3D = made[0]
	await wait_physics_frames(2)
	for monitor: SecurityMonitor in Security.get_monitors():
		assert_false(monitor.is_feed_active(), "nobody near: no feed draws")
	var table: SecurityMapTable = Security.get_map_table()
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 1
	body.name = "1"
	root.add_child(body)
	body.set_input_override(PlayerInputState.new())
	body.global_position = table.global_position + Vector3(0, 0.2, 2.5)
	await wait_physics_frames(3)
	assert_true(Security.is_anyone_near(), "a player stands in the security room")
	for monitor: SecurityMonitor in Security.get_monitors():
		assert_true(monitor.is_feed_active(), "the feeds draw")
	body.global_position = table.global_position + Vector3(0, 0.2, _tuning().feed_active_radius + 20.0)
	await wait_physics_frames(3)
	assert_false(Security.is_anyone_near(), "the player walked off")
	for monitor: SecurityMonitor in Security.get_monitors():
		assert_false(monitor.is_feed_active(), "the feeds stop drawing")
	body.queue_free()
	Level.clear()


func test_monitor_buttons_step_through_cameras_on_every_pc() -> void:
	var cameras: Array[Array] = [["0/Markers/A", "CAM 01 A", false], ["0/Markers/B", "CAM 02 B", true],
		["0/Markers/C", "CAM 03 C", false]]
	var host_pc := _pc()
	var client_pc := _pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 4), OK)
	host_pc.multiplayer.multiplayer_peer = server
	var host_monitor := _pc_monitor(host_pc, cameras)
	await wait_physics_frames(2)
	host_monitor.receive(&"next")
	assert_eq(host_monitor.get_camera_index(), 1, "Next goes to the next camera")
	assert_true(host_monitor.is_showing_static(), "a broken camera shows static")
	var client_peer := ENetMultiplayerPeer.new()
	client_peer.create_client("127.0.0.1", PORT)
	client_pc.multiplayer.multiplayer_peer = client_peer
	await wait_until(func() -> bool: return client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, WAIT)
	var client_monitor := _pc_monitor(client_pc, cameras)
	await wait_until(func() -> bool: return client_monitor.get_camera_index() == 1, WAIT)
	assert_eq(client_monitor.get_camera_index(), 1, "a monitor built later asks the host which camera it shows")
	host_monitor.receive(&"prev")
	host_monitor.receive(&"prev")
	assert_eq(host_monitor.get_camera_index(), 2, "Prev wraps round to the last camera")
	await wait_until(func() -> bool: return client_monitor.get_camera_index() == 2, WAIT)
	assert_eq(client_monitor.get_camera_index(), 2, "the other PC follows")
	assert_eq(client_monitor.get_camera_label(), "CAM 03 C")
	for pc: Node in [host_pc, client_pc]:
		var path: NodePath = pc.get_path()
		var peer: MultiplayerPeer = pc.multiplayer.multiplayer_peer
		pc.free()
		peer.close()
		get_tree().set_multiplayer(null, path)


## One "PC": its own world and multiplayer.
func _pc() -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % get_child_count()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var level := Node3D.new()
	level.name = "Level"
	pc.add_child(level)
	return pc


func _pc_monitor(pc: Node, cameras: Array[Array]) -> SecurityMonitor:
	var monitor := SecurityMonitor.new()
	monitor.name = "Monitor"
	monitor.cameras = cameras
	pc.get_node("Level").add_child(monitor)
	return monitor


## floor_ready also makes the enemies bake their navigation, and the first bake in a run warns that it parsed
## the CSG tiles' meshes (an enemies matter, not this test's): that warning doesn't fail the test.
func _allow_navigation_warning() -> void:
	for error: GutTrackedError in get_errors():
		if error.contains_text("Source geometry parsing"):
			error.handled = true
