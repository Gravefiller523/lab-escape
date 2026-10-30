# debug_console

Folder: `res://systems/debug_console/` · Autoload: `DebugConsole` · Size: S · Phase 1a (early, it speeds up all testing)

## Purpose
An in-game console (open with the `` ` `` key) for testing: spawn any content by id, give mutations,
jump floors, turn on god mode. Other systems register their own commands, so the console never needs
editing when content or systems are added.

**Not responsible for:** the cheats' effects (each system implements its own command).

## Public API
```gdscript
## handler: func(args: PackedStringArray, player_id: int) -> String   (returns text to print)
func register_command(name: StringName, handler: Callable, help: String, host_only: bool = true) -> void
## handler: func(id: StringName, at: Transform3D, count: int, player_id: int) -> String
func register_spawner(type_key: StringName, handler: Callable) -> void
func run(command_line: String) -> String
func cheats_allowed() -> bool        # editor builds, CHANGED 2026-10-18: or exports with the custom feature "cheats", or Config.game.cheats_in_release
func print_line(text: String) -> void
func is_open() -> bool
func set_open(open: bool) -> void   # NEW 2026-10-18: opens/closes the window (the ` key does this)
static func spread(at: Transform3D, index: int) -> Transform3D   # NEW: lays out the index-th of several spawns in a grid
func use_test_setup(net: NetService, config: GameConfig, is_editor: bool) -> void   # NEW: tests only
var last_remote_output: String   # NEW: the last output the host sent back (tests)
```

Built-in commands: `help`, `list <type>` (ids of a content type), `validate` (runs ContentValidator
and prints problems), `spawn <id> [count]` (finds the type from the id prefix, calls that type's
spawner at the point you are looking at), `seed`, `net` (roster and ping), `fps`, `clear`.

Commands other systems register (listed in their specs): `give <upgrade_id> [player]`,
`item <item_id>`, `gems <amount>`, `god`, `noclip`, `kill [player]`, `reprint [player]`,
`floor <n> [department_id]`, `unlock_cosmetics`, `wipe`, `boss`, `lift_ready`.

Spawners registered by type: prop (physics_props), item (items), enemy (enemies), boss (bosses),
mutation and cybernetic (upgrades: spawns a glowing gem or robot part holding it), task (objectives).
A new content type that should be spawnable registers its own spawner.

## EventBus
None.

## Data it owns and saves
Command history in `user://console_history.txt` (local, optional).

## Adding content
None. New content is spawnable at once through its type's spawner.

## Multiplayer
- Any player can open the console. `host_only` commands typed by a client are sent to the host,
  which runs them only if the host has cheats allowed; output is sent back to the typer.
- Spawning always happens on the host through the owning system's API.

## Dependencies and stubs
net_core (host check and sending commands). Works in solo with no other system present.

## Test scene and GUT tests
GUT tests: `test_register_and_run_command`, `test_unknown_command_message`, `test_spawn_routes_by_prefix`
(CHANGED: fake spawner for `prop`, since no mutation content exists yet), `test_client_host_only_command_goes_to_host`, `test_cheats_blocked_in_release_by_default`.
NEW extra tests: `test_spawn_without_spawner_says_so`, `test_spread_lays_things_out_apart`, `test_validate_matches_content_test`,
`test_list_shows_ids`, and `tests/integration/test_console_spawns_props.gd` (real console + real props).
Test scene: `systems/debug_console/test/console_test.tscn` (floor, player, PropSpawner, a `hello` test cheat; launch options `host`, `join`, `port=`).

## Acceptance criteria
- [x] `spawn <any id>` works for every type with a registered spawner, with no console code per content.
- [x] `validate` prints the same problems as the GUT content test.
- [x] Cheats can't run in a release build unless the config allows it.

## Open design questions
- DEFAULT: in multiplayer only the host's cheat setting matters.
- DEFAULT: `seed` is a stub that says there is no run until game_flow exists; game_flow should replace it
  (register_command(&"seed", ...) again overwrites the built-in).
- DEFAULT: `net` shows ping only in local (ENet) mode; Steam ping can be added with steam_session later.

## Changelog
- 2026-10-07: spec created.
- 2026-10-18: built. NEW: `set_open`, `spread`, `use_test_setup`, `last_remote_output`. CHANGED: the spawn test
  uses a fake `prop` spawner. physics_props registers the `prop` spawner.
- 2026-10-18: CHANGED: test builds exported with the custom feature `cheats` (the "Windows Steam test"
  preset in export_presets.cfg) allow cheats, so console cheats work on the 2-PC Steam test. Release presets
  must not have this feature.
- 2026-10-29 (feel step 0): NEW commands (cheats only, run on this PC): `tune` (list sections), `tune <section>` (list numbers), `tune <section>.<name> [value]` (show or change one now), `tune_save` (editor only: write them into the .tres files), `tune_reset` (reload from the files). Code in `systems/debug_console/tune_commands.gd` (`TuneCommands`). Player numbers change your own PC; props and enemies run on the host, so tune those there.
- 2026-10-30 (HL2 feel step 4.1): `tune` has a fourth section, `interaction` (aiming help and the "can't use" buzz).

## HANDOFF
**Built (2026-10-18):** `systems/debug_console/debug_console.gd` (`DebugConsoleService`, autoload `DebugConsole`,
a CanvasLayer on layer 20). Press `` ` `` to open/close, Esc closes, Up/Down go through history
(saved in `user://console_history.txt`). While open, the local player's input is turned off.

**How it works:** commands live in a dictionary (name -> handler, help, host_only). `host_only` means "cheat":
on a client it is sent to the host (`_run_on_host` RPC), which checks the host's `cheats_allowed()`, runs it as
the sending player and sends the text back (`_print_remote`). `spawn <id> [count]` finds the type with
`ContentRegistry.type_key_for_id` and calls that type's registered spawner at the point the player looks at
(ray from the aim, lifted 0.5 m), count 1–100.

**Foundation / project.godot changes:** autoload line `DebugConsole` added last (after Props). No core changes.

**Other system touched (with this branch):** physics_props `props.gd` registers the `prop` spawner (deferred,
in `_ready`).

**Stubs:** `seed` (no runs yet). No other spawners exist yet: items, enemies, bosses, upgrades and objectives
register theirs when they are built.

**For other systems:** register cheats in your autoload's `_ready` with
`DebugConsole.register_command(&"god", _cmd_god, "god: can't take damage")` (handler
`func(args: PackedStringArray, player_id: int) -> String`). It runs on the host for the player who typed it.
Spawnable content types call `DebugConsole.register_spawner(&"<type>", handler)` and can use
`DebugConsoleService.spread(at, index)` for several at once.
