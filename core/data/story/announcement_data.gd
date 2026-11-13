class_name AnnouncementData
extends ContentData
## A line the lab's PA system reads out (NEW 2026-11-12, roadmap WP8): cheerful corporate notices that tell the
## premise (decision D5). Example id: "announcement_escaping_fireable". Files live in res://content/announcements/.
## Shown as a line of text at the top of the screen a few seconds after the lift arrives on a floor; voiced later.

## What the PA says.
@export_multiline var text: String = ""
## Only on floors of these departments. Empty = anywhere.
@export var department_ids: Array[StringName] = []
## How likely it is to be picked compared with the others that fit.
@export var weight: float = 1.0
## NEW 2026-11-13 (roadmap WP19): when it is read: &"floor" (a few seconds into a floor; empty means the same) or
## &"escape_ride" (on the last ride up, after the last boss).
@export var moment: StringName = &"floor"


func get_type_key() -> StringName:
	return &"announcement"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("text")
	return fields
