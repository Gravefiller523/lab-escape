@tool
class_name RoomMarker
extends Marker3D
## A spot inside a room scene that another system uses: where players start, a crate goes, the lift
## is... The kind is a plain name, so new kinds need no code here. Common kinds: player_spawn,
## enemy_spawn, prop_spawn, item_spawn, vendor, supply_counter, printer, cart, lift, lift_part,
## keycard, locked_door, task, boss_spawn, minion_spawn.
## Systems ask Level.get_markers(kind) on floor_ready and spawn their things there.

@export var kind: StringName = &"prop_spawn"
## Extra settings for whoever uses the marker, e.g. {"prop_id": "prop_crate"} for a fixed prop.
@export var params: Dictionary = {}
