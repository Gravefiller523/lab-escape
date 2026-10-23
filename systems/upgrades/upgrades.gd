class_name UpgradesService
extends Node
## Autoload "Upgrades": mutations (glowing gems) and cybernetics (robot parts), one shared system.
## Spec: docs/systems/upgrades.md.
## - Hold a glowing gem or robot part and press E: you eat / install it (the host checks you hold it).
## - An upgrade is a list of effect pieces (UpgradeEffect runtime blocks, found by file name).
## - UNIQUE upgrades do nothing the second time (the gem is still eaten); STACKS add again up to max_stacks.
## - Sharing a clash tag with one you have replaces the old one ("Eat glowing gem: Frog (replaces Octo)").
## - The host keeps your upgrades in your PlayerRecord (upgrade_ids), so they survive death and reconnects;
##   every PC applies the effects (the owner needs movement; everyone needs looks and voice).
## - A glowing gem's prompt says what's inside only once someone has eaten that mutation this run ("???").
## Console: `upgrade <id>`, `unupgrade <id>`, spawners `spawn mutation_<name>` / `spawn cybernetic_<name>`.

## Above physics_props' grab (50): E while holding a carrier eats it instead of dropping it.
const USE_PRIORITY: int = 70
const UNKNOWN_NAME: String = "???"
const GLOWING_GEM_TAG: String = "glowing_gem"
const ROBOT_PART_TAG: String = "robot_part"

## player_id -> the source ids applied on this PC (in order), so they can be removed.
var _applied: Dictionary[int, Array] = {}
## Upgrades someone has gained this run (every PC): their names show on gems.
var _known: Dictionary[StringName, bool] = {}


func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.run_ended.connect(func(_result: StringName) -> void: _clear_all())
	EventBus.run_started.connect(func(_run_seed: int) -> void: _known.clear())
	DebugConsole.register_command(&"upgrade", _cmd_upgrade, "upgrade <id>: give yourself a mutation or cybernetic")
	DebugConsole.register_command(&"unupgrade", _cmd_unupgrade, "unupgrade <id>: lose a mutation or cybernetic")
	DebugConsole.register_spawner(&"mutation", _console_spawn)
	DebugConsole.register_spawner(&"cybernetic", _console_spawn)


# --- Reading -----------------------------------------------------------------------------------------

## A player's upgrades (repeated ids are stacks), from their record.
func get_upgrades(player_id: int) -> Array[StringName]:
	var record: PlayerRecord = Net.get_record(player_id)
	var ids: Array[StringName] = []
	if record != null:
		ids.assign(record.upgrade_ids)
	return ids


func has_upgrade(player_id: int, upgrade_id: StringName) -> bool:
	return get_upgrades(player_id).has(upgrade_id)


func get_stack_count(player_id: int, upgrade_id: StringName) -> int:
	return get_upgrades(player_id).count(upgrade_id)


## Cosmetic slots the player's upgrades hide (e.g. Slug hides "shoes").
func get_hidden_cosmetic_slots(player_id: int) -> PackedStringArray:
	var hidden: PackedStringArray = []
	for upgrade_id: StringName in get_upgrades(player_id):
		var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
		if upgrade == null:
			continue
		for effect: UpgradeEffectData in upgrade.effects:
			var visual := effect as VisualAttachmentEffectData
			if visual != null:
				for slot: String in visual.hides_cosmetic_slots:
					if not hidden.has(slot):
						hidden.append(slot)
	return hidden


## The upgrades gaining this one would replace (shared clash tags).
func preview_clash(player_id: int, upgrade_id: StringName) -> Array[StringName]:
	var replaced: Array[StringName] = []
	var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
	if upgrade == null:
		return replaced
	for owned_id: StringName in get_upgrades(player_id):
		if owned_id == upgrade_id or replaced.has(owned_id):
			continue
		var owned := ContentRegistry.get_content(owned_id) as UpgradeData
		if owned == null:
			continue
		for tag: String in upgrade.clash_tags:
			if owned.clash_tags.has(tag):
				replaced.append(owned_id)
				break
	return replaced


## True once someone has gained this upgrade this run (its name shows on gems).
func is_known(upgrade_id: StringName) -> bool:
	return _known.has(upgrade_id)


# --- Changing (host) -------------------------------------------------------------------------------

