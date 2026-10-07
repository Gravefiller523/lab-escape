# Adding content

This guide is for adding new mutations, items, enemies, rooms and everything else. **Adding content
means adding files. You should never need to edit code.** If you find you do, stop and ask: either a
new building block is needed (see the end of this guide) or something is wrong.

## How content works (read once)
- Every piece of content is a **`.tres` file** (a Godot "Resource": a saved bundle of settings) in its
  type's folder under `res://content/`. Subfolders are fine, e.g. `content/enemies/zoology/`.
- The game finds every file automatically when it starts (`ContentRegistry`). There is no list to update.
- Each file has an **id**: `<type>_<name>` in lower_snake_case, e.g. `mutation_fly`. The **file name
  must be the id**: `mutation_fly.tres`. Ids are permanent; never rename one after it has shipped.
- Files point to other content **by id** (fields ending in `_id` or `_ids`), never by dragging the
  other file in. Scenes, models, textures and sounds are dragged in directly.
- Files and folders starting with `_` are ignored. Use `_drafts/` for unfinished work, or untick `enabled`.

## The general steps (every type)
1. In Godot's FileSystem panel, open the type's folder (table below).
2. **Easiest:** right-click an existing file of the same type → **Duplicate...** → name it `<new id>.tres`.
   **Or:** right-click the folder → **Create New → Resource...** → search for the data class (e.g. `MutationData`) → save as `<new id>.tres`.
3. Click the new file. In the **Inspector**, set `id` (same as the file name), `display_name`,
   `description`, and the type's fields (below). Hover over any field to see its explanation.
