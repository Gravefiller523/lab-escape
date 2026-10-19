class_name EnemySpawner
extends Node3D
## Spawns enemies for everyone through a MultiplayerSpawner (late joiners get them too). The Enemies
## autoload has one; tests and test scenes can make their own. Spec: docs/systems/enemies.md.

var _replicator: MultiplayerSpawner
var _next_id: int = 1


func _ready() -> void:
	_replicator = MultiplayerSpawner.new()
	_replicator.name = "EnemyReplicator"
	add_child(_replicator)
	_replicator.spawn_path = _replicator.get_path_to(self)
	_replicator.spawn_function = _make_enemy


## Host: spawn an enemy for everyone. Its health is max_health x health_multiplier. Null if unknown.
func spawn(enemy_id: StringName, xform: Transform3D, health_multiplier: float = 1.0, rng_seed: int = 0) -> Enemy:
	if not multiplayer.is_server():
		push_error("EnemySpawner.spawn: only the host spawns enemies.")
		return null
	var data := ContentRegistry.get_content(enemy_id) as EnemyData
	if data == null or data.scene == null:
		push_error("EnemySpawner.spawn: no enemy called '%s' (or it has no scene)." % enemy_id)
		return null
	var net_id: int = _next_id
	_next_id += 1
	return _replicator.spawn({"enemy_id": String(enemy_id), "net_id": net_id, "xform": xform,
		"health": health_multiplier, "seed": rng_seed}) as Enemy


func get_alive() -> Array[Enemy]:
	var alive: Array[Enemy] = []
	for child: Node in get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead() and not enemy.is_queued_for_deletion():
			alive.append(enemy)
	return alive


## Host: remove every enemy (between floors).
func despawn_all() -> void:
	if not multiplayer.is_server():
		return
	for child: Node in get_children():
		if child is Enemy:
			child.queue_free()


## Every PC (the MultiplayerSpawner replays it for late joiners).
func _make_enemy(spawn_data: Variant) -> Node:
	var info: Dictionary = spawn_data
	var enemy_id := StringName(str(info["enemy_id"]))
	var data := ContentRegistry.get_content(enemy_id) as EnemyData
	var enemy := data.scene.instantiate() as Enemy
	var net_id: int = info["net_id"]
	var health_multiplier: float = info["health"]
	var rng_seed: int = info["seed"]
	enemy.name = "Enemy%d" % net_id
	enemy.transform = info["xform"]
	enemy.setup(data, health_multiplier, rng_seed, net_id)
	_next_id = maxi(_next_id, net_id + 1)
	return enemy
