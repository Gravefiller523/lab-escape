class_name UpgradesService
extends Node
## Autoload "Upgrades": mutations and cybernetics, one shared system. Spec: docs/systems/upgrades.md.
## CHANGED 2026-10-23 (Zachary): upgrades are applied by the mutation machine (UpgradeMachine), one per floor
## at a seeded spot. Load it with a DNA vial (a mutation) or a data drive (a cybernetic): drop it in the
## hopper or press E at the machine while holding it. Then step into the booth. Vials spawn with a low
## chance on Zoology and Botany floors (that department's mutations), drives on Robotics floors.
## - An upgrade is a list of effect pieces (UpgradeEffect runtime blocks, found by file name).
## - UNIQUE upgrades can't be had twice (the machine keeps it loaded for someone else); STACKS add again up
##   to max_stacks.
## - Sharing a clash tag with one you have replaces the old one.
## - The host keeps your upgrades in your PlayerRecord (upgrade_ids), so they survive death and reconnects;
##   every PC applies the effects (the owner needs movement; everyone needs looks and voice).
## - A vial says what's inside only once someone has had that mutation this run ("???").
## Console: `upgrade <id>`, `unupgrade <id>`, `spawn mutation_<name>` (a DNA vial), `spawn cybernetic_<name>`
## (a data drive), `machine` (a mutation machine in front of you).

## Above physics_props' grab (50): E at the machine while holding a vial puts it in instead of dropping it.
const USE_PRIORITY: int = 70
const UNKNOWN_NAME: String = "???"
const DNA_VIAL_TAG: String = "dna_vial"
const DATA_DRIVE_TAG: String = "data_drive"
const MACHINE_SCENE: PackedScene = preload("res://systems/upgrades/upgrade_machine.tscn")
const MACHINE_MARKER: StringName = &"upgrade_machine"
## Room kind where floors start: no vials there.
const START_ROOM_KIND: StringName = &"lift"

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
	DebugConsole.register_command(&"machine", _cmd_machine, "machine: a mutation machine in front of you")
	EventBus.floor_ready.connect(_on_floor_ready)


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


## The carrier prop for a kind of upgrade: a DNA vial (mutations) or a data drive (cybernetics). &"" if none.
static func carrier_prop_for(upgrade_id: StringName) -> StringName:
	var tag: String = DATA_DRIVE_TAG if ContentRegistry.get_content(upgrade_id) is CyberneticData else DNA_VIAL_TAG
	return _first_with_tag(tag)


## Every PC: the floor's mutation machine, at one of the `upgrade_machine` markers picked with the run's
## seed (so every PC picks the same one), as child "UpgradeMachine" of the marker. Null if there are none.
func place_machine(floor_number: int) -> UpgradeMachine:
	var spots: Array[RoomMarker] = Level.get_markers(MACHINE_MARKER)
	if spots.is_empty():
		return null
	var run: RunState = GameFlow.get_run()
	var rng: RandomNumberGenerator = SeededRng.make(run.run_seed if run != null else 0, &"upgrade_machine_spot", floor_number)
	var marker: RoomMarker = spots[rng.randi_range(0, spots.size() - 1)]
	var machine := marker.get_node_or_null(^"UpgradeMachine") as UpgradeMachine
	if machine == null:
		machine = MACHINE_SCENE.instantiate() as UpgradeMachine
		machine.name = "UpgradeMachine"
		marker.add_child(machine)
	return machine


## Host: DNA vials (or, on Robotics floors, data drives) at random prop spots: Config.game.upgrade_carrier_tries
## tries, each with the department's chance (or upgrade_carrier_chance). Not in the lift room.
func spawn_floor_carriers(floor_number: int, department: DepartmentData) -> Array[NetProp]:
	var spawned: Array[NetProp] = []
	if not multiplayer.is_server() or Props.get_spawner() == null:
		return spawned
	var spots: Array[RoomMarker] = []
	for marker: RoomMarker in Level.get_markers(&"prop_spawn"):
		var room: RoomData = Level.get_room_for_position(marker.global_position)
		if room == null or room.room_kind != START_ROOM_KIND:
			spots.append(marker)
	if spots.is_empty():
		return spawned
	var type_key: StringName = &"mutation"
	var chance: float = Config.game.upgrade_carrier_chance
	if department != null:
		if department.upgrade_type != &"":
			type_key = department.upgrade_type
		if department.upgrade_carrier_chance >= 0.0:
			chance = department.upgrade_carrier_chance
	var run: RunState = GameFlow.get_run()
	var rng: RandomNumberGenerator = SeededRng.make(run.run_seed if run != null else 0, &"upgrade_carriers", floor_number)
	for attempt: int in Config.game.upgrade_carrier_tries:
		if rng.randf() >= chance:
			continue
		var upgrade_id: StringName = Loot.pick_upgrade(type_key, rng)
		var prop_id: StringName = carrier_prop_for(upgrade_id) if upgrade_id != &"" else &""
		if prop_id == &"":
			continue
		var marker: RoomMarker = spots[rng.randi_range(0, spots.size() - 1)]
		var prop: NetProp = Props.spawn_prop(prop_id, marker.global_transform.translated(Vector3.UP * 0.4), {"upgrade_id": String(upgrade_id)})
		if prop != null:
			spawned.append(prop)
	return spawned


