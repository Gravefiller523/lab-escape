class_name GameWorld
extends Node3D
## The scene that stays loaded from the Break Room to the end of a run (game_world.tscn). It holds the
## cargo lift, the player and prop spawners, and a LevelRoot that game_flow fills with the current level
## (the Break Room, or a floor level_gen builds), lined up so the level's lift spot is where the lift is.
## Nothing inside the lift is ever unloaded, so players and props ride along between levels.
##
## STUBS until other systems exist:
## - physics_props: a crate (or the marker's "prop_id") at each prop_spawn marker on floor_ready (host);
## - bosses: a "Defeat the boss" button at each boss_spawn marker (emits boss_defeated on every PC);
## - ui HUD: the "E: ..." prompt and a crosshair.

const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const DEFAULT_PROP_ID: StringName = &"prop_crate"
const STUB_BUTTON_HEIGHT: float = 1.2

var _level_root: Node3D
var _lift: CargoLift
var _players: PlayerSpawner
var _props: PropSpawner
var _prompt: Label


const GROUP: StringName = &"game_world"


## The game world in the game right now, or null (the main menu).
static func current() -> GameWorld:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var world := node as GameWorld
		if world != null and world.is_inside_tree() and not world.is_queued_for_deletion():
			return world
	return null


func _ready() -> void:
	add_to_group(GROUP)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.13, 0.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_level_root = Node3D.new()
	_level_root.name = "LevelRoot"
	add_child(_level_root)
	_lift = LIFT_SCENE.instantiate() as CargoLift
	_lift.name = "CargoLift"
	add_child(_lift)
	_players = PlayerSpawner.new()
	_players.name = "PlayerSpawner"
	# game_flow turns this on once the first level is in, so nobody appears before there is a floor.
	_players.auto_spawn = false
	add_child(_players)
	_props = PropSpawner.new()
	_props.name = "Props"
	add_child(_props)
	EventBus.floor_ready.connect(_on_floor_ready)
	_build_hud()


func get_lift() -> CargoLift:
	return _lift


func get_player_spawner() -> PlayerSpawner:
	return _players


func get_prop_spawner() -> PropSpawner:
	return _props


## Every PC: takes the current level away (the rooms or the Break Room).
func clear_level() -> void:
	Level.clear()
	for child: Node in _level_root.get_children():
		_level_root.remove_child(child)
		child.queue_free()
	_level_root.transform = Transform3D.IDENTITY


## Every PC: puts the Break Room in, lined up with the lift. Returns its spawn points.
func build_break_room(scene: PackedScene) -> Array[Node3D]:
	clear_level()
	var room := scene.instantiate() as BreakRoom
	_level_root.add_child(room)
	_line_up(room.get_lift_spot())
	return room.get_spawn_points()


## Every PC: builds a floor from its layout, lined up with the lift (at its lift room's lift marker).
func build_floor(layout: FloorLayout) -> void:
	clear_level()
	Level.build(layout, _level_root)
	var spots: Array[RoomMarker] = Level.get_markers(&"lift")
	if not spots.is_empty():
		_line_up(spots[0])
	for index: int in Level.get_markers(&"boss_spawn").size():
		_stub_button("BossStub%d" % index, Level.get_markers(&"boss_spawn")[index], "Defeat the boss (stub)",
			Color(0.85, 0.2, 0.2), _on_boss_used)


## Moves LevelRoot so that spot (inside it) ends up exactly where the lift is.
func _line_up(spot: Node3D) -> void:
	if spot == null:
		return
	var spot_in_root: Transform3D = _level_root.global_transform.affine_inverse() * spot.global_transform
	_level_root.global_transform = _lift.global_transform * spot_in_root.affine_inverse()


## Host, STUB for physics_props: the floor's crates.
func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	for marker: RoomMarker in Level.get_markers(&"prop_spawn"):
		var prop_id := StringName(str(marker.params.get("prop_id", DEFAULT_PROP_ID)))
		_props.spawn_prop(prop_id, marker.global_transform)


func _process(_delta: float) -> void:
	# STUB (ui HUD): the "E: ..." prompt.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt


func _on_boss_used(_player_id: int) -> void:
	_boss_defeated_rpc.rpc()


## Host -> everyone: what bosses will announce for real.
@rpc("authority", "call_local", "reliable")
func _boss_defeated_rpc() -> void:
	if not is_inside_tree():
		return
	var department: DepartmentData = GameFlow.get_current_department()
	EventBus.boss_defeated.emit(department.boss_id if department != null else &"")
	for child: Node in _level_root.get_children():
		if child.name.begins_with("BossStub"):
			child.queue_free()


func _stub_button(node_name: String, marker: RoomMarker, prompt: String, color: Color, on_used: Callable) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
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
	_level_root.add_child(body)
	body.global_position = marker.global_position + Vector3.UP * STUB_BUTTON_HEIGHT


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
