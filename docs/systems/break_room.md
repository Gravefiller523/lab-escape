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
func get_elevator_zone() -> ElevatorZone      # CHANGED 2026-10-17: returns ElevatorZoneStub until cargo_lift exists
func can_force_start() -> bool                # host: AFK timer passed
func request_start() -> void                  # local; the elevator button calls it
func request_force_start() -> void            # host only button, appears after Config.game.afk_force_start_after seconds
func use_net(net: NetService, config: GameConfig) -> void   # NEW 2026-10-17: tests only
func get_prop_spawner() -> PropSpawner      # NEW 2026-10-18: the room's props (fun props + console spawns)
```
CHANGED 2026-10-18: the start button, "Start anyway", the jacket closet and the mirror are Interactables
(interaction system): look at one and press E. `request_start()` still works for code that wants it.
NEW 2026-10-17: the AFK timer counts from when the first player stepped into the elevator (it
resets when the elevator is empty again).
Contents of the scene: spawn points, elevator (ElevatorZone + button + doors), jacket closet
(Interactable that opens the cosmetics screen), a mirror with voice loopback (voice test), a
"who's missing" sign by the elevator, a whiteboard showing the last run summary.

## EventBus
- Emits: `elevator_start_accepted` (all).
- Listens: `player_joined` (host: spawn them), `run_ended` (show summary on the whiteboard), `cosmetics_changed`.
  CHANGED 2026-10-17: spawning on `player_joined` is done by the scene's `PlayerSpawner` (player system),
  not by break_room code. `cosmetics_changed` isn't used yet (no cosmetics).

## Data it owns and saves
The Break Room scene. Saves nothing.

## Adding content
Decorations are scene edits by the break_room owner. Cosmetics come from cosmetics. No content type.

## Multiplayer
- Host spawns players at spawn points (via `PlayerSpawner`). Joining is open while here (game_flow sets it).
  CHANGED 2026-10-17: joining is open during runs too (mid-run joining); nothing to do here.
- Start: a press sends a request; the host checks `ElevatorZone.contains_all_players()`; if someone is
  missing it shows their names; if all are in, it closes the doors and emits `elevator_start_accepted`.
- AFK: after `afk_force_start_after` seconds with at least one player in the elevator, the host sees
  "Start anyway". Players left outside are moved into the elevator (teleported) at start.

## Dependencies and stubs
cargo_lift (ElevatorZone; stub: an Area3D counting players), cosmetics (closet; stub: a toast), player (spawner),
interaction (Interactable, NEW 2026-10-18).

## Test scene and GUT tests
The Break Room scene itself is the test scene (run with 2 to 4 local instances).
CHANGED 2026-10-17: because there's no main menu yet, the test scene is
`systems/break_room/test/break_room_test.tscn`: the Break Room plus Host local / Join local /
Host (Steam) / Invite / Leave / "End run (stub)" buttons, a toast line, an overview camera while you
have no body, and launch options `-- host`, `-- join`, `port=7790`.
GUT tests (`tests/unit/break_room/test_break_room.gd`): `test_enough_spawn_points_for_max_players` (set 8, and 12),
`test_start_refused_if_someone_outside`, `test_start_accepted_when_all_inside`,
`test_force_start_only_after_timer_and_only_host`, NEW `test_solo_player_spawns_in_the_room`.

## Acceptance criteria
- [ ] Phase 1a: 2+ players on Steam join into the grey-box Break Room and walk around together.
  *Done with 2 local windows (2026-10-17). Real Steam on 2 PCs still to do.*
- [x] Elevator only starts when everyone is inside; force start works after the timer. *(GUT tests)*
- [ ] Returning after a run puts everyone back here. *Needs game_flow.*

## Open design questions
- DEFAULT: the host gets "Start anyway" after 60 s (config).
- DEFAULT: Break Room has no enemies or physics props except a few fun ones (a ball, a chair) for testing grabs.

## Changelog
- 2026-10-07: spec created.
- 2026-10-17: Phase 1a grey box built. `get_elevator_zone()` returns `ElevatorZoneStub` for now;
  added the test-only `use_net`; separate test scene with Host/Join buttons.
- 2026-10-18: switched to the interaction system. The stand-near areas (`StartButtonArea`, `ForceButtonArea`,
  `ClosetArea`, `MirrorArea`) are gone; each thing has a `StaticBody3D` with an `Interactable` (`%StartUse`,
  `%ForceUse`, `%ClosetUse`, `%MirrorUse`). "Start anyway" can only be used by the host's own player and
  can't be looked at while hidden. Closet and mirror messages go to whoever used them. The test scene shows the
  "E: ..." prompt and a crosshair. Tests: NEW `test_only_the_host_can_use_start_anyway`,
  `test_closet_note_goes_to_whoever_used_it`; the two button tests now use the InteractionController.
- 2026-10-18: fix (found in the 2-PC Steam test): the room had no PropSpawner, so `spawn prop_...` failed.
  The room now makes one (`Props` child; NEW `get_prop_spawner()`), and the host spawns a few props to play
  with, one per Marker3D under `%FunProps` (its `prop_id` metadata says which). Test: `test_room_has_props_to_play_with`.
- 2026-10-18: fix (Steam test): props slid through the closing elevator doors. The doors are now
  AnimatableBody3Ds (moving physics bodies) moved in physics steps, so they push props. Test: `test_closed_doors_stop_props`.
- 2026-10-18 (game_flow branch): "Elevator starting!" no longer says game_flow is missing; the doors reopen only
  matter in the room's own test scene (in the game, game_flow takes everyone to the first floor).

## HANDOFF
**Done (Phase 1a grey box):** `break_room.tscn`: floor, walls, a table, 8 spawn points (more are
added in a ring if `max_players` is bigger), an elevator with sliding doors, a green start button,
a "Not in the elevator: ..." sign, a red host-only "Start anyway" button that appears after
`afk_force_start_after` seconds, placeholders for the jacket closet, the mirror and the whiteboard
(shows the last run's result on `run_ended`). Start requests go to the host, which checks the zone
and emits `elevator_start_accepted` on every PC; "Start anyway" teleports outside players into the
elevator first. 5 GUT tests, all pass. Checked with 2 local windows.

**Layout change (2026-10-17, after Zachary's test):** the green start button and the red "Start
anyway" button are on the elevator's inside walls (right and left), so players standing inside can
press them, and the "who's missing" sign has a copy on the elevator's back wall. Tests:
`test_start_button_is_inside_the_elevator`, `test_start_anyway_button_is_inside_the_elevator`.

**Stubbed:**
- ~~interaction~~ DONE 2026-10-18: look at a button and press E (Interactables).
- ui HUD: the "E: ..." prompt and crosshair only show in the test scene until the HUD exists.
- cargo_lift: `ElevatorZoneStub` (`stubs/elevator_zone_stub.gd`) has the same functions as
  `ElevatorZone` minus props. Swap the scene's ElevatorZone node for the real one.
- game_flow: after a start is accepted, the doors reopen after 4 seconds instead of a run starting.
- cosmetics / voice: the closet and mirror only show a message.
- ui: toasts are shown by the test scene.

**Known limits:** walls only, no ceiling or real art; grey-box sizes may change. Not tested on real Steam yet.

**For the next systems:**
- **ui (main menu, next):** after Host/Join, load `break_room.tscn` as the scene. The `PlayerSpawner`
  inside spawns everyone automatically.
- **game_flow:** listen to `elevator_start_accepted` and start the run; when it ends, load the Break Room again.
- **cargo_lift:** replace the ElevatorZone node in `break_room.tscn` (break_room owns the scene, so ask).
