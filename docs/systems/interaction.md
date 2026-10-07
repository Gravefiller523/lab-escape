# interaction

Folder: `res://systems/interaction/` · Size: S · Phase 1a

## Purpose
Works out what the local player is looking at, shows the "Press E to ..." prompt, and decides what
pressing **use** does. Buttons, doors, vendors, the closet and printers are `Interactable`s. Grabbing
props and eating gems are added by other systems as **use handlers**, so interaction never depends on them.

**Not responsible for:** what an object does when used (the object's owner listens to `used`), physics grab (physics_props), consuming upgrades (upgrades).

## Public API
```gdscript
class_name Interactable extends Node            # child of any object on the INTERACTABLES layer (or a prop)
signal used(player_id: int)                     # fires on the HOST after checks
@export var prompt_text: String = "Use"
@export var hold_seconds: float = 0.0           # 0 = press; >0 = hold (e.g. 1 s to pull the refund lever)
@export var max_distance: float = 2.5
@export var enabled: bool = true
var use_condition: Callable                     # optional func(player_id: int) -> bool, checked on the host
static func of(node: Node) -> Interactable

class_name InteractionController extends Node   # child "Interaction" of the player
signal target_changed(target: Node3D)
func get_target() -> Node3D
func get_prompt() -> String
func get_hold_progress() -> float               # 0..1 for the HUD ring
## handler: func(target: Node3D) -> bool  (return true if it handled the press)
## Higher priority runs first. Used by physics_props (grab/drop) and upgrades (eat/install).
func register_use_handler(priority: int, handler: Callable) -> void
func unregister_use_handler(handler: Callable) -> void
## prompt: func(target: Node3D) -> String  ("" = no opinion). Lets handlers change the prompt ("Eat glowing gem").
func register_prompt_provider(priority: int, provider: Callable) -> void
```
What pressing **use** does, in order: (1) use handlers by priority (e.g. holding a glowing gem → eat it;
holding a normal prop → drop it; looking at a prop → grab it); (2) otherwise, if the target has an
`Interactable`, request a use from the host.

## EventBus
None.

## Data it owns and saves
Nothing.

## Adding content
None. Any scene becomes usable by adding an `Interactable` child and a collision shape on the INTERACTABLES layer.

## Multiplayer
- Targeting and prompts are local. A use is a request RPC to the host with the target's node path;
  the host checks distance, `enabled` and `use_condition`, then emits `used(player_id)` on the host only.
- Owners that need clients to react sync their own state (e.g. door open) themselves.

## Dependencies and stubs
player (camera ray and input). Stub: a camera-only rig with the `InteractionController`.

## Test scene and GUT tests
Test scene: a room with a button (press), a lever (hold 1 s), a disabled button, and one far away.
GUT tests: `test_target_found_by_ray`, `test_out_of_range_rejected_on_host`, `test_hold_requires_full_time`,
`test_use_condition_blocks`, `test_handler_priority_order`, `test_prompt_provider_overrides_text`.

## Acceptance criteria
- [ ] Looking at a button shows its prompt; pressing E makes the host emit `used` with the right player id.
- [ ] A client's use works through the host; too-far uses are refused.
- [ ] physics_props and upgrades can plug in without editing this system.

## Open design questions
- DEFAULT: holding a non-upgrade prop and pressing use **drops** it (Half-Life 2 style); `drop` (Q) always drops.

## Changelog
- 2026-10-07: spec created.
