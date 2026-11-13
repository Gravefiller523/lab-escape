# Floor tuning stats (step 6c, 2026-11-13)

Numbers from **900 generated floors**: 25 per department (Botany, Robotics, Zoology) for every floor number 1 to 12,
solo, with the live `config/floor_gen_tuning.tres`. The same seeds were used before and after the change, so the
two runs compare the same floors. Boss floors (4, 8, 12) are a boss arena in a real run; here they are generated
as normal floors only to show the curve.

## How to run it

```
godot --headless --path . res://systems/level_gen/test/floor_stats_runner.tscn -- count=25 builds=2 label=after
```

Options (all optional): `count` floors per department per floor number, `builds` how many of each to build to
time it, `players` (the enemy budget grows with players), `out` a folder (default `user://floorgen/stats/`),
`label` added to the file names. `budget=department` works the enemy budget out the old way (before step 6c), and
`enemy_budget_per_floor=0.2` tries a budget value for that run only (no file changes). It writes `floor_stats_<label>.csv` (one line per floor, every number) and
`floor_stats_<label>.md` (checks against the plan, averages by floor number and by department).
It takes about 45 seconds for 900 floors.

## What I looked for, and what I found

| Check | Before | Verdict |
|---|---|---|
| Floors grow too fast or too slowly | Rooms 10 → 28 over floors 1-12, +1 to +2 every floor; tiles 34 → 90; longest walk 80 → 129 m | Fine, steady. No change. |
| Parts too close or too far | Part walk back 62 m (floor 1) → 98 m (floor 12); 19 of 900 floors had a part closer than the plan's 40% (the generator relaxes it when it has to) | Fine. No change. |
| Too many locks early | **Floor 3 jumped**: lift parts 1.5 → 2.5, keycard doors 0.5 → 1.5 (38 of 75 floor-3s had two keycard doors), locked doors 3.7 → 5.5, loops 0.9 → 1.6. Plan: 0-1 keycard doors and 1-2 parts on floors 1-3 | **Outlier. Fixed.** |
| Enemy density per room | 0.43 spawn spots per room on floor 1, falling to 0.33 by floor 12; real enemies 0.52 per room falling to 0.20 | **Fixed** with Zachary's OK (see "Enemy crowding" below). |
| Hazards on low floors | 1.5 on floor 1, 1.4 on floor 2, 2.6 on floor 3 | Matches the plan (1-2 on floor 1, +1 per 2 floors). No change. |
| Fallbacks and time | 0 fallback floors, 0.02 retries per floor; planning 12-36 ms, building 93-242 ms a floor | Fine. |

### The change (one number)

`floor_brackets`: **(1, 3, 6, 8) → (1, 4, 6, 9)**.

The "by bracket" lists (parts, keycard doors, loops, branch depth, smaller incidents...) change at the first
floor of each bracket. In step 6a I spread the brackets evenly over 12 floors, which put a step **in the middle of
the first department** (floor 3). Now the whole first department (floors 1-3) is the gentlest bracket, as the plan
says. Floors 5-7 and 9-11 are in exactly the same brackets as before, so nothing else changes in a real run (boss
floor 8 moved bracket, but boss floors are an arena).

### Before and after, by floor (averages of 75 floors each)

| Floor | Rooms | Lift parts (before → after) | Locked doors | Keycard doors | Loops | Hazards | Enemy spots per room | Part walk (m) |
|---|---|---|---|---|---|---|---|---|
| 1 | 10.0 | 1.6 → 1.6 | 3.1 → 3.1 | 0.4 → 0.4 | 0.7 → 0.7 | 1.5 → 1.5 | 0.43 → 0.43 | 62 → 62 |
| 2 | 11.0 | 1.5 → 1.5 | 3.7 → 3.7 | 0.5 → 0.5 | 0.9 → 0.9 | 1.4 → 1.4 | 0.48 → 0.48 | 68 → 68 |
| 3 | 13.0 | 2.5 → 1.5 | 5.5 → 3.8 | 1.5 → 0.5 | 1.6 → 0.9 | 2.6 → 2.5 | 0.41 → 0.42 | 70 → 67 |
| 4 (boss) | 15.0 | 2.4 → 2.4 | 6.3 → 6.3 | 1.6 → 1.6 | 1.7 → 1.7 | 3.5 → 3.5 | 0.37 → 0.37 | 74 → 74 |
| 5 | 16.0 | 2.6 → 2.6 | 5.6 → 5.6 | 1.5 → 1.5 | 1.9 → 1.9 | 4.5 → 4.5 | 0.35 → 0.35 | 77 → 77 |
| 6 | 18.0 | 4.1 → 4.1 | 7.8 → 7.8 | 2.4 → 2.4 | 2.5 → 2.5 | 4.6 → 4.6 | 0.36 → 0.36 | 78 → 78 |
| 7 | 20.0 | 3.9 → 3.9 | 8.3 → 8.3 | 2.4 → 2.4 | 2.7 → 2.7 | 5.4 → 5.4 | 0.33 → 0.33 | 84 → 84 |
| 8 (boss) | 21.0 | 3.9 → 3.9 | 8.7 → 8.7 | 2.5 → 2.5 | 3.3 → 2.7 | 6.4 → 6.4 | 0.33 → 0.33 | 85 → 85 |
| 9 | 23.0 | 4.0 → 4.0 | 9.3 → 9.3 | 2.5 → 2.5 | 3.5 → 3.5 | 7.3 → 7.3 | 0.35 → 0.35 | 90 → 90 |
| 10 | 25.0 | 4.1 → 4.1 | 9.0 → 9.0 | 2.5 → 2.5 | 3.7 → 3.7 | 7.4 → 7.4 | 0.32 → 0.32 | 93 → 93 |
| 11 | 27.0 | 4.0 → 4.0 | 9.6 → 9.6 | 2.5 → 2.5 | 3.8 → 3.8 | 8.3 → 8.3 | 0.34 → 0.34 | 97 → 97 |
| 12 (boss) | 28.0 | 3.9 → 3.9 | 9.4 → 9.4 | 2.5 → 2.5 | 3.7 → 3.7 | 8.7 → 8.7 | 0.33 → 0.33 | 98 → 98 |

