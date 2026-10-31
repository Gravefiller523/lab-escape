# hazards

Folder: `res://systems/hazards/` · Autoload: `Hazards` · Size: S · Floor generation step 4b (NEW 2026-10-31)

## Purpose
Dangerous spots on damaged floors: sparks, fire (and later toxic gas, water...). The floor generator
(level_gen) decides **where** hazards are: it switches on some `hazard` markers in heavily damaged and destroyed
rooms and writes the kind into each marker's params (`hazard_kind`). This system **makes** them: a zone at each
of those markers that hurts whoever stands in it, through the damage system.

**Not responsible for:** choosing hazard spots or counts (level_gen, `Config.floor_gen` V12), damage rules
(damage).

## Public API
```gdscript
# Autoload Hazards (HazardsService)
func spawn_for_floor() -> int              # every PC: a zone at each switched-on hazard marker (on floor_ready)
func get_zones() -> Array[HazardZone]

class_name HazardZone extends Area3D       # group "hazards"
var kind: StringName                       # "sparks", "fire" (others look like sparks for now)
func setup(hazard_kind: StringName) -> void
```

## How it works
- On `floor_ready` (every PC) `spawn_for_floor()` adds a `HazardZone` under each `Level.get_markers(&"hazard")`
  marker that has a `hazard_kind` param. Zones go away with the floor.
- A zone is a cylinder (`hazard_radius`) on the TRIGGERS layer that sees players and enemies. Looks: sparks = a
  crackling yellow light, fire = an orange glow. The flicker is looks only.
- **Host only:** every `hazard_tick_seconds` each living body inside takes
  `hazard_damage_per_second[kind] x hazard_tick_seconds` of `hazard_damage_types[kind]` damage
  (`HealthComponent.apply_damage`).
- Numbers: `config/floor_gen_tuning.tres`, group "Hazards (V12)".

## EventBus
- Listens: `floor_ready`. Emits: none.

## Multiplayer
Every PC builds the same zones from the floor plan (no network traffic). Only the host deals damage; health
is synced by the damage system.

## Test scene and GUT tests
`systems/hazards/test/hazards_test.tscn` (F6): a sparks zone and a fire zone; walk in and watch your health.
GUT `tests/unit/hazards/test_hazards.gd`: fire hurts inside and not outside; sparks use the tuning numbers;
zones appear at exactly the switched-on markers, once.

## Open design questions
- Placeholder looks and effects. Real particles, sounds, burning status, slowing water, toxic gas clouds and
  per-kind data (a HazardData content type) come later.

## Changelog
- 2026-10-31: created (floor generation step 4b).
