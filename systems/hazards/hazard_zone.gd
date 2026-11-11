class_name HazardZone
extends Area3D
## NEW 2026-10-31 (floor generation step 4b): a placeholder hazard. Sparks (a crackling yellow light) and
## fire (an orange glow); NEW 2026-11-11 (step 5a): toxic spores (green motes), toxic gas (a haze) and water (a pool
## that slows players: Config.floor_gen.hazard_slow); any other kind looks like sparks for now. Everyone standing in
## it (players and enemies) is hurt through the damage system: only on the host, every hazard_tick_seconds.
## Spec: docs/systems/hazards.md.

const GROUP: StringName = &"hazards"
const HEIGHT: float = 2.2

var kind: StringName = &"sparks"
var _tick_left: float = 0.0
var _light: OmniLight3D
var _flicker_left: float = 0.0
var _rng := RandomNumberGenerator.new()
## NEW 2026-11-11 (step 5a): for the slow glow of spores and gas, and the players this zone slows down (water).
var _pulse: float = 0.0
var _slowed: Array[PlayerCharacter] = []


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
	# CHANGED 2026-11-11 (step 5a): toxic spores (drifting green motes), toxic gas (a yellow-green haze) and water
	# (a flat pool on the floor) look like themselves; other new kinds still look like sparks.
	match kind:
		&"toxic_spores":
			_build_spores(tuning)
			return
		&"toxic_gas":
			_build_haze(tuning, Color(0.75, 0.9, 0.3), 0.22)
			return
		&"water":
			_build_pool(tuning)
			return
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
	if _light == null:
		return
	if kind == &"toxic_spores" or kind == &"toxic_gas":
		_pulse += delta
		_light.light_energy = 0.6 + 0.4 * sin(_pulse * 1.7)
		return
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


# --- NEW 2026-11-11 (floor generation step 5a): Botany's hazards ------------------------------------------

## Drifting green motes and a soft green glow.
func _build_spores(tuning: FloorGenTuning) -> void:
	var color := Color(0.45, 1.0, 0.35)
	var material := _glow_material(color, 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for index: int in 14:
		var mote := MeshInstance3D.new()
		mote.name = "Mote%d" % index
		var sphere := SphereMesh.new()
		sphere.radius = 0.04
		sphere.height = 0.08
		sphere.material = material
		mote.mesh = sphere
		var angle: float = rng.randf() * TAU
		var reach: float = rng.randf() * tuning.hazard_radius
		mote.position = Vector3(cos(angle) * reach, rng.randf_range(0.3, 2.0), sin(angle) * reach)
		add_child(mote)
	_add_light(tuning, color)


## A see-through haze filling the zone (toxic gas).
func _build_haze(tuning: FloorGenTuning, color: Color, alpha: float) -> void:
	var haze := MeshInstance3D.new()
	haze.name = "Haze"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = tuning.hazard_radius
	cylinder.bottom_radius = tuning.hazard_radius
	cylinder.height = 1.8
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cylinder.material = material
	haze.mesh = cylinder
	haze.position.y = 0.9
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)
	_add_light(tuning, color)


## A flat pool of murky water on the floor. It slows players down (hazard_slow) and stings a little.
func _build_pool(tuning: FloorGenTuning) -> void:
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	var disc := CylinderMesh.new()
	disc.top_radius = tuning.hazard_radius
	disc.bottom_radius = tuning.hazard_radius
	disc.height = 0.04
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.2, 0.35, 0.3, 0.75)
	material.roughness = 0.05
	material.metallic = 0.3
	disc.material = material
	pool.mesh = disc
	pool.position.y = 0.03
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _add_light(tuning: FloorGenTuning, color: Color) -> void:
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = color
	_light.light_energy = 0.8
	_light.omni_range = tuning.hazard_radius * 2.5
	_light.position.y = 1.0
	add_child(_light)


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## Every PC: a player stepping into a slowing hazard moves slower until they step out (the owner's PC is the
## one that moves them; the others need it for the host's speed check).
func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerCharacter
	var tuning: FloorGenTuning = Config.floor_gen
	if player == null or not tuning.hazard_slow.has(kind) or _slowed.has(player):
		return
	var effect := MovementEffectData.new()
	effect.speed_multiplier = tuning.hazard_slow[kind]
	player.get_movement().set_modifier(_slow_source(), effect)
	_slowed.append(player)


func _on_body_exited(body: Node3D) -> void:
	var player := body as PlayerCharacter
	if player == null or not _slowed.has(player):
		return
	_slowed.erase(player)
	if is_instance_valid(player) and player.get_movement() != null:
		player.get_movement().remove_modifier(_slow_source())


func _exit_tree() -> void:
	for player: PlayerCharacter in _slowed:
		if is_instance_valid(player) and player.get_movement() != null:
			player.get_movement().remove_modifier(_slow_source())
	_slowed.clear()


## Is this player slowed by this zone now? (For tests.)
func is_slowing(player: PlayerCharacter) -> bool:
	return _slowed.has(player)


func _slow_source() -> StringName:
	return StringName("hazard_%d" % get_instance_id())
