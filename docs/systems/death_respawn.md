# death_respawn

Folder: `res://systems/death_respawn/` · Autoload: `Death` · Size: M · Phase 1b

## Purpose
What happens when a player dies and how they come back. On death everything they carry drops where
they died, and they become a ghost that can watch teammates. Teammates bring **meat** (dropped by
monsters) to a **3D printer** to reprint them. Reprinted players keep their mutations and cybernetics,
not their items. If everyone is dead at once, the team is wiped and the run ends.

**Not responsible for:** health (damage), meat drops (loot), spawning printers' positions (level_gen markers), ending the run (game_flow listens to `team_wiped`).

## Public API
```gdscript
# Autoload Death
func is_dead(player_id: int) -> bool
func get_dead_players() -> Array[int]           # in order of death
func get_reprint_cost() -> int                  # meat needed for the next reprint this floor
func get_free_reprints_left() -> int            # solo only
func kill(player_id: int, info: DamageInfo = null) -> void    # host (cheats, kill zones)
func reprint(player_id: int, xform: Transform3D) -> void      # host

class_name Printer3D extends Node3D             # scene: systems/death_respawn/printer_3d.tscn
signal meat_changed(inserted: int, needed: int)
func get_meat_inserted() -> int
func can_print() -> bool
func request_print() -> void                    # local; the print button's Interactable calls it
```
Meat is a prop (`prop_meat`), identified by the `meat` tag on its PropData. Dropping meat into the
printer's hopper (an Area3D) inserts it; extra meat stays inserted for the next reprint.

## EventBus
- Emits: `player_died`, `player_reprinted`, `team_wiped`.
- Listens: `HealthComponent.died` on each player (host), `player_left` (drop their items),
  `floor_ready` (host: spawn printers at `Level.get_markers(&"printer")`; reset solo free reprints and cost growth),
  `floor_loading` (dead players come along as ghosts and stay dead).

## Data it owns and saves
Numbers from `Config.game`: `meat_per_reprint`, `meat_cost_growth_per_reprint`,
`solo_free_reprints_per_floor`, `reprint_min_wait`. Marks `is_alive` in PlayerRecord. Saves nothing.

## Adding content
New printer looks: new scenes using `Printer3D`. Different meats: props tagged `meat`. No code.

## Multiplayer
- Host decides death: takes all inventory items (`InventoryComponent.take_all`) and spawns them as
  pickups (`Props.spawn_item`) in a small spread; releases any held prop; marks the record; tells all PCs.
- Ghost: the dead player's body is hidden and its collision is off; their camera follows a living
  teammate (cycle with PRIMARY/SECONDARY). Ghosts can still talk (voice keeps working).
- Reprint: host checks meat and the wait time, picks the player dead longest, `PlayerCharacter.teleport`
  to the printer's output, `HealthComponent.revive`, then upgrades re-applies (via `player_spawned`).
- **Solo:** if the only player dies and has free reprints left this floor, they are reprinted at the
  nearest printer after a short delay. Otherwise the run ends.
- Team wipe: all living players dead at the same moment → `team_wiped` (host decides, sends to all).

## Dependencies and stubs
damage, inventory, physics_props, player, net_core. Stub printer: a box with an Area3D and a button.

## Test scene and GUT tests
Test scene: two players, a crowbar each, a pile of meat, a printer, a kill button.
GUT tests: `test_death_drops_all_items`, `test_death_releases_held_prop`, `test_printer_needs_meat`,
`test_reprint_keeps_upgrades_not_items`, `test_cost_grows_if_configured`, `test_solo_free_reprint_then_run_ends`,
`test_all_dead_emits_team_wiped_once`, `test_disconnect_drops_items`.

## Acceptance criteria
- [ ] Dying drops every item; teammates can pick them up.
- [ ] Meat in the printer reprints the dead player with their mutations intact, on 2 PCs.
- [ ] Team wipe ends the run; solo gets one free reprint per floor (from config).

## Open design questions
- DEFAULT: reprint costs 1 meat, no growth (both config numbers).
- DEFAULT: solo gets 1 free reprint per floor.
- DEFAULT: printers come from markers; level_gen places at least one per floor, near the start room.
- DEFAULT: a dead player's lift part or keycard drops like any prop (key objects are safe-respawned only if they fall out of the world).
- Should ghosts be able to do anything (e.g. haunt enemies)? DEFAULT: watch and talk only.

## Changelog
- 2026-10-07: spec created.
