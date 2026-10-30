class_name IncidentData
extends Resource
## NEW 2026-10-30 (floor generation): what went wrong on a floor, e.g. a fabrication fire. Saved inside a
## DepartmentData file (its incidents list). Each floor picks one; damage spreads out from a room it can
## start in. See docs/design/floor-generation-plan.md, sections 4.4 and 5 (step 6).

## Unique name inside its department, e.g. "incident_fabrication_fire".
@export var id: StringName = &""
## Shown in the generation log and the debug view, e.g. "Fabrication fire".
@export var display_name: String = ""
## How often it is picked compared with the department's other incidents.
@export var weight: float = 1.0
## Room kinds it can start in (RoomData.room_kind), e.g. ["assembly_floor"].
@export var origin_room_kinds: PackedStringArray = PackedStringArray()
## The look of its damage overlays: "scorch", "water", "biohazard", "vines", "frost"...
@export var overlay_flavour: StringName = &""
## Extra hazards it adds near where it started, e.g. ["fire", "sparks"].
@export var hazard_kinds: PackedStringArray = PackedStringArray()
## Its lighting (e.g. red emergency light, darkness). Empty = the department's lighting.
@export var lighting: LightingStyleData
