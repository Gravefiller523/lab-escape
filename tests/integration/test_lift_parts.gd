extends GutTest
## The cargo lift's parts on a real generated floor (solo): broken parts spawn far away, a battery
## charges on the charger and then fits, and a lost part comes back.

const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const WAIT: float = 5.0

var _lift: CargoLift
var _props: PropSpawner
var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_props = PropSpawner.new()
	_props.name = "Props"
	_root.add_child(_props)
	_lift = LIFT_SCENE.instantiate() as CargoLift
	_root.add_child(_lift)
	var department: DepartmentData = GameFlow.get_department(GameFlowService.PLACEHOLDER_DEPARTMENT_ID)
	# A seed whose floor has rooms with charger markers (halls or corridors).
	var layout: FloorLayout = LevelGenerator.generate(department, 1, 1, 7, 1)
	Level.build(layout, _root)
	await wait_physics_frames(3)


func after_each() -> void:
	Level.clear()


func test_parts_spawn_far_away_and_the_battery_charges() -> void:
	assert_gt(Level.get_markers(&"charger").size(), 0, "this floor has chargers")
	_lift.arrive(9, false)
	EventBus.floor_ready.emit(1, GameFlowService.PLACEHOLDER_DEPARTMENT_ID)
	await wait_physics_frames(3)
	for slot: StringName in _lift.get_slot_names():
		assert_eq(_props.get_props(_lift.get_slot_part(slot).id).size(), 1, "a %s is somewhere on the floor" % slot)
	var battery: NetProp = _props.get_props(&"prop_lift_battery")[0]
	assert_false(_lift.is_charged(battery), "it starts flat")
	var charger := _root.find_child("ChargerPad", true, false) as Area3D
	assert_not_null(charger, "the charger is on the floor")
	var data: PropData = battery.data
	var charge_seconds: float = data.needs_charge_seconds
	data.needs_charge_seconds = 0.3
	battery.global_position = charger.global_position + Vector3.UP * 0.5
	await wait_until(func() -> bool: return _lift.is_charged(battery), WAIT)
	data.needs_charge_seconds = charge_seconds
	assert_true(_lift.is_charged(battery), "charged on the charger")
	var socket := _lift.get_node("Slot_battery/Socket") as Area3D
	battery.global_position = socket.global_position + Vector3.UP * 0.2
	await wait_until(func() -> bool: return not _lift.get_broken_slots().has(&"battery"), WAIT)
	assert_false(_lift.get_broken_slots().has(&"battery"), "a charged battery fits")


func test_a_lost_part_comes_back() -> void:
	_lift.arrive(9, false)
	EventBus.floor_ready.emit(1, GameFlowService.PLACEHOLDER_DEPARTMENT_ID)
	await wait_physics_frames(3)
	_props.despawn(_props.get_props(&"prop_lift_vacuum_tube")[0])
	await wait_physics_frames(2)
	assert_eq(_props.get_props(&"prop_lift_vacuum_tube").size(), 0)
	await wait_until(func() -> bool: return _props.get_props(&"prop_lift_vacuum_tube").size() == 1, WAIT)
	assert_eq(_props.get_props(&"prop_lift_vacuum_tube").size(), 1, "a new one appears far away")
