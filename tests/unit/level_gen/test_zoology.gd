extends GutTest
## NEW 2026-11-11 (floor generation step 5b): the Zoology department: its required rooms on every floor, its own
## welcome center, palette, room signs and amber emergency light, incidents in their rooms with their overlays,
## and broken enclosures that let an animal out (an enemy spawn wakes in their room) without hurting anyone.


func _zoology() -> DepartmentData:
	return ContentRegistry.get_content(&"department_zoology") as DepartmentData


func _room(placement: RoomPlacement) -> RoomData:
	return ContentRegistry.get_content(placement.room_id) as RoomData


func _kinds_on(layout: FloorLayout) -> Dictionary[StringName, int]:
	var kinds: Dictionary[StringName, int] = {}
	for placement: RoomPlacement in layout.placements:
		var kind: StringName = _room(placement).room_kind
		kinds[kind] = kinds.get(kind, 0) + 1
	return kinds


func test_zoology_floors_have_their_required_rooms() -> void:
	var zoology: DepartmentData = _zoology()
	var department_rooms: int = 0
	var shared_rooms: int = 0
	for floor_seed: int in 40:
		var floor_number: int = 1 + floor_seed % 12
		var layout: FloorLayout = FloorGenerator.generate_from_seed(zoology, floor_number, floor_seed * 19 + 7, Config.floor_gen)
		var label: String = "floor %d seed %d" % [floor_number, floor_seed]
		assert_false(layout.is_fallback, "%s: a real floor" % label)
		var kinds: Dictionary[StringName, int] = _kinds_on(layout)
		for required: String in zoology.required_room_kinds:
			if required == "lift":
				continue
			assert_gte(kinds.get(StringName(required), 0), 1, "%s: a %s" % [label, required])
		assert_eq(_room(layout.placements[1]).id, &"room_tile_zoology_welcome_center", "%s: Zoology's welcome center" % label)
		for room_type: RoomTypeData in zoology.room_types:
			if room_type.max_per_floor > 0:
				assert_lte(kinds.get(room_type.room_kind, 0), room_type.max_per_floor, "%s: %s" % [label, room_type.room_kind])
		for placement: RoomPlacement in layout.placements:
			var room: RoomData = _room(placement)
			assert_false(room.department_ids.has(&"department_robotics") or room.department_ids.has(&"department_botany"),
				"%s: no other department's rooms" % label)
			if room.tile_role != TileStandards.ROLE_ROOM:
				continue
			if room.department_ids.has(zoology.id):
				department_rooms += 1
			else:
				shared_rooms += 1
	assert_gt(department_rooms, shared_rooms, "most rooms are Zoology rooms")
	assert_gt(shared_rooms, 0, "but shared rooms turn up too")
	assert_true(zoology.boss_floors, "Zoology keeps its giant rat boss floors")


func test_zoology_floors_get_the_palette_signs_and_amber_emergency_light() -> void:
	var zoology: DepartmentData = _zoology()
	FloorGenerator.debug_damage = &"heavy"
	var layout: FloorLayout = FloorGenerator.generate_from_seed(zoology, 4, 3131, Config.floor_gen)
	FloorGenerator.debug_damage = &""
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var parent := Node3D.new()
	viewport.add_child(parent)
	Level.build(layout, parent)
	var wall: Material = zoology.palette["wall"]
	var painted: int = 0
	var signs := PackedStringArray()
	var slits: int = 0
	for node: Node in RoomShape.all_children(parent):
		if node is CSGBox3D and node.get_meta(TileStandards.MATERIAL_SLOT_META, &"") == &"wall":
			assert_eq((node as CSGBox3D).material, wall, "%s has the Zoology wall material" % node.get_path())
			painted += 1
		var label := node as Label3D
		if label != null and label.name == "Sign":
			signs.append(label.text)
		var light := node as Light3D
		if light != null and light.is_in_group(TileStandards.EMERGENCY_LIGHT_GROUP):
			assert_eq(light.light_color, zoology.lighting.emergency_color, "emergency slits glow Zoology amber")
			slits += 1
	assert_gt(painted, 10, "walls take the Zoology palette")
	assert_true(signs.has("ANIMAL HOLDING"), "the holding room has its sign (%s)" % ", ".join(signs))
	assert_gt(slits, 5, "the damaged floor has emergency slits")
	Level.clear()


