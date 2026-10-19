class_name HealthComponent
extends Node
## Health for anything that can be hurt: players, enemies, bosses, breakable props. Add it as a child
## named "Health" (the Damage autoload gives every player body one). Spec: docs/systems/damage.md.
##
## Only the host changes health. It sends the new numbers to every PC, so health_changed and died fire
## on every PC. A PC that joins (or a node that appears late) asks the host for the current numbers.
## A sibling StatsComponent can change it: stat "max_health" adds to / multiplies max_health, and stat
## "damage_taken" (default 1) multiplies all damage.

signal health_changed(current: float, maximum: float)
signal died(info: DamageInfo)
## NEW: health went from 0 back above 0 (revived). Fires on every PC.
signal revived()

const NODE_NAME: String = "Health"

@export var max_health: float = 100.0
## Damage type -> multiplier, e.g. {"fire": 2.0} for the ent. Types not listed take normal damage.
@export var damage_multipliers: Dictionary = {}
## God mode, spawn protection. Host only (not synced).
var invulnerable: bool = false

var _current: float = -1.0
var _maximum: float = 0.0
var _dead: bool = false


## Finds the HealthComponent of a node (the node itself, a child named "Health", or up the parents,
## so a hitbox or a weapon's collider finds its owner's health).
static func of(node: Node) -> HealthComponent:
	var current: Node = node
	while current != null:
		var health := current as HealthComponent
		if health != null:
			return health
		health = current.get_node_or_null(NodePath(NODE_NAME)) as HealthComponent
		if health != null:
			return health
		current = current.get_parent()
	return null


func _ready() -> void:
	name = NODE_NAME
	_maximum = _stat_max()
	if _current < 0.0:
		_current = _maximum
	var stats: StatsComponent = _stats()
	if stats != null:
		stats.stat_changed.connect(_on_stat_changed)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


func get_current() -> float:
	return _current


func get_max() -> float:
	return _maximum


func get_fraction() -> float:
	return _current / _maximum if _maximum > 0.0 else 0.0


func is_dead() -> bool:
	return _dead


## Host: hurt it. Multiplied by damage_multipliers[type] and the "damage_taken" stat. Knockback pushes
## players (through PlayerMovement) and physics bodies. Emits EventBus.damage_dealt.
func apply_damage(info: DamageInfo) -> void:
	if not _is_host() or info == null or _dead or invulnerable:
		return
	var type_multiplier: float = damage_multipliers.get(String(info.damage_type), 1.0)
	var amount: float = info.amount * type_multiplier
	var stats: StatsComponent = _stats()
	if stats != null:
		amount *= stats.get_value(&"damage_taken", 1.0)
	amount = maxf(amount, 0.0)
	_push(info.knockback)
	if amount <= 0.0:
		return
	_current = maxf(_current - amount, 0.0)
	EventBus.damage_dealt.emit(get_parent(), amount, info.damage_type, info.source)
	if not info.status_id.is_empty():
		var statuses: StatusEffectComponent = StatusEffectComponent.of(get_parent())
		if statuses != null:
			statuses.apply(info.status_id, info.source_player_id)
	if _current <= 0.0:
		_dead = true
		_state_rpc.rpc(_current, _maximum)
		# The host keeps the full info (with the source node); other PCs get a copy without it.
		died.emit(info)
		_died_rpc.rpc(info.amount, info.damage_type, info.source_player_id, info.hit_position)
	else:
		_state_rpc.rpc(_current, _maximum)


## Host: heal it (not above max, and not if dead: use revive).
func heal(amount: float) -> void:
	if not _is_host() or _dead or amount <= 0.0:
		return
	_current = minf(_current + amount, _maximum)
	_state_rpc.rpc(_current, _maximum)


## Host: bring it back with a fraction of max health (3D printer reprints, debug).
func revive(health_fraction: float = 1.0) -> void:
	if not _is_host():
		return
	_current = maxf(_maximum * clampf(health_fraction, 0.0, 1.0), 1.0)
	_state_rpc.rpc(_current, _maximum)


func _is_host() -> bool:
	return is_inside_tree() and multiplayer.is_server()


func _stats() -> StatsComponent:
	var parent: Node = get_parent()
	return parent.get_node_or_null(NodePath(StatsComponent.NODE_NAME)) as StatsComponent if parent != null else null


func _stat_max() -> float:
	var stats: StatsComponent = _stats()
	if stats == null:
		return max_health
	# The component's max_health is the base; upgrades add and multiply on top.
	if stats.get_base(&"max_health", -1.0) < 0.0:
		stats.set_base(&"max_health", max_health)
	return stats.get_value(&"max_health")


## Max health changed (an upgrade or a status): keep the same fraction of health. Every PC works it
## out; the host's numbers win when they arrive.
func _on_stat_changed(stat: StringName, _value: float) -> void:
	if stat != &"max_health" or not _is_host():
		return
	var fraction: float = get_fraction()
	_maximum = _stat_max()
	if not _dead:
		_current = maxf(_maximum * fraction, 1.0)
	_state_rpc.rpc(_current, _maximum)


func _push(knockback: Vector3) -> void:
	if knockback.is_zero_approx():
		return
	var owner_node: Node = get_parent()
	var player := owner_node as PlayerCharacter
	if player != null:
		player.get_movement().apply_knockback(knockback)
		return
	var body := owner_node as RigidBody3D
	if body != null:
		body.apply_central_impulse(knockback)


## Host -> everyone: the current numbers. Also fires "revived" when coming back from 0.
@rpc("authority", "call_local", "reliable")
func _state_rpc(current: float, maximum: float) -> void:
	if not is_inside_tree():
		return
	var was_dead: bool = _dead
	_current = current
	_maximum = maximum
	_dead = current <= 0.0
	health_changed.emit(_current, _maximum)
	if was_dead and not _dead:
		revived.emit()


## Host -> other PCs: it died (once). The info is rebuilt from what crosses the network (no source node).
@rpc("authority", "call_remote", "reliable")
func _died_rpc(amount: float, damage_type: StringName, source_player_id: int, hit_position: Vector3) -> void:
	if not is_inside_tree():
		return
	_dead = true
	var info := DamageInfo.make(amount, damage_type)
	info.source_player_id = source_player_id
	info.hit_position = hit_position
	died.emit(info)


## A client's copy appeared: ask the host for the numbers.
@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), _current, _maximum)
