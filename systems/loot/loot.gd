class_name LootService
extends Node
## Autoload "Loot". Decides and spawns what drops when monsters die: gems (money), meat (for reprints) and
## items. Host only; the floor's seed makes every roll. Spec: docs/systems/loot.md.
## CHANGED 2026-10-23 (Zachary): no glowing gems or robot parts any more: mutations and cybernetics come
## from DNA vials and data drives (upgrades system). pick_upgrade() still says which upgrade one holds.
## - Merging: past max_loose_gems_per_floor loose plain gems, nearby resting ones merge into bigger gems
##   (the same total value).
## Console: `gems <amount>`, `loot <loot_id>`.

## Drops pop out around the spot within this radius (metres), a little above it.
const DROP_SPREAD: float = 0.6
const DROP_HEIGHT: float = 0.6
const POP_IMPULSE: float = 1.5
const MERGE_CHECK_SECONDS: float = 2.0
## Gems this close together merge into one.
const MERGE_RADIUS: float = 1.5

var _run_seed: int = 0
var _drop_counter: int = 0
var _merge_left: float = MERGE_CHECK_SECONDS
## For tests: a fixed department (null = the current one).
var _department_override: DepartmentData
var _use_department_override: bool = false


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.run_started.connect(func(run_seed: int) -> void: _run_seed = run_seed)
	EventBus.floor_ready.connect(func(_floor_number: int, _department_id: StringName) -> void: _drop_counter = 0)
	DebugConsole.register_command(&"gems", _cmd_gems, "gems <amount>: drop that much gem value in front of you")
	DebugConsole.register_command(&"loot", _cmd_loot, "loot <loot_id>: roll a loot table in front of you")


## Pure: what a table gives with this rng (no spawning; tests use it).
func roll(loot_id: StringName, rng: RandomNumberGenerator) -> Array[LootDrop]:
	var drops: Array[LootDrop] = []
	var table := ContentRegistry.get_content(loot_id) as LootTableData
	if table == null:
		return drops
	for roll_index: int in table.rolls:
		var weights: PackedFloat32Array = [table.nothing_weight]
		for entry: LootEntryData in table.entries:
			weights.append(entry.weight)
		var picked: int = SeededRng.pick_weighted(rng, weights)
		if picked <= 0:
			continue
		var entry: LootEntryData = table.entries[picked - 1]
		var count: int = rng.randi_range(entry.min_count, maxi(entry.min_count, entry.max_count))
		if entry.prop_id == &"":
			drops.append(LootDrop.make(&"", entry.item_id, count))
			continue
		if ContentRegistry.get_content(entry.prop_id) is PropData:
			drops.append(LootDrop.make(entry.prop_id, &"", count))
	return drops


## Host: roll a table and spawn it around a spot. `source_id` is who dropped it (an enemy id).
func roll_and_spawn(loot_id: StringName, at: Vector3, source_id: StringName) -> Array[NetProp]:
	var spawned: Array[NetProp] = []
	if not multiplayer.is_server() or loot_id == &"":
		return spawned
	# Nowhere to drop things (a test world or menu without a PropSpawner): nothing drops.
	if Props.get_spawner() == null:
		return spawned
	var rng: RandomNumberGenerator = SeededRng.make(_current_seed(), &"loot", _drop_counter)
	_drop_counter += 1
	for drop: LootDrop in roll(loot_id, rng):
		for index: int in drop.count:
			var spot: Vector3 = at + Vector3(rng.randf_range(-DROP_SPREAD, DROP_SPREAD), DROP_HEIGHT,
				rng.randf_range(-DROP_SPREAD, DROP_SPREAD))
			var xform := Transform3D(Basis.IDENTITY, spot)
			var prop: NetProp
			if drop.item_id != &"":
				prop = Props.spawn_item(drop.item_id, xform)
			else:
				var extra: Dictionary = {}
				if drop.upgrade_id != &"":
					extra["upgrade_id"] = String(drop.upgrade_id)
				prop = Props.spawn_prop(drop.prop_id, xform, extra)
			if prop != null:
				spawned.append(prop)
				Props.apply_impulse(prop, Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)) * POP_IMPULSE * prop.mass)
	EventBus.loot_dropped.emit(source_id, at)
	return spawned


## Which mutation (&"mutation") or cybernetic (&"cybernetic") a DNA vial or data drive holds: weighted by drop_weight, only
## ones allowed in the current department. &"" if there are none.
func pick_upgrade(type_key: StringName, rng: RandomNumberGenerator) -> StringName:
	var department: DepartmentData = _department()
	var ids: Array[StringName] = []
	var weights: PackedFloat32Array = []
	for content: ContentData in ContentRegistry.get_all(type_key):
		var upgrade := content as UpgradeData
		if upgrade == null or upgrade.drop_weight <= 0.0:
			continue
		if not upgrade.department_ids.is_empty() and (department == null or not upgrade.department_ids.has(department.id)):
			continue
		ids.append(upgrade.id)
		weights.append(upgrade.drop_weight)
	var index: int = SeededRng.pick_weighted(rng, weights)
	return ids[index] if index >= 0 else &""


