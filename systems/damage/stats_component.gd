class_name StatsComponent
extends Node
## Numbers that upgrades and status effects can change: max_health, move_speed, melee_damage,
## throw_strength, carry_strength (extra kg you can lift), damage_taken (a multiplier) ... Any name works:
## an unknown stat has base 0 (or 1 for multipliers, see get_value) and no modifiers, so new stats need no code.
## Value = (base + every add) x every multiply. Local data: every PC applies the same modifiers (upgrades
## and statuses are decided by the host and synced by their own systems). Spec: docs/systems/damage.md.

signal stat_changed(stat: StringName, value: float)

const NODE_NAME: String = "Stats"

var _base: Dictionary[StringName, float] = {}
## source id -> its modifiers.
var _modifiers: Dictionary[StringName, Array] = {}


## Finds the StatsComponent of a node (the node itself, a child named "Stats", or up the parents).
static func of(node: Node) -> StatsComponent:
	var current: Node = node
	while current != null:
		var stats := current as StatsComponent
		if stats != null:
			return stats
		stats = current.get_node_or_null(NodePath(NODE_NAME)) as StatsComponent
		if stats != null:
			return stats
		current = current.get_parent()
	return null


func _ready() -> void:
	name = NODE_NAME


func set_base(stat: StringName, value: float) -> void:
	var before: float = get_value(stat)
	_base[stat] = value
	_notify_if_changed(stat, before)


func get_base(stat: StringName, default: float = 0.0) -> float:
	return _base.get(stat, default)


## Base, plus all adds, times all multiplies. `default` is the base for a stat nobody set
## (use 1.0 for multipliers like damage_taken).
func get_value(stat: StringName, default: float = 0.0) -> float:
	var add: float = 0.0
	var multiply: float = 1.0
	for source_id: StringName in _modifiers:
		for modifier: StatEffectData in _modifiers[source_id]:
			if modifier.stat == stat:
				add += modifier.add
				multiply *= modifier.multiply
	return (get_base(stat, default) + add) * multiply


func add_modifier(source_id: StringName, modifier: StatEffectData) -> void:
	if modifier == null:
		return
	var before: float = get_value(modifier.stat)
	if not _modifiers.has(source_id):
		_modifiers[source_id] = []
	_modifiers[source_id].append(modifier)
	_notify_if_changed(modifier.stat, before)


## Removes every modifier that came from one source (an upgrade id, a status id).
func remove_modifiers(source_id: StringName) -> void:
	if not _modifiers.has(source_id):
		return
	var removed: Array = _modifiers[source_id]
	var befores: Dictionary[StringName, float] = {}
	for modifier: StatEffectData in removed:
		befores[modifier.stat] = get_value(modifier.stat)
	_modifiers.erase(source_id)
	for stat: StringName in befores:
		_notify_if_changed(stat, befores[stat])


func has_modifiers(source_id: StringName) -> bool:
	return _modifiers.has(source_id)


func _notify_if_changed(stat: StringName, before: float) -> void:
	var after: float = get_value(stat)
	if not is_equal_approx(before, after):
		stat_changed.emit(stat, after)
