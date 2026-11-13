extends GutTest
## NEW 2026-11-11 (floor generation step 5a): the Botany department: its required rooms on every floor, its own
## welcome center, palette and room signs, incidents in their rooms with their overlays, and its new hazards
## (toxic spores, toxic gas, water that slows players).

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")


func _botany() -> DepartmentData:
	return ContentRegistry.get_content(&"department_botany") as DepartmentData


func _room(placement: RoomPlacement) -> RoomData:
	return ContentRegistry.get_content(placement.room_id) as RoomData


func _kinds_on(layout: FloorLayout) -> Dictionary[StringName, int]:
	var kinds: Dictionary[StringName, int] = {}
	for placement: RoomPlacement in layout.placements:
		var kind: StringName = _room(placement).room_kind
		kinds[kind] = kinds.get(kind, 0) + 1
	return kinds


func test_botany_floors_have_their_required_rooms() -> void:
	var botany: DepartmentData = _botany()
	var department_rooms: int = 0
	var shared_rooms: int = 0
	for floor_seed: int in 40:
		var floor_number: int = 1 + floor_seed % 12
		var layout: FloorLayout = FloorGenerator.generate_from_seed(botany, floor_number, floor_seed * 17 + 3, Config.floor_gen)
		var label: String = "floor %d seed %d" % [floor_number, floor_seed]
		assert_false(layout.is_fallback, "%s: a real floor" % label)
		var kinds: Dictionary[StringName, int] = _kinds_on(layout)
		for required: String in botany.required_room_kinds:
			if required == "lift":
				continue
			assert_gte(kinds.get(StringName(required), 0), 1, "%s: a %s" % [label, required])
		assert_eq(_room(layout.placements[1]).id, &"room_tile_botany_welcome_center", "%s: Botany's welcome center" % label)
		for room_type: RoomTypeData in botany.room_types:
			if room_type.max_per_floor > 0:
				assert_lte(kinds.get(room_type.room_kind, 0), room_type.max_per_floor, "%s: %s" % [label, room_type.room_kind])
		for placement: RoomPlacement in layout.placements:
			var room: RoomData = _room(placement)
			assert_false(room.department_ids.has(&"department_robotics"), "%s: no Robotics rooms" % label)
			if room.tile_role != TileStandards.ROLE_ROOM:
				continue
			if room.department_ids.has(botany.id):
				department_rooms += 1
			else:
				shared_rooms += 1
	assert_gt(department_rooms, shared_rooms, "most rooms are Botany rooms")
	assert_gt(shared_rooms, 0, "but shared rooms turn up too")


func test_botany_floors_get_the_palette_signs_and_green_emergency_light() -> void:
	var botany: DepartmentData = _botany()
	FloorGenerator.debug_damage = &"heavy"
	var layout: FloorLayout = FloorGenerator.generate_from_seed(botany, 4, 3030, Config.floor_gen)
	FloorGenerator.debug_damage = &""
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var parent := Node3D.new()
	viewport.add_child(parent)
	Level.build(layout, parent)
	var wall: Material = botany.palette["wall"]
	var painted: int = 0
	var signs := PackedStringArray()
	var green_slits: int = 0
	for node: Node in RoomShape.all_children(parent):
		if node is CSGBox3D and node.get_meta(TileStandards.MATERIAL_SLOT_META, &"") == &"wall":
			assert_eq((node as CSGBox3D).material, wall, "%s has the Botany wall material" % node.get_path())
			painted += 1
		var label := node as Label3D
		if label != null and label.name == "Sign":
			signs.append(label.text)
		var light := node as Light3D
		if light != null and light.is_in_group(TileStandards.EMERGENCY_LIGHT_GROUP):
			assert_eq(light.light_color, botany.lighting.emergency_color, "emergency slits glow Botany green")
			green_slits += 1
	assert_gt(painted, 10, "walls take the Botany palette")
	assert_true(signs.has("GREENHOUSE"), "the greenhouse has its sign (%s)" % ", ".join(signs))
	assert_gt(green_slits, 5, "the damaged floor has emergency slits")
	Level.clear()


func test_botany_incidents_start_in_their_rooms_and_leave_their_mark() -> void:
	var botany: DepartmentData = _botany()
	var fitting: int = 0
	var flavours: Dictionary[StringName, bool] = {}
	for floor_seed: int in 30:
		var layout: FloorLayout = FloorGenerator.generate_from_seed(botany, 6, 400 + floor_seed, Config.floor_gen)
		for incident: IncidentData in botany.incidents:
			if incident.id == layout.incident_id:
				flavours[incident.overlay_flavour] = true
				if incident.origin_room_kinds.has(String(_room(layout.placements[layout.origin]).room_kind)):
					fitting += 1
	assert_gt(fitting, 20, "incidents start in rooms they fit (%d of 30)" % fitting)
	assert_gte(flavours.size(), 3, "several kinds of incident happen (%s)" % str(flavours.keys()))
	# The origin tile, built, wears its incident's overlay.
	var layout: FloorLayout = FloorGenerator.generate_from_seed(botany, 6, 400, Config.floor_gen)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var parent := Node3D.new()
	viewport.add_child(parent)
	Level.build(layout, parent)
	var origin: Node3D = Level.get_room_nodes()[layout.origin]
	var overlay: Node = origin.get_node_or_null(IncidentOverlays.NODE_NAME)
	assert_not_null(overlay, "the incident's room has its overlay")
	if overlay != null:
		assert_gt(overlay.get_child_count(), 0, "with pieces in it")
	assert_eq(IncidentOverlays.flavour_for(layout.origin, layout, botany),
		_flavour_of(botany, layout.incident_id), "the origin takes the main incident's flavour")
	Level.clear()


func _flavour_of(department: DepartmentData, incident_id: StringName) -> StringName:
	for incident: IncidentData in department.incidents:
		if incident.id == incident_id:
			return incident.overlay_flavour
	return &""


func test_water_slows_players_and_spores_hurt() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var water := HazardZone.new()
	water.setup(&"water")
	world.add_child(water)
	var spores := HazardZone.new()
	spores.setup(&"toxic_spores")
	spores.position = Vector3(8, 0, 0)
	world.add_child(spores)
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = Net.local_player_id()
	body.name = str(body.player_id)
	body.position = Vector3(0, 0.1, 0)
	world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	assert_true(water.is_slowing(body), "a player in the water is slowed")
	assert_almost_eq(body.get_movement().get_speed_multiplier(), Config.floor_gen.hazard_slow[&"water"], 0.01,
		"to the water's speed")
	body.global_position = Vector3(8, 0.1, 0)
	await wait_physics_frames(5)
	assert_false(water.is_slowing(body), "out of the water, full speed again")
	assert_almost_eq(body.get_movement().get_speed_multiplier(), 1.0, 0.01)
	var health: HealthComponent = HealthComponent.of(body)
	var before: float = health.get_current()
	await wait_seconds(Config.floor_gen.hazard_tick_seconds * 2.5)
	assert_lt(health.get_current(), before, "toxic spores hurt")
	assert_not_null(spores.get_node_or_null("Mote0"), "spores look like drifting motes")
	assert_not_null(water.get_node_or_null("Pool"), "water looks like a pool")
