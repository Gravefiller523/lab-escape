@tool
class_name RoomDoorway
extends Marker3D
## A gap in a room's wall where it can join another room. Put it on the edge of the room's footprint,
## at floor height (y = 0), in the middle of a cell's edge. Doorways that don't lead anywhere on a
## floor are filled with a wall plug when the floor is built.
## Cart rule: width must be at least Config.game.cart_width + 0.4 m (checked by a GUT test).
## NEW 2026-10-30: on the new 3 m tiles a doorway is called a "socket": 2.4 m wide, 2.8 m tall
## (Config.floor_gen.doorway_width / doorway_height). See docs/systems/level_gen.md, "Tile standards".

## The values of `connection` below.
const CONNECTION_DOOR: StringName = &"door"
const CONNECTION_VENT: StringName = &"vent"
const CONNECTION_CRAWL: StringName = &"crawl"
const CONNECTION_JUMP: StringName = &"jump"

@export var width: float = 3.0
## How tall the opening is (the wall plug that fills it is this tall too).
@export var height: float = 3.0
## NEW 2026-10-30: what goes through it: "door" (a normal walk-through doorway), "vent", "crawl" (a
## crawlspace) or "jump" (a gap you jump across). Only "door" counts for carrying lift parts back.
@export var connection: StringName = CONNECTION_DOOR
## NEW 2026-10-30: true = the tile has no wall at all along this grid unit's edge (hallway ends, so
## hallway pieces join into one long hallway). Two open edges joined look seamless; an open edge
## against a wall with a doorway is closed by that wall. Unused, it gets a cap as wide as the grid unit.
@export var open_edge: bool = false
