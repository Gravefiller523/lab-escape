class_name LightingStyleData
extends Resource
## NEW 2026-10-30 (floor generation): the colours of a department's (or an incident's) lights. Saved inside a
## DepartmentData or IncidentData file. Tiles mark their lights with the groups "tile_light" and
## "tile_emergency_light"; level_gen colours them with this when it builds a floor (from step 4b of the plan).
## How damage makes lights flicker, dim and die is in Config.floor_gen ("Damage lighting").
## See docs/design/floor-generation-plan.md, sections 3.6 and 9.

## Colour of the normal ceiling lights.
@export var light_color: Color = Color(1.0, 1.0, 1.0)
## Brightness of the normal ceiling lights (1 = the tile's own setting).
@export var light_energy: float = 1.0
## Colour of the emergency lights in damaged rooms.
@export var emergency_color: Color = Color(1.0, 0.15, 0.1)
