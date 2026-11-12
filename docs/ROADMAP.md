# Lab Escape roadmap: from grey box to a finished game

Written 2026-11-11 from an audit of the repo on `main` (commit `cf8cde7`, Zoology step 5b merged), every spec in
`docs/systems/`, the floor generation plan, the Half-Life 2 feel plan, the brainstorm, the design decisions, the
test-build notes, a full GUT run and play sessions (see "How the audit was done" at the end).

**A fresh session can pick up from this file alone.** Read "Working rules" (section i) first, then find the first
work package whose status is not "done" and isn't waiting on Zachary.

Words used a lot here:
- **Work package (WP):** one chunk of work of 1 to 3 Claude Code sessions that ends in something you can play.
- **Session:** one sitting with Claude Code, roughly 1 to 2 hours.
- **Grey box:** placeholder shapes and flat colours standing in for real art.
- **Stand-in:** content borrowed from somewhere else until the real thing exists (Botany using Zoology's rats).
- **Look target:** one small slice of the game taken to final quality, used as the reference for everything else.
- **CC0:** "no rights reserved". Free to use in a commercial game with no credit needed.

---

## a. What 1.0 is

### The launch version, in one paragraph
Up to 4 friends ride a broken cargo lift up through a ruined lab, one floor at a time, in three departments
(Zoology, Botany, Robotics) that each have **their own enemies, their own boss, their own upgrades, their own loot
and shop stock**. A run is about an hour. You find the lift's broken parts, fight, buy items with physical gems,
step into the mutation machine, die, get reprinted from meat, and beat three bosses to reach the surface and see
an ending. Between runs you unlock and wear cosmetics in the Break Room. Everything has real low-poly models,
lighting, sound and music, the HUD tells you what you need, the first floor teaches you the game, and the Steam
page, achievements and cloud saves are in place.

### What 1.0 contains
| Area | At launch |
|---|---|
| Players | 1 to 4 officially. 8 stays a config number we test but don't advertise. |
| Run | 12 floors with a boss every 4th floor (decision D1; today it's 18 floors, boss every 6th). Change is two config numbers. |
| Departments | Zoology, Botany, Robotics, each with its own 3 to 4 enemies and its own boss. |
| Bosses | Giant Rat (exists), Mushroom Man (Botany), Robobrain (Robotics). |
| Upgrades | 5 animal mutations (exist), 4 plant mutations (new), 4 to 5 cybernetics (2 exist). |
| Items | The 6 that exist plus the laser pointer (from the brainstorm) and 1 or 2 more. |
| Co-op tasks | The hamster wheel (one task that works for any number of players). Keycards and locked doors already exist. |
| Meta | Cosmetics from the jacket closet (about 12), lifetime stats, about 15 achievements. |
| Story | A short comic premise, told through the Break Room whiteboard, lab PA text and signs, and an escape ending with credits. |
| Teaching | The Break Room and the first floor teach the controls and the loop with hints that show once. |
| UI | Full HUD, ghost (death) screen, run summary, boss health bar, player list with mute, all settings, one UI theme. |
| Art and audio | Everything replaced: rooms, props, characters, enemies, bosses, effects, UI, sounds and music. |

### Cut list: waits for updates
| Cut | Why it can wait |
|---|---|
| Marine Biology department | Already planned as Update 1. It's the test that "content is files, not code". |
| Crane game co-op task | Needs a 2-player claw machine with its own physics. Great for Update 1 next to Marine Biology. |
| 8 players as an advertised feature | Needs real-PC voice and bandwidth proof that you can't get alone. Keep the config, test it, don't promise it. |
| Endless mode, multi-storey floors, host migration | Each is a big system with little gain before launch. |
| Riding in carts, enemies stealing from carts, ghosts haunting, loud talkers attracting enemies, slug slime trail | Funny ideas already noted in the specs. Good update material. |
| Full controller support | Mouse and keyboard first. Rebinding already exists; gamepad later. |
| Translations | English at launch. Keep player-facing text in one place so it can be translated later. |
| Mutation stacking, removing mutations | Today's rules (unique, clashes replace) are fine for launch. |

### Where your current scope is too big for one beginner (plainly)
1. **18 floors is a long run.** With 18 floors and 3 bosses, most test runs will never reach the last boss, so
   the end of the game gets the least testing. 12 floors with a boss every 4th gives the same shape in two thirds
   of the time. It's two numbers in `config/game_config.tres`, so you can raise it again after launch.
2. **Art is the biggest job by far.** About 60 room data files, 31 props, 4 enemies, 1 boss and the player are
   all grey. Hand-making 60 rooms is not realistic. The plan below swaps the walls, floors and doors for one
   **modular kit** (a set of pieces every room is built from) with a colour swap per department, plus about
   15 hero props per department. That turns "60 rooms" into "one kit and 45 props".
3. **Three bosses and about 12 new enemies is a lot of code-plus-art.** The plan builds one new building block
   (ranged attacks and projectiles) and then makes most new enemies by combining existing pieces, so each new
   enemy is mostly a content file and a model.
4. **8 players** multiplies voice streams, bandwidth and balance work, and you can only prove it with 8 real PCs.
   It is cut from the launch promise (not from the code).
5. **The crane game** is the most complicated co-op task. The hamster wheel delivers the same "work together"
   moment for much less work.

Rough size of everything below: **about 95 to 130 sessions**, plus your own time for asset tools, playtests and
the Steam page. At 4 to 6 sessions a week that is roughly 5 to 7 months. Reliability and the HUD come first so the
game is fun to playtest with friends early, long before art.

---

## b. Gap list from the audit

Tags: **reliability**, **fun**, **looks**, **sound**, **content**, **release**. Size: **S** = under a session,
**M** = 1 to 2 sessions, **L** = 3 or more. **You** = needs Zachary (a decision, money, a real PC, or a playtest).

### Reliability
| # | Gap | Tag | Size | You |
|---|---|---|---|---|
| G1 | No automated test plays a whole run (Break Room to escape, with a client). Each system is tested alone; a run that breaks between floor 7 and 8 would only show up by hand. | reliability | M | |
| G2 | A client that disconnects only drops its items if its body still exists when the host hears about it (death_respawn "Not yet", never tested). Lift parts or keycards in its hands could vanish and block the floor. | reliability | S | |
| G3 | Ghosts left outside the lift "ride along invisibly where they died" (death_respawn). After the ride they are somewhere odd on the new floor. | reliability | S | |
| G4 | ~~Gems pushed into a vendor inside a cart don't count.~~ Fixed in WP3 (the cart bay). | reliability | S | |
| G5 | The boss arena has a printer marker by default, but nothing checks that a death in a boss fight can be reprinted on every boss floor. | reliability | S | |
| G6 | Mid-floor joining, host quitting mid-floor and 3+ PCs were never checked on real Steam. Local tests exist for parts of it. | reliability | M | You |
| G7 | Voice delay, the Fly voice over Steam, and voice CPU with many players were never judged on real Steam. | reliability | S | You |
| G8 | Nameplates of ghosts still show (ui "OPEN"). | reliability | S | |
| G9 | Rebinding lets two actions share one key with no warning. | reliability | S | |
| G10 | The editor that's open on your PC was started before the Security autoload existed, so the security test scene shows a parse error there until you use Project > Reload Current Project. Not a real bug. | reliability | S | You |
| G11 | Steam rich presence in a friend's list never checked. | reliability | S | You |
| G49 | The test run prints 79 RPC errors (from `test_speed_check.gd`'s fake client) and leaves 1 orphan node, so a real new error is easy to miss in the Output panel. | reliability | S | |
| G50 | Enemy navigation baking reads visual meshes (Godot warns this is slow) and reports 2 navmesh edge errors on some floors: a possible hitch on floor load and odd enemy paths. | reliability | S | |
| G51 | When the host leaves a local (no Steam) game, ENet prints one "Unable to send packet on channel 0" error while saying goodbye. Harmless; found by WP1. | reliability | S | |
| G52 | ~~A player who joins mid-floor built the floor before their connection opened, so its vending machines, printers, mutation machine, doors, buttons, boss arena and plants asked the host for their state too early and never heard back (no shop offers, wrong door states).~~ Fixed in WP1. | reliability | S | |
| G53 | ~~Prop snapshot messages reached 1,900 bytes, over one network packet, so on real connections they'd be lost more often (jumpy props).~~ Fixed in WP1. | reliability | S | |
| G56 | ~~Twice, in full test runs, the full-run test's client got about 300 "spawner is null" errors and no body.~~ Found in WP7: the client asked to join while the host was still loading the Break Room, was told "nothing yet", and missed the host's "come into the world" message. Fixed in WP7 (game_flow sends a joiner straight to the Break Room while the host loads it). The full-run driver also has `--join_delay` to try joins at other moments. | reliability | S | |
| G57 | `test_thrown_crate_barely_hurts_a_heavy_enemy` (physics_props) failed once in a full run: the thrown crate hit the 50 kg test enemy twice (it bounced), leaving 6.6 health where the test wants more than 9. It passed 3 times in a row alone. Physics bounce timing; worth making the test count only the first hit. Found in WP11. | reliability | S | ||
| G55 | The open editor lists about 130 typing warnings in existing code (mostly "a Variant was given where an int/float/String is needed"): most in level_gen, some in physics_props, enemies, security, hazards. CLAUDE.md counts them as bugs. Found in WP3; level_gen's share is for the floor generator thread. | reliability | M | |
| G54 | Now and then an enemy's position update reaches a client just before the enemy exists there (or just after it's gone): "Node not found: Enemies/Spawner/EnemyN" errors. Harmless, but noisy. Found by WP2's test. | reliability | S | |

### Fun and clarity
| # | Gap | Tag | Size | You |
|---|---|---|---|---|
| G12 | **No health bar and no inventory bar.** You can't see your health, your slots or what you're holding. The HUD only has the crosshair, the use prompt, the lift panel and nameplates. | fun | M | You (mock-up OK) |
| G13 | No ghost (death) screen, no run summary, no boss health bar, no "joined mid-run: you'll spawn next floor" notice. | fun | M | You (mock-up OK) |
| G14 | Little feedback on hits: no hit flash, hit pause, camera kick on being hurt, enemy hurt reactions, or death effects. Combat reads as "numbers went down". | fun | M | You (mock-up OK) |
| G15 | All three boss floors are the Giant Rat; Botany and Robotics use Zoology's enemies, loot and shop stock. Floors feel the same after the first boss. | content | L | |
| G16 | Botany's DNA vials hold animal mutations (no plant mutations). Robotics' data drives only have the test arm and the punt arm. | content | M | |
| G17 | No ranged enemies at all (no ranged attack state). The brainstorm's spore shooter, turrets, drones and Robobrain's lasers and rockets all need it. | content | M | |
| G18 | Co-op tasks (hamster wheel, crane game) don't exist. Today the only co-op beats are heavy lifting, carts and reprints. | fun | M | |
| G19 | No laser pointer (brainstorm item). Fly isn't drawn to trash and flies aren't drawn to Fly players (brainstorm). Giraffe doesn't have to crouch through doors. | fun | S each | |
| G20 | Balance is untested: prices, gem drops, vial chance, enemy budgets per player count, run length. There is no playtest log to tune from (telemetry is empty). | fun | S + playtests | You |
| G21 | No player list (Tab) with ping, mute per player, or a host kick button (Net already has kick). | fun | S | |
| G22 | Octo can climb other players and crates; tune or keep as comedy. | fun | S | You |

### Content and systems that are empty
| # | Gap | Tag | Size | You |
|---|---|---|---|---|
| G23 | objectives: co-op floor tasks (keycards and locked doors are already done by level_gen and world_io). | content | M | |
| G24 | cosmetics and the jacket closet; save_load (profile, lifetime stats). | content | M + S | You (unlock list) |
| G25 | achievements (data-driven). Can only be tested for real with your own App ID. | release | S | You ($) |
| G26 | telemetry (playtest log). | release | S | |
| G27 | Hazards are placeholder visuals; no HazardData content type (per-kind data). | content | S | |

### Story and teaching (nobody has written these down yet)
| # | Gap | Tag | Size | You |
|---|---|---|---|---|
| G28 | No premise: why are we escaping, who are we, what happened? (Brainstorm priority 6.) | content | S | You (approve) |
| G29 | No ending beyond the word "escaped", and no credits. | content | M | |
| G30 | Nothing teaches a new player: the controls, that gems are money, that the lift needs parts, how reprinting works. | fun | M | |
| G31 | No controls page in the pause menu. | fun | S | |
| G32 | Brainstorm achievement names reference other games' characters ("Frank Horrigan disapproves"). Rule: no existing characters or brands. Use original names. | release | S | |

### Looks and sound
| # | Gap | Tag | Size | You |
|---|---|---|---|---|
| G33 | No models: every room is grey blockout, every character a capsule, every prop a box. `assets/models` is empty. | looks | L | You ($ month) |
| G34 | No textures or real materials: 12 flat colour materials. | looks | M | |
| G35 | Lighting is plain: no fog, no glow on emissives, no light colour per department beyond the tint. | looks | M | |
| G36 | No animations (players, enemies, held items beyond a tween). | looks | L | |
| G37 | No UI theme (`lab_theme.tres` doesn't exist); Godot's default look. | looks | M | You (mock-up OK) |
| G38 | Every sound is a generated beep or drone. `assets/audio` is empty. | sound | L | You ($ month) |
| G39 | No music. | sound | M | You |
| G40 | Lift ride has no rumble or arrival jolt (cargo_lift "Not done"). | looks | S | |
| G41 | Zoology's "broken skylights and dark corners" damage look is left for art. | looks | S | |

### Release
| # | Gap | Tag | Size | You |
|---|---|---|---|---|
| G42 | No App ID yet (Steam Direct fee). Still on Spacewar (480). | release | S | You ($) |
| G43 | No Steam page, capsule art, trailer, screenshots. | release | M | You |
| G44 | AI content log is empty (fine today: nothing AI-made is in the game yet). | release | S | |
| G45 | No credits list (Godot, GodotSteam, CC0 packs, AI tools). | release | S | |
| G46 | Steam Cloud for the profile file isn't set up. | release | S | You |
| G47 | No performance target or check on a modest PC; no LODs. | release | M | You |
| G48 | Export presets must leave out `tests/` and `addons/gut`. | release | S | |

---

## c. Work packages, in order

Ordered by what players gain per hour of work, with reliability before polish. Each one ends in something you
can play. Every package follows the Working rules (section i). Status values: **not started**, **in progress**,
**waiting for your play test**, **waiting for your OK**, **done**, **cut**.

### Phase R: reliable runs

#### WP1: A whole run, played by a robot
- **What:** an integration test (`tests/integration/test_full_run.gd`) that plays a short run through public APIs:
  host plus a local client, Break Room, lift, every floor, a death and a reprint, every boss, the escape, back to
  the Break Room. Plus a slower "soak" version (all floors) behind a flag. Fix anything it finds.
- **Why first:** every later package changes many systems. This catches "the run breaks on floor 8" in minutes.
- **Test it in the game:** run the test from the GUT panel and watch it pass; the soak prints one line per floor.
- Also: silence the 79 RPC errors and the orphan in the test run, so the Output panel is clean (G49).
- **Gaps:** G1, G5, G49, G52, G53.
- **Built:** `tests/integration/test_full_run.gd` starts 3 Godot processes (host, a client, and a late joiner who
  connects during floor 1) running `tests/integration/full_run/full_run_launcher.tscn`. The quick run: 4 floors, a
  boss every 2nd floor, 1 s rides; the host fixes the lift by slotting each broken part, a client dies and is
  reprinted on floor 3, both bosses are beaten, and everyone rides back to the Break Room. It checks every floor in
  order on all 3 PCs with the same departments, bodies for everyone, the late joiner waiting then spawning, and no
  errors in any process's log (two known ones, G50 and G51, are listed in the test and printed). About 25 s.
  Long version: set `LAB_ESCAPE_FULL_RUN=soak` to play the real 18 floors.
- **Fixed on the way:** G52 (mid-floor joiners' machines and devices), G53 (prop messages too big), "player left"
  handling sending to the closed connection (net_core now handles a disconnect a frame later), the speed check's
  put-back message to players who aren't connected (G49), and the orphan node in the damage test.
- **Status: done.** Merged into main 2026-11-11.

#### WP2: Disconnects, late joiners and ghosts
- **What:** a leaving client always drops what it held (lift parts and keycards come back); ghosts are moved into
  the lift when it leaves; a mid-floor joiner gets the "you'll spawn next floor" notice and spawns; the host
  quitting sends clients to the menu with a message; a rejoining player gets their mutations back. Tested with
  3 local windows.
- **Test it:** Host local + 2 Join local. Close a client while it carries a lift part; the part reappears.
  Die outside the lift and let it leave; you arrive inside the lift as a ghost. Join while a floor is running.
- Start from WP1's full-run test: add a client leaving mid-floor while carrying a lift part, and the host leaving.
  Note from WP1: the host's log shows one ENet error when it leaves a local game (G51).
- **Gaps:** G2, G3, G8, G51.
- **Built:** a second full-run test, `test_players_leaving_mid_floor`: a client holding a lift part and a crowbar
  quits on floor 1 (the crowbar drops, the part stays on the floor let go, the lift can still be fixed), then the
  host walks out on floor 2 (the last client lands in the main menu). Ghosts are moved into the lift when it leaves
  (death_respawn), and ghosts have no nameplate (ui). G2 turned out to work already; the test now guards it.
- **Not done here:** a rejoining player getting their mutations back can only be checked with real Steam IDs
  (local test players get a new id each time), so it's on the real-Steam checklist; G51 is still listed as known.
- **Status: done.** Merged into main 2026-11-11.

#### WP3: Small leftovers that break plans
- **What:** gems in a cart count at a vendor (the pusher gets the credit); duplicate key bindings warn; voice reads
  "reduce voice effects"; boss-floor reprints checked.
- **Test it:** push a cart of gems into a vending machine; bind two actions to one key.
- Also: bake enemy navigation from collision shapes instead of visual meshes, and look at the navmesh edge errors
  (enemies system only; level_gen stays untouched) (G50).
- Also: G54, enemy position updates that reach a client before the enemy exists there (or after it's gone).
  When G50 and G54 are fixed, take their lines out of `KNOWN` in `tests/integration/test_full_run.gd`.
- **Gaps:** G4, G9, G50, G54, settings_input leftovers.
- **Built:** a cart bay in front of every vending machine (push a cart of gems into it and the pusher gets the
  credit; no new art, it's an invisible box at floor level), a warning on the rebinding buttons when two actions
  share a key, "quieter voice effects" now works, enemy navigation reads the rooms' collision shapes (G50 gone),
  enemies wait a moment before their first position update (G54 gone; both removed from the test's known list),
  and the full-run test checks every floor, boss floors included, has a 3D printer (G5).
- **Status: done.** Merged into main 2026-11-11.

#### WP4: Playtest log (telemetry)
- **What:** the telemetry system from its spec: writes every EventBus event and a per-run summary (floors, deaths,
  gems, time per floor, mutations) to `user://telemetry/`. Off unless `--telemetry` or the console turns it on.
- **Why now:** every balance decision afterwards (prices, drops, run length) comes from these files.
- **Test it:** console `telemetry on`, play two floors, open the file it names.
- **Gaps:** G20, G26.
- **Built:** `Telemetry` autoload, 5 tests. Each PC writes its own log; the host's is the most complete.
- **Status: done.** Merged into main 2026-11-11.

### Phase U: the game explains itself

#### WP5: HUD essentials (needs your OK on a mock-up first)
- **What:** health bar, inventory bar with the held item and uses, boss health bar, ghost screen (who you're
  watching, "a teammate can reprint you with meat"), the joiner notice, and the run summary screen.
- **Test it:** take damage, switch slots, die, beat or lose a run.
- **Gaps:** G12, G13.
- **Built:** everything in the mock-up, plus a player list in the bottom right (names with speaking / ghost / joining; the Tab list with ping, mute and kick is still WP6). The run summary shows deaths, gems spent and upgrades per player. Kills are left out for now because only the host hears about them (a later package can send them). `run_summary_seconds` went from 5 to 12 so the summary can be read.
- **Status: done.** Mock-up approved and merged into main 2026-11-11.

#### WP6: Player list and pause menu
- **What:** Tab shows every player with ping, a mute button and (host) kick; the pause menu gets a controls page.
- **Gaps:** G21, G31.
- **Built:** Tab opens a list of every player with their ping, Mute / Unmute (only what you hear) and, for the host, Kick; Tab or Esc closes it. The pause menu has a Controls button listing every action and its key. Ping shows "-" over Steam for now (Steam's relay doesn't report it the same way); it works in local tests.
- **Status: done.** Merged into main 2026-11-11.

#### WP7: Hits you can feel (needs your OK on a mock-up first)
- **What:** hit flash on enemies and players, a 40 to 60 ms hit pause on melee hits, camera kick when hurt (honours
  "reduce motion"), enemy flinch, a pop of debris and a squeak on death, a sparkle on gem pickup. All numbers in
  feel tuning.
- **Gaps:** G14.
- **Built:** all six effects from the approved mock-up. The hit pause holds the enemy you hit still for a blink rather than freezing the whole game, because a real freeze on the host would pause everyone's game. Every number is in `config/feel_tuning.tres` under Hits, and `tune` works on them live.
- **Status: done.** Merged into main 2026-11-12.

#### WP8: First-run teaching and the premise
- **What:** Break Room orientation boards (controls, "the lift is broken, find the part"), hints that show once
  per profile on the first floor (first gem, first vendor, first vial, first death), the PA text lines and
  whiteboard premise from decision D5.
- **Needs:** WP12 (save_load) for "show once"; until then hints show once per session.
- **Gaps:** G28, G30.
- **Built:** the whiteboard premise, three how-to boards by the lift, 8 PA lines (2 for each department plus general ones, as content files) shown a few seconds after each floor starts, and 7 first-time hints (content files). Hints are remembered in a small file on the PC (once ever, not once per session), which moves into the profile with WP12.
- **Status: waiting for your play test.** Branch `wp/08-teaching` (stacked on `wp/10-botany`).

### Phase C: each department its own

#### WP9: Ranged attacks building block
- **What:** a projectile scene plus a ranged attack state that any enemy or boss can use from its content file
  (speed, damage, spread, status on hit, wind-up). One test enemy uses it.
- **Gaps:** G17.
- **Built:** RangedAttackData, the attack_ranged state, EnemyProjectile, and a grey-box test enemy (`enemy_test_spitter`, in no department) that keeps its distance and fires 3-shot bursts of slow green balls. A turret is the same enemy with `move_speed` 0 and no moving states. How to make one is in ADDING_CONTENT.md.
- **Status: done.** Merged into main 2026-11-11.

#### WP10: Botany roster (2 to 3 sessions)
- **What:** flytrap (hides, snaps at whoever comes close), spore shooter (ranged, leaves a spore cloud that
  burns slowly), vine creeper (slow, tough, pulls you towards it), mushroom zombie (minion, also used by the boss).
  Botany loot table and vendor stock. 4 plant mutations (decision D4 list). Remove the Zoology stand-ins.
- **Gaps:** G15, G16.
- **Built (part 1 of 2):** the four enemies, `status_spores` (poison over time), `loot_botany_small` / `loot_botany_medium`, `stock_botany_vending` (more energy drinks and potted plants), and the Botany department now uses them instead of Zoology's. Grey box until the art pass. The spore shooter's "cloud" is a spores status on whoever its puffball hits, not a cloud left on the floor (a lingering cloud is a hazard job for later).
- **Built (part 2):** the 4 plant mutations from decision D4. Photosynthesis heals you once nothing has hurt you for 4 seconds (true "in the light" waits for real lighting in the art pass). Spore Cough coughs by itself every 8 seconds, making enemies within 4 m stop to sneeze. Vine Arm is the punt arm's pull without the punt. Botany vials now hold only plant mutations, and Zoology vials only animal ones.
- **Status: part 1 (enemies, loot, stock) merged into main 2026-11-12; part 2 (plant mutations) waiting for your OK.** Branch `wp/10-botany`.

#### WP11: Robotics roster (2 to 3 sessions)
- **What:** roomba (fast, knocks props and players over), turret (stationary ranged, turns slowly), drone (flying
  ranged), flock camera (spots you and calls nearby robots; uses the security cameras the floor plan places).
  Robotics loot and stock. 3 new cybernetics (decision D4 list).
- **Gaps:** G15, G16.
- **Built (part 1 of 2):** the four enemies, `loot_robotics_small` / `loot_robotics_medium`, `stock_robotics_vending` (more crowbars and coffee), and the Robotics department now uses them instead of Zoology's rats and bats. The flock camera is its own small enemy (spawned like the others), not the floor plan's security cameras; joining the two can come with the security room work later. The roomba knocks players back hard; knocking props over comes from its body bumping them.
- **Built (part 2):** the 3 cybernetics from decision D4. Magnet Hand tugs loose gems within 6 m towards you. Spring Legs give a higher jump and a stomp when you land hard (there is no fall damage in the game, so "fall immunity" has nothing to protect against yet). Night-Vision Eye gives you, and only you, a soft green light. All three only come from Robotics data drives.
- **Status: waiting for your play test.** Branch `wp/11-robotics` (stacked on `wp/08-teaching`).

#### WP12: Profile saves (save_load)
- **What:** the profile file from the spec, versioned, autosaved on run end and quit. Lifetime stats.
- **Gaps:** G24 (half). **Status: not started.**

#### WP13: Mushroom Man and Robobrain (2 to 3 sessions)
- **What:** Mushroom Man: spore phases, mushroom zombie waves, a spore cloud slam. Robobrain: laser sweep,
  rocket volleys, drone waves. Botany and Robotics boss floors turned on.
- **Gaps:** G15. **Status: not started.**

#### WP14: Items and brainstorm leftovers
- **What:** laser pointer (a "lure" behaviour piece: some enemies chase the dot), 1 or 2 more items, Fly drawn to
  trash props and flies drawn to Fly players, Giraffe crouches through doors.
- **Gaps:** G19. **Status: not started.**

#### WP15: The hamster wheel (objectives)
- **What:** the floor task framework from the objectives spec and one task: running in a hamster wheel charges a
  fuse box that powers a locked area or the lift. More players run it faster.
- **Gaps:** G18, G23. **Status: not started.**

#### WP16: Balance pass 1
- **What:** with telemetry from at least 3 of your play sessions: run length (D1), prices, gem drops, vial chance,
  enemy budgets for 1 to 4 players.
- **Gaps:** G20. **Status: not started** (needs your play sessions).

### Phase M: reasons to come back

#### WP17: Cosmetics and the jacket closet (needs your OK on the closet mock-up)
- **What:** cosmetics from the spec, about 12 starter items, unlock rules (decision D6), the closet screen, fitting
  on mutated bodies (Slug can't wear shoes).
- **Gaps:** G24. **Status: not started.**

#### WP18: Achievements
- **What:** the achievements system and about 15 achievements with original names (G32).
- **Needs:** your App ID (D8) to test on Steam for real; built and unit-tested against Spacewar before that.
- **Gaps:** G25, G32. **Status: not started.**

#### WP19: The ending and credits
- **What:** the last boss opens the way up; the lift breaks out into daylight, a short "you escaped" scene with the
  run summary, then credits from `docs/CREDITS.md`.
- **Gaps:** G29, G45. **Status: not started.**

### Phase A: art (see section d)
#### WP20: Art bible, tools and import pipeline
- Install Blender (and its MCP), set import settings, write `docs/ART_BIBLE.md` from section d. **Status: not started.**
#### WP21: Look target (needs your OK on screenshots before anything rolls out)
- One Zoology animal holding room, the lift, the rat, a crate, gem, meat and DNA vial at final quality.
  **Status: not started.**
#### WP22 to WP27: Art rollout
- WP22 modular kit (walls, floors, ceilings, doors, hallway pieces) for all three palettes; WP23 shared props;
  WP24 player body and mutation parts; WP25 enemies and bosses with animation; WP26 effects and lighting per
  department; WP27 UI theme and icons. **Status: not started.**

### Phase S: sound (see section e)
#### WP28: Audio mix and free sounds
- Buses, reverb shared with voice, footsteps and impacts from CC0 packs. **Status: not started.**
#### WP29: Generated sounds month (ElevenLabs batch)
- Creature sounds, boss voices, machines, UI, PA lines. **Status: not started.**
#### WP30: Music
- One loop per department, boss music, menu and Break Room. **Status: not started.**

### Phase L: launch
#### WP31: Performance and 8-player stress
- LODs, light and shadow limits, a frame-time budget on a modest PC, 8 local instances. **Status: not started.**
#### WP32: Steam setup and builds
- App ID, achievements in Steamworks, Steam Cloud for the profile, export presets without tests and GUT, depot
  upload, playtest branch. **Status: not started.**
#### WP33: Store page and launch
- Capsules, screenshots, trailer, description, AI disclosure, release checklist (section g). **Status: not started.**

---

## d. Art plan

### Art bible (short version; the full one goes in `docs/ART_BIBLE.md` in WP20)
- **Style:** chunky low-poly, flat shading with a few soft gradients, big readable shapes, slightly exaggerated
  proportions (big hands, big heads on enemies), comedic. No photo textures.
- **Colours per department** (already in the department files' palettes):
  - Zoology: warm wood, sand and moss green; warm light (around 3200 K, amber). Damage: dark corners, broken
    skylights.
  - Botany: clinical white with green accents; bright flat light (around 5500 K). Damage: green-tinted, dim.
  - Robotics: industrial grey with safety yellow stripes; cold strip lights (around 6500 K, blue-white). Damage:
    red emergency lights.
  - Shared: the Break Room is a cosy staff room (warm, posters, a fridge), the lift is scuffed safety yellow.
- **Triangle budgets:** player body 2,000 to 3,000; mutation parts 300 to 800 each; small enemy 800 to 2,000;
  large enemy 2,000 to 4,000; boss 6,000 to 10,000; small prop 50 to 400; large prop 400 to 1,200; one kit wall
  piece under 300. A typical view stays under about 300,000 triangles.
- **Surfaces:** one shared **palette texture** (a 256 x 256 image of colour swatches) per department. Models are
  UV-mapped onto swatches instead of having their own textures. Swapping the department swaps the palette, so one
  kit serves all three departments. Hero objects (bosses, the lift) may have one 512 px texture of their own.
- **Lighting rules:** each room has a few real lights (at most 4 casting shadows in view), plus emissive strips
  that glow; light fog per department; a little ambient occlusion. No baked lightmaps (floors are generated).
- **Scale:** 1 Godot unit = 1 m. Player 1.8 m tall. Grid 3 m. Doorways 2.4 m wide, 2.8 m tall. Ceilings 3.6 m.
  Lift cage 5 x 5 m inside. A crate is about 0.6 m.
- **File names:** `<kind>_<name>.glb`, matching content ids where there is one (`enemy_rat.glb`,
  `prop_crate.glb`, `kit_zoology_wall_door.glb`).
- **Folders:** `assets/models/<department or shared>/`, `assets/textures/<department>/`,
  `assets/materials/<department>/`. Drop new files in `assets/_incoming/` and Claude moves and imports them.
- **Import settings:** glTF 2.0 (`.glb`) from Blender, +Y up, metres, apply transforms, origin at the base
  centre (for props and characters). Godot: generate LODs on, shadow meshes on, textures VRAM compressed with
  mipmaps, nearest-free (linear) filtering.
- **Animation:** Mixamo for the player and humanoid enemies (free with an Adobe account; check its terms), simple
  code or Blender animation for animals and robots.

### The look target (WP21; shown to you before anything else changes)
1. The Zoology **animal holding** room (pens, aisle, hay, cage bars) with final lights and fog.
2. **The lift** (cage, gate, part panel, sparks).
3. **The rat** with idle, run, bite and death.
4. Props: **crate, gem, large gem, meat, DNA vial**.
5. The HUD from WP5 on top.
I'll post 4 screenshots (wide room, lift inside, rat close up, props on a table) next to the grey-box version.
Nothing else is rolled out until you say yes.

### What I can make myself for free
Lighting and fog per department, materials and the palette textures, shaders (glow strips, glass, water,
dissolve on death, hologram screens), particle effects (sparks, spores, gem sparkle, blood-free comedic poofs),
simple meshes in code or Blender to replace CSG (walls, pipes, tables, shelves, cages), the modular kit, hit
feedback, camera feel, the UI theme and icons, simple animations for robots and props, the lift ride rumble.

### Asset order list for you
Free first (CC0, no credit needed, check each pack's licence file before importing):
| What | Tool / source | Size budget | File name | Drop in |
|---|---|---|---|---|
| Furniture, lab equipment, crates | Kenney or Quaternius CC0 packs (pick low-poly ones) | per piece budgets above | keep their names, Claude renames | `assets/_incoming/cc0/` |
| Humanoid rig and animations for the player | Mixamo (free; check terms) | player 2–3k tris | `player_body.glb` | `assets/_incoming/` |

Paid, **one Meshy month** (only after the look target is approved; Meshy's own docs say the free plan's models are
CC BY 4.0, which needs credit, and paid plans include commercial rights; the Pro plan is listed around $20 a month:
check the price and terms on meshy.ai/pricing the day you buy). Generate all of these in that one month, then
clean up in Blender. Prompts are written to avoid any existing character or brand:
| Model | Prompt | Budget | File name | Drop in |
|---|---|---|---|---|
| Rat | "chunky low-poly cartoon lab rat, oversized head and front teeth, stubby legs, simple flat colours, game asset, T-pose side view" | 1,500 | `enemy_rat.glb` | `assets/_incoming/meshy/` |
| Kangaroo | "chunky low-poly cartoon kangaroo wearing a torn lab tag, big feet, boxing stance, flat colours, game asset" | 3,000 | `enemy_kangaroo.glb` | same |
| Bat | "chunky low-poly cartoon bat, wide wings spread, big ears, flat colours, game asset" | 1,200 | `enemy_bat.glb` | same |
| Fly | "chunky low-poly cartoon housefly, huge red eyes, small wings, flat colours, game asset" | 800 | `enemy_fly.glb` | same |
| Giant Rat boss | "huge chunky low-poly cartoon rat boss, scarred, lab collar with broken chain, flat colours, game asset" | 8,000 | `boss_giant_rat.glb` | same |
| Flytrap | "chunky low-poly cartoon carnivorous plant monster in a cracked lab pot, wide jaws, flat colours, game asset" | 2,000 | `enemy_flytrap.glb` | same |
| Spore shooter | "chunky low-poly cartoon mushroom creature with a puffball on its back, flat colours, game asset" | 1,500 | `enemy_spore_shooter.glb` | same |
| Vine creeper | "chunky low-poly cartoon walking tangle of vines with leaves, flat colours, game asset" | 2,500 | `enemy_vine_creeper.glb` | same |
| Mushroom zombie | "chunky low-poly cartoon lab worker with mushrooms growing from the head, goofy, flat colours, game asset" | 2,000 | `enemy_mushroom_zombie.glb` | same |
| Mushroom Man boss | "giant chunky low-poly cartoon mushroom king, cap like a dome, stubby arms, flat colours, game asset" | 8,000 | `boss_mushroom_man.glb` | same |
| Roomba | "chunky low-poly cartoon robot vacuum with angry LED eyes and a spinning brush, flat colours, game asset" | 800 | `enemy_roomba.glb` | same |
| Turret | "chunky low-poly cartoon ceiling-free floor turret on a tripod, one big lens, safety yellow, game asset" | 1,500 | `enemy_turret.glb` | same |
| Drone | "chunky low-poly cartoon quadcopter drone with one big eye, safety yellow, game asset" | 1,200 | `enemy_drone.glb` | same |
| Robobrain boss | "huge chunky low-poly cartoon robot with a glass dome holding a brain, tank treads, two arm cannons, flat colours, game asset" | 10,000 | `boss_robobrain.glb` | same |
| Lift parts (12) | one each: "chunky low-poly cartoon [gear / fuse / vacuum tube / cable spool / battery / lever / counterweight / motor / brake assembly / control board / light / button], flat colours, game asset" | 200–600 | `prop_lift_<name>.glb` | same |
| Vendor machine | "chunky low-poly cartoon vending machine with a big coin slot, scuffed, flat colours, game asset" | 1,200 | `prop_vendor.glb` | same |
| 3D printer | "chunky low-poly cartoon large 3D printer with a meat hopper and output pad, comedic, flat colours, game asset" | 1,500 | `prop_printer_3d.glb` | same |
| Mutation machine | "chunky low-poly cartoon sci-fi booth with a glass door and DNA helix sign, flat colours, game asset" | 1,500 | `prop_upgrade_machine.glb` | same |

Every Meshy file gets a line in `docs/AI_CONTENT_LOG.md` (asset, tool, plan, date).

---

## e. Audio plan

### Audio rules (short)
- Every sound goes through the existing `event_sounds.tres` and surface types, so swapping a beep for a real sound
  is a file change, not code.
- One shared reverb feel with voice chat (20 ms pre-delay, room 0.55, damping 0.7) so the lab sounds like one place.
- Buses: Master > Music, SFX, Voice, UI. Loudness target around -16 LUFS for music, peaks under -1 dB.
- Formats: `.ogg` for music and long loops, `.wav` for short effects. Mono for anything positional.
- File names: `sfx_<thing>_<action>_<n>.wav` (`sfx_rat_bite_1.wav`), `music_<where>.ogg` (`music_zoology.ogg`).
- Folders: `assets/audio/sfx/<department or shared>/`, `assets/audio/music/`. Drop new files in
  `assets/_incoming/audio/`.

### What I can do for free
The mix (buses, ducking music under voice), placeholder replacement with CC0 packs (Kenney's audio packs and
CC0 files on Freesound; check each file shows CC0), footsteps per surface, impacts, UI clicks, the lift's rumble.

### Sound order list for you (one ElevenLabs month)
Free ElevenLabs accounts can't be used commercially. The cheapest paid plan (Starter) is listed at about $6 a
month with commercial use; check elevenlabs.io/pricing and its terms the day you buy, and whether sounds made
in that month stay licensed after you cancel. Generate everything in one month:
| Sound | Prompt | Length | File name |
|---|---|---|---|
| Rat squeak, bite, death | "cartoon rat squeak, short, comedic" / "small creature bite snap" / "cartoon squeak cut off with a pop" | 0.3–1 s | `sfx_rat_<action>_<n>.wav` |
| Kangaroo, bat, fly | "cartoon kangaroo grunt", "bat screech short", "buzzing fly loop" | 0.3–2 s | `sfx_<enemy>_<action>_<n>.wav` |
| Botany enemies | "carnivorous plant snapping shut, wet", "puffball releasing spores", "creaking vines" | 0.3–2 s | same pattern |
| Robotics enemies | "angry robot vacuum whirr", "small turret servo and laser zap", "drone propeller loop" | 0.5–3 s | same pattern |
| Bosses | roar, phase change, attack wind-up, death for each boss | 1–3 s | `sfx_boss_<name>_<action>.wav` |
| Machines | vending clunk and coins, printer whirr and ding, mutation booth zap, lift motor, lift arrival jolt | 1–4 s | `sfx_<machine>_<action>.wav` |
| PA announcer lines (text to speech) | about 20 dry, funny facility announcements from D5 ("Reminder: escaping is a fireable offence.") | 2–5 s | `vo_pa_<n>.wav` |
| Music (only if its licence covers games) | one tense-but-silly loop per department, a boss loop, a cosy Break Room loop, a menu theme | 1–3 min loops | `music_<where>.ogg` |
If the music licence doesn't fit, use CC0 music or a one-off purchase from a royalty-free library instead.

---

## f. Real-Steam test checklist (you and friends, real PCs)

Do these on two or more PCs with different Steam accounts, using a test build. Tick each box in the thread.
- [ ] Invite through the Steam overlay, and "Join game" from the friends list, both land in the Break Room.
- [ ] Rich presence shows "In the Break Room" / "Floor N, department" in a friend's list.
- [ ] Voice: delay feels under about a quarter of a second; the Fly voice is buzzy and still understandable.
- [ ] Voice through a closed door is muffled; far voices fade.
- [ ] 3 and 4 PCs: everyone sees and hears everyone (server relay on), no rubber-banding when running and hopping.
- [ ] Pass a crate back and forth; two people lift the counterweight; push a cart into the lift.
- [ ] A friend joins **mid-floor**: they watch as a ghost and spawn on the next floor.
- [ ] A client quits mid-floor while carrying a lift part: the part comes back.
- [ ] **The host quits mid-floor:** every client returns to the menu with a message, nobody crashes.
- [ ] Die, get reprinted with meat, keep mutations; team wipe ends the run.
- [ ] Beat a boss; the whole team rides on.
- [ ] Achievements pop on Steam (needs the real App ID).
- [ ] Cloud save: unlock a cosmetic on one PC, see it on another PC with the same account.
- [ ] 8 players (if you can gather them): voice quality, host upload, frame rate. Optional for 1.0.
- [ ] A modest PC (for example an older GTX 1060-class card, 8 GB RAM) holds 60 frames per second at 1080p medium.

---

## g. Release checklist

- [ ] Name check: search Steam and the web for games already called "Lab Escape" before paying for the page
      (decision D9).
- [ ] Steam Direct fee paid, App ID set in GodotSteam and `steam_appid.txt` (decision D8).
- [ ] Store page: description, tags, system requirements, 5+ screenshots, trailer, capsule images in Steam's
      required sizes, "Coming soon" up early to collect wishlists.
- [ ] **AI-content disclosure** on the Steamworks content survey, written from `docs/AI_CONTENT_LOG.md` (which tools,
      which assets). The game creates no AI content while it runs.
- [ ] Every AI tool's licence checked for the plan used, and saved as a note in the log.
- [ ] Credits screen and `docs/CREDITS.md`: Godot (MIT licence notice), GodotSteam (MIT), CC0 packs (optional
      thanks), Meshy and ElevenLabs if used, Mixamo, friends who playtested.
- [ ] Achievements created in Steamworks, matching `content/achievements/`.
- [ ] Steam Cloud set up for the profile file (`user://profile...`); settings stay local.
- [ ] Performance check on a modest PC (section f). Graphics settings (shadows, fog, render scale) work.
- [ ] Export presets leave out `tests/`, `addons/gut` and debug-only tools; cheats off in release.
- [ ] Release build uploaded with SteamPipe to a beta branch, played by friends, then set live.
- [ ] Pricing, release date, and the Steam review time planned in.
- [ ] A short bug-report route for players (Steam discussions) and telemetry off by default.

---

## h. Decisions for you (at most 10)

**Answered 2026-11-11 (Zachary):** D1 to D7 and D10 approved as recommended. D8 and D9 are on hold until he says so. The WP5 HUD mock-up is approved. D1 (run length) is set by the floor generator thread in its step 6 pass, not here.

| # | Decision | My recommendation | Why |
|---|---|---|---|
| D1 | Run length | **12 floors, boss every 4th** (bosses on 4, 8, 12) | About an hour; the ending gets tested; it's two numbers you can raise later. |
| D2 | Players at launch | **1 to 4 advertised**, 8 kept as an untested-in-public option | You can't prove 8 alone, and the game is tuned for 4. |
| D3 | Scope cuts | **Accept the cut list in section a** (crane game and Marine Biology to Update 1) | Saves roughly 15 to 20 sessions before launch. |
| D4 | New upgrades | **Plant mutations:** Photosynthesis (heal slowly in light), Thorns (melee attackers get hurt), Spore Cough (voice gets a raspy effect; your cough makes enemies sneeze and stop), Vine Arm (pull a prop to you from range). **Cybernetics:** Magnet Hand (gems fly to you), Spring Legs (big fall immunity and a stomp), Night-Vision Eye (see in dark damaged rooms). | Each one is a new combination of existing effect pieces except Vine Arm and Magnet Hand, which reuse the punt arm's pull. |
| D5 | Premise and tone | **You're the night-shift interns.** A cost-cutting "Lab Assistant AI" printed staff from meat to save money, the experiments got loose, and the only way out is the broken cargo lift to the surface. The PA keeps reading cheerful corporate notices. Ending: the lift bursts into daylight in the car park. | Explains the 3D printer reprints, the meat, the lift and the comedy in one go, and it's cheap to tell (text, signs, PA lines). |
| D6 | Cosmetic unlocks | **6 starter items, 3 for runs escaped (1, 3, 10), 1 per boss beaten, 2 from achievements** | Easy to follow, gives every boss a reward. |
| D7 | Paid tool months | **One Meshy month after the look target is approved, one ElevenLabs month after the art rollout.** Free CC0 and my own work until then. | Each month is planned and batched; nothing is paid for before you've seen the style. |
| D8 | When to pay the Steam Direct fee (about $100) | **When the look target is approved** | You need the App ID for achievements, cloud saves, playtests and a "Coming soon" page that collects wishlists. |
| D9 | Name | **Do a name check now**, keep "Lab Escape" if it's clear, otherwise pick a subtitle ("Lab Escape: Night Shift") | Short generic names are often taken on Steam, and changing later is painful. |
| D10 | Friendly fire | **Keep today's default:** no melee friendly fire, thrown objects and fire do hurt teammates | It's funny, it rewards care, and the code already works that way. |

---

## i. Working rules (every session follows these)

- Follow `CLAUDE.md`. One branch per work package (`wp/<number>-<short-name>`); a package that builds on an
  unmerged one stacks on its branch. **Commit locally only. Never push or merge until Zachary types
  "push and merge <name> into main".**
- Never delete, skip or weaken a test. Run the whole suite before calling a package done, and report the pass
  count and any errors or warnings in the Output log honestly.
- Static typing everywhere. Tuning numbers go in config files, never in code. New content must be new data files,
  not new code, wherever a building block already exists.
- Every feature must work for a host, a client and a late joiner. Test with 2 local windows.
- **Show Zachary a diagram, mock-up or screenshot plan before any change to how the game looks, and wait for his OK.**
- Money: about $20 a month for Claude and nothing else by default. Plan paid tools one month at a time and batch the
  work. Ask before anything costs money. Free CC0 packs are fine where they fit the style.
- Before using any tool's output, check that tool's current licence for the plan in use. Log every AI-made asset in
  `docs/AI_CONTENT_LOG.md`. Never prompt for existing characters or brands. Keep `docs/CREDITS.md` up to date.
- If Blender or its MCP isn't installed, give the install steps as one small step.
- After each package: a short plain-language note (what changed, how to test it in the game, what's needed from
  Zachary) and update its status box here.
- Ask only when a choice changes the game's design, costs money or can't be undone. Otherwise choose, say what was
  chosen, and keep going.
- **Don't change `systems/level_gen` or `config/floor_gen_tuning.tres`** while the floor generator's step 6 tuning
  pass is open in its own thread. Write needs from level_gen here instead (see below).

### Needs from level_gen (for the step 6 thread, not changed here)
- Botany and Robotics will need `enemy_spawn` markers that suit stationary enemies (turrets, flytraps): a wall or
  corner spot with a view down a room.
- A `task` marker in some medium rooms for the hamster wheel (WP15).
- Boss arenas per department (Botany and Robotics boss floors are off today).
- The Zoology "broken skylights and dark corners" damage look (with art).
- Lift parts per floor reach 5 by floor 10 in the scripted run. That may be a lot for 1 or 2 players; worth
  checking in the tuning pass against the player count.

---

## How the audit was done (2026-11-11)
- Read `CLAUDE.md`, `docs/ARCHITECTURE.md`, `BUILD_ORDER.md`, `ADDING_CONTENT.md`, every spec's Handoff, Stubbed,
  Not done and Open design questions, the floor generation plan, the HL2 feel plan, the brainstorm, the design
  decisions (with its numbered gaps), the step 5b report and both test-build notes. The tech research PDF can't be
  read on this PC (no PDF text tool); its summary in the project notes was used.
- Counted content and code: 27 systems with code, 5 empty (objectives, cosmetics, save_load, achievements,
  telemetry); 4 enemies, 1 boss, 5 mutations, 2 cybernetics, 6 items, 2 status effects, 31 props, 55 rooms,
  3 departments (Botany and Robotics use Zoology's enemies, loot, stock and boss; their boss floors are off, so all
  boss floors are Zoology's Giant Rat); no files in `assets/models`, `textures`, `audio` or `fonts`.
- Full GUT suite on `main`: **583 of 583 pass** (55 scripts, 508 s). Output noise: 79 "Attempt to call RPC with
  unknown peer ID: 7" errors, all from `tests/unit/player/test_speed_check.gd` (its fake client peer), 1 orphan node
  in `test_damage.gd`, and Godot's usual leak report at exit. The expected "floor 6 seed 777 used the safe fallback
  floor" warning comes from a level_gen test that checks the fallback.
- Played in the editor: main menu, Host local, the Break Room (grey box, closet placeholder), the tile gallery.
  The main menu and Break Room have no errors in the log.
- Scripted run (headless, through public APIs): **all 18 floors loaded and played through on the host**, floor 1
  to the escape and back to the Break Room in about 5.5 minutes of lift rides (about 8 s per ride). Every floor got
  enemies and lift parts (1 part on floor 1, rising to 5 by floor 10); boss floors 6, 12 and 18 were all the Giant
  Rat, and killing it moved the run on; a death on floor 2 was undone by the solo free reprint. Two warnings came up
  on floor loads: the navmesh bake reads visual meshes (a slow path that can cause a hitch) and "navigation region
  synchronization had 2 edge errors". The client half of that script didn't connect (a quirk of running Godot
  with `--script`, which compiles some classes before the autoloads exist), so a proper host-plus-client version
  is WP1's first job, inside GUT where the autoloads are real.
