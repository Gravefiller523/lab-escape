# cargo_lift

Folder: `res://systems/cargo_lift/` · Size: M · Phase 1b

## Purpose
The cargo lift that carries the team up through the facility. Each floor's lift needs a number of
**lift parts** (props found on the floor or earned from tasks). When it has them all and every living
player is aboard, someone presses the button and it goes up, carrying players, carts and any props
inside to the next floor. Also provides the **ElevatorZone** ("who's inside?") used by the Break Room elevator.

**Not responsible for:** loading the next floor (game_flow), where lift parts spawn (level_gen markers + loot/objectives rewards), the Break Room scene (break_room).

## Public API
```gdscript
# CHANGED 2026-10-19: built to Zachary's design; this is the real API (see the Changelog).
class_name ElevatorZone extends Area3D
signal occupants_changed()
func get_players_inside() -> Array[int]
func get_missing_players() -> Array[int]      # living, connected players not inside
func contains_all_players() -> bool
func get_props_inside() -> Array[NetProp]     # includes carts (contents ride with them)
func use_net(net: NetService) -> void         # NEW: tests only

class_name CargoLift extends Node3D           # scene: systems/cargo_lift/cargo_lift.tscn
signal parts_changed(delivered: int, needed: int)
signal state_changed()                         # NEW: broken / riding / doors changed
static func current() -> CargoLift             # NEW: the lift in the game (null if none)
func get_parts_needed() -> int                # DepartmentData.lift_parts_per_floor
func get_parts_delivered() -> int
func is_ready() -> bool
func is_broken() -> bool                       # NEW
func is_riding() -> bool                       # NEW
func is_in_break_room() -> bool                # NEW
func request_depart() -> void                 # local; the Go button calls it (the host checks)
func depart_blocker() -> String               # NEW, host: why Go won't work now, or ""
func get_zone() -> ElevatorZone
func get_spawn_points() -> Array[Node3D]      # NEW: 8 spots inside (players arrive here on floors)
func arrive(parts_needed: int, in_break_room: bool, waiting_for_boss: bool = false) -> void  # NEW, host (game_flow)
func depart_now() -> void                     # NEW, host (game_flow): ride without Go (back after a run)
func gather_players() -> void                 # NEW, host: bring everyone outside into the lift
func can_force_start() -> bool                # NEW, host: Break Room "Start anyway" allowed
func use_net(net: NetService, config: GameConfig) -> void   # NEW: tests only
const MSG_BROKEN, MSG_WAITING, MSG_BOSS, INSIDE, WALL, LIFT_PART_TAG
```
NEW 2026-10-19, the design (Zachary): the cargo lift IS the elevator. You board it in the Break Room;
it rides up one floor and arrives broken. Players find the part (spawned at the floor's `lift_part`
marker farthest from the lift), carry it back and **slot it into the socket** on the lift's back wall
(only props tagged `lift_part`; the part is used up). Go only works when it's fixed and **everyone is
inside** (it says who's missing). Everything inside rides along: the lift never unloads (game_flow
loads the levels around it), so players, props and carts stay exactly where they were. While it rides
the lift stands still and the shaft walls with light strips slide down past it (`lift_ride_speed`); the
ride lasts at least `lift_ride_seconds` (8), longer if a PC is still building the floor; then it stops
and the gate opens. A boss floor: it arrives "waiting for the boss"; beating the boss fixes it. In the
Break Room it isn't broken: Go starts the run, and after `afk_force_start_after` seconds with someone
inside, the host gets "Start anyway" (players outside are brought in). Props left outside are lost.
The lift: an open cargo cage 5 x 5 m inside, 3.4 m tall: floor, back wall with the panel (status,
socket, Go), side railings with invisible walls (nobody falls out), roof, sliding gate on the -z side.
Lift parts are props tagged `lift_part` (is_key_object = true). Dropping one into the lift's part
socket (an Area3D) installs it: the prop is despawned and the count goes up.
CHANGED 2026-10-19: the carry-over below is not needed: the lift never unloads (see above).

**Carry-over:** when it departs, the host records every prop inside the zone (`content_id`, transform
relative to the lift, `extra`, and cart contents) and, after the next floor is built, respawns them in
the new floor's lift. Players are teleported to matching spots. Dead players come along as ghosts.

