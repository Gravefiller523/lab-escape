class_name TaskStation
extends Node3D
## A building block for floor tasks (NEW 2026-11-13, roadmap WP15): a box players stand in to take part (the hamster
## wheel's running belt). It only answers "who is in me right now"; the task decides what that does. It reads
## positions, which every PC has (players' bodies are synced), so it works the same on the host and on clients.
## Spec: docs/systems/objectives.md.

signal occupant_changed(player_id: int)

## The box, in the station's own space: centred on its origin in x and z, from the floor up.
@export var size: Vector3 = Vector3(2.4, 2.0, 3.2)

var _occupants: Array[int] = []


## The living players standing in it now (ghosts don't count).
func get_occupants() -> Array[PlayerCharacter]:
	var found: Array[PlayerCharacter] = []
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var player := node as PlayerCharacter
		if player != null and not player.is_ghost() and player.get_world_3d() == get_world_3d() and contains(player.global_position):
			var health: HealthComponent = HealthComponent.of(player)
			if health == null or not health.is_dead():
				found.append(player)
	return found


## The first occupant's id, or 0.
func get_occupant() -> int:
	var found: Array[PlayerCharacter] = get_occupants()
	return found[0].player_id if not found.is_empty() else 0


## Is this point (a player's feet) inside the box?
func contains(point: Vector3) -> bool:
	var local: Vector3 = global_transform.affine_inverse() * point
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5 and local.y >= -0.5 and local.y <= size.y


func _physics_process(_delta: float) -> void:
	var now: Array[int] = []
	for player: PlayerCharacter in get_occupants():
		now.append(player.player_id)
	for player_id: int in now:
		if not _occupants.has(player_id):
			occupant_changed.emit(player_id)
	for player_id: int in _occupants:
		if not now.has(player_id):
			occupant_changed.emit(player_id)
	_occupants = now