## Host: give a player an upgrade. False if it did nothing (unknown, UNIQUE already held, max stacks).
func grant(player_id: int, upgrade_id: StringName) -> bool:
	if not multiplayer.is_server():
		return false
	var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
	if upgrade == null or Net.get_record(player_id) == null:
		return false
	var stacks: int = get_stack_count(player_id, upgrade_id)
	if stacks > 0 and (upgrade.stack_rule == UpgradeData.StackRule.UNIQUE or stacks >= upgrade.max_stacks):
		return false
	for old_id: StringName in preview_clash(player_id, upgrade_id):
		while has_upgrade(player_id, old_id):
			remove(player_id, old_id)
	var ids: Array[StringName] = get_upgrades(player_id)
	ids.append(upgrade_id)
	Net.update_record(player_id, &"upgrade_ids", ids)
	_gained_rpc.rpc(player_id, upgrade_id, stacks + 1)
	return true


## Host: lose one stack of an upgrade (cheats, clashes, future cures).
func remove(player_id: int, upgrade_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var ids: Array[StringName] = get_upgrades(player_id)
	var stack: int = ids.count(upgrade_id)
	if stack == 0:
		return
	ids.remove_at(ids.rfind(upgrade_id))
	Net.update_record(player_id, &"upgrade_ids", ids)
	_lost_rpc.rpc(player_id, upgrade_id, stack)


## Local: eat / install the carrier prop you're holding (the host checks it).
func request_consume(prop: NetProp) -> void:
	if prop == null:
		return
	if multiplayer.is_server():
		_consume(Net.local_player_id(), prop.net_id)
	else:
		_consume_rpc.rpc_id(1, prop.net_id)


func _consume(player_id: int, net_id: int) -> bool:
	var prop: NetProp = Props.get_prop(net_id)
	var carrier: UpgradeCarrier = UpgradeCarrier.of(prop)
	if carrier == null or not prop.get_holder_ids().has(player_id) or carrier.get_upgrade() == null:
		return false
	var upgrade_id: StringName = carrier.upgrade_id
	if prop.get_spawner() != null:
		prop.get_spawner().release_all(prop)
	Props.despawn(prop)
	grant(player_id, upgrade_id)
	return true


# --- Applying (every PC) ---------------------------------------------------------------------------

func _source_id(upgrade_id: StringName, stack: int) -> StringName:
	return StringName("%s#%d" % [upgrade_id, stack])


func _apply(player_id: int, upgrade_id: StringName, stack: int) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
	if body == null or upgrade == null:
		return
	var source: StringName = _source_id(upgrade_id, stack)
	if not _applied.has(player_id):
		_applied[player_id] = []
	if _applied[player_id].has(source):
		return
	for effect: UpgradeEffectData in upgrade.effects:
		var runtime: UpgradeEffect = UpgradeEffect.for_data(effect)
		if runtime != null:
			runtime.apply(body, effect, source)
	_applied[player_id].append(source)


func _unapply(player_id: int, upgrade_id: StringName, stack: int) -> void:
	var source: StringName = _source_id(upgrade_id, stack)
	if not _applied.has(player_id) or not _applied[player_id].has(source):
		return
	_applied[player_id].erase(source)
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
	if body == null or upgrade == null:
		return
	for effect: UpgradeEffectData in upgrade.effects:
		var runtime: UpgradeEffect = UpgradeEffect.for_data(effect)
		if runtime != null:
			runtime.remove(body, effect, source)


## A new body (first spawn, reconnect): apply everything in the record, in order.
func _on_player_spawned(player_id: int, player_node: Node3D) -> void:
	var body := player_node as PlayerCharacter
	if body == null:
		return
	_applied[player_id] = []
	var counts: Dictionary[StringName, int] = {}
	for upgrade_id: StringName in get_upgrades(player_id):
		counts[upgrade_id] = counts.get(upgrade_id, 0) + 1
		_apply(player_id, upgrade_id, counts[upgrade_id])
	if body.is_local():
		_hook_into_interaction.call_deferred(body)


## The run is over: everyone loses their upgrades.
func _clear_all() -> void:
	for player_id: int in _applied.keys():
		# From what was applied here (the record may already be cleared for the new run).
		var sources: Array = _applied[player_id].duplicate()
		sources.reverse()
		for source: Variant in sources:
			var parts: PackedStringArray = str(source).split("#")
			_unapply(player_id, StringName(parts[0]), parts[1].to_int() if parts.size() > 1 else 1)
		if multiplayer.is_server() and Net.get_record(player_id) != null:
			var none: Array[StringName] = []
			Net.update_record(player_id, &"upgrade_ids", none)
	_known.clear()


# --- Eating (the use key) ----------------------------------------------------------------------------

func _hook_into_interaction(candidate: Variant) -> void:
	# Called deferred: the body may be gone by then (a Variant, so a freed one is safe to check).
	if not is_instance_valid(candidate):
		return
	var body := candidate as PlayerCharacter
	if body == null:
		return
	var interaction: InteractionController = InteractionService.controller_of(body)
	if interaction == null:
		return
	interaction.register_use_handler(USE_PRIORITY, func(_target: Node3D) -> bool: return _on_use(body))
	interaction.register_prompt_provider(USE_PRIORITY, func(_target: Node3D) -> String: return _prompt(body))


func _held_carrier(body: PlayerCharacter) -> NetProp:
	var grab: GrabController = PropsService.grab_of(body) if is_instance_valid(body) else null
	var held: NetProp = grab.get_held() if grab != null else null
	return held if UpgradeCarrier.of(held) != null else null


func _on_use(body: PlayerCharacter) -> bool:
	var prop: NetProp = _held_carrier(body)
	if prop == null:
		return false
	request_consume(prop)
	return true


func _prompt(body: PlayerCharacter) -> String:
	var prop: NetProp = _held_carrier(body)
	if prop == null:
		return ""
	var carrier: UpgradeCarrier = UpgradeCarrier.of(prop)
	var upgrade: UpgradeData = carrier.get_upgrade()
	var title: String = UNKNOWN_NAME
	if upgrade != null and is_known(upgrade.id):
		title = upgrade.display_name
	var verb: String = "Install robot part" if prop.data != null and prop.data.tags.has(ROBOT_PART_TAG) else "Eat glowing gem"
	var text: String = "%s: %s" % [verb, title]
	if upgrade != null:
		var replaced: PackedStringArray = []
		for old_id: StringName in preview_clash(body.player_id, upgrade.id):
			var old := ContentRegistry.get_content(old_id) as UpgradeData
			replaced.append(old.display_name if old != null else String(old_id))
		if not replaced.is_empty():
			text += " (replaces %s)" % ", ".join(replaced)
	return text


# --- Network -----------------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _gained_rpc(player_id: int, upgrade_id: StringName, stack: int) -> void:
	_known[upgrade_id] = true
	_apply(player_id, upgrade_id, stack)
	EventBus.upgrade_gained.emit(player_id, upgrade_id)


@rpc("authority", "call_local", "reliable")
func _lost_rpc(player_id: int, upgrade_id: StringName, stack: int) -> void:
	_unapply(player_id, upgrade_id, stack)
	EventBus.upgrade_lost.emit(player_id, upgrade_id)


@rpc("any_peer", "call_remote", "reliable")
func _consume_rpc(net_id: int) -> void:
	if multiplayer.is_server():
		_consume(Net.get_player_id_for_peer(multiplayer.get_remote_sender_id()), net_id)


# --- Console -----------------------------------------------------------------------------------------

func _cmd_upgrade(args: PackedStringArray, player_id: int) -> String:
	if args.is_empty():
		return "Usage: upgrade <id>. Try: list mutation"
	var upgrade_id := StringName(args[0])
	if not ContentRegistry.get_content(upgrade_id) is UpgradeData:
		return "No mutation or cybernetic called '%s'." % upgrade_id
	return "You gained %s." % upgrade_id if grant(player_id, upgrade_id) else "Nothing happened (already have it?)."


func _cmd_unupgrade(args: PackedStringArray, player_id: int) -> String:
	if args.is_empty():
		return "Usage: unupgrade <id>"
	remove(player_id, StringName(args[0]))
	return "Removed %s." % args[0]


## `spawn mutation_fly`: a glowing gem holding it (cybernetics: a robot part).
func _console_spawn(id: StringName, at: Transform3D, count: int, _player_id: int) -> String:
	var tag: String = ROBOT_PART_TAG if ContentRegistry.get_content(id) is CyberneticData else GLOWING_GEM_TAG
	var prop_id: StringName = _first_with_tag(tag)
	if prop_id == &"":
		return "No prop tagged '%s' to put it in." % tag
	for index: int in count:
		Props.spawn_prop(prop_id, at.translated(Vector3(0.0, 0.3 * float(index), 0.0)), {"upgrade_id": String(id)})
	return "Spawned %d x %s in a %s." % [count, id, prop_id]


static func _first_with_tag(tag: String) -> StringName:
	for content: ContentData in ContentRegistry.get_all(&"prop"):
		if content.tags.has(tag):
			return content.id
	return &""
