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
func unregister_prompt_provider(provider: Callable) -> void   # NEW 2026-10-17
func press_use(target: Node3D) -> bool          # NEW 2026-10-17: what pressing use does (handlers, then the Interactable)
func request_use(target: Node3D, held_seconds: float) -> void   # NEW 2026-10-17: ask the host to use a target
const NODE_NAME: String = "Interaction"

# NEW 2026-10-17 on Interactable:
func get_anchor() -> Node3D                     # the object distance is measured to (its parent)
func allows(player_id: int) -> bool             # host: enabled and use_condition

# NEW 2026-10-30 (HL2 feel step 4.1) on Interactable:
signal refused(player_id: int)                  # host: in reach, but disabled or use_condition said no
signal use_started(player_id: int)              # host, continuous objects: started holding E on it
signal use_tick(player_id: int, delta: float)   # host, continuous objects: every physics step while held
signal use_stopped(player_id: int)              # host, continuous objects: let go, looked away, walked off
@export var continuous: bool = false            # hold E to keep using it (valves, cranks)
@export var use_point: NodePath                 # reach is measured to this Node3D (a handle), e.g. "../Handle"
func get_use_position() -> Vector3

# NEW 2026-10-30 on InteractionController:
func set_continuous_use(target: Node3D) -> void # start (target) or stop (null) holding E on a continuous object
func deny() -> void                             # the "can't use" buzz on this PC (EventBus.use_denied)

# NEW 2026-10-30: Config.feel.interaction (UseTuning, systems/interaction/use_tuning.gd):
#   aim_assist_radius (0.12 m), deny_cooldown (0.3 s)

# NEW 2026-10-17: autoload "Interaction" (systems/interaction/interaction.gd, class_name InteractionService)
func get_local_controller() -> InteractionController   # null if you have no body
static func controller_of(body: PlayerCharacter) -> InteractionController
```
NEW 2026-10-17: the `Interaction` autoload adds an `InteractionController` (child "Interaction") to
every player body when `player_spawned` fires, on every PC, so the player scene needn't change. Only the
local body's controller looks and listens to the key; the others are there so use requests (RPCs) have
the same node path on every PC. Target paths are sent relative to the multiplayer root. The look ray
is 4 m long and hits INTERACTABLES, PROPS, CARTS and WORLD (walls block it). The host allows
`max_distance` + 0.75 m (network delay), measured from the player's eyes to the Interactable's parent.
What pressing **use** does, in order: (1) use handlers by priority (e.g. holding a glowing gem → eat it;
holding a normal prop → drop it; looking at a prop → grab it); (2) otherwise, if the target has an
`Interactable`, request a use from the host.

## EventBus
- Emits: `use_denied(player_id)` (NEW 2026-10-30), on the PC of the player who tried.

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
(`systems/interaction/test/interaction_test.tscn`; the lamp changes colour when the host accepts a use,
and the prompt and hold bar are drawn by the test scene until the HUD exists. Launch options `-- host`,
`-- join`, `port=7790`.)
GUT tests: `test_target_found_by_ray`, `test_out_of_range_rejected_on_host`, `test_hold_requires_full_time`,
`test_use_condition_blocks`, `test_handler_priority_order`, `test_prompt_provider_overrides_text`.
NEW 2026-10-17: `test_controller_added_to_every_body`, `test_press_fires_used_on_host_with_player_id`,
`test_client_use_goes_through_the_host` (real ENet, two "PCs").

## Acceptance criteria
- [x] Looking at a button shows its prompt; pressing E makes the host emit `used` with the right player id. *(GUT; test scene)*
- [x] A client's use works through the host; too-far uses are refused. *(GUT, two PCs over ENet)*
- [x] physics_props and upgrades can plug in without editing this system. *(use handlers and prompt providers, tested)*

## Open design questions
- DEFAULT: holding a non-upgrade prop and pressing use **drops** it (Half-Life 2 style); `drop` (Q) always drops.

## Changelog
- 2026-10-07: spec created.
- 2026-10-17: built. Added the `Interaction` autoload, `press_use`, `request_use`,
  `unregister_prompt_provider`, `Interactable.get_anchor`/`allows`.
- 2026-10-30 (HL2 feel step 4.1): (1) The "can't use" buzz: pressing use when nothing takes it (a wall,
  nothing, something out of reach or switched off) emits NEW `EventBus.use_denied` on your PC, and so does
  the host turning a use down (it sends NEW `_denied_rpc` to that player's PC and emits NEW
  `Interactable.refused` on the host). Audio plays it; at most once per `deny_cooldown`. `press_use` now
  returns true for hold-to-use and continuous objects (the held key does the work) instead of false.
  (2) Continuous use: NEW `Interactable.continuous`; holding E sends NEW `_continuous_rpc` to the host,
  which fires `use_started`, `use_tick` every physics step while you're in reach and allowed, then
  `use_stopped`. (3) NEW `Interactable.use_point`: reach (prompt and host check) is measured to it.
  (4) A fatter aim check: if the thin look ray finds nothing usable, a ball of `aim_assist_radius` is swept
  along the same line, stopping at the wall the ray hit, and only counts if no wall is in between.
  NEW tuning section `Config.feel.interaction` (UseTuning). 6 new GUT tests.

## HANDOFF
**Done:** `Interactable`, `InteractionController` (look ray, prompt, hold-to-use, use handlers and prompt
providers by priority, host-checked use requests with the player id), the `Interaction` autoload that
gives every body a controller, the test scene, 9 GUT tests (all pass). Checked with 2 local windows.

**Not done / stubbed:** the on-screen "Press E to ..." prompt and hold ring belong to ui's HUD (the
test scene draws its own for now). The drop key (Q) is physics_props' to handle.

**Should switch over to Interactables later (not changed now, they belong to other systems):**
- break_room: the elevator start button, "Start anyway" button, jacket closet and mirror use a
  "stand next to it and press E" stub. Give each an `Interactable` (on the INTERACTABLES layer) and
  connect `used`; the host-side checks they do now can move into `use_condition`.
- voice: the voice test room's door is opened with E by distance. It should become an Interactable
  (the real doors system will own doors anyway).

**For physics_props (next):** get `Interaction.get_local_controller()` when the local body spawns and
register a use handler (grab/drop) and a prompt provider ("Grab box"). Props are hit by the look ray
(PROPS layer), so the target is the prop's body.