func test_zoology_incidents_start_in_their_rooms_and_leave_their_mark() -> void:
	var zoology: DepartmentData = _zoology()
	var fitting: int = 0
	var flavours: Dictionary[StringName, bool] = {}
	for floor_seed: int in 30:
		var layout: FloorLayout = FloorGenerator.generate_from_seed(zoology, 6, 500 + floor_seed, Config.floor_gen)
		for incident: IncidentData in zoology.incidents:
			if incident.id == layout.incident_id:
				flavours[incident.overlay_flavour] = true
				if incident.origin_room_kinds.has(String(_room(layout.placements[layout.origin]).room_kind)):
					fitting += 1
	assert_gt(fitting, 20, "incidents start in rooms they fit (%d of 30)" % fitting)
	assert_true(flavours.has(&"claws") and flavours.has(&"flood"), "both incidents happen (%s)" % str(flavours.keys()))
	var layout: FloorLayout = FloorGenerator.generate_from_seed(zoology, 6, 500, Config.floor_gen)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var parent := Node3D.new()
	viewport.add_child(parent)
	Level.build(layout, parent)
	var overlay: Node = Level.get_room_nodes()[layout.origin].get_node_or_null(IncidentOverlays.NODE_NAME)
	assert_not_null(overlay, "the incident's room has its overlay")
	if overlay != null:
		assert_gt(overlay.get_child_count(), 0, "with pieces in it")
	Level.clear()


func test_broken_enclosures_let_an_animal_out_but_dont_hurt() -> void:
	var zoology: DepartmentData = _zoology()
	var found: int = 0
	FloorGenerator.debug_damage = &"destroyed"
	for floor_seed: int in 20:
		var layout: FloorLayout = FloorGenerator.generate_from_seed(zoology, 10, 700 + floor_seed, Config.floor_gen)
		var spawns: PackedStringArray = layout.active_markers.get(&"enemy_spawn", PackedStringArray())
		var quiet_rooms: Dictionary[int, bool] = {}
		for part: Array in layout.lift_parts:
			quiet_rooms[int(part[2])] = true
		for key: String in layout.active_markers.get(&"hazard", PackedStringArray()):
			if str((layout.marker_params.get(key, {}) as Dictionary).get("hazard_kind", "")) != "broken_enclosure":
				continue
			var room: int = key.get_slice("/", 0).to_int()
			var awake: bool = false
			var has_spot: bool = false
			for marker: Dictionary in RoomShape.of(_room(layout.placements[room]), Config.floor_gen.grid_unit).markers:
				if marker["kind"] == &"enemy_spawn":
					has_spot = true
					awake = awake or spawns.has(FloorLayout.marker_key(room, marker["path"]))
			if has_spot and not awake:
				# Only the one lift part room kept calm (Q15) may stay asleep.
				assert_true(quiet_rooms.has(room), "seed %d: a broken enclosure's room has an enemy awake" % floor_seed)
			elif has_spot:
				found += 1
	FloorGenerator.debug_damage = &""
	assert_gt(found, 3, "broken enclosures turned up and woke enemies (%d)" % found)
	assert_eq(Config.floor_gen.hazard_damage_per_second.get(&"broken_enclosure", -1.0), 0.0, "a broken enclosure doesn't hurt")
	var zone := HazardZone.new()
	zone.setup(&"broken_enclosure")
	add_child_autofree(zone)
	assert_not_null(zone.get_node_or_null("Straw"), "it looks like a broken cage with straw")
