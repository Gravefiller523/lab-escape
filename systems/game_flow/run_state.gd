class_name RunState
extends RefCounted
## Where a run is: its seed, the departments in order, and which floor we are on.
## The host owns it; clients get a copy with every state change (to_dict / from_dict).

## (Named run_seed, not seed: `seed` is a built-in GDScript function.)
var run_seed: int = 0
## Department ids in the order this run visits them. CHANGED 2026-10-31: one per floor (index = floor_number - 1),
## rolled when the run starts (a department every floor, boss floors included).
var department_ids: Array[StringName] = []
## 1-based across the whole run (boss floors count too).
var floor_number: int = 0
## Which department of department_ids we are in (0-based). CHANGED 2026-10-31: floor_number - 1.
var department_index: int = 0
## 1..floor_count for regular floors; floor_count + 1 is the boss floor. CHANGED 2026-10-31: the floor's place in
## its block of GameConfig.boss_every_floors floors (1 to 5, the boss floor is 6). Enemy budgets and min_floor use it.
var floor_in_department: int = 0
var is_boss_floor: bool = false


func get_department_id() -> StringName:
	if department_index < 0 or department_index >= department_ids.size():
		return &""
	return department_ids[department_index]


func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for id: StringName in department_ids:
		ids.append(String(id))
	return {
		"seed": run_seed,
		"department_ids": ids,
		"floor_number": floor_number,
		"department_index": department_index,
		"floor_in_department": floor_in_department,
		"is_boss_floor": is_boss_floor,
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.run_seed = data.get("seed", 0)
	for id: Variant in data.get("department_ids", []):
		run.department_ids.append(StringName(str(id)))
	run.floor_number = data.get("floor_number", 0)
	run.department_index = data.get("department_index", 0)
	run.floor_in_department = data.get("floor_in_department", 0)
	run.is_boss_floor = data.get("is_boss_floor", false)
	return run