### Not changed, for Zachary to decide

- **Floor 1 is already quite damaged** (half the tiles damaged, a quarter heavy or worse), so it has about 3
  locked doors (pry 0.6, power 0.9, debris 1.2). That comes from your damage settings (heavy damage from floor 1),
  so I left it.
- **Floor 5 → 6 still steps up** (parts 2.6 → 4.1, keycard doors 1.5 → 2.4): that is the middle of the second
  department. Worth checking in the playtest; moving the third bracket from 6 to 7 would smooth it.

## Enemy crowding (added the same day, Zachary: "keep floor 1's crowding")

The first stats counted enemy *spawn spots*. Counting the enemies the spawner really puts down showed a bigger drop:
the spawner worked its budget out from the floor's place in its department block (1, 2, 3, then back to 1 after
each boss), so every floor got about 5 enemies while floors grew from 10 to 27 rooms. Enemies per room fell from
0.52 on floor 1 to 0.20 by floor 11.

Two changes (Zachary OK'd both):
1. The spawner (`Enemies.spawn_floor`, new optional `budget_floor`) works the budget out from the **run's** floor
   (1 to 12). Which enemy types can appear still follows the department floor, as before.
2. `enemy_budget_per_floor` in `config/game_config.tres`: **0.1 → 0.2** (the core default stays 0.1). Picked with
   the stats tool: 0.17 drifted down to 0.43 per room by floor 11, 0.22 and up overshot; 0.20 averages 0.52 over
   the normal floors, the same as floor 1.

Before → after (solo, 75 floors each; 4 players get about twice the budget, as before):

| Floor | Rooms | Enemy budget (before → after) | Enemies spawned | Enemies per room | Spawn spots per room |
|---|---|---|---|---|---|
| 1 | 10 | 6 → 6 | 5.2 → 5.2 | 0.52 → 0.52 | 0.43 → 0.43 |
| 2 | 11 | 7 → 7 | 5.5 → 5.5 | 0.50 → 0.50 | 0.48 → 0.48 |
| 3 | 13 | 7 → 8 | 5.4 → 6.1 | 0.41 → 0.47 | 0.42 → 0.42 |
| 4 (boss) | 15 | 8 → 10 | 6.1 → 7.4 | 0.41 → 0.49 | 0.37 → 0.44 |
| 5 | 16 | 6 → 11 | 5.2 → 9.5 | 0.33 → 0.60 | 0.35 → 0.48 |
| 6 | 18 | 7 → 12 | 5.4 → 9.1 | 0.30 → 0.50 | 0.36 → 0.47 |
| 7 | 20 | 7 → 13 | 5.0 → 9.4 | 0.25 → 0.47 | 0.33 → 0.43 |
| 8 (boss) | 21 | 8 → 14 | 5.9 → 10.2 | 0.28 → 0.49 | 0.33 → 0.47 |
| 9 | 23 | 6 → 16 | 5.2 → 13.6 | 0.23 → 0.59 | 0.35 → 0.48 |
| 10 | 25 | 7 → 17 | 5.4 → 12.9 | 0.22 → 0.52 | 0.32 → 0.47 |
| 11 | 27 | 7 → 18 | 5.4 → 13.1 | 0.20 → 0.48 | 0.34 → 0.45 |
| 12 (boss) | 28 | 8 → 19 | 5.8 → 13.5 | 0.20 → 0.48 | 0.33 → 0.47 |

The first floor of each department block (5, 9) is the busiest, because the costlier enemy types only unlock on
the block's later floors, so the same budget buys more small enemies there.
