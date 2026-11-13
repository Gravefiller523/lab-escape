# Floor stats (after)

900 floors: 25 per department per floor number, 1 player(s), tuning config/floor_gen_tuning.tres. Boss floors (every 4) are generated as normal floors here.
Times are on this PC (plan = generate the layout, build = Level.build without the navigation bake).

## Checks against the plan

- Fallback floors: 0 of 900. Average retries: 0.03.
- Rooms per floor (floors 1 to 12): 10.0, 11.0, 13.0, 15.0, 16.0, 18.0, 20.0, 21.0, 23.0, 25.0, 27.0, 28.0.
- Growth steps outside +0.5 to +3.0 rooms: none.
- Floors with a part closer than 40% of the longest walk: 19 of 900 (the plan's minimum; the generator relaxes it when it must).
- Floors 1 to 3: 3.6 locked doors on average (pry 0.8, power 1.0, debris 1.3, keycard 0.5); 0 floors with more than 1 keycard door.
- Floors 1 to 3: 1.8 hazards on average; 41 floors with more than 2.
- Enemy spawn spots per room (floors 1 to 12): 0.43, 0.48, 0.42, 0.37, 0.35, 0.36, 0.33, 0.33, 0.35, 0.32, 0.34, 0.33.

## By floor number (all departments)

| floor | n | rooms | tiles | longest_path_m | parts | part_path_mean_m | part_path_min_share | locks | door_pry | door_power | door_debris | door_keycard | keycards | enemies | enemies_per_room | hazards | damaged_share | heavy_share | cameras | loops | attempt | plan_ms | build_ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 75 | 9.99 | 34.08 | 79.92 | 1.61 | 61.95 | 0.72 | 3.12 | 0.63 | 0.93 | 1.17 | 0.39 | 0.39 | 4.33 | 0.43 | 1.51 | 0.53 | 0.27 | 7.61 | 0.71 | 0.09 | 12.08 | 93.61 |
| 2 | 75 | 10.99 | 38.73 | 84.13 | 1.51 | 67.67 | 0.76 | 3.73 | 0.92 | 1.03 | 1.24 | 0.55 | 0.55 | 5.32 | 0.48 | 1.43 | 0.52 | 0.27 | 7.51 | 0.87 | 0.04 | 12.99 | 111.83 |
| 3 | 75 | 13.00 | 44.29 | 90.01 | 1.48 | 67.06 | 0.69 | 3.84 | 0.81 | 1.19 | 1.36 | 0.48 | 0.48 | 5.44 | 0.42 | 2.55 | 0.49 | 0.25 | 7.48 | 0.93 | 0.07 | 15.26 | 115.59 |
| 4 | 75 | 15.00 | 50.88 | 93.61 | 2.39 | 74.18 | 0.66 | 6.29 | 1.24 | 1.35 | 2.11 | 1.60 | 1.60 | 5.55 | 0.37 | 3.55 | 0.50 | 0.26 | 8.39 | 1.75 | 0.03 | 18.53 | 145.23 |
| 5 | 75 | 16.00 | 56.45 | 99.43 | 2.56 | 77.48 | 0.63 | 5.63 | 1.08 | 1.40 | 1.69 | 1.45 | 1.45 | 5.68 | 0.35 | 4.48 | 0.44 | 0.25 | 8.56 | 1.87 | 0.03 | 20.32 | 131.37 |
| 6 | 75 | 18.00 | 59.91 | 102.45 | 4.07 | 77.60 | 0.54 | 7.84 | 1.77 | 1.65 | 2.05 | 2.36 | 2.36 | 6.48 | 0.36 | 4.56 | 0.51 | 0.28 | 10.07 | 2.45 | 0.00 | 22.85 | 156.96 |
| 7 | 75 | 20.00 | 65.72 | 109.76 | 3.92 | 84.15 | 0.58 | 8.29 | 1.51 | 1.77 | 2.60 | 2.41 | 2.41 | 6.64 | 0.33 | 5.39 | 0.47 | 0.27 | 9.92 | 2.73 | 0.00 | 25.13 | 181.25 |
| 8 | 75 | 20.99 | 70.17 | 111.91 | 3.88 | 84.63 | 0.55 | 8.71 | 1.61 | 1.83 | 2.72 | 2.55 | 2.55 | 6.92 | 0.33 | 6.41 | 0.46 | 0.27 | 9.88 | 2.68 | 0.00 | 26.92 | 182.77 |
| 9 | 75 | 23.00 | 79.39 | 117.47 | 4.04 | 89.78 | 0.57 | 9.25 | 1.73 | 2.01 | 3.00 | 2.51 | 2.51 | 8.12 | 0.35 | 7.35 | 0.43 | 0.25 | 10.04 | 3.55 | 0.00 | 30.68 | 184.65 |
| 10 | 75 | 24.97 | 83.68 | 120.96 | 4.15 | 93.15 | 0.56 | 9.01 | 1.51 | 2.15 | 2.89 | 2.47 | 2.47 | 7.92 | 0.32 | 7.40 | 0.43 | 0.25 | 10.15 | 3.69 | 0.01 | 32.94 | 190.72 |
| 11 | 75 | 27.00 | 90.32 | 127.88 | 3.96 | 96.74 | 0.55 | 9.61 | 1.73 | 2.41 | 2.99 | 2.48 | 2.48 | 9.24 | 0.34 | 8.27 | 0.40 | 0.22 | 9.96 | 3.84 | 0.03 | 35.98 | 197.08 |
| 12 | 75 | 28.00 | 89.95 | 128.53 | 3.85 | 98.35 | 0.56 | 9.36 | 1.84 | 2.13 | 2.88 | 2.51 | 2.51 | 9.25 | 0.33 | 8.75 | 0.40 | 0.23 | 9.85 | 3.71 | 0.01 | 35.83 | 243.48 |

## By department (all floors)

| department | n | rooms | tiles | longest_path_m | parts | part_path_mean_m | part_path_min_share | locks | door_pry | door_power | door_debris | door_keycard | keycards | enemies | enemies_per_room | hazards | damaged_share | heavy_share | cameras | loops | attempt | plan_ms | build_ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| department_botany | 300 | 18.92 | 65.03 | 105.84 | 3.09 | 81.81 | 0.63 | 7.01 | 1.57 | 1.49 | 2.18 | 1.77 | 1.77 | 6.00 | 0.33 | 5.17 | 0.46 | 0.26 | 9.09 | 2.37 | 0.02 | 24.39 | 158.50 |
| department_robotics | 300 | 18.91 | 62.26 | 105.83 | 3.16 | 81.41 | 0.60 | 6.77 | 0.94 | 1.86 | 2.08 | 1.89 | 1.89 | 6.00 | 0.33 | 5.11 | 0.45 | 0.25 | 9.16 | 2.41 | 0.04 | 23.88 | 160.14 |
| department_zoology | 300 | 18.91 | 63.60 | 104.84 | 3.11 | 79.97 | 0.62 | 7.39 | 1.59 | 1.61 | 2.41 | 1.78 | 1.78 | 8.22 | 0.44 | 5.13 | 0.48 | 0.26 | 9.11 | 2.41 | 0.02 | 24.11 | 164.99 |

