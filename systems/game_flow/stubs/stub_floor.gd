class_name StubFloor
extends Node3D
## STUB for level_gen, cargo_lift and bosses: the "floor" every run uses until they exist.
## A grey box room with a few crates, a sign saying which floor this is, and one button:
## - regular floors: "Depart (stub lift)" emits lift_departed on every PC (cargo_lift's job later);
## - boss floors: "Defeat the boss (stub)" emits boss_defeated on every PC (bosses' job later).
## Anyone can press it; the host runs it. Built in code with fixed node names, so every PC matches.

const ROOM_HALF: float = 10.0
const WALL_HEIGHT: float = 4.0
const BUTTON_POSITION: Vector3 = Vector3(0, 1.2, -9.7)
const CRATE_ROW: Vector3 = Vector3(-2, 0.4, -3)

var _is_boss: bool = false
var _players: PlayerSpawner
var _props: PropSpawner
var _prompt: Label


func _ready() -> void:
	var run: RunState = GameFlow.get_run()
	_is_boss = run != null and run.is_boss_floor
	_build_room()
	_players = PlayerSpawner.new()
	_players.name = "PlayerSpawner"
	# Bodies and crates appear on floor_ready, once every PC has this scene: anything spawned
	# earlier would reach PCs that are still loading.
	_players.auto_spawn = false
	add_child(_players)
	_props = PropSpawner.new()
	_props.name = "Props"
	add_child(_props)
	EventBus.floor_ready.connect(_on_floor_ready)
	_build_button()
	_build_sign(run)
	_build_hud()


## Host: everyone has the floor now: bring in the players and a few crates.
func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var points: Array[Node3D] = []
	_players.spawn_all(points)
	for index: int in 3:
		_props.spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, CRATE_ROW + Vector3(float(index) * 1.2, 0, 0)))


func _process(_delta: float) -> void:
	# STUB (ui HUD): the "E: ..." prompt.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt


## Host: someone pressed the button.
func _on_button_used(_player_id: int) -> void:
	_button_pressed_rpc.rpc()


## Host -> everyone: what cargo_lift or bosses will announce for real.
@rpc("authority", "call_local", "reliable")
func _button_pressed_rpc() -> void:
	var run: RunState = GameFlow.get_run()
	if run == null:
		return
	if _is_boss:
		var department: DepartmentData = GameFlow.get_current_department()
		EventBus.boss_defeated.emit(department.boss_id if department != null else &"")
	else:
		EventBus.lift_departed.emit(run.floor_number)


func _build_room() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.22, 0.25) if not _is_boss else Color(0.3, 0.15, 0.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var grey := Color(0.45, 0.46, 0.5)
	_box("Floor", Vector3(0, -0.25, 0), Vector3(ROOM_HALF * 2, 0.5, ROOM_HALF * 2), grey)
	_box("WallNorth", Vector3(0, WALL_HEIGHT / 2, -ROOM_HALF - 0.25), Vector3(ROOM_HALF * 2, WALL_HEIGHT, 0.5), grey)
	_box("WallSouth", Vector3(0, WALL_HEIGHT / 2, ROOM_HALF + 0.25), Vector3(ROOM_HALF * 2, WALL_HEIGHT, 0.5), grey)
	_box("WallWest", Vector3(-ROOM_HALF - 0.25, WALL_HEIGHT / 2, 0), Vector3(0.5, WALL_HEIGHT, ROOM_HALF * 2), grey)
	_box("WallEast", Vector3(ROOM_HALF + 0.25, WALL_HEIGHT / 2, 0), Vector3(0.5, WALL_HEIGHT, ROOM_HALF * 2), grey)


func _build_button() -> void:
	var body := StaticBody3D.new()
	body.name = "StubButton"
	body.position = BUTTON_POSITION
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.3)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.7, 0.7, 0.2)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.2, 0.2) if _is_boss else Color(0.2, 0.75, 0.3)
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.5
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	var use := Interactable.new()
	use.name = "Use"
	use.prompt_text = "Defeat the boss (stub)" if _is_boss else "Depart (stub lift)"
	use.used.connect(_on_button_used)
	body.add_child(use)
	add_child(body)


func _build_sign(run: RunState) -> void:
	var floor_sign := Label3D.new()
	floor_sign.name = "FloorSign"
	floor_sign.position = Vector3(0, 2.8, -9.9)
	floor_sign.font_size = 72
	floor_sign.pixel_size = 0.005
	if run == null:
		floor_sign.text = "No run (stub floor)"
	else:
		var department: DepartmentData = GameFlow.get_current_department()
		floor_sign.text = "Floor %d: %s\n%s" % [run.floor_number, department.display_name if department != null else "?",
			"BOSS FLOOR (stub)" if run.is_boss_floor else "floor %d (stub room)" % run.floor_in_department]
	add_child(floor_sign)


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


func _box(box_name: String, center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = center
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
