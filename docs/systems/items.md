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

class_name ItemBehaviour extends RefCounted      # runtime building block, one per behaviour data class
func can_use(user: PlayerCharacter, data: ItemBehaviourData) -> bool
func use_local(user: PlayerCharacter, data: ItemBehaviourData) -> void    # instant feedback (animation, sound)
func use_host(user: PlayerCharacter, data: ItemBehaviourData, aim_origin: Vector3, aim_dir: Vector3) -> void   # the real effect

class_name ItemPickup extends Node               # child of an item's world_scene (root is NetProp)
# Interactable prompt "Take <name>"; on use (host): Inventory.add_item, then Props.despawn.

class_name UseTarget extends Node                # child of a world object that reacts to items
signal item_used_on(tag: StringName, player_id: int)   # host
@export var accepted_tags: PackedStringArray     # e.g. ["water"]
@export var single_use: bool = true
static func of(node: Node) -> UseTarget
```
Behaviour data → runtime, found by file name: `MeleeBehaviourData` → `behaviours/melee_behaviour.gd`,
`ThrowBehaviourData` → `throw_behaviour.gd`, `ConsumeBehaviourData` → `consume_behaviour.gd`,
`UseOnObjectBehaviourData` → `use_on_object_behaviour.gd`.
Example use target: `systems/items/world/mutated_plant.tscn`: accepts `water`; when watered, grows a
climbable ladder (synced state `grown: bool`). Laser pointer: needs a new `LureBehaviourData` piece that
enemies' perception listens to (marked as a new building block for Phase 2).

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

## Acceptance criteria
- [ ] All launch items (except laser pointer) work on 2 PCs from data.
- [ ] Watering the plant grows a ladder everyone can climb.
- [ ] A new item made of existing pieces needs no code changes.

## Open design questions
- DEFAULT: thrown items can be picked up again unless `breaks_on_impact`.
- DEFAULT: energy drink is one item with two behaviours (drink = PRIMARY, pour = SECONDARY).

## Changelog
- 2026-10-07: spec created.
