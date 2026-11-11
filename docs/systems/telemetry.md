# telemetry

Folder: `res://systems/telemetry/` · Autoload: `Telemetry` · Size: S · Phase 2 (useful from the first playtests)

## Purpose
A simple playtest log. When turned on, it writes every EventBus event with a timestamp to a file on
the player's PC, plus a summary at the end of each run (floors reached, deaths, gems collected, time
per floor, mutations found). The team reads these files after playtests to balance prices, drop rates
and difficulty. Nothing is sent anywhere.

**Not responsible for:** sending data online (we don't), crash reports (Godot's own logs).

## Public API
```gdscript
func is_enabled() -> bool
func set_enabled(enabled: bool) -> void
func log_custom(event_name: StringName, data: Dictionary) -> void
func get_current_log_path() -> String
```
Enabled by the `--telemetry` launch option, the debug console (`telemetry on`), or a settings toggle
in playtest builds. Off by default in release builds.

## EventBus
- Emits: none.
- Listens: **every** EventBus signal, found automatically with `EventBus.get_signal_list()`, so new
  signals are logged with no change here.

## Data it owns and saves
`user://telemetry/run_<date>_<time>.jsonl`, one JSON object per line: `{"t": 12.3, "event": "enemy_killed", "args": ["enemy_rat", [1,0,2], 765...]}`.
Nodes are written as their name and, for players, their player id.

## Adding content
None.

## Multiplayer
Each PC logs what it sees. The host's log is the most complete (host-only events like `enemy_killed`).

## Dependencies and stubs
Foundation only. Can be built at any time by anyone.

## Test scene and GUT tests
GUT tests: `test_disabled_writes_nothing`, `test_every_signal_connected`, `test_line_is_valid_json`, `test_nodes_written_as_names`.

## Acceptance criteria
- [ ] A playtest run produces a readable log and a run summary.
- [ ] Adding an EventBus signal needs no change here.
- [ ] Off by default; no network use.

## Open design questions
- DEFAULT: players in public playtests are told about the log and asked to send it manually.

## Changelog
- 2026-10-07: spec created.
- 2026-11-11 (roadmap WP4): built. `TelemetryService` (`systems/telemetry/telemetry.gd`), autoload line `Telemetry` (after
  Security). NEW `use_folder(folder)` for tests. Console `telemetry [on|off]` (not a cheat: any player can log their own
  PC). The first line of each file is `telemetry_started` (version, this PC's player id, host or not). At `run_ended` a
  `run_summary` line: result, floors reached, minutes, seconds per floor, deaths, gems spent, upgrades found, players.
  Signals with up to 5 arguments are logged (EventBus's longest has 4); a longer one prints a warning. Tests: the spec's
  four plus `test_run_summary_is_written_when_a_run_ends`.

## HANDOFF
**Built (2026-11-11, roadmap WP4):** see the Changelog. **How to use it in a playtest:** start the game with `--telemetry`
(or type `telemetry on` in the console), play, and the console's `telemetry` command shows where the file is (Windows:
`%APPDATA%\Godot\app_userdata\Lab Escape\telemetry\`). **Not yet:** a settings toggle for playtest builds (settings_input)
and kills per player in the summary (the host's log has every `enemy_killed` with the killer's id).
