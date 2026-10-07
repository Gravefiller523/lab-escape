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
func cheats_allowed() -> bool        # editor builds, or Config.game.cheats_in_release
func print_line(text: String) -> void
func is_open() -> bool
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
(fake spawner for `mutation`), `test_client_host_only_command_goes_to_host`, `test_cheats_blocked_in_release_by_default`.

## Acceptance criteria
- [ ] `spawn <any id>` works for every type with a registered spawner, with no console code per content.
- [ ] `validate` prints the same problems as the GUT content test.
- [ ] Cheats can't run in a release build unless the config allows it.

## Open design questions
- DEFAULT: in multiplayer only the host's cheat setting matters.

## Changelog
- 2026-10-07: spec created.
