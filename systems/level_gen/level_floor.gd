class_name LevelFloor
extends Node3D
## The scene every floor is built in (Level.FLOOR_SCENE). game_flow loads it on every PC and calls
## Level.build(), which puts the rooms in. It has the light, the player and prop spawners, and:
## - on floor_ready (host): players appear at the player_spawn markers (inside the lift room: every
##   floor starts in the elevator);
## - STUB for physics_props: a crate (or the marker's "prop_id") at each prop_spawn marker;
## - STUB for cargo_lift: the department's lift parts at the lift_part markers farthest from the lift,
##   and a "Depart" button at the lift marker. It only leaves (lift_departed on every PC) once the parts
##   are in the lift room and every player is in there too. Not on boss floors.
## - STUB for bosses: a "Defeat the boss" button at each boss_spawn marker (emits boss_defeated).
## Nodes for markers are made on every PC with the same names (markers come in the same order).

const DEFAULT_PROP_ID: StringName = &"prop_crate"
const STUB_BUTTON_HEIGHT: float = 1.2

var _players: PlayerSpawner
var _props: PropSpawner
var _prompt: Label
## Host: the lift parts spawned on this floor.
var _parts: Array[NetProp] = []


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.17, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_players = PlayerSpawner.new()
	_players.name = "PlayerSpawner"
	# Bodies and props appear on floor_ready, once every PC has built the floor.
	_players.auto_spawn = false
	add_child(_players)
	_props = PropSpawner.new()
	_props.name = "Props"
	add_child(_props)
	Level.floor_built.connect(_on_floor_built)
	EventBus.floor_ready.connect(_on_floor_ready)
	_build_hud()


func _exit_tree() -> void:
	if Level.floor_built.is_connected(_on_floor_built):
		Level.floor_built.disconnect(_on_floor_built)


## Every PC: the rooms are in. Add the stand-in lift and boss buttons.
func _on_floor_built() -> void:
	var layout: FloorLayout = Level.get_layout()
	var lifts: Array[RoomMarker] = []
	if layout != null and not layout.is_boss_floor:
		lifts = Level.get_markers(&"lift")
	for index: int in lifts.size():
		_stub_button("LiftStub%d" % index, lifts[index], "Depart (stub lift)", Color(0.2, 0.75, 0.3), _on_lift_used)
	var bosses: Array[RoomMarker] = Level.get_markers(&"boss_spawn")
	for index: int in bosses.size():
		_stub_button("BossStub%d" % index, bosses[index], "Defeat the boss (stub)", Color(0.85, 0.2, 0.2), _on_boss_used)


## Host: everyone has the floor now: bring in the players and the props.
func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var points: Array[Node3D] = []
	for marker: RoomMarker in Level.get_markers(&"player_spawn"):
		points.append(marker)
	_players.spawn_all(points)
	for marker: RoomMarker in Level.get_markers(&"prop_spawn"):
		var prop_id := StringName(str(marker.params.get("prop_id", DEFAULT_PROP_ID)))
		_props.spawn_prop(prop_id, marker.global_transform)
	_spawn_lift_parts()


## Host, STUB for cargo_lift: the lift parts go at the lift_part markers farthest from the lift.
func _spawn_lift_parts() -> void:
	var layout: FloorLayout = Level.get_layout()
	var department: DepartmentData = GameFlow.get_department(layout.department_id) if layout != null else null
	var lifts: Array[RoomMarker] = Level.get_markers(&"lift")
	var spots: Array[RoomMarker] = Level.get_markers(&"lift_part")
	if layout == null or layout.is_boss_floor or department == null or lifts.is_empty() or spots.is_empty():
		return
	if department.lift_part_prop_id == &"":
		push_warning("LevelFloor: department '%s' has no lift_part_prop_id." % department.id)
		return
	var lift_at: Vector3 = lifts[0].global_position
	# Farthest first; a stable sort keeps the marker order for ties, so every run is the same.
	var order: Array[RoomMarker] = spots.duplicate()
	order.sort_custom(func(a: RoomMarker, b: RoomMarker) -> bool:
		return a.global_position.distance_to(lift_at) > b.global_position.distance_to(lift_at))
	for index: int in department.lift_parts_per_floor:
		var part: NetProp = _props.spawn_prop(department.lift_part_prop_id, order[index % order.size()].global_transform)
		if part != null:
			_parts.append(part)


## Host: what still stops the lift leaving, or "" if it can go.
func lift_blocker() -> String:
	var delivered: int = 0
	for part: NetProp in _parts:
		if is_instance_valid(part) and _in_lift_room(part.global_position):
			delivered += 1
	if delivered < _parts.size():
		return "Bring the lift part to the elevator first (%d/%d)." % [delivered, _parts.size()]
	var missing: PackedStringArray = []
	for player_id: int in Net.get_player_ids():
		var body: PlayerCharacter = PlayerCharacter.find(player_id)
		if body != null and not _in_lift_room(body.global_position):
			missing.append(Net.get_display_name(player_id))
	if not missing.is_empty():
		return "Everyone into the elevator first. Waiting for: %s" % ", ".join(missing)
	return ""


func _in_lift_room(point: Vector3) -> bool:
	var room: RoomData = Level.get_room_for_position(point)
	return room != null and room.room_kind == LevelGenerator.KIND_LIFT


func _process(_delta: float) -> void:
	# STUB (ui HUD): the "E: ..." prompt.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt


func _on_lift_used(player_id: int) -> void:
	var blocker: String = lift_blocker()
	if blocker.is_empty():
		_lift_departed_rpc.rpc()
		return
	var peer_id: int = Net.get_peer_id(player_id)
	if peer_id != 0:
		_note_rpc.rpc_id(peer_id, blocker)


## Host -> the player who pressed Depart: why the lift can't go yet.
@rpc("authority", "call_local", "reliable")
func _note_rpc(text: String) -> void:
	EventBus.toast_requested.emit(text)


func _on_boss_used(_player_id: int) -> void:
	_boss_defeated_rpc.rpc()


## Host -> everyone: what cargo_lift will announce for real.
@rpc("authority", "call_local", "reliable")
func _lift_departed_rpc() -> void:
	var run: RunState = GameFlow.get_run()
	EventBus.lift_departed.emit(run.floor_number if run != null else 0)


## Host -> everyone: what bosses will announce for real.
@rpc("authority", "call_local", "reliable")
func _boss_defeated_rpc() -> void:
	var department: DepartmentData = GameFlow.get_current_department()
	EventBus.boss_defeated.emit(department.boss_id if department != null else &"")


func _stub_button(node_name: String, marker: RoomMarker, prompt: String, color: Color, on_used: Callable) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = marker.global_position + Vector3.UP * STUB_BUTTON_HEIGHT
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.6, 0.6, 0.6)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.5
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	var label := Label3D.new()
	label.text = prompt
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3.UP * 0.8
	label.pixel_size = 0.004
	body.add_child(label)
	var use := Interactable.new()
	use.name = "Use"
	use.prompt_text = prompt
	use.used.connect(on_used)
	body.add_child(use)
	add_child(body)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(300, 80)
	center.add_child(middle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	middle.add_child(_prompt)
