# achievements

Folder: `res://systems/achievements/` · Autoload: `Achievements` · Size: S · Phase 2

## Purpose
Steam achievements driven by data. Each `AchievementData` names an EventBus signal to count, an
optional id to match and how many are needed. This system listens, counts, stores progress in a Steam
stat (and the local profile), and unlocks the achievement on Steam.

**Not responsible for:** cosmetics unlocked by achievements (cosmetics listens to `achievement_unlocked`), the Steam overlay popup (Steam shows it).

## Public API
```gdscript
func get_progress(achievement_id: StringName) -> int
func is_unlocked(achievement_id: StringName) -> bool
func reset_all_for_testing() -> void      # editor builds only
```
At startup it connects to every EventBus signal named by an `AchievementData.trigger_event`
(found with `EventBus.has_signal`; unknown names are reported by the validation test). A handler with
variable arguments checks `local_player_only` (first argument equals `Net.local_player_id()`) and
`match_id` (first StringName argument equals it).

## EventBus
- Emits: `achievement_unlocked` (local).
- Listens: whatever the data says.

## Data it owns and saves
Uses `AchievementData`. Progress lives in Steam stats (`steam_stat_name`) with a copy in the save_load profile.

## Adding content
New achievements: add it on the Steamworks site, then add an `AchievementData` `.tres`. **No code**,
as long as an EventBus signal for it exists. Examples: first escape (`run_ended`, match `escaped`), beat
the Giant Rat (`boss_defeated`, `boss_giant_rat`), eat 10 gems (`upgrade_gained`, local only, count 10).

## Multiplayer
Each PC tracks its own player's achievements. Shared events (`boss_defeated`) count for everyone present.

## Dependencies and stubs
steam_session (Steam user stats). Stub: a fake Steam object recording unlock calls.

## Test scene and GUT tests
GUT tests: `test_counts_matching_events`, `test_ignores_other_players_when_local_only`,
`test_match_id_filters`, `test_unlocks_once_at_required_count`, `test_unknown_trigger_event_reported`,
`test_new_achievement_file_needs_no_code`.

## Acceptance criteria
- [ ] Beating the Giant Rat unlocks its achievement on Steam (test App ID 480 has its own test achievements; real ones need our App ID).
- [ ] New achievements are data only.

## Open design questions
- Achievements can't be tested for real until the game has its own Steam App ID ($100 Steam Direct fee).

## Changelog
- 2026-10-07: spec created.