func _on_floor_ready(floor_number: int, _department_id: StringName) -> void:
	place_machine(floor_number)
	var run: RunState = GameFlow.get_run()
	if run != null and not run.is_boss_floor:
		spawn_floor_carriers(floor_number, GameFlow.get_current_department())


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


# --- Loading the machine (the use key) ----------------------------------------------------------------------------

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
	interaction.register_use_handler(USE_PRIORITY, func(target: Node3D) -> bool: return _on_use(body, target))
	interaction.register_prompt_provider(USE_PRIORITY, func(target: Node3D) -> String: return _prompt(body, target))


func _held_carrier(body: PlayerCharacter) -> NetProp:
	var grab: GrabController = PropsService.grab_of(body) if is_instance_valid(body) else null
	var held: NetProp = grab.get_held() if grab != null else null
	return held if UpgradeCarrier.of(held) != null else null


func _on_use(body: PlayerCharacter, target: Node3D) -> bool:
	var prop: NetProp = _held_carrier(body)
	var machine: UpgradeMachine = UpgradeMachine.of(target) if target != null else null
	if prop == null or machine == null:
		return false
	machine.request_insert(prop)
	return true


## Holding a vial at the machine: "Put DNA vial: Frog (replaces Octo) in the machine". Looking at a vial on the
## floor: "Pick up DNA vial: Frog" (??? until someone has had it this run).
func _prompt(body: PlayerCharacter, target: Node3D) -> String:
	var held: NetProp = _held_carrier(body)
	var machine: UpgradeMachine = UpgradeMachine.of(target) if target != null else null
	var prop: NetProp = held
	if held == null:
		var grab: GrabController = PropsService.grab_of(body)
		if grab != null and grab.get_held() != null:
			return ""
		prop = NetProp.of(target) if target != null else null
		if UpgradeCarrier.of(prop) == null:
			return ""
	elif machine == null:
		return ""
	var carrier: UpgradeCarrier = UpgradeCarrier.of(prop)
	var upgrade: UpgradeData = carrier.get_upgrade()
	var title: String = UNKNOWN_NAME
	if upgrade != null and is_known(upgrade.id):
		title = upgrade.display_name
	var kind: String = "data drive" if prop.data != null and prop.data.tags.has(DATA_DRIVE_TAG) else "DNA vial"
	var text: String = "%s %s: %s" % ["Put" if held != null else "Pick up", kind, title]
	if upgrade != null:
		var replaced: PackedStringArray = []
		for old_id: StringName in preview_clash(body.player_id, upgrade.id):
			var old := ContentRegistry.get_content(old_id) as UpgradeData
			replaced.append(old.display_name if old != null else String(old_id))
		if not replaced.is_empty():
			text += " (replaces %s)" % ", ".join(replaced)
	if held != null:
		text += " in the machine"
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


## `spawn mutation_fly`: a DNA vial holding it (cybernetics: a data drive).
func _console_spawn(id: StringName, at: Transform3D, count: int, _player_id: int) -> String:
	var prop_id: StringName = carrier_prop_for(id)
	if prop_id == &"":
		return "No DNA vial or data drive prop to put it in."
	for index: int in count:
		Props.spawn_prop(prop_id, at.translated(Vector3(0.0, 0.3 * float(index), 0.0)), {"upgrade_id": String(id)})
	return "Spawned %d x %s in a %s." % [count, id, prop_id]


static func _first_with_tag(tag: String) -> StringName:
	for content: ContentData in ContentRegistry.get_all(&"prop"):
		if content.tags.has(tag):
			return content.id
	return &""


## `machine`: a mutation machine in front of you (cheats; for testing where no marker is).
func _cmd_machine(_args: PackedStringArray, player_id: int) -> String:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if body == null:
		return "You have no body right now."
	var forward: Vector3 = body.get_aim_direction()
	forward.y = 0.0
	_machine_rpc.rpc(body.global_position + forward.normalized() * 3.0, atan2(forward.x, forward.z) + PI)
	return "A mutation machine appeared."


## Host -> everyone: the console's machine (the same node name everywhere, under this autoload).
@rpc("authority", "call_local", "reliable")
func _machine_rpc(where: Vector3, yaw: float) -> void:
	var old := get_node_or_null(^"ConsoleMachine")
	if old != null:
		old.free()
	var machine := MACHINE_SCENE.instantiate() as UpgradeMachine
	machine.name = "ConsoleMachine"
	add_child(machine)
	machine.global_position = where
	machine.rotation.y = yaw
