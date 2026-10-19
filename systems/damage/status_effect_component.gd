class_name StatusEffectComponent
extends Node
## Timed effects on a player or enemy, e.g. burning or a speed boost (StatusEffectData content in
## content/status_effects/). Add it as a child named "Statuses" (the Damage autoload gives every player
## body one). Spec: docs/systems/damage.md.
##
## The host starts, ticks and ends effects, and sends the list of active ids to every PC. Every PC then
## applies the effect's stat modifiers to the sibling StatsComponent and shows its visual_scene, so a
## new status effect is just a new .tres file. Tick damage goes through the sibling HealthComponent.
## A dead target loses all its effects.

signal status_added(status_id: StringName)
signal status_removed(status_id: StringName)

const NODE_NAME: String = "Statuses"
const VISUAL_PREFIX: String = "StatusVisual_"

## Host only: one running effect.
class ActiveTimer:
	## Seconds left, or -1 = until removed.
	var left: float = -1.0
	## Seconds to the next damage tick.
	var tick: float = 0.0
	var source_player_id: int = 0


## Host only: status id -> its timer.
var _timers: Dictionary[StringName, ActiveTimer] = {}
## Every PC: what is active here now, in the order it started.
var _active: Array[StringName] = []


static func of(node: Node) -> StatusEffectComponent:
	var current: Node = node
	while current != null:
		var statuses := current as StatusEffectComponent
		if statuses != null:
			return statuses
		statuses = current.get_node_or_null(NodePath(NODE_NAME)) as StatusEffectComponent
		if statuses != null:
			return statuses
		current = current.get_parent()
	return null


func _ready() -> void:
	name = NODE_NAME
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


func has_status(status_id: StringName) -> bool:
	return _active.has(status_id)


func get_active() -> Array[StringName]:
	return _active.duplicate()


## Host: start an effect (or restart its timer if refresh_on_reapply). Unknown ids are ignored with an error.
func apply(status_id: StringName, source_player_id: int = 0) -> void:
	if not _is_host():
		return
	var data := ContentRegistry.get_content(status_id) as StatusEffectData
	if data == null:
		push_error("StatusEffectComponent.apply: no status effect '%s'." % status_id)
		return
	var health: HealthComponent = _health()
	if health != null and health.is_dead():
		return
	if _timers.has(status_id) and not data.refresh_on_reapply:
		return
	var timer := ActiveTimer.new()
	timer.left = data.duration if data.duration > 0.0 else -1.0
	timer.tick = data.tick_interval
	timer.source_player_id = source_player_id
	_timers[status_id] = timer
	if not _active.has(status_id):
		_send_active()


## Host: end an effect now.
func remove(status_id: StringName) -> void:
	if not _is_host() or not _timers.has(status_id):
		return
	_timers.erase(status_id)
	_send_active()


## Host: seconds left on an effect (-1 = until removed, 0 = not active).
func get_time_left(status_id: StringName) -> float:
	if not _timers.has(status_id):
		return 0.0
	return _timers[status_id].left


func _process(delta: float) -> void:
	if _timers.is_empty() or not _is_host():
		return
	var health: HealthComponent = _health()
	if health != null and health.is_dead():
		_timers.clear()
		_send_active()
		return
	var ended: Array[StringName] = []
	for status_id: StringName in _timers.keys():
		var data := ContentRegistry.get_content(status_id) as StatusEffectData
		var timer: ActiveTimer = _timers[status_id]
		if data != null and data.tick_damage > 0.0 and data.tick_interval > 0.0:
			timer.tick -= delta
			while timer.tick <= 0.0 and health != null and not health.is_dead():
				timer.tick += data.tick_interval
				var info := DamageInfo.make(data.tick_damage, data.damage_type)
				info.source_player_id = timer.source_player_id
				health.apply_damage(info)
		if timer.left >= 0.0:
			timer.left -= delta
			if timer.left <= 0.0:
				ended.append(status_id)
	if ended.is_empty():
		return
	for status_id: StringName in ended:
		_timers.erase(status_id)
	_send_active()


func _is_host() -> bool:
	return is_inside_tree() and multiplayer.is_server()


func _health() -> HealthComponent:
	var parent: Node = get_parent()
	return parent.get_node_or_null(NodePath(HealthComponent.NODE_NAME)) as HealthComponent if parent != null else null


func _stats() -> StatsComponent:
	var parent: Node = get_parent()
	return parent.get_node_or_null(NodePath(StatsComponent.NODE_NAME)) as StatsComponent if parent != null else null


func _send_active() -> void:
	var ids: Array[StringName] = []
	for status_id: StringName in _timers:
		ids.append(status_id)
	_active_rpc.rpc(ids)


## Host -> everyone: the active effects. Each PC adds or removes the stat modifiers and visuals.
@rpc("authority", "call_local", "reliable")
func _active_rpc(id_list: Array) -> void:
	if not is_inside_tree():
		return
	# Arrays lose their element type on the network.
	var ids: Array[StringName] = []
	for status_id: Variant in id_list:
		ids.append(StringName(str(status_id)))
	for status_id: StringName in _active.duplicate():
		if not ids.has(status_id):
			_end_here(status_id)
	for status_id: StringName in ids:
		if not _active.has(status_id):
			_start_here(status_id)


func _start_here(status_id: StringName) -> void:
	_active.append(status_id)
	var data := ContentRegistry.get_content(status_id) as StatusEffectData
	var stats: StatsComponent = _stats()
	if data != null and stats != null:
		for modifier: StatEffectData in data.stat_modifiers:
			stats.add_modifier(status_id, modifier)
	var target := get_parent() as Node3D
	if data != null and data.visual_scene != null and target != null:
		var visual: Node = data.visual_scene.instantiate()
		visual.name = VISUAL_PREFIX + String(status_id)
		target.add_child(visual)
	status_added.emit(status_id)
	EventBus.status_effect_applied.emit(get_parent(), status_id)


func _end_here(status_id: StringName) -> void:
	_active.erase(status_id)
	var stats: StatsComponent = _stats()
	if stats != null:
		stats.remove_modifiers(status_id)
	var parent: Node = get_parent()
	var visual: Node = parent.get_node_or_null(NodePath(VISUAL_PREFIX + String(status_id))) if parent != null else null
	if visual != null:
		visual.queue_free()
	status_removed.emit(status_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var ids: Array[StringName] = []
	for status_id: StringName in _timers:
		ids.append(status_id)
	_active_rpc.rpc_id(multiplayer.get_remote_sender_id(), ids)
