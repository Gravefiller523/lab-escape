class_name CyberneticData
extends UpgradeData
## A cybernetic, gained by installing a robot part. Example id: "cybernetic_jump_legs".
## Files live in res://content/cybernetics/.

## Which body part it replaces, e.g. "arm", "legs", "eyes". Shown to players.
@export var body_part: StringName = &""


func get_type_key() -> StringName:
	return &"cybernetic"
