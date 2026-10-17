class_name BreakRoom
extends Node3D
## The Break Room: the lobby room where players arrive, walk around and step into the elevator to
## start a run (systems/break_room/break_room.tscn). Phase 1a grey box.
##
## STUBS until other systems exist:
## - interaction: stand next to a button and press Use (E) to press it.
## - cargo_lift: the elevator's "who's inside" check is ElevatorZoneStub.
## - game_flow: when the elevator start is accepted, a sign says so and the doors reopen after a few
##   seconds, instead of a run starting.
## - cosmetics / voice: the closet and mirror only show a message.

const SPAWN_RING_RADIUS: float = 3.0
## STUB (game_flow): seconds before the doors reopen after a start, since no run starts yet.
const STUB_REOPEN_SECONDS: float = 4.0
const DOOR_SPEED: float = 2.0
## How far from the middle each door panel sits when closed (metres).
const DOOR_CLOSED_X: float = 1.0

var _net: NetService
var _config: GameConfig
## Host: when someone first stood in the elevator (msec), or -1 if it's empty.
var _occupied_since_msec: int = -1
var _doors_closed: bool = false
var _starting: bool = false
## Which button areas the local player is standing in.
var _near: Dictionary[StringName, bool] = {}
## Door x positions, read from the scene: open is where they start, closed is DOOR_CLOSED_X.
var _left_open_x: float = 0.0
var _right_open_x: float = 0.0

@onready var _spawns: Node3D = %Spawns
@onready var _spawner: PlayerSpawner = %PlayerSpawner
@onready var _zone: ElevatorZoneStub = %ElevatorZone
@onready var _left_door: Node3D = %LeftDoor
@onready var _right_door: Node3D = %RightDoor
@onready var _missing_sign: Label3D = %MissingSign
@onready var _force_button: Node3D = %ForceButton
@onready var _whiteboard: Label3D = %WhiteboardText
@onready var _message: Label3D = %MessageSign


## For tests only: use a different Net and config. Call before adding the node to the tree.
func use_net(net: NetService, config: GameConfig) -> void:
	_net = net
	_config = config


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	_spawner.use_net(_net)
	_zone.use_net(_net)
	_spawner.spawn_points = get_spawn_points()
	_left_open_x = _left_door.position.x
	_right_open_x = _right_door.position.x
	for area_name: StringName in [&"StartButtonArea", &"ForceButtonArea", &"ClosetArea", &"MirrorArea"]:
		var area := get_node("%" + String(area_name)) as Area3D
		area.collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
		area.collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS)
		area.body_entered.connect(_on_area_body.bind(area_name, true))
		area.body_exited.connect(_on_area_body.bind(area_name, false))
	_zone.occupants_changed.connect(_on_occupants_changed)
	EventBus.run_ended.connect(_on_run_ended)
	_whiteboard.text = "Last run:\n(no runs yet)"
	_message.text = ""


## Spawn points for everyone: the ones in the scene, plus extra ones in a ring if max_players is larger.
func get_spawn_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for child: Node in _spawns.get_children():
		var point := child as Node3D
		if point != null:
			points.append(point)
	var placed: int = points.size()
	for index: int in range(placed, _config.max_players):
		var extra := Marker3D.new()
		extra.name = "ExtraSpawn%d" % index
		var angle: float = TAU * float(index) / float(maxi(_config.max_players, 1))
		extra.position = Vector3(cos(angle), 0.0, sin(angle)) * (SPAWN_RING_RADIUS + 1.5)
		_spawns.add_child(extra)
		points.append(extra)
	return points


## STUB until cargo_lift exists: returns the stand-in zone.
func get_elevator_zone() -> ElevatorZoneStub:
	return _zone


## Host: the "Start anyway" button is allowed (someone has waited in the elevator long enough).
func can_force_start() -> bool:
	if not _net.is_host() or _config.afk_force_start_after <= 0.0 or _occupied_since_msec < 0:
		return false
	return Time.get_ticks_msec() - _occupied_since_msec >= int(_config.afk_force_start_after * 1000.0)


