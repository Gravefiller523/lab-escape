extends Node
## cargo_lift test scene (run with F6, then with 2 windows). The game world with a generated floor
## around the cargo lift: find the lift part (the room farthest away), carry it back, drop it in the
## socket on the lift's back wall, get everyone in and press Go. game_flow isn't in charge here, so
## this scene does its job: it builds a new floor during the ride and the lift arrives broken again.
## Launch options after "--": "host", "join", "port=7796".

const WORLD_SCENE: PackedScene = preload("res://systems/game_flow/game_world.tscn")

var _world: GameWorld
var _floor_number: int = 1
var _status: Label


func _ready() -> void:
	_world = WORLD_SCENE.instantiate() as GameWorld
	add_child(_world)
	_build_floor()
	var spawner: PlayerSpawner = _world.get_player_spawner()
	spawner.spawn_points = _world.get_lift().get_spawn_points()
	spawner.auto_spawn = true
	spawner.spawn_all(spawner.spawn_points)
	_arrive.call_deferred()
	EventBus.lift_departed.connect(_on_lift_departed)
	var layer := CanvasLayer.new()
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(12, 12)
	layer.add_child(_status)
	EventBus.toast_requested.connect(func(text: String) -> void: _status.text = text)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = 7796
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			port = arg.trim_prefix("port=").to_int()
	if args.has("host"):
		SteamSession.host_local.call_deferred(port)
	elif args.has("join"):
		SteamSession.join_local.call_deferred("127.0.0.1", port)


func _build_floor() -> void:
	var department: DepartmentData = GameFlow.get_department(GameFlowService.PLACEHOLDER_DEPARTMENT_ID)
	_world.build_floor(LevelGenerator.generate(department, 1, _floor_number, 4242, 1))


## Host: the lift is here and broken; the part appears (cargo_lift does that on floor_ready).
func _arrive() -> void:
	if not multiplayer.is_server():
		return
	_world.get_lift().arrive(1, false)
	_floor_ready_rpc.rpc(_floor_number)


@rpc("authority", "call_local", "reliable")
func _floor_ready_rpc(floor_number: int) -> void:
	_floor_number = floor_number
	EventBus.floor_ready.emit(floor_number, GameFlowService.PLACEHOLDER_DEPARTMENT_ID)


## Every PC: the lift left: build the next floor while it rides; the host makes it arrive.
func _on_lift_departed(_from_floor: int) -> void:
	_floor_number += 1
	_build_floor()
	if multiplayer.is_server():
		# Props left outside the lift stay behind (as in the game).
		var keep: Array[NetProp] = _world.get_lift().get_zone().get_props_inside()
		for prop: NetProp in _world.get_prop_spawner().get_props():
			if not keep.has(prop) and not prop.is_held():
				_world.get_prop_spawner().despawn(prop)
		get_tree().create_timer(Config.game.lift_ride_seconds).timeout.connect(_arrive)
