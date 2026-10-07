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
class_name ElevatorZone extends Area3D
signal occupants_changed()
func get_players_inside() -> Array[int]
func get_missing_players() -> Array[int]      # living, connected players not inside
func contains_all_players() -> bool
func get_props_inside() -> Array[NetProp]     # includes carts (contents ride with them)

class_name CargoLift extends Node3D           # scene: systems/cargo_lift/cargo_lift.tscn
signal parts_changed(delivered: int, needed: int)
func get_parts_needed() -> int                # DepartmentData.lift_parts_per_floor
func get_parts_delivered() -> int
func is_ready() -> bool
func request_depart() -> void                 # local; the button's Interactable calls it
func get_zone() -> ElevatorZone
```
Lift parts are props tagged `lift_part` (is_key_object = true). Dropping one into the lift's part
socket (an Area3D) installs it: the prop is despawned and the count goes up.

**Carry-over:** when it departs, the host records every prop inside the zone (`content_id`, transform
relative to the lift, `extra`, and cart contents) and, after the next floor is built, respawns them in
the new floor's lift. Players are teleported to matching spots. Dead players come along as ghosts.

## EventBus
- Emits: `lift_part_delivered`, `lift_ready`, `lift_departed` (all).
- Listens: `floor_ready` (host: spawn the lift at `Level.get_markers(&"lift")`, respawn carried props, spawn lift parts at `lift_part` markers).

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
GUT tests: `test_part_in_socket_counts`, `test_not_ready_without_all_parts`, `test_depart_needs_all_living_players`,
`test_dead_players_not_required`, `test_props_and_cart_contents_carried_over`, `test_parts_needed_from_department`.

## Acceptance criteria
- [ ] Collect parts, all board, press button, arrive on the next floor with the cart and its gems.
- [ ] The button refuses (with the missing names) if someone is outside.

## Open design questions
- DEFAULT: 3 parts per floor (data); some may come from co-op tasks.
- DEFAULT: props left behind on a floor are lost.

## Changelog
- 2026-10-07: spec created.
