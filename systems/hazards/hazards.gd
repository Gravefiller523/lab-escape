class_name HazardsService
extends Node
## Autoload "Hazards". NEW 2026-10-31 (floor generation step 4b): puts a HazardZone at every "hazard" marker
## the floor plan switched on (its params say the kind: "hazard_kind"), on every PC when the floor is ready.
## Only the host hurts anyone (HazardZone). Placeholder sparks and fire; real effects come later.
## Spec: docs/systems/hazards.md.


func _ready() -> void:
	EventBus.floor_ready.connect(_on_floor_ready)


## The hazards on the current floor (for tests and the debug view).
func get_zones() -> Array[HazardZone]:
	var zones: Array[HazardZone] = []
	for node: Node in get_tree().get_nodes_in_group(HazardZone.GROUP):
		var zone := node as HazardZone
		if zone != null:
			zones.append(zone)
	return zones


## Every PC: a zone at each switched-on hazard marker (they go away with the floor).
func spawn_for_floor() -> int:
	var count: int = 0
	for marker: RoomMarker in Level.get_markers(&"hazard"):
		var kind := StringName(str(marker.params.get("hazard_kind", "")))
		if kind == &"" or marker.get_node_or_null(^"Hazard") != null:
			continue
		var zone := HazardZone.new()
		zone.name = "Hazard"
		zone.setup(kind)
		marker.add_child(zone)
		count += 1
	return count


func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	if is_inside_tree():
		spawn_for_floor()
