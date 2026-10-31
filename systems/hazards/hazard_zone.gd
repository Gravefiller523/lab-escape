class_name HazardZone
extends Area3D
## NEW 2026-10-31 (floor generation step 4b): a placeholder hazard. Sparks (a crackling yellow light) and
## fire (an orange glow); any other kind looks like sparks for now. Everyone standing in it (players and
## enemies) is hurt through the damage system: only on the host, every Config.floor_gen.hazard_tick_seconds.
## Spec: docs/systems/hazards.md.

const GROUP: StringName = &"hazards"
const HEIGHT: float = 2.2

var kind: StringName = &"sparks"
var _tick_left: float = 0.0
var _light: OmniLight3D
var _flicker_left: float = 0.0
var _rng := RandomNumberGenerator.new()


## The hazard kind ("sparks", "fire"...). Call before adding it to the tree.
func setup(hazard_kind: StringName) -> void:
	kind = hazard_kind


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS) | PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	monitorable = false
	var tuning: FloorGenTuning = Config.floor_gen
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = tuning.hazard_radius
	cylinder.height = HEIGHT
	shape.shape = cylinder
	shape.position.y = HEIGHT / 2.0
	add_child(shape)
	_build_look(tuning)
	# Looks only: each PC flickers on its own (seeded by where it is, so they look alike).
	_rng.seed = hash(str(global_position.snapped(Vector3.ONE * 0.1)))
	_tick_left = tuning.hazard_tick_seconds


func _build_look(tuning: FloorGenTuning) -> void:
	var fire: bool = kind == &"fire"
	var color := Color(1.0, 0.45, 0.1) if fire else Color(1.0, 0.9, 0.3)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var mesh: PrimitiveMesh = CylinderMesh.new() if fire else BoxMesh.new()
	if fire:
		var cone := mesh as CylinderMesh
		cone.top_radius = 0.05
		cone.bottom_radius = tuning.hazard_radius * 0.5
		cone.height = 1.0
	else:
		(mesh as BoxMesh).size = Vector3(0.15, 0.15, 0.15)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	glow.mesh = mesh
	glow.position.y = 0.5 if fire else 1.6
	add_child(glow)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = color
	_light.omni_range = tuning.hazard_radius * 3.0
	_light.position.y = 1.2
	add_child(_light)


func _process(delta: float) -> void:
	_flicker_left -= delta
	if _flicker_left > 0.0:
		return
	if kind == &"fire":
		_flicker_left = _rng.randf_range(0.05, 0.15)
		_light.light_energy = _rng.randf_range(1.2, 2.0)
	else:
		_flicker_left = _rng.randf_range(0.02, 0.3)
		_light.light_energy = 2.5 if _rng.randf() < 0.3 else 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var tuning: FloorGenTuning = Config.floor_gen
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tuning.hazard_tick_seconds
	var per_second: float = tuning.hazard_damage_per_second.get(kind, tuning.hazard_damage_per_second.get(&"sparks", 0.0))
	var damage_type: StringName = tuning.hazard_damage_types.get(kind, &"electric")
	for body: Node3D in get_overlapping_bodies():
		var health: HealthComponent = HealthComponent.of(body)
		if health == null or health.is_dead():
			continue
		var info := DamageInfo.make(per_second * tuning.hazard_tick_seconds, damage_type, self)
		info.hit_position = body.global_position
		health.apply_damage(info)
