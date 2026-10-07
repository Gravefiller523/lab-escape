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

PhysicsLayers.WORLD, .PLAYERS, .ENEMIES, .PROPS, .HELD_PROPS, .CARTS, .TRIGGERS, .INTERACTABLES, .HITBOXES
static func PhysicsLayers.bit(layer: int) -> int

static func SeededRng.make(base_seed: int, stream: StringName, index: int = 0) -> RandomNumberGenerator
static func SeededRng.pick_weighted(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int
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
