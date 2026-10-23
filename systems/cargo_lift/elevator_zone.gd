class_name ElevatorZone
extends Area3D
## The inside of a lift: who (and what) is in it. Used by the CargoLift to decide if it may leave,
## and by game_flow to know which props ride along.

signal occupants_changed()

var _net: NetService
var _inside: Array[int] = []


## For tests only: use a different Net. Call before adding the node to the tree.
func use_net(net: NetService) -> void:
	_net = net


func _ready() -> void:
	if _net == null:
		_net = Net
	collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS) | PhysicsLayers.bit(PhysicsLayers.PROPS) \
		| PhysicsLayers.bit(PhysicsLayers.CARTS)
	monitorable = false


func _physics_process(_delta: float) -> void:
	var now: Array[int] = []
	for body: Node3D in get_overlapping_bodies():
		var player := body as PlayerCharacter
		if player != null and not now.has(player.player_id):
			now.append(player.player_id)
	now.sort()
	if now != _inside:
		_inside = now
		occupants_changed.emit()


func get_players_inside() -> Array[int]:
	return _inside.duplicate()


## Connected players who should be here but aren't. Players waiting for the next floor don't count.
func get_missing_players() -> Array[int]:
	var missing: Array[int] = []
	for player_id: int in _net.get_player_ids():
		var record: PlayerRecord = _net.get_record(player_id)
		# CHANGED 2026-10-23 (death_respawn branch): dead players (ghosts) aren't waited for; they come along.
		var dead: bool = record != null and not record.is_alive
		if not _inside.has(player_id) and not _net.is_waiting_for_next_floor(player_id) and not dead:
			missing.append(player_id)
	return missing


func contains_all_players() -> bool:
	return get_missing_players().is_empty()


## Props (and carts, with what's in them) inside the lift right now.
func get_props_inside() -> Array[NetProp]:
	var props: Array[NetProp] = []
	for body: Node3D in get_overlapping_bodies():
		var prop := body as NetProp
		if prop != null and not prop.is_queued_for_deletion():
			props.append(prop)
	return props
