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

@export_group("Atmosphere")
## NEW 2026-11-14 (art phase WP26, Zachary OK'd the lighting mock-up): the air and light of a whole floor. GameWorld
## puts these on the world when a floor of this department is built. The defaults change nothing.
## Light that fills the shadows (ambient), and how strong it is.
@export var ambient_color: Color = Color(0.55, 0.55, 0.6)
@export var ambient_energy: float = 1.0
## What you see where nothing is drawn.
@export var background_color: Color = Color(0.12, 0.13, 0.15)
## Haze: its colour and how thick it is (0 = none). Volumetric haze also catches the lights' beams.
@export var fog_color: Color = Color(0.5, 0.5, 0.5)
@export var fog_density: float = 0.0
@export var volumetric_fog: bool = false
## Overall brightness after the filmic tone curve.
@export var exposure: float = 1.0
## Ceiling lights cast soft shadows (they fade out with distance, so only nearby ones cost anything).
@export var shadows: bool = false
## Specks floating around the players: dust, spores, sparks. Amount 0 = none. fall: how fast they drop (sparks).
@export var mote_color: Color = Color(1, 1, 1, 0.7)
@export var mote_amount: int = 0
@export var mote_size: float = 0.025
@export var mote_speed: float = 0.08
@export var mote_fall: float = 0.0
## A slowly pulsing warning light in every warning_light_every-th room (alpha 0 = none).
@export var warning_light_color: Color = Color(1, 0.15, 0.1, 0)
@export var warning_light_every: int = 3
