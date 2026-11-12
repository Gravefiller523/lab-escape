class_name HintData
extends ContentData
## A first-time hint (NEW 2026-11-12, roadmap WP8): a short tip shown once per player, the first time its trigger
## happens, then never again on that PC. Example id: "hint_gems". Files live in res://content/hints/.
## The triggers are listed in docs/systems/ui.md (a new trigger needs a small code change in ui's Hints).

## When it shows: first_floor, gem_grabbed, vial_grabbed, lift_part_grabbed, vendor_near, someone_died, boss_floor.
@export var trigger: StringName = &""
## The tip.
@export_multiline var text: String = ""


func get_type_key() -> StringName:
	return &"hint"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append_array(PackedStringArray(["trigger", "text"]))
	return fields
