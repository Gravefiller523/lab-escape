# save_load

Folder: `res://systems/save_load/` · Autoload: `SaveSystem` · Size: S · Phase 2 (stub in Phase 1)

## Purpose
Saves the player's **profile** on their own PC: which cosmetics they have unlocked, the outfit they
are wearing, and lifetime stats (runs played, bosses beaten) used for unlocks. Runs are never saved:
every run starts from scratch. The file has a version number so new fields can be added without
breaking old saves.

**Not responsible for:** settings (settings_input), deciding unlocks (cosmetics), Steam achievements (achievements).

## Public API
```gdscript
signal profile_loaded()
const SAVE_VERSION: int = 1

func get_profile() -> PlayerProfile
func save_profile() -> void                   # writes now (also autosaves on run_ended and quit)
func get_stat(stat: StringName) -> int
func increment_stat(stat: StringName, amount: int = 1) -> void
```
`PlayerProfile` (`class_name PlayerProfile extends RefCounted`):
```gdscript
var unlocked_cosmetic_ids: Array[StringName] = []
var loadout: Dictionary = {}                  # slot -> cosmetic id
var stats: Dictionary = {}                    # StringName -> int
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> PlayerProfile
```
Stat names (more can be added freely): `runs_started`, `runs_escaped`, `floors_reached_best`,
`enemies_killed`, `deaths`, `reprints`, `boss_defeated:<boss_id>` (e.g. `boss_defeated:boss_giant_rat`),
`mutations_gained`, `cybernetics_installed`.

## EventBus
- Emits: none.
- Listens: `run_started`, `run_ended`, `floor_ready`, `enemy_killed` (local player kills only),
  `player_died`/`player_reprinted` (local player), `boss_defeated`, `upgrade_gained` (local) → stats.

## Data it owns and saves
`user://profile_<steam_id>.json`:
```json
{ "save_version": 1, "unlocked_cosmetic_ids": [], "loadout": {}, "stats": {} }
```
- Loading runs a step-by-step upgrade: `_migrate_1_to_2(data)`, `_migrate_2_to_3(data)`, ...
- Ids of content that no longer exists are kept in the file but ignored, so removing content never deletes progress.
- A broken file is renamed `.broken` and a fresh profile starts (no crash).
- Steam Cloud backup is set up on the Steamworks site (Auto-Cloud on `user://profile_*.json`), no code needed.

## Adding content
None. New cosmetics and stats need no change here.

## Multiplayer
Local only. Each player's own PC saves their own profile. (A player could edit their file to unlock
cosmetics; that's harmless because cosmetics never affect gameplay.)

## Dependencies and stubs
steam_session (Steam ID for the file name; uses `local` in local mode). Phase 1 stub: in-memory profile with everything default.

## Test scene and GUT tests
GUT tests: `test_new_profile_defaults`, `test_round_trip`, `test_migration_from_version_0_fixture`,
`test_broken_file_is_renamed_not_crash`, `test_unknown_ids_are_kept`, `test_increment_stat`.

## Acceptance criteria
- [ ] Profile survives restart; stats update after a run.
- [ ] A save from an older version loads (fixture test).
- [ ] Removing a cosmetic file doesn't break loading.

## Open design questions
- DEFAULT: one profile per Steam account per PC.

## Changelog
- 2026-10-07: spec created.
