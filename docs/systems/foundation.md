# foundation

Folder: `res://core/`, `res://config/`, `res://content/` (folders only) · Size: done (written in the planning session) · Phase 0

## Purpose
The shared base every system builds on: tuning numbers (`Config`), the content registry that finds
every content file (`ContentRegistry`), all content data classes, the content validator, input
action names, physics layer names and seeded random numbers. It holds data and lookups, not gameplay.

**Not responsible for:** any gameplay, networking, saving, UI. The EventBus has its own spec (`event_bus.md`).

## Public API

### Config (autoload)
```gdscript
var game: GameConfig            # Config.game.max_players, Config.game.gem_glow_chance, ...
```
`GameConfig` (`core/config/game_config.gd`) fields, grouped: Players (`max_players`), Run, Inventory,
Floors, Gems and loot, Death and reprinting, Physics props, Carts, Voice, Difficulty, Break Room, Debug.
Read the file for the full list; every field has a comment.

### ContentRegistry (autoload)
```gdscript
const TYPE_FOLDERS: Dictionary                     # type key -> folder under res://content/
var load_errors: PackedStringArray                 # empty when everything loaded cleanly
func reload() -> void
func get_content(id: StringName) -> ContentData    # null if missing
func has_content(id: StringName) -> bool
func get_all(type_key: StringName, include_disabled: bool = false) -> Array[ContentData]  # sorted by id
func get_all_ids(type_key: StringName, include_disabled: bool = false) -> Array[StringName]
func get_everything() -> Array[ContentData]
func get_type_keys() -> Array[StringName]
func register_content(data: ContentData) -> bool   # tests and debug only
static func type_key_for_id(id: StringName) -> StringName   # "mutation_fly" -> &"mutation"
```
Typical use: `var mutation := ContentRegistry.get_content(&"mutation_fly") as MutationData`.

### Content types
| Type key (id prefix) | Folder | Data class |
|---|---|---|
| mutation | mutations | MutationData (extends UpgradeData) |
| cybernetic | cybernetics | CyberneticData (extends UpgradeData) |
| item | items | ItemData |
| status | status_effects | StatusEffectData |
| prop | props | PropData |
| enemy | enemies | EnemyData |
| boss | bosses | BossData |
| room | rooms | RoomData |
| department | departments | DepartmentData |
| task | floor_tasks | FloorTaskData |
| cosmetic | cosmetics | CosmeticData |
| achievement | achievements | AchievementData |
| loot | loot_tables | LootTableData |
| stock | vendor_stock | VendorStockData |

Sub-resources saved inside content files (not content themselves): `UpgradeEffectData` and its
pieces (`MovementEffectData`, `VoiceEffectData`, `SlotEffectData`, `StatEffectData`,
`VisualAttachmentEffectData`, `BehaviourEffectData`), `ItemBehaviourData` pieces
(`MeleeBehaviourData`, `ThrowBehaviourData`, `ConsumeBehaviourData`, `UseOnObjectBehaviourData`),
`BossPhaseData`, `WeightedIdData`, `UnlockRuleData`, `LootEntryData`, `VendorEntryData`.

All content classes extend `ContentData`: `id`, `display_name`, `description`, `icon`, `tags`,
`enabled`, plus `get_type_key()` and `get_required_fields()`.

### ContentValidator
```gdscript
static func validate_all(all_content: Array[ContentData], known_type_keys: Array[StringName]) -> PackedStringArray
static func validate_one(data: ContentData, by_id: Dictionary, known_type_keys: Array[StringName]) -> PackedStringArray
```
Rules: id prefix matches type, id is lower_snake_case, file name matches id, required fields are
filled, every field ending `_id`/`_ids` points at existing content (and the right type when the word
before `_id` is a type key, e.g. `boss_id`, `minion_enemy_ids`), and sub-resources are checked too.

