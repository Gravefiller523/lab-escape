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
static func unknown_trigger_events() -> PackedStringArray   # NEW 2026-11-13: achievement files naming a signal EventBus lacks
func count_everywhere(on: bool) -> void   # NEW, tests only: count outside the game world too
func get_unlock_log() -> Array[String]    # NEW, tests only: Steam names unlocked this session
```
NEW 2026-11-13 (roadmap WP18), how it works: one handler per counted signal (a variadic function, `...args`, with the
signal's name bound last). `match_id` / NEW `match_text` (a plain word, like run_ended's `escaped`, that the content
test shouldn't treat as a content id) compare against the event's **first StringName argument**; `local_player_only`
compares the event's **first int argument** with `Net.local_player_id()` (for `kill_credited(enemy_id, killer)` that is
the killer). Counting happens only in the game world, like lifetime stats. Progress is the profile stat
`achievement:<id>`; with a `steam_stat_name`, that Steam stat is set too. At `required_count`: `SteamSession.unlock_achievement`,
a toast ("Achievement: <name>") and `EventBus.achievement_unlocked`. Console: `achievements`, `achievements reset`
(editor builds).
The 15 launch achievements (`content/achievements/`), with original names (gap G32): Clocking Out (escape), Overtime
Champion (escape 5 times), Pest Control / Weed Killer / Unplugged (each boss), Workplace Accident (die), Printed Fresh
(be reprinted), Side Effects May Vary (first upgrade), Science Project (10 upgrades), Animal Control (100 kills),
Employee Discount (buy something), Cardio Day (fill a hamster wheel), Maintenance Crew (50 lift parts fitted), Mass
Layoff (team wipe), Red Dot Special (use the laser pointer 20 times).
**To set up in Steamworks once the game has its App ID** (each file's `steam_api_name`; stats are INT, increment
only): achievements ACH_FIRST_ESCAPE, ACH_ESCAPE_5, ACH_BEAT_GIANT_RAT, ACH_BEAT_MUSHROOM_MAN, ACH_BEAT_ROBOBRAIN,
ACH_FIRST_DEATH, ACH_FIRST_REPRINT, ACH_FIRST_UPGRADE, ACH_UPGRADES_10, ACH_KILLS_100, ACH_FIRST_PURCHASE,
ACH_HAMSTER_WHEEL, ACH_LIFT_PARTS_50, ACH_TEAM_WIPE, ACH_LASER_POINTER; stats STAT_ESCAPES, STAT_UPGRADES, STAT_KILLS,
STAT_LIFT_PARTS, STAT_LASER_POINTER.
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
- 2026-11-13 (roadmap WP18): built (see Public API). NEW autoload `Achievements` (project.godot, after Telemetry). AchievementData NEW `match_text`. 15 achievements. steam_session NEW `unlock_achievement`, `set_stat`, `store_stats`. Tests: `tests/unit/achievements/test_achievements.gd` (9). Not yet: checking on real Steam (needs the App ID, decision D8); Steam's own copy of progress isn't read back (the profile is the truth on each PC).
