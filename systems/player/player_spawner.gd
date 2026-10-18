class_name PlayerSpawner
extends Node
## Put one in every playable scene (Break Room, floors, test scenes). It spawns and removes player
## bodies for everyone, using a MultiplayerSpawner it creates as its child. Only the host decides.
##
## Automatic behaviour on the host:
## - when the scene starts, and when a player joins or reconnects: spawn their body,
##   unless they joined mid-run and are waiting for the next floor;
## - on floor_ready: spawn anyone connected who has no body yet (that's when waiting players appear);
## - when a player leaves: remove their body.
## Bodies are children of `container` (this node's parent if not set), named by player id.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

## Where bodies appear, used in turn. If empty, bodies appear around this node.
@export var spawn_points: Array[Node3D] = []
## Where the bodies go in the scene tree. Defaults to this node's parent.
@export var container: Node3D
## Spawns bodies by itself (see above). Turn off if another system wants to place players itself.
@export var auto_spawn: bool = true

var _net: NetService
var _spawner: MultiplayerSpawner
var _peer_seen: MultiplayerPeer
var _next_point: int = 0


## For tests only: use a different Net. Call before adding the node to the tree.
func use_net(net: NetService) -> void:
	_net = net


func _ready() -> void:
	if _net == null:
		_net = Net
	if container == null:
		container = get_parent() as Node3D
	_create_spawner()

	EventBus.player_joined.connect(_on_player_joined)
	EventBus.player_reconnected.connect(_on_player_joined)
	EventBus.player_left.connect(_on_player_left)
	EventBus.floor_ready.connect(_on_floor_ready)
	_peer_seen = multiplayer.multiplayer_peer
	if auto_spawn:
		_spawn_missing.call_deferred()


func _process(_delta: float) -> void:
	# When the connection changes (hosting, joining, leaving), bodies from the old session are stale.
	# Net (an autoload, so it runs first) has already rebuilt its roster this frame.
	if multiplayer.multiplayer_peer != _peer_seen:
		_peer_seen = multiplayer.multiplayer_peer
		_clear_local_bodies()
		if auto_spawn:
			_spawn_missing()


## Host. Spawns every connected player who isn't waiting for the next floor, one per spawn point.
func spawn_all(points: Array[Node3D]) -> void:
	spawn_points = points
	_next_point = 0
	_spawn_missing()


## Host. Spawns one body. Returns null if not allowed or already spawned.
func spawn_player(player_id: int, xform: Transform3D) -> PlayerCharacter:
	if not _net.is_host():
		push_error("PlayerSpawner.spawn_player: only the host spawns players.")
		return null
	if _find_body(player_id) != null:
		return null
	var peer_id: int = _net.get_peer_id(player_id)
	if peer_id == 0:
		return null
	return _spawner.spawn({"player_id": player_id, "peer_id": peer_id, "xform": xform}) as PlayerCharacter


## Host. Removes a body (for everyone).
func despawn_player(player_id: int) -> void:
	if not _net.is_host():
		return
	var body: PlayerCharacter = _find_body(player_id)
	if body != null:
		body.queue_free()


## The body of a player under this spawner. Null if none.
func get_body(player_id: int) -> PlayerCharacter:
	return _find_body(player_id)


## Runs on every PC (the MultiplayerSpawner calls it for the host's spawn() and replays it for
## everyone who joins later).
func _make_body(data: Variant) -> Node:
	var info: Dictionary = data
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = info["player_id"]
	body.name = str(body.player_id)
	var peer_id: int = info["peer_id"]
	body.set_multiplayer_authority(peer_id)
	body.transform = info["xform"]
	return body


func _spawn_missing() -> void:
	if not _net.is_host():
		return
	for player_id: int in _net.get_player_ids():
		if not _net.is_waiting_for_next_floor(player_id):
			spawn_player(player_id, _next_spawn_transform())


func _next_spawn_transform() -> Transform3D:
	if spawn_points.is_empty():
		# Spread bodies in a small circle so they don't spawn inside each other.
		var angle: float = TAU * float(_next_point) / 8.0
		_next_point += 1
		var base: Vector3 = container.global_position if container != null else Vector3.ZERO
		return Transform3D(Basis.IDENTITY, base + Vector3(cos(angle), 0.0, sin(angle)) * 1.5)
	var point: Node3D = spawn_points[_next_point % spawn_points.size()]
	_next_point += 1
	return point.global_transform


func _find_body(player_id: int) -> PlayerCharacter:
	if container == null:
		return null
	var body := container.get_node_or_null(NodePath(str(player_id))) as PlayerCharacter
	if body == null or body.is_queued_for_deletion():
		return null
	return body


func _create_spawner() -> void:
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "BodySpawner"
	add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(container)
	_spawner.spawn_function = _make_body


## Removes every body on this PC only (bodies from an old connection).
func _clear_local_bodies() -> void:
	for child: Node in container.get_children():
		if child is PlayerCharacter:
			container.remove_child(child)
			child.queue_free()


func _on_player_joined(player_id: int) -> void:
	# A level being unloaded (e.g. the host left and we go back to the menu) spawns nobody.
	if not is_inside_tree():
		return
	if auto_spawn and _net.is_host() and not _net.is_waiting_for_next_floor(player_id):
		spawn_player(player_id, _next_spawn_transform())


func _on_player_left(player_id: int) -> void:
	despawn_player(player_id)


func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	if auto_spawn:
		_spawn_missing()
