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
`label` added to the file names. It writes `floor_stats_<label>.csv` (one line per floor, every number) and
`floor_stats_<label>.md` (checks against the plan, averages by floor number and by department).
It takes about 45 seconds for 900 floors.

## What I looked for, and what I found

| Check | Before | Verdict |
|---|---|---|
| Floors grow too fast or too slowly | Rooms 10 → 28 over floors 1-12, +1 to +2 every floor; tiles 34 → 90; longest walk 80 → 129 m | Fine, steady. No change. |
| Parts too close or too far | Part walk back 62 m (floor 1) → 98 m (floor 12); 19 of 900 floors had a part closer than the plan's 40% (the generator relaxes it when it has to) | Fine. No change. |
| Too many locks early | **Floor 3 jumped**: lift parts 1.5 → 2.5, keycard doors 0.5 → 1.5 (38 of 75 floor-3s had two keycard doors), locked doors 3.7 → 5.5, loops 0.9 → 1.6. Plan: 0-1 keycard doors and 1-2 parts on floors 1-3 | **Outlier. Fixed.** |
| Enemy density per room | 0.43 spawn spots per room on floor 1, falling to 0.33 by floor 12 | Worth a look, but not a floor_gen_tuning number (see below). Not changed. |
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

- **Enemies per room fall as floors grow** (0.43 → 0.33). Spawn spots are 60% of the enemy budget, and the budget
  grows 10% a floor (`enemy_budget_per_floor` in `config/game_config.tres`) while rooms nearly triple. That number
  belongs to the run difficulty, not the floor generator, so I left it. About 0.17 instead of 0.1 would keep
  roughly the floor-1 density all the way up. Zoology is higher (0.44) because broken enclosures wake extra spots.
- **Floor 1 is already quite damaged** (half the tiles damaged, a quarter heavy or worse), so it has about 3
  locked doors (pry 0.6, power 0.9, debris 1.2). That comes from your damage settings (heavy damage from floor 1),
  so I left it.
- **Floor 5 → 6 still steps up** (parts 2.6 → 4.1, keycard doors 1.5 → 2.4): that is the middle of the second
  department. Worth checking in the playtest; moving the third bracket from 6 to 7 would smooth it.
