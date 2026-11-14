extends Node3D
## The game's start scene (Project Settings > Run > Main Scene): a lit lab room behind the main menu.
## STUB: game_flow will own the start scene later; for now it only opens the main menu.
## CHANGED 2026-11-14 (roadmap WP27, Zachary OK'd the menu mock-up): instead of a plain dark backdrop, Zoology's
## animal holding room in warm light with a little haze and floating dust, seen from a slowly drifting camera.

const ROOM_SCENE: String = "res://systems/level_gen/tiles/tile_zoology_animal_holding.tscn"
const ROOM_DEPARTMENT: StringName = &"department_zoology"
const CAMERA_FROM: Vector3 = Vector3(15.5, 1.65, 16.5)
const CAMERA_LOOK_AT: Vector3 = Vector3(7.0, 1.2, 5.0)
## How far (metres) and how slowly (radians per second) the camera drifts side to side.
const DRIFT_METRES: float = 0.6
const DRIFT_SPEED: float = 0.12
const LIGHT_COLOR: Color = Color(1.0, 0.8, 0.55)
const LIGHT_ENERGY: float = 1.25
const DUST_COLOR: Color = Color(1.0, 0.85, 0.55, 0.7)

var _camera: Camera3D
var _time: float = 0.0


func _ready() -> void:
	var environment := WorldEnvironment.new()
	var look := Environment.new()
	look.background_mode = Environment.BG_COLOR
	look.background_color = Color(0.05, 0.035, 0.02)
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color(0.4, 0.32, 0.22)
	look.ambient_light_energy = 0.55
	look.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	look.tonemap_exposure = 1.1
	look.ssao_enabled = true
	look.glow_enabled = true
	look.fog_enabled = true
	look.fog_light_color = Color(0.38, 0.29, 0.18)
	look.fog_density = 0.018
	environment.environment = look
	add_child(environment)
	_add_room()
	_add_dust()
	_camera = Camera3D.new()
	_camera.position = CAMERA_FROM
	add_child(_camera)
	_camera.look_at(CAMERA_LOOK_AT)
	_camera.current = true
	UI.show_screen(UIService.SCREEN_MAIN_MENU)


func _process(delta: float) -> void:
	if _camera == null:
		return
	_time += delta
	_camera.position = CAMERA_FROM + Vector3(sin(_time * DRIFT_SPEED) * DRIFT_METRES, 0.0, 0.0)
	_camera.look_at(CAMERA_LOOK_AT)


func _add_room() -> void:
	var scene := load(ROOM_SCENE) as PackedScene
	if scene == null:
		return
	var room := scene.instantiate() as Node3D
	add_child(room)
	var department := ContentRegistry.get_content(ROOM_DEPARTMENT) as DepartmentData
	if department != null:
		TileStandards.apply_palette(room, department.palette)
	for light: Node in room.find_children("*", "Light3D", true, false):
		if light.is_in_group(TileStandards.LIGHT_GROUP):
			(light as Light3D).light_color = LIGHT_COLOR
			(light as Light3D).light_energy *= LIGHT_ENERGY
			(light as Light3D).shadow_enabled = true


func _add_dust() -> void:
	var dust := GPUParticles3D.new()
	dust.amount = 220
	dust.lifetime = 8.0
	dust.preprocess = 8.0
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(9.0, 1.5, 9.0)
	motion.gravity = Vector3(0.0, 0.02, 0.0)
	motion.initial_velocity_min = 0.02
	motion.initial_velocity_max = 0.08
	motion.spread = 180.0
	dust.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var speck := StandardMaterial3D.new()
	speck.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	speck.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	speck.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	speck.albedo_color = DUST_COLOR
	quad.material = speck
	dust.draw_pass_1 = quad
	dust.position = Vector3(9.0, 1.6, 9.0)
	add_child(dust)