## Local: the elevator button calls this. The host checks everyone is inside.
func request_start() -> void:
	_request_start_rpc.rpc_id(1)


## Host only: start even though some players are outside; they are moved into the elevator.
func request_force_start() -> void:
	if not can_force_start() or _starting:
		return
	var zone_spot: Vector3 = _zone.global_position
	var index: int = 0
	for player_id: int in _zone.get_missing_players():
		var body: PlayerCharacter = _spawner.get_body(player_id)
		if body != null:
			var offset := Vector3(float(index % 3) - 1.0, 0.1 - _zone.position.y, floorf(float(index) / 3.0) - 0.5)
			body.teleport(Transform3D(Basis.IDENTITY, zone_spot + offset * 0.8))
			index += 1
	_accept_start()


@rpc("any_peer", "call_local", "reliable")
func _request_start_rpc() -> void:
	if not _net.is_host() or _starting:
		return
	if _net.sender_player_id() == 0:
		return
	if _zone.contains_all_players():
		_accept_start()
	else:
		_start_refused.rpc_id(multiplayer.get_remote_sender_id(), _missing_names())


func _accept_start() -> void:
	_starting = true
	_start_accepted.rpc()


## Host -> everyone: the elevator start was accepted.
@rpc("authority", "call_local", "reliable")
func _start_accepted() -> void:
	_starting = true
	_doors_closed = true
	_message.text = "Elevator starting!\n(game_flow isn't built yet, so no run starts)"
	EventBus.elevator_start_accepted.emit()
	# STUB (game_flow): reopen so testing can carry on.
	get_tree().create_timer(STUB_REOPEN_SECONDS).timeout.connect(_reopen_after_stub)


@rpc("authority", "call_local", "reliable")
func _start_refused(missing_names: String) -> void:
	_message.text = "Can't start yet. Waiting for:\n" + missing_names
	EventBus.toast_requested.emit("Waiting for: " + missing_names)


func _reopen_after_stub() -> void:
	_starting = false
	_doors_closed = false
	_message.text = ""


func _process(delta: float) -> void:
	_left_door.position.x = move_toward(_left_door.position.x,
		-DOOR_CLOSED_X if _doors_closed else _left_open_x, DOOR_SPEED * delta)
	_right_door.position.x = move_toward(_right_door.position.x,
		DOOR_CLOSED_X if _doors_closed else _right_open_x, DOOR_SPEED * delta)
	var missing: String = _missing_names()
	_missing_sign.text = "Everyone's in! Press E at the button." if missing.is_empty() \
		else "Not in the elevator:\n" + missing
	_force_button.visible = can_force_start()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(InputActions.USE):
		return
	# STUB (interaction): pressing Use while standing next to something presses it.
	if _near.get(&"StartButtonArea", false):
		request_start()
	elif _near.get(&"ForceButtonArea", false) and can_force_start():
		request_force_start()
	elif _near.get(&"ClosetArea", false):
		EventBus.toast_requested.emit("Jacket closet: coming with the cosmetics system.")
		_message.text = "Jacket closet: coming later (cosmetics)."
	elif _near.get(&"MirrorArea", false):
		EventBus.toast_requested.emit("Mirror voice test: coming with the voice system.")
		_message.text = "Mirror voice test: coming later (voice)."


func _missing_names() -> String:
	var names: PackedStringArray = []
	for player_id: int in _zone.get_missing_players():
		names.append(_net.get_display_name(player_id))
	return ", ".join(names)


func _on_area_body(body: Node3D, area_name: StringName, entered: bool) -> void:
	var player := body as PlayerCharacter
	if player != null and player.is_local():
		_near[area_name] = entered


func _on_occupants_changed() -> void:
	if _zone.get_players_inside().is_empty():
		_occupied_since_msec = -1
	elif _occupied_since_msec < 0:
		_occupied_since_msec = Time.get_ticks_msec()


func _on_run_ended(result: StringName) -> void:
	_whiteboard.text = "Last run:\n%s" % String(result).capitalize()
