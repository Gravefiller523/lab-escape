class_name VendorsService
extends Node
## Autoload "Vendors". On every floor (every PC) it puts a vending machine at up to
## Config.game.vendors_per_floor of the floor's `vendor` markers (picked with the run's seed, so every PC
## picks the same ones), as child "Vendor" of the marker (the same path on every PC). The host rolls the
## offers. `supply_counter` markers (the Supply Room) always get one. Spec: docs/systems/vendors.md.

const VENDING_SCENE: PackedScene = preload("res://systems/vendors/vending_machine.tscn")


func _ready() -> void:
	EventBus.floor_ready.connect(func(floor_number: int, _department_id: StringName) -> void: place_vendors(floor_number))


## Every PC: the vendors for this floor. Returns them.
func place_vendors(floor_number: int = 0, limit: int = -1) -> Array[Vendor]:
	var spots: Array[RoomMarker] = Level.get_markers(&"vendor")
	var run: RunState = GameFlow.get_run()
	var rng: RandomNumberGenerator = SeededRng.make(run.run_seed if run != null else 0, &"vendor_spots", floor_number)
	# The same shuffle on every PC (the markers come in the same order everywhere).
	for index: int in range(spots.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: RoomMarker = spots[index]
		spots[index] = spots[other]
		spots[other] = swap
	var wanted: int = limit if limit >= 0 else Config.game.vendors_per_floor
	spots = spots.slice(0, mini(wanted, spots.size()))
	var placed: Array[Vendor] = []
	for marker: RoomMarker in spots:
		placed.append(_place(marker, placed.size(), "VENDING"))
	for marker: RoomMarker in Level.get_markers(&"supply_counter"):
		placed.append(_place(marker, placed.size(), "SUPPLY ROOM"))
	return placed


func _place(marker: RoomMarker, index: int, title: String) -> Vendor:
	var vendor := marker.get_node_or_null(^"Vendor") as Vendor
	if vendor != null:
		return vendor
	vendor = VENDING_SCENE.instantiate() as Vendor
	vendor.name = "Vendor"
	vendor.vendor_index = index
	vendor.screen_title = title
	vendor.stock_id = StringName(str(marker.params.get("stock_id", "")))
	marker.add_child(vendor)
	return vendor
