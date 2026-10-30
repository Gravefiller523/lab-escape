class_name WorldRelay
extends WorldDevice
## NEW 2026-10-30 (HL2 feel step 4.2): passes a signal on. The input "trigger" fires the output
## "triggered" (with the same player). Use it to set off many devices from one place, or to switch a whole
## chain off at once (disable the relay). Outputs: triggered. Inputs: trigger (and enable, disable).


func get_inputs() -> PackedStringArray:
	return PackedStringArray(["trigger"])


func _on_input(_action: StringName, activator_id: int) -> void:
	fire_output(&"triggered", activator_id)
