class_name ElevatorZoneStub
extends Area3D
## STUB for cargo_lift's ElevatorZone (docs/systems/cargo_lift.md), which isn't built yet.
## Same functions (minus props): who is standing inside the elevator? Swap it for the real
## ElevatorZone when cargo_lift is merged.

signal occupants_changed()

var _net: NetService
var _inside: Array[int] = []


## For tests only: use a different Net.
func use_net(net: NetService) -> void:
	_net = net


func _ready() -> void:
	if _net == null:
		_net = Net
	collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS)
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
		if not _inside.has(player_id) and not _net.is_waiting_for_next_floor(player_id):
			missing.append(player_id)
	return missing


func contains_all_players() -> bool:
	return get_missing_players().is_empty()
