class_name GameWorld
extends Node3D
## The scene that stays loaded from the Break Room to the end of a run (game_world.tscn). It holds the
## cargo lift, the player and prop spawners, and a LevelRoot that game_flow fills with the current level
## (the Break Room, or a floor level_gen builds), lined up so the level's lift spot is where the lift is.
## Nothing inside the lift is ever unloaded, so players and props ride along between levels.
##
## STUBS until other systems exist:
## - physics_props: a crate (or the marker's "prop_id") at each prop_spawn marker on floor_ready (host);
## (CHANGED 2026-10-23: the "Defeat the boss" button stub is gone: the bosses system spawns the real boss.)
## (CHANGED 2026-10-19: the "E: ..." prompt and crosshair stub is gone: the ui HUD shows them.)

const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const DEFAULT_PROP_ID: StringName = &"prop_crate"
## NEW 2026-11-13 (roadmap WP19): the light in the lab and in the car park.
const NIGHT_BACKGROUND: Color = Color(0.12, 0.13, 0.15)
const NIGHT_AMBIENT: Color = Color(0.55, 0.55, 0.6)
const DAY_SKY: Color = Color(0.55, 0.75, 0.95)
const DAY_AMBIENT: Color = Color(0.8, 0.82, 0.85)
const DAY_SUN_ENERGY: float = 1.6
## NEW 2026-11-14 (art phase WP26): the box around your camera where floating specks appear (half sizes, metres).
const MOTE_BOX: Vector3 = Vector3(6.0, 2.0, 6.0)

var _level_root: Node3D
var _lift: CargoLift
var _players: PlayerSpawner
var _props: PropSpawner
var _environment: WorldEnvironment
var _sun: DirectionalLight3D
## NEW 2026-11-14 (art phase WP26): the look of the floor we are on (null = the plain default), and the specks
## floating around this PC's camera.
var _look: LightingStyleData
var _motes: GPUParticles3D


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
	_environment = environment
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = NIGHT_BACKGROUND
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = NIGHT_AMBIENT
	add_child(environment)
	var sun := DirectionalLight3D.new()
	_sun = sun
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
	apply_look(null)
	var room := scene.instantiate() as BreakRoom
	apply_look(room.look)
	_level_root.add_child(room)
	_line_up(room.get_lift_spot())
	return room.get_spawn_points()


## NEW 2026-11-13 (roadmap WP19): every PC: puts the car park in (the ending), lined up with the lift. Returns its
## spawn points.
func build_surface(scene: PackedScene) -> Array[Node3D]:
	clear_level()
	var car_park := scene.instantiate() as CarPark
	_level_root.add_child(car_park)
	_line_up(car_park.get_lift_spot())
	return car_park.get_spawn_points()


## NEW 2026-11-13 (roadmap WP19): daylight (the car park) or the lab's dark (every other level).
func set_daylight(on: bool) -> void:
	if _environment == null or _sun == null:
		return
	if not on:
		apply_look(_look)
		return
	# Outside: the plain look with sky and sun, but remember the floor's look for coming back in.
	var inside: LightingStyleData = _look
	apply_look(null)
	_look = inside
	_environment.environment.background_color = DAY_SKY
	_environment.environment.ambient_light_color = DAY_AMBIENT
	_sun.light_energy = DAY_SUN_ENERGY


func is_daylight() -> bool:
	return _environment != null and _environment.environment.background_color == DAY_SKY


## Every PC: builds a floor from its layout, lined up with the lift (at its lift room's lift marker).
func build_floor(layout: FloorLayout) -> void:
	clear_level()
	Level.build(layout, _level_root)
	# NEW 2026-11-14 (art phase WP26): the department's light and air.
	var department: DepartmentData = GameFlow.get_department(layout.department_id) if layout.department_id != &"" else null
	apply_look(department.lighting if department != null else null)
	var spots: Array[RoomMarker] = Level.get_markers(&"lift")
	if not spots.is_empty():
		_line_up(spots[0])


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



## NEW 2026-11-14 (art phase WP26, Zachary OK'd the lighting mock-up): every PC: puts a department's atmosphere on the
## world (LightingStyleData's "Atmosphere" group): ambient light, background, haze, tone curve and floating specks.
## null puts back the plain look (the Break Room). Indoors the sun is off; the plain look keeps it.
func apply_look(style: LightingStyleData) -> void:
	_look = style
	if _environment == null:
		return
	var environment: Environment = _environment.environment
	var plain: bool = style == null
	environment.background_color = NIGHT_BACKGROUND if plain else style.background_color
	environment.ambient_light_color = NIGHT_AMBIENT if plain else style.ambient_color
	environment.ambient_light_energy = 1.0 if plain else style.ambient_energy
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR if plain else Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0 if plain else style.exposure
	environment.ssao_enabled = not plain
	environment.glow_enabled = not plain
	environment.fog_enabled = not plain and style.fog_density > 0.0
	environment.volumetric_fog_enabled = not plain and style.fog_density > 0.0 and style.volumetric_fog
	if not plain:
		environment.fog_light_color = style.fog_color
		environment.fog_density = style.fog_density
		environment.volumetric_fog_density = style.fog_density * 0.8
		environment.volumetric_fog_albedo = style.fog_color
	if _sun != null:
		_sun.visible = plain
		_sun.light_energy = 1.0
	_set_motes(style)


## The look on the world now (null = the plain one).
func get_look() -> LightingStyleData:
	return _look


func _set_motes(style: LightingStyleData) -> void:
	if _motes != null:
		_motes.queue_free()
		_motes = null
	if style == null or style.mote_amount <= 0:
		return
	_motes = GPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = style.mote_amount
	_motes.lifetime = 6.0
	_motes.preprocess = 6.0
	_motes.local_coords = false
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = MOTE_BOX
	motion.gravity = Vector3(0.0, -style.mote_fall if style.mote_fall > 0.0 else 0.02, 0.0)
	motion.initial_velocity_min = style.mote_speed * 0.25
	motion.initial_velocity_max = style.mote_speed
	motion.spread = 180.0
	_motes.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2(style.mote_size, style.mote_size)
	var speck := StandardMaterial3D.new()
	speck.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	speck.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	speck.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	speck.albedo_color = style.mote_color
	quad.material = speck
	_motes.draw_pass_1 = quad
	add_child(_motes)


func _process(_delta: float) -> void:
	# The specks follow this PC's camera, so there are always some around you and none wasted far away.
	if _motes == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		_motes.global_position = camera.global_position
