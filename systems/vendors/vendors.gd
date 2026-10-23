class_name VendorsService
extends Node
## Autoload "Vendors". On every floor (every PC) it puts a vending machine at each `vendor` marker, as
## child "Vendor" of the marker (so it has the same path on every PC). The host rolls its offers.
## Spec: docs/systems/vendors.md.

const VENDING_SCENE: PackedScene = preload("res://systems/vendors/vending_machine.tscn")
const MARKER_KINDS: Array[StringName] = [&"vendor", &"supply_counter"]


func _ready() -> void:
	EventBus.floor_ready.connect(func(_floor_number: int, _department_id: StringName) -> void: place_vendors())


## Every PC: a vendor at each marker that hasn't got one yet. Returns them.
func place_vendors() -> Array[Vendor]:
	var placed: Array[Vendor] = []
	var index: int = 0
	for kind: StringName in MARKER_KINDS:
		for marker: RoomMarker in Level.get_markers(kind):
			var vendor := marker.get_node_or_null(^"Vendor") as Vendor
			if vendor == null:
				vendor = VENDING_SCENE.instantiate() as Vendor
				vendor.name = "Vendor"
				vendor.vendor_index = index
				vendor.stock_id = StringName(str(marker.params.get("stock_id", "")))
				if kind == &"supply_counter":
					vendor.screen_title = "SUPPLY ROOM"
				marker.add_child(vendor)
			placed.append(vendor)
			index += 1
	return placed
