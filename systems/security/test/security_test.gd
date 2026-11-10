extends Node3D
## NEW 2026-11-10 (floor generation step 4e): the security room on its own (run with F6). Builds a generated
## Robotics floor (floor 6, so parts are spread out and some cameras are broken) with the cargo lift, spawns
## the parts, and puts you in the security room. Press E at the table to lean over the map (E or a movement key
## stands back up); press E on a monitor's Prev and Next buttons to change its camera. Walk more than
## feed_active_radius away and the screens stop updating.

const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const FLOOR_NUMBER: int = 6
const FLOOR_SEED: int = 5151


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.1, 0.1, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.4, 0.4, 0.45)
	add_child(environment)
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var lift := LIFT_SCENE.instantiate() as CargoLift
	lift.position = Vector3(0, -40, 0)
	add_child(lift)
	var department := ContentRegistry.get_content(&"department_robotics") as DepartmentData
	var layout: FloorLayout = FloorGenerator.generate_from_seed(department, FLOOR_NUMBER, FLOOR_SEED, Config.floor_gen)
	Level.build(layout, self)
	var spot := Marker3D.new()
	spot.name = "StartSpot"
	add_child(spot)
	var table: SecurityMapTable = Security.get_map_table()
	if table != null:
		spot.global_transform = Transform3D(Basis.IDENTITY, table.global_position + Vector3(0, 0.2, 2.0))
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_points = [spot] as Array[Node3D]
	add_child(spawner)
	_start.call_deferred(lift, layout)


func _start(lift: CargoLift, layout: FloorLayout) -> void:
	if not multiplayer.is_server():
		return
	lift.arrive(1, false)
	EventBus.floor_ready.emit(FLOOR_NUMBER, layout.department_id)
