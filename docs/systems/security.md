# security

Folder: `res://systems/security/` · Autoload: `Security` · Size: M · Floor generation step 4e (NEW 2026-11-10)

## Purpose
The security room in each floor's welcome center: a **map table** that shows the floor from above (where every
player is, which wings hold broken lift parts) and **camera monitors** that show the floor's security cameras.
The floor generator (level_gen) decides **which cameras** work (`FloorLayout.cameras`, plan step 9); this
system **builds and runs** the table and the monitors. Plan: `docs/design/floor-generation-plan.md`, section 7.

**Not responsible for:** picking cameras (level_gen, `Config.floor_gen` V11), where parts are (level_gen and
cargo_lift), the security room's walls and furniture (the welcome center tiles).

## Public API
```gdscript
# Autoload Security (SecurityService)
func get_map_table() -> SecurityMapTable           # this floor's table, or null
func get_monitors() -> Array[SecurityMonitor]      # this floor's monitors, in marker order
func is_anyone_near() -> bool                       # the local player is within feed_active_radius of the table
func part_highlight_rooms() -> Array[int]           # placements to blink: each broken part's wing (or tile) now
func player_dots() -> Array[Dictionary]             # {"cells": Vector2, "color": Color} per player

class_name SecurityMapTable extends Node3D          # on the security_map marker
func show_layout(layout: FloorLayout, accent: Color) -> void
func refresh(highlighted: Array[int], dots: Array[Dictionary], delta: float) -> void
func lean_in() -> void                              # local: lean over the map
func lean_out() -> void                             # local: stand back up
func is_leaning() -> bool
func get_overlay() -> SecurityMapOverlay
func get_interactable() -> Interactable

class_name SecurityMapOverlay extends Control       # blinking wings, player dots, scan line (on the map)

class_name SecurityMonitor extends WorldDevice      # world_io device: inputs next, prev; output changed
var cameras: Array[Array]                           # FloorLayout.cameras: [marker key, label, broken]
var start_index: int
func get_camera_index() -> int
func get_camera_label() -> String
func is_showing_static() -> bool
func is_feed_active() -> bool
func set_feed_active(active: bool) -> void
func render_once() -> void
```

## How it works
- On `Level.floor_built` (every PC, while the lift rides) on a generated floor: a `SecurityMapTable` named
  `MapTable` under the `security_map` marker, and under each of the first `security_monitors` `security_monitor`
  markers a `SecurityMonitor` named `Monitor` (its screen faces +Z) with `WorldButton`s `Prev` and `Next`
  wired to it. The same names on every PC, so the monitors' state reaches everyone (world_io).
- **Map table** (Zachary: "go with your suggestions"): the floor plan drawn once by a `FloorMapView` in the
  "security" style (dark screen, rooms outlined in the department's `accent_color`, small room names, the
  elevator, locked and blocked doors, no key spots), in a `SubViewport` shown on the table top. On top, a
  `SecurityMapOverlay` draws the wings (or, outside the wings, the tiles) where broken lift parts are now,
  shaded and blinking (`map_blink_seconds`), each player as a dot in their colour (`map_player_colors`, by join
  order), and a slow scan line (`map_scan_seconds`). A part carried into another wing moves its blink; a part
  slotted into the lift stops it. **E** on the table leans you over it: the view eases down onto the map
  (`map_lean_seconds`, `map_lean_height`); **E** or a movement key stands back up. The host tells only that
  player's PC to lean in; nothing else about the map crosses the network.
- **Monitors:** each shows one camera of `FloorLayout.cameras`: a `Camera3D` in a `feed_resolution` `SubViewport`,
  hung at the camera marker and looking at the middle of its room, through a security-footage shader (grain,
  scan lines, tint) with the camera's label and the time; a broken camera shows static. Prev and Next step
  through the cameras; which one a monitor shows is host state, sent like a door's.
- **Cheap:** nothing redraws unless the **local** player is within `feed_active_radius` of the table: then the
  map refreshes `map_updates_per_second` and the feeds `feed_updates_per_second` times a second (each
  `SubViewport` is set to "update once"). Every PC draws its own pictures.

## Multiplayer
Host: the Interactables (table, buttons) and the monitors' camera choice. Every PC: building, drawing and the
feeds. One RPC: host -> the leaning player's PC ("lean in").

## Dependencies and stubs
level_gen (`Level.floor_built`, `get_layout`, `get_markers`, `get_marker_by_key`, `get_room_nodes`,
`get_room_index_for_position`, `get_floor_transform`, `FloorMapView`), world_io (`WorldDevice`, `WorldButton`),
cargo_lift (`CargoLift.current()`, `get_broken_slots`, `get_slot_part`), physics_props (`Props.get_props`),
player (`PlayerCharacter`), net_core (`Net.get_player_ids`, `get_peer_id`), interaction (`Interactable`).
No stubs.

## Test scene and GUT tests
`systems/security/test/security_test.tscn` (F6): a floor-6 Robotics floor with the lift and its parts; you start
in the security room. GUT `tests/unit/security/test_security.gd`: cameras picked by the rules, the same on every
PC; the table and 4 monitors are built; part wings blink, follow a moved part and stop once it is delivered;
feeds only draw while someone is near; Prev and Next sync between two PCs (real ENet).

## Changelog
- 2026-11-10: created (floor generation step 4e).
