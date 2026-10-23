class_name EnemySpawner
extends Node3D
## Spawns enemies for everyone through a MultiplayerSpawner (late joiners get them too). The Enemies
## autoload has one; tests and test scenes can make their own. Spec: docs/systems/enemies.md.

var _replicator: MultiplayerSpawner
var _next_id: int = 1
## NEW 2026-10-23: the connection this spawner last saw, and how each enemy was spawned (to respawn them).
var _peer_seen: MultiplayerPeer
var _spawn_info: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	_replicator = MultiplayerSpawner.new()
	_replicator.name = "EnemyReplicator"
	add_child(_replicator)
	_replicator.spawn_path = _replicator.get_path_to(self)
	_replicator.spawn_function = _make_enemy
	_peer_seen = multiplayer.multiplayer_peer


## Host: spawn an enemy for everyone. Its health is max_health x health_multiplier. Null if unknown.
## CHANGED 2026-10-23 (bosses branch): also takes BossData ids (a Boss is an Enemy; see Enemy.setup_from).
func spawn(enemy_id: StringName, xform: Transform3D, health_multiplier: float = 1.0, rng_seed: int = 0) -> Enemy:
	if not multiplayer.is_server():
		push_error("EnemySpawner.spawn: only the host spawns enemies.")
		return null
	if _scene_of(ContentRegistry.get_content(enemy_id)) == null:
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
	var content: ContentData = ContentRegistry.get_content(enemy_id)
	var enemy := _scene_of(content).instantiate() as Enemy
	var net_id: int = info["net_id"]
	var health_multiplier: float = info["health"]
	var rng_seed: int = info["seed"]
	enemy.name = "Enemy%d" % net_id
	enemy.transform = info["xform"]
	enemy.setup_from(content, health_multiplier, rng_seed, net_id)
	_next_id = maxi(_next_id, net_id + 1)
	_spawn_info[StringName(enemy.name)] = info
	enemy.tree_exiting.connect(func() -> void: _spawn_info.erase(StringName(enemy.name)))
	return enemy


## The scene of an EnemyData or BossData, or null.
static func _scene_of(content: ContentData) -> PackedScene:
	var enemy_data := content as EnemyData
	if enemy_data != null:
		return enemy_data.scene
	var boss_data := content as BossData
	return boss_data.scene if boss_data != null else null


## NEW 2026-10-23: a new connection (hosting or joining after playing alone). Enemies spawned before it
## only exist on this PC: a host spawns them again so everyone gets them; a client drops its copies and
## gets the host's. (Same idea as physics_props' PropSpawner.)
func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == _peer_seen:
		return
	_peer_seen = multiplayer.multiplayer_peer
	var keep: Array[Dictionary] = []
	for enemy: Enemy in get_alive():
		var info: Dictionary = _spawn_info.get(StringName(enemy.name), {})
		if not info.is_empty():
			var again: Dictionary = info.duplicate()
			again["xform"] = enemy.global_transform
			keep.append(again)
	for child: Node in get_children():
		if child is Enemy:
			remove_child(child)
			child.queue_free()
	_spawn_info.clear()
	_next_id = 1
	if not multiplayer.is_server():
		return
	for info: Dictionary in keep:
		var enemy_id := StringName(str(info["enemy_id"]))
		var xform: Transform3D = info["xform"]
		var health_multiplier: float = info["health"]
		var rng_seed: int = info["seed"]
		spawn(enemy_id, xform, health_multiplier, rng_seed)
