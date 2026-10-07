# break_room

Folder: `res://systems/break_room/` · Size: S · Phase 1a (grey box), Phase 2 (art, closet)

## Purpose
The Break Room **is the lobby**: a small, fixed (not generated) 3D room where players arrive after
hosting or joining, walk around, test their voice, change outfits at the jacket closet, and step into
the elevator to start a run. Everyone returns here after a run ends.

**Not responsible for:** lobby networking (steam_session, net_core), cosmetic logic (cosmetics), the run (game_flow), the "who's inside" check (cargo_lift's ElevatorZone).

## Public API
```gdscript
class_name BreakRoom extends Node3D           # scene: systems/break_room/break_room.tscn (owned by this system)
func get_spawn_points() -> Array[Node3D]      # at least Config.game.max_players points; extra points are generated in a ring if max_players grows
func get_elevator_zone() -> ElevatorZone
func can_force_start() -> bool                # host: AFK timer passed
func request_start() -> void                  # local; the elevator button calls it
func request_force_start() -> void            # host only button, appears after Config.game.afk_force_start_after seconds
```
Contents of the scene: spawn points, elevator (ElevatorZone + button + doors), jacket closet
(Interactable that opens the cosmetics screen), a mirror with voice loopback (voice test), a
"who's missing" sign by the elevator, a whiteboard showing the last run summary.

## EventBus
- Emits: `elevator_start_accepted` (all).
- Listens: `player_joined` (host: spawn them), `run_ended` (show summary on the whiteboard), `cosmetics_changed`.

## Data it owns and saves
The Break Room scene. Saves nothing.

## Adding content
Decorations are scene edits by the break_room owner. Cosmetics come from cosmetics. No content type.

## Multiplayer
- Host spawns players at spawn points (via `PlayerSpawner`). Joining is open while here (game_flow sets it).
- Start: a press sends a request; the host checks `ElevatorZone.contains_all_players()`; if someone is
  missing it shows their names; if all are in, it closes the doors and emits `elevator_start_accepted`.
- AFK: after `afk_force_start_after` seconds with at least one player in the elevator, the host sees
  "Start anyway". Players left outside are moved into the elevator (teleported) at start.

## Dependencies and stubs
cargo_lift (ElevatorZone; stub: an Area3D counting players), cosmetics (closet; stub: a toast), player (spawner).

## Test scene and GUT tests
The Break Room scene itself is the test scene (run with 2 to 4 local instances).
GUT tests: `test_enough_spawn_points_for_max_players` (set 8), `test_start_refused_if_someone_outside`,
`test_start_accepted_when_all_inside`, `test_force_start_only_after_timer_and_only_host`.

## Acceptance criteria
- [ ] Phase 1a: 2+ players on Steam join into the grey-box Break Room and walk around together.
- [ ] Elevator only starts when everyone is inside; force start works after the timer.
- [ ] Returning after a run puts everyone back here.

## Open design questions
- DEFAULT: the host gets "Start anyway" after 60 s (config).
- DEFAULT: Break Room has no enemies or physics props except a few fun ones (a ball, a chair) for testing grabs.

## Changelog
- 2026-10-07: spec created.
