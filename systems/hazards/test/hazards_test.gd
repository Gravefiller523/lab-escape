extends Node3D
## Test scene for hazards (run alone with F6): a floor with a sparks zone (left) and a fire zone (right).
## Walk into them and watch your health at the top left. Numbers: config/floor_gen_tuning.tres, "Hazards".

var _info: Label


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.22, 0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	add_child(environment)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	floor_body.position = Vector3(0, -0.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	floor_body.add_child(mesh)
	add_child(floor_body)
	for kind: StringName in [&"sparks", &"fire"]:
		var zone := HazardZone.new()
		zone.setup(kind)
		zone.position = Vector3(-4.0 if kind == &"sparks" else 4.0, 0, -6)
		add_child(zone)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(12, 12)
	layer.add_child(_info)


func _process(_delta: float) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	var health: HealthComponent = HealthComponent.of(body) if body != null else null
	_info.text = "Sparks on the left, fire on the right. Walk in.\nHealth: %s" % (
		"%.0f / %.0f" % [health.get_current(), health.get_max()] if health != null else "(no body yet)")