### InputActions, PhysicsLayers, SeededRng
```gdscript
InputActions.USE, .DROP, .PRIMARY, .SECONDARY, .JUMP, ...   # StringName constants
static func InputActions.slot_action(slot_number: int) -> StringName
static func InputActions.ensure_registered() -> void        # called by Config at startup

PhysicsLayers.WORLD, .PLAYERS, .ENEMIES, .PROPS, .HELD_PROPS, .CARTS, .TRIGGERS, .INTERACTABLES, .HITBOXES, .DEBRIS (NEW 2026-10-29)
static func PhysicsLayers.bit(layer: int) -> int

static func SeededRng.make(base_seed: int, stream: StringName, index: int = 0) -> RandomNumberGenerator
static func SeededRng.pick_weighted(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int

# NEW 2026-11-11 (roadmap WP1). Client: call send() now if the connection to the host is open, else once it opens.
# Use it for "ask the host for my state" requests in _ready of anything built with a floor. send = a method of node.
static func HostLink.when_connected(node: Node, send: Callable) -> void
# NEW 2026-11-12 (roadmap WP13b): which build of the game this is (core/util/build_info.gd)
static func BuildInfo.get_version() -> String     # Project Settings > Application > Config > Version, e.g. "0.1.0"
static func BuildInfo.get_stamp() -> String       # a fingerprint: exported = first 7 letters of the .pck's MD5; editor = "dev-" + git commit
static func BuildInfo.get_build_id() -> String    # "<version>+<stamp>": what net_core compares on join
static func BuildInfo.get_label() -> String       # for people: "v0.1.0 build 3fa9c1d"
static func BuildInfo.label_for(build_id: String) -> String
```

## EventBus
Owns the EventBus file; see `event_bus.md`. Emits and listens to nothing itself.

## Data it owns and saves
Owns every data class above and `config/game_config.tres`. Saves nothing.

## Adding content
See `docs/ADDING_CONTENT.md`. Adding a new content **type** (rare) means: a data class in
`core/data/`, a line in `ContentRegistry.TYPE_FOLDERS`, a folder in `content/`, and a section in
ADDING_CONTENT.md.

## Multiplayer
Nothing here is networked. Every PC loads the same content and config from the game files, which is
why network messages can safely send ids instead of whole objects.

## Dependencies
None. Everything else depends on this.

## Test scene and GUT tests
- `tests/content/test_content_validation.gd`: loads all content and fails with a readable list of problems.
- `tests/unit/core/test_content_validator.gd`: checks the validator catches duplicate ids, wrong
  prefixes, empty required fields, missing references, wrong-type references, references inside
  sub-resources, and that `SeededRng` repeats.

## Acceptance criteria
- [x] Project opens in Godot 4.7 with no errors; autoloads `Config`, `EventBus`, `ContentRegistry` load.
- [x] `Config.game.max_players == 4` by default; input actions are registered.
- [x] A `.tres` dropped in a content folder is found with no code change; `_`-prefixed files are skipped.
- [x] Validator catches a missing boss reference (checked headless in the planning session).
- [ ] GUT installed and both test files pass (needs GUT added to `addons/`).

## Open design questions
- DEFAULT: content files can't reference other content directly (only by id), so moving files never
  breaks anything. Scenes, textures and audio are referenced directly.
- Later: also validate `_id` fields in `GameConfig` (e.g. `unarmed_item_id`) once `item_fists` exists.

## Changelog
- 2026-10-07: created.
- 2026-10-29 (feel step 0): NEW `Config.feel` (`FeelTuning`, `core/config/feel_tuning.gd`): every "how it feels" number in one file, `config/feel_tuning.tres`, with sections `player` (PlayerTuning), `props` (PropTuning) and `ai` (AiTuning). Loaded in `Config._enter_tree` after `Config.game`; an empty section falls back to its script defaults. GameConfig keeps game rules and network rates.
- 2026-11-11 (floor generation step 5b): FloorGenTuning: Zoology debris in `debris_prop_ids_by_department`;
  `broken_enclosure` in the hazard tables (0 damage). Content: the Zoology department, its tiles and room data, 3
  debris props, `assets/materials/zoology/`. Additions only.
- 2026-11-11 (floor generation step 5a): FloorGenTuning NEW `debris_prop_ids_by_department`, `debris_props_for()`,
  `hazard_slow`; `hazard_damage_per_second` and `hazard_damage_types` gain toxic_spores, toxic_gas and water. Content:
  the Botany department, its tiles and room data, `prop_debris_vines`, `assets/materials/botany/`. Additions only.
- 2026-11-10 (floor generation step 4f): FloorGenTuning NEW `enemy_spot_share`, `enemy_spots_min`,
  `enemy_spot_min_distance`. Additions only.
- 2026-11-10 (floor generation step 4e): FloorGenTuning NEW `map_resolution`, `map_blink_seconds`, `map_scan_seconds`,
  `map_player_colors`, `map_lean_seconds`, `map_lean_height`. project.godot: NEW autoload `Security` (after
  `Hazards`). Additions only.
- 2026-11-10 (floor generation step 4d): FloorGenTuning NEW `part_backup_spots`, `part_branch_end_weight`,
  `part_cue_color`, `part_cue_range`. Content: `prop_lift_motor`, `prop_lift_control_board`, `prop_lift_brake_assembly`.
  Additions only.
