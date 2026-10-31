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
`ItemPickup` child), `held_scene` (first-person model), `uses` (-1 = unlimited), NEW 2026-10-19 `max_stack` (how many fit in one
inventory slot; 1 = no stacking, like drinks and weapons), `world_mass` (kg of the pickup lying in the world), and `behaviours`:
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
`grants_upgrade` (glowing gems and robot parts). NEW 2026-10-31: loose debris props (tag `debris`, e.g.
`prop_debris_chunk`) turn up in damaged rooms when listed in `config/floor_gen_tuning.tres` `debris_prop_ids`. NEW 2026-10-19: `lift_slot` (a lift part: the slot it fits; a new
slot name adds a new slot to the lift), `fragile_break_speed` (above 0: shatters when it hits something this fast,
m/s), `needs_charge_seconds` (above 0: must sit on the lift charger this long before it fits). NEW 2026-10-30
(lift parts, for the new floor generator): `part_size` (`small`, `medium`, `large`, `huge`: which `lift_part`
markers it fits) and `part_category` (`mechanical`, `electrical`, `electronic`, `power`, `structural`: which
rooms it turns up in). **Tags that systems look for:** `meat`, `lift_part`,
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
`lift_part`, `keycard`, `locked_door`, `task`, `boss_spawn`, `minion_spawn`, NEW 2026-10-19 `charger` (where the lift charger may go)).
**Cart rules (checked by a test):** doorways at least cart width + 0.4 m (1.6 m by default); ramps,
never stairs, between doorways; room for a cart to turn. The lift room must fit a cart plus every player.
**Fill in:** `scene`, `size_cells`, `room_kind` (`normal`, `lift` (every floor starts in it: give it a `lift`
marker where the cargo lift stands, facing out of its doorway; CHANGED 2026-10-19: no player spawns, players arrive inside the lift), `start` (old name, not used), `corridor`, `hr`, `armory`,
`cafeteria`, `supply`, `boss_arena`), `department_ids`, `weight`, `min_floor`, `max_per_floor`.
Add its id to the department's `room_ids` (or leave `department_ids` empty to share it).
**Test:** level_gen's viewer scene, then `floor 1` in the console.
NEW 2026-10-18, the grid rules: the scene's origin is the footprint corner with the smallest x and z, at
floor height; the footprint covers `size_cells` cells along +x and +z (one cell = `room_cell_size`,
12 m). Put each `RoomDoorway` on the footprint's edge, in the middle of a cell's edge, at y = 0.
For a quick grey-box room, put the `GreyboxRoom` script on the root (it builds the floor and walls and
leaves a gap at every doorway); see `systems/level_gen/rooms/` for examples. Navigation regions come
with the enemies system.
NEW 2026-10-30, **3 m tiles for the new floor generator** (rules: `docs/systems/level_gen.md`, "Tile
standards"). **Copy** a tile from `systems/level_gen/tiles/` (root script `BlockoutTile`, set `size_units`)
and its `content/rooms/room_tile_<name>.tres`. **Sockets:** `RoomDoorway` direct children of the root, on the
edge, centred on a 3 m unit's edge, width 2.4, height 2.8; `connection` (`door`, `vent`, `crawl`, `jump`);
`open_edge` for hallway ends. A room needs a socket on every side. **Markers** under a `Markers` node (kinds
in the spec's marker table). **Damage:** keep the `Damage/Light`, `Damage/Heavy`, `Damage/Destroyed` nodes
(empty = placeholder boxes). Furniture: CSG boxes with `use_collision` on and the metadata `material_slot`
(`accent`). NEW 2026-10-31 (step 4b): put your own debris in `Damage/Light`, `Damage/Heavy`, `Damage/Destroyed`
(solid rubble in a `CSGCombiner3D` with `use_collision` on, keeping doorways, cart lanes and machine and spawn
spots clear); an overlay left empty gets generated blockout debris. Hazard spots: `hazard` markers with
`hazard_kinds` and `min_damage` params. **Fill in** as above plus `grid` = `tile_3m`, `tile_role` (`room`, `main_hall`, `secondary_hall`,
`template`), `size_category` (rooms: `small` 2x2/2x3/3x3, `medium` 3x4/4x4/4x5, `large` 5x6/6x6/6x8; empty
otherwise), `damage_levels`, `part_categories` (lift part categories that fit, e.g. `mechanical`),
`is_combat_room`. **Test:** run `tests/unit/level_gen/test_tile_standards.gd` and look at it in
`systems/level_gen/test/tile_gallery.tscn` (F6). New tiles don't appear in today's floors (only the new
generator, from step 3, uses them). NEW 2026-10-31: since step 3 the generator uses every enabled tile: shared
rooms (no `department_ids`) on every floor, a department's own tiles on its floors. Hallway pieces need no
code: the generator works out what a piece is from its open edges (2 opposite = straight, 2 next to each
other = corner, 3 = T, 4 = crossing, 1 = end) and asks for straight pieces 1, 3 or 5 units long. A
department's own welcome center is a `template` tile with `room_kind` `welcome_center` and the department in
`department_ids`. **Test:** `systems/level_gen/test/floorgen_viewer.tscn` (F6), or in a run press F3.

## Department
A department is a bundle. Make its rooms, enemies, boss, loot tables and stock first, then one
`DepartmentData`: `floor_count`, `room_ids`, `enemy_spawns`, `boss_id`, `loot_id`, `stock_id`,
`task_ids`, `lift_parts_per_floor`, NEW 2026-10-19 `lift_breaks_min`/`lift_breaks_max` (how many lift slots break per floor, 1 to 3) and `lift_part_ids` (which lift parts can break here; empty = all; `lift_parts_per_floor` and `lift_part_prop_id` are deprecated), NEW 2026-10-18 `lift_part_prop_id` (the prop carried back to the lift; CHANGED 2026-10-19: give that PropData the tag `lift_part` so the lift socket takes it), `rooms_per_floor_min/max`, `required_room_kinds`,
`optional_room_chances` (e.g. `{"supply": 0.6}`), `tile_library`, `music`, colours, `order_hint`,
NEW 2026-10-23: `upgrade_type` (`mutation` for DNA vials, `cybernetic` for data drives) and `upgrade_carrier_chance` (-1 = the GameConfig number). `in_run_rotation`. Put its art in `assets/<kind>/<department>/`. **Test:** `floor 1 department_<name>`.
NEW 2026-10-30, for the new floor generator (not used by gameplay yet), in the Inspector's "Floor generation"
group: `welcome_center_scene` (empty = the generic one), `room_types` (each a RoomTypeData: `id` like
`room_type_robot_test_bay`, `room_kind`, `display_name`, `weight`, `max_per_floor`, `min_floor`,
`size_categories`, `part_categories`), `shared_room_weight` (-1 = the tuning file's `shared_room_share`),
`palette` (`"wall"`, `"floor"`, `"trim"`, `"accent"` -> Material), `signage_style` (sign scene), `lighting`
(a LightingStyleData: light colour and energy, emergency light colour; how damage makes lights flicker and die is in `config/floor_gen_tuning.tres`),
`prop_pool` (prop ids with weights), `hazard_kinds` (e.g. `sparks`, `fire`), `incidents` (each an
IncidentData: `id` like `incident_fabrication_fire`, `display_name`, `weight`, `origin_room_kinds`,
`overlay_flavour`, `hazard_kinds`, `lighting`). NEW 2026-10-31 (step 4a): the generator uses `room_types` (department rooms
by weight), `required_room_kinds` (each one placed on every floor, far from the elevator), `shared_room_weight`,
`palette` and the room types' `display_name` for signs. NEW `boss_floors` (default on): off for a department
whose `boss_id` is only a stand-in, so its boss floors aren't rolled. Runs roll a department every floor (all
departments with `in_run_rotation`); `floor_count` is deprecated. Its own rooms: tiles with the department in
`department_ids` and the room type's `room_kind`; its own welcome center: a template tile with `room_kind`
`welcome_center`. Example: `content/departments/department_robotics.tres`. **Test:** `floor 1 department_<name>`
then F3.

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
NEW 2026-10-30: floor generation numbers (hallway lengths, branch odds, damage, doors, keycards, lift parts
per floor, cameras, hazards, tile sizes) are in `config/floor_gen_tuning.tres` (`Config.floor_gen`), grouped
and commented. Lists named `..._by_bracket` have one number per floor bracket (`floor_brackets`: 1, 4, 8).

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
