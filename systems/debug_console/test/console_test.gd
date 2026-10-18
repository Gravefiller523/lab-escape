extends Node3D
## Debug console test scene (run alone with F6, then with 2 windows). A grey floor with a player and a
## PropSpawner, so the real `prop` spawner works. Press ` to open and close the console.
## Things to try: help, list, list prop, validate, net, fps, spawn prop_crate 5, hello (a test cheat
## this scene adds; in the joining window it runs on the host and the answer comes back).
## Launch options after "--": "host", "join", "port=7795".

const FLOOR_HALF: float = 12.0


func _ready() -> void:
	_build_world()
	var players := PlayerSpawner.new()
	players.name = "PlayerSpawner"
	add_child(players)
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	DebugConsole.register_command(&"hello", _cmd_hello, "hello: a test cheat that says where it ran")
	_run_launch_options.call_deferred()
	DebugConsole.print_line.call_deferred("Debug console test. Type help to see every command.")


func _cmd_hello(_args: PackedStringArray, player_id: int) -> String:
	return "Hello %s, this ran on the %s." % [Net.get_display_name(player_id), "host" if Net.is_host() else "client"]


func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = 7795
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			port = arg.trim_prefix("port=").to_int()
	if args.has("host"):
		SteamSession.host_local(port)
	elif args.has("join"):
		SteamSession.join_local("127.0.0.1", port)


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.34, 0.38)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	add_child(sun)
	var body := StaticBody3D.new()
	body.position = Vector3(0, -0.25, 0)
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var size := Vector3(FLOOR_HALF * 2.0, 0.5, FLOOR_HALF * 2.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48, 0.49, 0.52)
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
