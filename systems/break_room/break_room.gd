class_name BreakRoom
extends Node3D
## The Break Room: the lobby where players arrive, walk around and get into the cargo lift to start a
## run (systems/break_room/break_room.tscn). Phase 1a grey box.
##
## CHANGED 2026-10-19: the Break Room is "floor 0" around the cargo lift. game_flow loads it into the
## game world and lines its LiftSpot up with the lift, which does the starting (Go, "Start anyway",
## who's missing). The room keeps the spawn points, the jacket closet, the mirror, the whiteboard
## and a few props to play with.
##
## The jacket closet and the mirror are Interactables: look at one and press E (their `used` fires on
## the host). CHANGED 2026-11-13 (roadmap WP17): the closet opens the jacket closet screen for whoever used it. STUB
## until voice exists: the mirror only shows a message.

const SPAWN_RING_RADIUS: float = 3.0
## NEW 2026-11-12 (roadmap WP8, decision D5): the whiteboard notice that tells the premise.
const WHITEBOARD_NOTICE: String = """NIGHT SHIFT NOTICE
To save money, staff are now reprinted from meat
by the Lab Assistant AI.
The experiments have escaped. Please do not.
The cargo lift is out of order. Again.

(scrawled underneath:) fix lift, go UP, get out"""

var _net: NetService
var _config: GameConfig
var _props: PropSpawner
## What opening the closet does on the PC of the player who used it (tests swap it; default Cosmetics.open_closet).
var _closet_opener: Callable

@onready var _spawns: Node3D = %Spawns
@onready var _lift_spot: Node3D = %LiftSpot
@onready var _whiteboard: Label3D = %WhiteboardText
@onready var _message: Label3D = %MessageSign
@onready var _closet_use: Interactable = %ClosetUse
@onready var _mirror_use: Interactable = %MirrorUse
@onready var _fun_props: Node3D = %FunProps


## For tests only: a different Net and config, and the prop spawner the fun props go into (default:
## the game world's, through the Props autoload). Call before adding the node to the tree.
func use_net(net: NetService, config: GameConfig, prop_spawner: PropSpawner = null) -> void:
	_net = net
	_config = config
	_props = prop_spawner


## NEW 2026-11-13 (roadmap WP17), for tests only: what opening the closet does on the user's PC.
func use_closet_opener(opener: Callable) -> void:
	_closet_opener = opener


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	for use: Interactable in [_closet_use, _mirror_use]:
		var body := use.get_anchor() as CollisionObject3D
		body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
		body.collision_mask = 0
	if not _closet_opener.is_valid():
		_closet_opener = Cosmetics.open_closet
	_closet_use.used.connect(_open_closet_for)
	_mirror_use.used.connect(_show_note_to.bind("Mirror voice test: coming with the voice system."))
	EventBus.run_ended.connect(_on_run_ended)
	var last: StringName = GameFlow.get_last_run_result()
	_show_whiteboard(String(last).capitalize() if last != &"" else "(no runs yet)")
	_message.text = ""
	if multiplayer.is_server():
		_spawn_fun_props.call_deferred()


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


## NEW 2026-10-19: where the cargo lift stands (game_flow lines this up with the lift; it faces the room).
func get_lift_spot() -> Node3D:
	return _lift_spot


## NEW 2026-11-12 (roadmap WP8): the whiteboard text (the game's premise, decision D5).
func get_whiteboard_text() -> String:
	return _whiteboard.text


func _on_run_ended(result: StringName) -> void:
	_show_whiteboard(String(result).capitalize())


## CHANGED 2026-11-12 (roadmap WP8, mock-up approved by Zachary): the board tells the premise, with the last run's
## result at the bottom.
func _show_whiteboard(last_run: String) -> void:
	_whiteboard.text = "%s\n\nLast run: %s" % [WHITEBOARD_NOTICE, last_run]


## NEW 2026-11-13 (roadmap WP17). Host: open the jacket closet on the PC of the player who used it.
func _open_closet_for(player_id: int) -> void:
	var peer_id: int = _net.get_peer_id(player_id)
	if peer_id != 0:
		_open_closet.rpc_id(peer_id)


@rpc("authority", "call_local", "reliable")
func _open_closet() -> void:
	if is_inside_tree() and _closet_opener.is_valid():
		_closet_opener.call()


## Host: show a short message to the player who used something (the mirror placeholder).
func _show_note_to(player_id: int, text: String) -> void:
	var peer_id: int = _net.get_peer_id(player_id)
	if peer_id != 0:
		_show_note.rpc_id(peer_id, text)


@rpc("authority", "call_local", "reliable")
func _show_note(text: String) -> void:
	if not is_inside_tree():
		return
	EventBus.toast_requested.emit(text)
	_message.text = text


## Host: a few props to play with. Each Marker3D under FunProps has a "prop_id" (scene data, not code).
func _spawn_fun_props() -> void:
	# Checked again here: in tests a PC can become a client between _ready and this call.
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var spawner: PropSpawner = _props if _props != null else Props.get_spawner()
	if spawner == null:
		return
	for marker: Node in _fun_props.get_children():
		var spot := marker as Node3D
		if spot != null and spot.has_meta(&"prop_id"):
			spawner.spawn_prop(StringName(str(spot.get_meta(&"prop_id"))), spot.global_transform)
