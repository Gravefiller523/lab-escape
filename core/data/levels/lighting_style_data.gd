class_name LightingStyleData
extends Resource
## NEW 2026-10-30 (floor generation): how a department's (or an incident's) lights look, and what damage
## does to them. Saved inside a DepartmentData or IncidentData file. Tiles mark their lights with the group
## "tile_light"; level_gen colours them with this when it builds a floor (from step 4b of the plan).
## See docs/design/floor-generation-plan.md, sections 3.6 and 9.

## Colour of the normal ceiling lights.
@export var light_color: Color = Color(1.0, 1.0, 1.0)
## Brightness of the normal ceiling lights (1 = the tile's own setting).
@export var light_energy: float = 1.0
## Lightly damaged rooms: share of lights that flicker (0 to 1).
@export var flicker_share_light: float = 0.25
## Heavily damaged rooms: the emergency light colour.
@export var emergency_color: Color = Color(1.0, 0.15, 0.1)
## Heavily damaged rooms: share of normal lights that are off (0 to 1).
@export var lights_off_share_heavy: float = 0.4
## Destroyed rooms: share of normal lights that are off (0 to 1).
@export var lights_off_share_destroyed: float = 0.85
