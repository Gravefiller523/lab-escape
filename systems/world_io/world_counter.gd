class_name WorldCounter
extends WorldDevice
## NEW 2026-10-30 (HL2 feel step 4.2): counts up and down, and fires "reached" when the count gets to
## `goal` (e.g. "both buttons pressed", "three fuses in"). It fires "left" if the count drops back below
## the goal, and "changed" on every change. The host keeps the count; there is nothing for other PCs to see.
## Outputs: changed, reached, left. Inputs: add, subtract, reset (and enable, disable).

@export var goal: int = 2

var _count: int = 0


func get_inputs() -> PackedStringArray:
	return PackedStringArray(["add", "subtract", "reset"])


func get_count() -> int:
	return _count


func _on_input(action: StringName, activator_id: int) -> void:
	var before: int = _count
	match action:
		&"add":
			_count += 1
		&"subtract":
			_count = maxi(_count - 1, 0)
		&"reset":
			_count = 0
	if _count == before:
		return
	fire_output(&"changed", activator_id)
	if before < goal and _count >= goal:
		fire_output(&"reached", activator_id)
	elif before >= goal and _count < goal:
		fire_output(&"left", activator_id)
