# world_io

Folder: `res://systems/world_io/` · Size: M · NEW 2026-10-30 (HL2 feel step 4.2)

## Purpose
A small kit for wiring the world together without code, like Half-Life 2's inputs and outputs:
"when this button is pressed, open that door after half a second". Buttons, triggers, doors, relays,
counters and valves are **devices**. Each device has **outputs** (events such as `pressed` or `opened`)
and **inputs** (actions such as `open` or `lock`). A device's `outputs` list holds the wires.

**Not responsible for:** what the use key does (interaction), keycards and floor tasks (objectives, which
can build on `WorldDoor` and its `lock`/`unlock` inputs), level layout (level_gen).

## Public API
```gdscript
class_name IOConnection extends Resource        # one wire
@export var event: StringName                   # on this device, e.g. &"pressed"
@export var target: NodePath                    # the device to act on, relative to this one
@export var action: StringName                  # e.g. &"open"
@export var delay: float                        # seconds to wait first
@export var once: bool                          # only the first time

class_name WorldDevice extends Node3D           # base of every device
signal output_fired(event: StringName, activator_id: int)   # host
@export var outputs: Array[IOConnection]
@export var start_enabled: bool = true
func is_enabled() -> bool
func set_enabled(on: bool) -> void              # host
func receive(action: StringName, activator_id: int = 0) -> void   # host: do an input
func fire_output(event: StringName, activator_id: int = 0) -> void # host: run the wires for an event
func wire(event, target: WorldDevice, action, delay = 0.0, once = false) -> IOConnection  # wiring from code
func push_state() -> void                       # host: send its state to every PC
func get_inputs() -> PackedStringArray          # besides enable and disable
# For a new kind of device to override: _build(), get_inputs(), _on_input(action, activator_id),
# get_state() -> Array, _apply_state(state: Array), _apply_enabled().
```
`activator_id` is the player who set a chain off (0 = nobody). It travels along the wires, so a door
opened by a button swings away from whoever pressed the button.

| Device | What it is | Outputs | Inputs (plus enable, disable) |
|---|---|---|---|
| `WorldButton` | a wall button; press E (or hold `press_seconds`); pops back out after `reset_seconds` (0 = stays in) | pressed, released, denied (pressed while locked) | press, lock, unlock |
| `WorldTrigger` | an invisible box (`size`) that notices players, and optionally props or enemies | entered (first in), exited (last out) | none |
| `WorldDoor` | a hinged door; swings away from whoever opens it; goes back if it would hit a player or enemy; pushes props; `auto_close_seconds`; `usable` (E works); `one_way` | opening, opened, closing, closed, blocked, locked_use | open, close, toggle, lock, unlock |
| `WorldRelay` | passes a signal on (fan out, or switch a chain off in one place) | triggered | trigger |
| `WorldCounter` | counts to `goal` | changed, reached, left | add, subtract, reset |
| `WorldCrank` | a valve wheel turned by holding E (continuous use) for `turn_seconds`; turns back when let go (`rewind_seconds`); two players turn it twice as fast | started, completed, rewound | reset, lock, unlock |

Geometry: a door's node is its hinge and the door runs `width` along +X; buttons and valves face +Z.

## EventBus
None. The "can't use" buzz on a locked or disabled device comes from interaction (`use_denied`).

## Data it owns and saves
Nothing saved. Sounds come from `event_sounds.tres`: `button_press`, `door_move`, `door_shut`, `crank_turn`.

## Adding content
In a level scene: add a device node (e.g. a `WorldButton`), and in the Inspector add an `IOConnection` to
its `outputs`: pick the event, the target device, the action and a delay. No code. A new kind of device
is a new script that extends `WorldDevice`.

## Multiplayer
- Only the host runs wires and changes devices. Use requests come in through interaction, which checks
  reach and `use_condition` on the host.
- Each device sends its own state (`push_state` -> `_state_rpc`) to every PC when it changes. A PC that
  builds a device after joining asks the host for its state (`_request_state_rpc`). Node paths must
  match on every PC (they do: every PC builds the same level).
- Doors: the host moves the door and checks for people in the way; other PCs get the angle and where
  it's heading on every change and swing it themselves. Valves send their turn 10 times a second while it changes.
- Buttons, doors and valves play their sounds on every PC.

## Dependencies
interaction (Interactable, continuous use, use points, `refused`), physics layers, audio (Sound), voice
(`SoundDoor` in each doorway), player (`PlayerCharacter.find` for which way a door opens).

## Test scene and GUT tests
Test level: the door course in `systems/player/test/feel_playtest.tscn`.
GUT (`tests/unit/world_io/test_world_io.gd`): `test_a_wire_waits_its_delay_and_once_means_once`,
`test_pressing_a_wired_button_opens_the_door`, `test_a_door_swings_away_from_whoever_opens_it`,
`test_a_closing_door_goes_back_when_a_player_is_in_the_way`, `test_a_locked_door_buzzes_and_reports_the_try`,
`test_a_trigger_fires_when_a_player_walks_in_and_out`, `test_a_counter_reaches_its_goal_once`,
`test_a_disabled_device_ignores_inputs_until_enabled`, `test_a_valve_turns_while_held_and_turns_back_when_let_go`,
`test_other_pcs_see_doors_move_and_joiners_get_the_state` (real ENet, two "PCs").

## Not done yet
- Enemies: the navigation bake treats a door as a wall (shut, as it was when baked), so enemies don't
  path through doorways that have doors. Needs navigation links that switch with the door.
- Enemies can't open doors.
- level_gen doesn't place devices yet; objectives' keycard doors should be built on `WorldDoor`.

## Changelog
- 2026-10-30 (HL2 feel step 4.2): created. `IOConnection`, `WorldDevice`, `WorldButton`, `WorldTrigger`,
  `WorldDoor`, `WorldRelay`, `WorldCounter`, `WorldCrank`, and 10 GUT tests.