4. Make any scene it needs (copy a similar scene and change it).
5. **Test it:**
   - Run the content validation test: GUT panel → run `tests/content/test_content_validation.gd`
     (or the debug console: `validate`). Fix anything it lists. It names the file and the field.
   - Run the game, open the console with `` ` `` and spawn it: `spawn <id>` (works for props, items,
     enemies, bosses, mutations, cybernetics and tasks).
6. If you used an AI tool for any asset, add a line to `docs/AI_CONTENT_LOG.md`.
7. Commit on a `content/<what>` branch.

| Type | Folder | Data class | Id prefix |
|---|---|---|---|
| Mutation | `content/mutations/` | MutationData | `mutation_` |
| Cybernetic | `content/cybernetics/` | CyberneticData | `cybernetic_` |
| Item | `content/items/` | ItemData | `item_` |
| Status effect | `content/status_effects/` | StatusEffectData | `status_` |
| Prop | `content/props/` | PropData | `prop_` |
| Enemy | `content/enemies/` | EnemyData | `enemy_` |
| Boss | `content/bosses/` | BossData | `boss_` |
| Room | `content/rooms/` | RoomData | `room_` |
| Department | `content/departments/` | DepartmentData | `department_` |
| Floor task | `content/floor_tasks/` | FloorTaskData | `task_` |
| Cosmetic | `content/cosmetics/` | CosmeticData | `cosmetic_` |
| Achievement | `content/achievements/` | AchievementData | `achievement_` |
| Loot table | `content/loot_tables/` | LootTableData | `loot_` |
| Vendor stock | `content/vendor_stock/` | VendorStockData | `stock_` |

---

## Mutation
**Copy:** `mutation_fly.tres` (once it exists). **Fill in:**
- `effects`: add effect pieces with "Add Element", then pick the piece type:
  - `MovementEffectData`: speed/jump/gravity/height multipliers, `can_jump`, `movement_mode`
    (`wall_climb`, `slide`, `hop`, `hover`, or empty), `mode_priority`.
  - `VoiceEffectData`: `pitch_scale` (above 1 = higher), `effect_preset` (`buzz`, `robot`, `gurgle`, `slime`, `deep`), `effect_strength`.
  - `SlotEffectData`: `extra_slots`.
  - `StatEffectData`: `stat` (`max_health`, `move_speed`, `melee_damage`, `throw_strength`, `carry_strength`, `damage_taken`), `add`, `multiply`.
  - `VisualAttachmentEffectData`: `scene` (wings, tentacles), `attach_point` (`head`, `face`, `back`, `left_arm`, `right_arm`, `legs`, `feet`, `body`), `hides_cosmetic_slots`.
  - `BehaviourEffectData`: a special-rule scene (ask a programmer if none fits).
- `stack_rule`, `max_stacks`, `clash_tags` (e.g. `legs` so Octo and Frog replace each other),
  `drop_weight`, `department_ids` (empty = can drop anywhere), `glow_color`.

**Test:** `give mutation_<name>` in the console, or `spawn mutation_<name>` to drop a glowing gem holding it and eat it (hold it, press E).

## Cybernetic
Same as a mutation (same effect pieces), plus `body_part`. Robot parts dropped by Robotics enemies
pick from all cybernetics automatically. **Test:** `spawn cybernetic_<name>` spawns a robot part holding it.

## Item
**Copy:** `item_crowbar.tres`. **Fill in:** `category` (weapon, tool, consumable), `world_scene` (the
pickup lying on the floor: copy an existing pickup scene; its root uses `NetProp` and it has an
`ItemPickup` child), `held_scene` (first-person model), `uses` (-1 = unlimited), and `behaviours`:
- `MeleeBehaviourData`: damage, damage_type (`blunt`, `sharp`, `fire`...), reach, knockback, status_id.
- `ThrowBehaviourData`: throw_force, damage, damage_type, status_id, breaks_on_impact.
- `ConsumeBehaviourData`: heal_amount, status_id.
- `UseOnObjectBehaviourData`: interaction_tag (`water`, `pry`, `cut`...), reach, spends_use.
Each behaviour has a `trigger` (PRIMARY = left mouse, SECONDARY = right mouse) and `cooldown`.
To sell it, add it to a vendor stock file. **Test:** `item item_<name>` or `spawn item_<name>`.

## Status effect
**Fill in:** `duration`, `tick_damage`, `tick_interval`, `damage_type`, `stat_modifiers`
(StatEffectData pieces, e.g. `move_speed` × 1.5 for a speed boost), `visual_scene`, `refresh_on_reapply`.
Items and attacks point to it with `status_id`.

## Prop
**Copy:** `prop_crate.tres`. **Fill in:** `scene` (copy an existing prop scene: root is `NetProp`
with a collision shape and mesh), `mass` (kg; above 40 needs two players, above 120 can't be lifted),
`is_key_object` (lift parts, keycards), `cart_allowed`, `despawn_after_seconds`, `gem_value` (gems only),
`grants_upgrade` (glowing gems and robot parts). **Tags that systems look for:** `meat`, `lift_part`,
`keycard`, `glowing_gem`, `robot_part`. **Test:** `spawn prop_<name>`.

## Enemy
**Copy:** `enemy_rat.tres` and its scene. **Scene:** start from the enemy template scene in
`systems/enemies/`, choose which shared states it uses (idle, patrol, chase, attack_melee,
attack_ranged, flee, swarm) and add behaviour nodes. **Fill in:** health, speed, attack numbers,
`sight_range`, `flee_health_fraction`, `spawn_cost`, `min_floor`, `loot_id`. Then add it to a
department's `enemy_spawns` (with a weight) so it appears. **Test:** `spawn enemy_<name>`.

## Boss
**Fill in:** `scene`, `max_health`, `phases` (each: `starts_at_health_fraction`, `attack_names` from
the boss scene's attack nodes, `minion_enemy_ids`, `minions_per_wave`, `minion_wave_interval`),
`arena_room_id`, `loot_id`, `music`. Set the department's `boss_id`. **Test:** `boss` in the console.

## Room
**Copy:** a similar room scene and its `.tres`. **Scene must have:** floor/walls, a baked
`NavigationRegion3D`, `RoomDoorway` markers on the edges, and `RoomMarker`s (kind: `player_spawn`,
`enemy_spawn`, `prop_spawn`, `item_spawn`, `vendor`, `supply_counter`, `printer`, `cart`, `lift`,
`lift_part`, `keycard`, `locked_door`, `task`, `boss_spawn`, `minion_spawn`).
**Cart rules (checked by a test):** doorways at least cart width + 0.4 m (1.6 m by default); ramps,
never stairs, between doorways; room for a cart to turn. The lift room must fit a cart plus every player.
**Fill in:** `scene`, `size_cells`, `room_kind` (`normal`, `start`, `lift`, `corridor`, `hr`, `armory`,
`cafeteria`, `supply`, `boss_arena`), `department_ids`, `weight`, `min_floor`, `max_per_floor`.
Add its id to the department's `room_ids` (or leave `department_ids` empty to share it).
**Test:** level_gen's viewer scene, then `floor 1` in the console.

## Department
A department is a bundle. Make its rooms, enemies, boss, loot tables and stock first, then one
`DepartmentData`: `floor_count`, `room_ids`, `enemy_spawns`, `boss_id`, `loot_id`, `stock_id`,
`task_ids`, `lift_parts_per_floor`, `rooms_per_floor_min/max`, `required_room_kinds`,
`optional_room_chances` (e.g. `{"supply": 0.6}`), `tile_library`, `music`, colours, `order_hint`,
`in_run_rotation`. Put its art in `assets/<kind>/<department>/`. **Test:** `floor 1 department_<name>`.

## Floor task
**Fill in:** `scene` (built from `FloorTask` and `TaskStation` pieces), `min_players`,
`max_participants`, `reward` (`lift_part`, `fuse`, `keycard`, `door_open`), `weight`, `room_kind`.
Add its id to departments' `task_ids`. **Test:** `spawn task_<name>`.

## Cosmetic
**Fill in:** `slot` (`hat`, `glasses`, `coat`, `gloves`, `shoes`), `scene`, `mutation_variants`
(mutation id → alternative scene, e.g. a tall hat for Giraffe), `unlock` (leave empty for unlocked from
the start, or an UnlockRuleData: `runs_completed`, `floors_reached`, `boss_defeated` + `boss_id`,
`achievement` + `achievement_id`, and `count`). **Test:** `unlock_cosmetics`, then the closet.

## Achievement
First create it on the Steamworks site. **Fill in:** `steam_api_name`, `trigger_event` (an EventBus
signal name, e.g. `boss_defeated`), `match_id` (e.g. `boss_giant_rat`, or empty), `local_player_only`,
`required_count`, `steam_stat_name` (for counted ones).

## Loot table
**Fill in:** `rolls`, `nothing_weight`, `entries` (each: `prop_id` or `item_id`, `weight`, `min_count`,
`max_count`). Plain gems may turn into glowing gems automatically (chance in `config/game_config.tres`);
robot parts always hold a cybernetic. Point enemies, bosses or departments at it with `loot_id`.
**Test:** `loot loot_<name>` drops one roll in front of you.

## Vendor stock
**Fill in:** `slots_shown`, `entries` (each: `item_id`, `price` in gem value, `weight`, `stock_count`).
Items only. Point a department at it with `stock_id`.

## Tuning numbers
Global numbers (player limit, glow chance, meat cost, carry limits, difficulty scaling) are in
`config/game_config.tres`. Click it and change values in the Inspector. Never type them into code.

---

## When you need a new building block (programmers)
These are small code additions, each in a known place, found by file name so no list needs editing:
| Building block | Data | Code |
|---|---|---|
| Upgrade effect piece | `core/data/upgrades/effects/<name>_effect_data.gd` | `systems/upgrades/effects/<name>_effect.gd` |
| Item behaviour | `core/data/items/behaviours/<name>_behaviour_data.gd` | `systems/items/behaviours/<name>_behaviour.gd` |
| Movement mode | (a name in MovementEffectData) | `systems/player/movement_modes/<name>_mode.gd` |
| Voice preset | (a name in VoiceEffectData) | `systems/voice/presets/<name>_preset.gd` |
| Enemy state / behaviour | (used in enemy scenes) | `systems/enemies/states/` or `systems/enemies/behaviours/` |
| Boss attack | (a name in BossPhaseData) | `systems/bosses/attacks/<name>.gd` |
| Room marker kind | (a name on RoomMarker) | the system that spawns things there |
Files in `core/data/` are foundation files: you may add new ones, but follow CLAUDE.md §2 and §10.

## Adding a new content type (rare)
1. A data class in `core/data/` extending `ContentData`, with `get_type_key()` returning the new prefix.
2. A line in `ContentRegistry.TYPE_FOLDERS` and a folder in `content/`.
3. Reference fields named `<type>_id` / `<type>_ids` so the validator checks them.
4. A section in this guide, and a note in `docs/systems/foundation.md`.
