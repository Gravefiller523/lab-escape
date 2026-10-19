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
## the host). STUBS until other systems exist: cosmetics / voice: they only show a message.

const SPAWN_RING_RADIUS: float = 3.0

var _net: NetService
var _config: GameConfig
var _props: PropSpawner

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


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	for use: Interactable in [_closet_use, _mirror_use]:
		var body := use.get_anchor() as CollisionObject3D
		body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
		body.collision_mask = 0
	_closet_use.used.connect(_show_note_to.bind("Jacket closet: coming with the cosmetics system."))
	_mirror_use.used.connect(_show_note_to.bind("Mirror voice test: coming with the voice system."))
	EventBus.run_ended.connect(_on_run_ended)
	var last: StringName = GameFlow.get_last_run_result()
	_whiteboard.text = "Last run:\n%s" % (String(last).capitalize() if last != &"" else "(no runs yet)")
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


func _on_run_ended(result: StringName) -> void:
	_whiteboard.text = "Last run:\n%s" % String(result).capitalize()


## Host: show a short message to the player who used something (closet, mirror placeholders).
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
