# items

Folder: `res://systems/items/` · Size: M · Phase 1b

## Purpose
What items do. Items are built from shared **behaviour pieces**: melee (crowbar, knife, fists), throw
(potted plant, hot coffee), consume (energy drink), use-on-object (water a mutated plant to grow a
ladder). Also owns item pickups in the world, the first-person held-item view, and **use targets**:
world objects that react to items (the plant ladder).

**Not responsible for:** slots (inventory), damage numbers and statuses (damage), physics of thrown items (physics_props).

## Public API
```gdscript
class_name HeldItemController extends Node       # child "HeldItem" of the player
signal item_action(item_id: StringName, trigger: int)
func get_active_item() -> ItemData
func is_on_cooldown(trigger: int) -> bool
func use(trigger: int) -> void                   # NEW 2026-10-19, local: what clicking does (tests call it)
func equip_target() -> bool                      # NEW 2026-10-19, local: F (the carried pickup, else the one you look at)
func equip(prop: NetProp) -> bool                # NEW 2026-10-19, local: put this pickup in your inventory

class_name ItemBehaviour extends RefCounted      # runtime building block, one per behaviour data class
func can_use(user: PlayerCharacter, data: ItemBehaviourData) -> bool
func use_local(user: PlayerCharacter, data: ItemBehaviourData) -> void    # instant feedback (animation, sound)
func use_host(user: PlayerCharacter, data: ItemBehaviourData, aim_origin: Vector3, aim_dir: Vector3, item: ItemData, slot_index: int) -> void   # the real effect; CHANGED 2026-10-19: + the item and its slot (-1 = fists)
static func for_data(data: ItemBehaviourData) -> ItemBehaviour   # NEW 2026-10-19: the runtime piece (found by file name)
static func find_in_reach(user, aim_origin, aim_dir, reach, mask, width = 0.6, also_skip = []) -> Dictionary   # NEW: shared sweep helper

class_name ItemPickup extends Node               # child of an item's world_scene (root is NetProp)
# CHANGED 2026-10-19: E grabs it like a prop; F equips it (HeldItemController.equip / equip_target); host:
# InventoryComponent.pick_up (swaps when full), then Props.despawn. CHANGED 2026-10-19: a marker node; helpers
static func prop_of(node: Node) -> NetProp
static func item_of(prop: NetProp) -> ItemData
static func uses_left_of(prop: NetProp) -> int

class_name UseTarget extends Node                # child of a world object that reacts to items
signal item_used_on(tag: StringName, player_id: int)   # host
@export var accepted_tags: PackedStringArray     # e.g. ["water"]
@export var single_use: bool = true
static func of(node: Node) -> UseTarget
signal used_changed(used: bool)                  # NEW 2026-10-19: every PC (the object shows it)
func try_use(tag: StringName, player_id: int) -> bool   # NEW 2026-10-19, host
func accepts(tag: StringName) -> bool
func is_used() -> bool
func reset() -> void                              # host (test scenes)

# NEW 2026-10-19: autoload Items (systems/items/items.gd, ItemsService): gives every body a HeldItemController
static func held_of(body: Node) -> HeldItemController
```
Behaviour data → runtime, found by file name: `MeleeBehaviourData` → `behaviours/melee_behaviour.gd`,
`ThrowBehaviourData` → `throw_behaviour.gd`, `ConsumeBehaviourData` → `consume_behaviour.gd`,
`UseOnObjectBehaviourData` → `use_on_object_behaviour.gd`.
Example use target: `systems/items/world/mutated_plant.tscn`: accepts `water`; when watered, grows a
climbable ladder (synced state `grown: bool`). Laser pointer: needs a new `LureBehaviourData` piece that
enemies' perception listens to (marked as a new building block for Phase 2).

NEW 2026-10-19, how it plays: left click = the PRIMARY behaviour, right click = SECONDARY (not while holding a prop:
then the left click throws the prop; not while a menu is open). Your swing plays at once; the host checks the item, the
slot, the cooldown and where you aimed (within 1.5 m of your eyes) and runs the effect; then everyone sees the swing.
Melee sweeps a 0.6 m box out to `reach` (hurtboxes and props; no wall in between) and hits the closest thing; it skips
other players (no friendly fire from melee). Thrown items fly as their world pickup (`Props.spawn_item`) with a host-only
`ThrownItem` rider: the first hurtbox it touches takes the damage and status (teammates too), a `breaks_on_impact` item
is gone after its first hit or hard bump. The held model sits in front of your camera (you) or at the `right_arm`
attach point (others). CHANGED 2026-10-19 (Zachary): E picks an item pickup up like any prop (carry, throw); **F** (InputActions `EQUIP`) puts
the pickup you look at, or the one you carry, into your inventory (swapping when full). The prompt over a pickup says
"Pick up <name>   [F] Equip" (prompt provider at priority 60). Console: `spawn item_<name>`, and
inventory's `give`. STUB (player movement): the mutated plant grows a spiral of steps, not a climbable ladder.

## EventBus
- Emits: `item_used` (all).
- Listens: none.