- 2026-10-31 (level_gen emergency slits): FloorGenTuning NEW group "Emergency slits" (`emergency_slit_*`,
  `emergency_small_room`, `emergency_long_wall`, `emergency_room_spacing`, door/furniture clearances,
  `emergency_hall_lit_every`, `emergency_max_lights_per_tile`). Additions only.
- 2026-10-31 (floor generation step 4c): FloorGenTuning NEW `keycard_colours`, `crowbar_item_id`, `power_cell_prop_id`.
  Additions only.
- 2026-10-31 (level_gen): InputActions NEW `DEBUG_FLOOR_MAP` (F3) and `DEBUG_FLOOR_REGENERATE` (F4). Additions only.
- 2026-10-31 (floor generation step 4b): FloorGenTuning NEW damaged-room prop shares, `debris_prop_ids`, hazard
  damage numbers. project.godot NEW autoload line `Hazards` (after `Level`). Additions only.
- 2026-10-31 (floor generation step 4a): GameConfig NEW `run_floor_count` (18), `boss_every_floors` (6);
  `floors_per_department` and `departments_per_run` deprecated (kept). DepartmentData NEW `boss_floors`;
  `floor_count` deprecated. FloorGenTuning step 3 additions (generator, secondary hallways, markers). Additions only.
- 2026-10-30 (floor generation step 2): NEW `Config.floor_gen` (`FloorGenTuning`, `core/config/floor_gen_tuning.gd`, live copy `config/floor_gen_tuning.tres`): every floor generation number (plan section 17, V1-V16), grouped. Loaded after `Config.feel`. NEW data classes `RoomTypeData`, `IncidentData`, `LightingStyleData` (`core/data/levels/`); new fields on RoomData, DepartmentData and PropData (see docs/systems/level_gen.md changelog). Additions only.
- 2026-10-29 (HL2 feel step 2): NEW `PhysicsLayers.DEBRIS` (10): broken prop pieces, which only hit the world. NEW `MovementEffectData.can_sprint` (default true), `PropData.surface`, `health`, `break_pieces`, `break_scene`, `EnemyData.impact_mass`, `BossData.impact_mass`.
- 2026-11-11 (roadmap WP1): NEW `HostLink` (`core/util/host_link.gd`): `HostLink.when_connected(node, send)` runs a client's request to the host now, or once the connection opens (a mid-floor joiner builds the floor before it is open). NEW GameConfig `prop_snapshot_max_bytes` (1100).
- 2026-11-11 (roadmap WP6): NEW `InputActions.PLAYER_LIST` (Tab): open or close the player list.
- 2026-11-11 (roadmap WP9): NEW `RangedAttackData` (`core/data/enemies/ranged_attack_data.gd`: shots, interval, speed, gravity, spread, damage, status, min/max range, projectile size and colour, lifetime) and `EnemyData.ranged_attack`.
- 2026-11-11 (roadmap WP7): NEW `HitFeelTuning` (`core/config/hit_feel_tuning.gd`), `FeelTuning.hits` (`Config.feel.hits`, a section in `config/feel_tuning.tres`): flash, hit pause, flinch, death poof, hurt kick and vignette, gem sparkle numbers. NEW `Effects` (`core/util/effects.gd`): `burst()` (a puff of little cubes) and `float_text()` (text that rises and fades); local, they free themselves.
- 2026-11-12 (roadmap WP8): NEW content types `announcement` (AnnouncementData, `content/announcements/`: text, department_ids, weight) and `hint` (HintData, `content/hints/`: trigger, text), in `core/data/story/`.
- 2026-11-12 (roadmap WP13b): NEW `BuildInfo` (`core/util/build_info.gd`): the version number plus a fingerprint that is different for every build and needs no build step (an exported game hashes its own `.pck`; the editor reads the git commit from `.git`). project.godot: NEW `application/config/version` = "0.1.0" (raise it by hand for builds that go to players). net_core refuses joiners whose build id differs; telemetry logs it; console `version` prints it. Tests: `tests/unit/core/test_build_info.gd` (5).
- 2026-11-12 (roadmap WP14): EnemyData NEW `lure_kinds` (PackedStringArray). NEW item behaviour data `LureBehaviourData` (`core/data/items/behaviours/lure_behaviour_data.gd`).
- 2026-11-13 (roadmap WP15b): NEW EventBus signal `kill_credited` (see event_bus.md).
- 2026-11-13 (roadmap WP15): FloorTaskData NEW `work_seconds`, `reward_loot_id`, `params`; reward kind `loot`. project.godot: NEW autoload `Objectives` (after Security).
