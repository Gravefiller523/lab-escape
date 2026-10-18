@tool
class_name RoomDoorway
extends Marker3D
## A gap in a room's wall where it can join another room. Put it on the edge of the room's footprint,
## at floor height (y = 0), in the middle of a cell's edge. Doorways that don't lead anywhere on a
## floor are filled with a wall plug when the floor is built.
## Cart rule: width must be at least Config.game.cart_width + 0.4 m (checked by a GUT test).

@export var width: float = 3.0
## How tall the opening is (the wall plug that fills it is this tall too).
@export var height: float = 3.0