## For tests: pretend we're in this department (null = none).
func use_department(department: DepartmentData) -> void:
	_department_override = department
	_use_department_override = true


func clear_department_override() -> void:
	_use_department_override = false
	_department_override = null


## Host: merge loose plain gems into bigger ones until at most max_loose_gems_per_floor are loose.
## Returns how many gems were removed. The total value never changes.
func merge_gems(max_loose: int = -1) -> int:
	if not multiplayer.is_server():
		return 0
	var limit: int = max_loose if max_loose >= 0 else Config.game.max_loose_gems_per_floor
	var loose: Array[NetProp] = _loose_plain_gems()
	if loose.size() <= limit:
		return 0
	var removed: int = 0
	var used: Dictionary[int, bool] = {}
	for gem: NetProp in loose:
		if loose.size() - removed <= limit:
			break
		if used.has(gem.net_id):
			continue
		var group: Array[NetProp] = [gem]
		for other: NetProp in loose:
			if other != gem and not used.has(other.net_id) and other.global_position.distance_to(gem.global_position) <= MERGE_RADIUS:
				group.append(other)
		if group.size() < 2:
			continue
		var value: int = 0
		for member: NetProp in group:
			value += member.data.gem_value
			used[member.net_id] = true
		var at: Vector3 = gem.global_position + Vector3.UP * 0.2
		for member: NetProp in group:
			Props.despawn(member)
		var made: int = 0
		for prop_id: StringName in gems_for_value(value):
			Props.spawn_prop(prop_id, Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.25 * float(made)))
			made += 1
		removed += group.size() - made
	return removed


## The gem props that add up to a value, biggest first (props with gem_value > 0).
static func gems_for_value(value: int) -> Array[StringName]:
	var kinds: Array[PropData] = []
	for content: ContentData in ContentRegistry.get_all(&"prop"):
		var prop := content as PropData
		if prop != null and prop.gem_value > 0:
			kinds.append(prop)
	kinds.sort_custom(func(a: PropData, b: PropData) -> bool: return a.gem_value > b.gem_value)
	var result: Array[StringName] = []
	var left: int = value
	for kind: PropData in kinds:
		while left >= kind.gem_value:
			result.append(kind.id)
			left -= kind.gem_value
	return result


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_merge_left -= delta
	if _merge_left <= 0.0:
		_merge_left = MERGE_CHECK_SECONDS
		merge_gems()


func _loose_plain_gems() -> Array[NetProp]:
	var gems: Array[NetProp] = []
	for prop: NetProp in Props.get_props():
		if prop.data == null or prop.data.gem_value <= 0:
			continue
		if prop.is_held() or prop.is_attached() or prop.is_queued_for_deletion() or not prop.sleeping:
			continue
		gems.append(prop)
	return gems


func _department() -> DepartmentData:
	return _department_override if _use_department_override else GameFlow.get_current_department()


func _current_seed() -> int:
	var run: RunState = GameFlow.get_run()
	return run.run_seed if run != null else _run_seed


func _on_enemy_killed(enemy_id: StringName, death_position: Vector3, _killer_player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var content: ContentData = ContentRegistry.get_content(enemy_id)
	var loot_id: StringName = &""
	if content is EnemyData:
		loot_id = (content as EnemyData).loot_id
	elif content is BossData:
		loot_id = (content as BossData).loot_id
	if loot_id == &"":
		var department: DepartmentData = _department()
		loot_id = department.loot_id if department != null else &""
	roll_and_spawn(loot_id, death_position, enemy_id)


func _spot_in_front(player_id: int) -> Vector3:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if body == null:
		return Vector3.ZERO
	var forward: Vector3 = body.get_aim_direction()
	forward.y = 0.0
	return body.global_position + forward.normalized() * 1.5


func _cmd_gems(args: PackedStringArray, player_id: int) -> String:
	var amount: int = args[0].to_int() if args.size() > 0 and args[0].is_valid_int() else 10
	var at: Vector3 = _spot_in_front(player_id) + Vector3.UP * 0.5
	var made: int = 0
	for prop_id: StringName in gems_for_value(amount):
		Props.spawn_prop(prop_id, Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.3 * float(made)))
		made += 1
	return "Dropped %d gem value (%d gems)." % [amount, made]


func _cmd_loot(args: PackedStringArray, player_id: int) -> String:
	if args.is_empty():
		return "Usage: loot <loot_id>. Try: list loot"
	var loot_id := StringName(args[0])
	if not ContentRegistry.get_content(loot_id) is LootTableData:
		return "No loot table called '%s'." % loot_id
	var spawned: Array[NetProp] = roll_and_spawn(loot_id, _spot_in_front(player_id), &"console")
	return "Rolled %s: %d things." % [loot_id, spawned.size()]
