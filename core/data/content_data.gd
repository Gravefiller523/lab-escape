class_name ContentData
extends Resource
## Base class for every piece of game content (mutations, items, enemies, rooms...).
##
## Each content file is a .tres saved in its type's folder under res://content/.
## The ContentRegistry finds it automatically. Other code refers to content by
## its [member id], never by file path or list position.
##
## Data classes hold fields only. Game logic lives in the systems that use them.

## Unique, stable name, e.g. "mutation_fly". Must start with the type prefix
## (see [method get_type_key]) and must match the file name ("mutation_fly.tres").
## Never rename an id after it has shipped: saves and achievements use it.
@export var id: StringName = &""
## Name shown to players.
@export var display_name: String = ""
## Text shown to players (tooltips, closet, debug console).
@export_multiline var description: String = ""
## Small picture for menus and the HUD. Optional.
@export var icon: Texture2D
## Free-form labels other systems can filter on, e.g. "zoology", "starter".
@export var tags: PackedStringArray = PackedStringArray()
## Switch off unfinished content without deleting the file.
## Disabled content is loaded and validated, but never spawned or rolled.
@export var enabled: bool = true


## The content type, which is also the id prefix. Every subclass overrides this.
func get_type_key() -> StringName:
	return &""


## Fields the content validation test requires to be filled in.
## Subclasses add their own names to this list.
func get_required_fields() -> PackedStringArray:
	return PackedStringArray(["id", "display_name"])