## EventBus
- Emits: `lift_part_delivered`, `lift_ready`, `lift_departed` (all).
- Listens: `floor_ready` (host: spawn the lift at `Level.get_markers(&"lift")`, respawn carried props, spawn lift parts at `lift_part` markers).
  CHANGED 2026-10-19: on `floor_ready` the host spawns the lift parts (`DepartmentData.lift_part_prop_id`) at
  the `lift_part` markers farthest from the lift; the lift itself is in game_flow's game world. Also listens
  to `boss_defeated` (fixes it) and `player_joined` (host sends a joiner the lift's state).

## Data it owns and saves
Uses `DepartmentData.lift_parts_per_floor` and lift-part `PropData`. Saves nothing.

## Adding content
Department-themed lift parts are props tagged `lift_part`. New lift looks are new scenes using `CargoLift`. No code.

## Multiplayer
Host counts parts, checks the zone and decides departure. Part count and lift state are synced.
Clients' `request_depart` is checked on the host (`is_ready()` and `contains_all_players()`).

## Dependencies and stubs
physics_props (part detection, carry-over spawning), level_gen markers (stub: one hand-placed lift),
interaction (button). Debug: `lift_ready` cheat.

## Test scene and GUT tests
Test scene: a grey-box room with the lift, 3 lift parts, a cart with gems, 2 local players.
DONE 2026-10-19: `test/lift_test.tscn` (the game world with a generated floor; it plays game_flow's part:
new floor during each ride). No carts or gems yet.
GUT tests: `test_part_in_socket_counts`, `test_not_ready_without_all_parts`, `test_depart_needs_all_living_players`,
`test_dead_players_not_required`, `test_props_and_cart_contents_carried_over`, `test_parts_needed_from_department`.
DONE 2026-10-19 (`tests/unit/cargo_lift/test_cargo_lift.gd`): `test_part_in_socket_counts`,
`test_crates_dont_count_as_parts`, `test_depart_needs_all_players`, `test_go_departs_and_every_pc_sees_it`,
`test_props_inside_are_found`, `test_boss_floor_waits_for_the_boss`, `test_force_start_after_the_timer`.
Not yet: dead players (needs death_respawn), carts (needs carts).

## Acceptance criteria
- [ ] Collect parts, all board, press button, arrive on the next floor with the cart and its gems.
  *Parts, boarding, Go and a crate riding along work (2 game copies, 2026-10-19). Carts and gems don't exist yet.*
- [x] The button refuses (with the missing names) if someone is outside. *(GUT)*

## Open design questions
- DEFAULT: 3 parts per floor (data); some may come from co-op tasks.
- DEFAULT: props left behind on a floor are lost.

## Changelog
- 2026-10-07: spec created.
- 2026-10-19: built to Zachary's design (the lift is the elevator, slot the part, wait for everyone, everything
  inside rides along, moving shaft, level loads during the ride). New GameConfig: `lift_ride_seconds`, `lift_ride_speed`.
  The `prop_lift_part_zoology` content file got the `lift_part` tag.

## HANDOFF
**Built (2026-10-19):** `CargoLift` (`cargo_lift.gd`, scene `cargo_lift.tscn`, geometry made in code with fixed
node names), `ElevatorZone`, the test scene and 7 GUT tests. game_flow's game world holds the one lift for the whole
run; the Break Room and the floors are loaded around it (lined up with it by their `lift` spot).

**How a floor goes:** arrive broken → part spawns far away (on `floor_ready`) → slot it → everyone in → Go →
`lift_departed` on every PC → game_flow swaps the level during the ride → `arrive()` (host) opens it, broken again.

**Foundation changes:** GameConfig `lift_ride_seconds` (8), `lift_ride_speed` (4). Content: `lift_part` tag on
`prop_lift_part_zoology`. No new EventBus signals (uses `lift_part_delivered`, `lift_ready`, `lift_departed`).

**Other systems touched (this branch):** game_flow (game world, levels around the lift), break_room ("floor 0":
its elevator moved onto the lift), level_gen (no per-floor scene; `room_lift_grey` just holds the lift), player
(host teleports aren't undone by the speed check).

**Not done yet:** the screen rumble while riding and the jolt on arrival (Zachary's suggestion 7; later), dead
players (death_respawn), carts (carts).