## Data it owns and saves
Uses `ItemData` and `StatusEffectData`. Owns `content/items/item_fists.tres` (the unarmed melee). Saves nothing.

## Adding content
New items made of existing behaviour pieces: one `.tres` in `content/items/` plus its world and held
scenes. **No code.** A new kind of behaviour is a data class + runtime file (building block).
Launch items: fists, crowbar (melee blunt, also `pry` use-on-object), knife (melee sharp), potted plant
(throw), energy drink (consume: speed boost; use-on-object: `water`), hot pot of coffee (throw: fire +
`status_burning`), laser pointer (Phase 2).

## Multiplayer
- PRIMARY/SECONDARY: the owner plays the swing at once (`use_local`) and sends a request with aim origin
  and direction; the host checks cooldown and range and runs `use_host` (raycast/shape-cast for melee,
  spawn a thrown prop, apply consume). Results sync through damage, inventory and physics_props.
- Use targets change state only on the host and sync it.

## Dependencies and stubs
inventory, damage, interaction, physics_props. Stubs: a dummy target with a HealthComponent.
Debug: registers `item <item_id>` and the `item` spawner.

## Test scene and GUT tests
Test scene: a range with dummies, a mutated plant, a crate to pry; keys to give each launch item.
GUT tests: `test_melee_hits_in_reach_only`, `test_cooldown_blocks_spam`, `test_throw_spawns_prop_and_removes_item`,
`test_coffee_applies_burning`, `test_drink_gives_speed_status_and_spends_use`, `test_water_grows_plant_ladder`,
`test_fists_when_slot_empty`, `test_new_item_file_needs_no_code`.
DONE 2026-10-19: `systems/items/test/items_test.tscn` (a table of pickups, 3 dummies, the mutated plant, boards to pry;
F1 crowbar, F2 knife, F3 potted plant, F4 energy drink, F7 hot coffee, F8 reset). GUT (`tests/unit/items/test_items.gd`, 15):
all of the above plus `test_fists_do_damage_too`, `test_melee_does_not_hurt_teammates`, `test_thrown_plant_hurts_what_it_hits`,
`test_crowbar_pries_but_stays`, `test_e_picks_an_item_up_like_a_prop`, `test_f_equips_the_item_you_look_at_or_carry`, `test_held_model_shows_in_your_view`, `test_item_used_event`.

## Acceptance criteria
- [ ] All launch items (except laser pointer) work on 2 PCs from data.
  *All 6 work from data (GUT); the crowbar and energy drink checked with 2 game copies (2026-10-19).*
- [ ] Watering the plant grows a ladder everyone can climb. *It grows steps (GUT); real ladder climbing needs a player movement mode.*
- [x] A new item made of existing pieces needs no code changes. *(GUT: `test_new_item_file_needs_no_code`)*

## Open design questions
- DEFAULT: thrown items can be picked up again unless `breaks_on_impact`.
- DEFAULT: energy drink is one item with two behaviours (drink = PRIMARY, pour = SECONDARY).

## Changelog
- 2026-10-07: spec created.
- 2026-10-19: built (Phase 1b). Changes marked above. Foundation: ItemData `world_mass`. physics_props: `Props.spawn_item`
  is real now (`PropSpawner.spawn_item`; `spawn_prop` also takes item ids, a PropData is made from the ItemData).
  inventory: NEW `take_one(index)` (throwing). Content: the 6 launch items in `content/items/`.
- 2026-10-19 (Zachary): F equips an item pickup (new InputActions `EQUIP`, F); E picks it up like a prop.

## HANDOFF
**Built (2026-10-19):** `HeldItemController`, `ItemBehaviour` + the melee, throw, consume and use-on-object runtime pieces,
`ThrownItem`, `ItemPickup`, `UseTarget`, `MutatedPlant` (`world/mutated_plant.tscn`), the `Items` autoload, grey-box world
and held scenes, the 6 launch items (fists, crowbar, knife, potted plant, energy drink, hot coffee), the test scene and
15 GUT tests. Checked with 2 game copies: a client's crowbar hit and energy drink matched on both PCs.

**Foundation / project.godot changes:** ItemData `world_mass` (2), InputActions `EQUIP` (F). Autoload line `Items` (after Inventory). No new EventBus
signals (emits `item_used` on every PC).

**Other systems touched (this branch):** physics_props (`Props.spawn_item`, `PropSpawner.spawn_item`, item ids in
`spawn_prop`), inventory (`take_one`).

**STUBS:** the plant's "ladder" is steps (player needs a ladder movement mode); held models don't animate beyond a
quick swing tween; no sounds yet (audio).

**For the next systems:**
- **enemies:** give enemies a `Hurtbox` (or `DamageService.give_components`) and melee and throws hit them.
- **ui:** show the held item's name / uses next to the inventory bar; `HeldItemController.item_action` for hit markers.
- **player:** a ladder movement mode so the plant can grow a real ladder; read `move_speed` (the energy drink's boost).
- **loot / vendors:** item drops are `Props.spawn_item(item_id, xform, uses_left)`.
