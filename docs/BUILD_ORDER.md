# Build order

The order to build Lab Escape's systems, split into phases. Each system is built in its own Claude
Code session with Prompt 2 ("build one system"), on its own branch, then merged with Prompt 3.
People are called **A**, **B** and **C** below: decide who is who. Sizes: S = a few days,
M = a week or two, L = several weeks, for a beginner working with Claude Code.

**The rule that makes parallel work possible:** if a system you need isn't merged yet, build against a
**stub** (a small fake with the same functions, described in your spec's "Dependencies and stubs").
Swap the stub for the real thing at merge time.

## Phase 0: setup (everyone, 1 to 2 days)
Versions checked on 2026-10-07:
1. Install **Git for Windows** (git wasn't found on Zachary's PC) and make sure `git --version` works.
2. Optional but recommended: update everyone to **Godot 4.7.2** (bug-fix release; same project format).
3. Install **GUT 9.7.1** (the version made for Godot 4.7) from GitHub, `bitwes/Gut`, release tag
   `v9.7.1`: copy its `addons/gut` folder into the project and enable the plugin. **Don't use the
   AssetLib tab for GUT**: it only offers 9.6.1, which is the Godot 4.6 version. Run the two tests in `tests/`.
4. Install **GodotSteam GDExtension 4.4+** (version 4.23 or newer, by Gramps, MIT) from Godot's
   AssetLib tab. It already includes `SteamMultiplayerPeer` (since 4.17) and the voice functions.
   Don't mix it with GodotSteam's pre-compiled editors. Put `steam_appid.txt` containing `480` in the
   project folder (or set the app ID in GodotSteam's project settings) and keep Steam running while testing.
5. Optional: the **Godot AI** MCP (`hi-godot/godot-ai`, free, MIT) so Claude Code can work in the live
   editor (build scenes, run the game, take screenshots, read errors). Needs `uv` installed. It sends
   anonymous usage telemetry unless you set `GODOT_AI_DISABLE_TELEMETRY=true`.
6. Commit the foundation to `main` (it's already written and checked).
7. Each person opens the project, runs it, and runs the tests. Agree who is A, B and C.

## Phase 1a: the risky proofs first (3 tracks in parallel)
Goal: find out early whether the three hardest things work, before building anything on top of them.

| Track | Who | Systems in order | Milestone |
|---|---|---|---|
| Networking + Break Room | A | steam_session (M) → net_core (M) → player, walking only (part of L) → break_room grey box (S) → ui main menu with Host/Join (part of L) | **2+ players join over Steam into a grey-box Break Room and walk around together.** |
| Voice proof | B | voice (L, proof part): mic → own bus → pitch effect with loopback, then Steam voice between 2 PCs; a debug key applies a test `VoiceEffectData` (Fly voice) | **On 2 Steam PCs, one player's voice sounds like Fly to the other, from that player's position.** |
| Physics grab proof | C | interaction (S) → physics_props (L, proof part) with a stub player, first offline, then networked with local ENet, then Steam | **Two players pass one box back and forth; it feels instant for the holder and smooth for the watcher.** |
| Tools | whoever finishes first | debug_console (S) | `spawn`, `list`, `validate` work. |

Tracks B and C start with local tests and use A's `SteamSession.host_local()` once it exists (or a
5-line ENet setup in their test scene until then). They switch to real Steam when A's track is merged.

**Phase 1a review (all together):** play the three proofs on real Steam with 2 to 4 PCs. Decide
physics approach A or B (see physics_props spec), check voice delay, and confirm client-owned
player movement. If something fails, fix the plan before Phase 1b.

## Phase 1b: the Zoology vertical slice
Goal: **Break Room → elevator → 5 Zoology floors + Giant Rat boss**, with gems, a vendor, meat and
3D printer reprints, a cart, mutations, and one debug-spawned robot part. Playable by 1 to 4 players on Steam.

| Person | Systems in order (each waits only on the ones before it, or stubs) |
|---|---|
| **A** | game_flow (M) → level_gen (L) → cargo_lift (M) → ui HUD basics (part of L) |
| **B** | damage (M) → items (M) → enemies with the 4 Zoology enemies (L) → bosses with the Giant Rat (M) → audio (S) |
| **C** | inventory (M) → physics_props finished (rest of L) → upgrades (L) → loot (M) → vendors (M) → death_respawn (M) → carts (M) |
| Anyone | settings_input (S), voice finished (rest of L), player movement modes (rest of L) |

Can run in parallel at the start of 1b: game_flow, damage, inventory, settings_input, level_gen.
Needs others first: items (inventory, damage), upgrades (inventory, damage stats, voice, physics_props),
loot (physics_props), vendors (loot's gems, items), death_respawn (damage, inventory, physics_props),
carts (physics_props), cargo_lift (level_gen markers, physics_props), enemies (damage, level_gen nav),
bosses (enemies).

**Content for the slice** (anyone, using `docs/ADDING_CONTENT.md`; grey-box art is fine):
- `department_zoology` with about 8 rooms (start, lift, corridors, a supply room, a boss arena).
- Enemies: `enemy_rat`, `enemy_kangaroo`, `enemy_bat`, `enemy_fly`. Boss: `boss_giant_rat`.
- Items: `item_fists`, `item_crowbar`, `item_knife`, `item_potted_plant`, `item_energy_drink`, `item_hot_coffee`.
- Mutations: at least `mutation_fly`, `mutation_frog`, `mutation_octo` (Slug and Giraffe if time allows).
- Cybernetic: `cybernetic_test_arm` on `prop_robot_part` (debug-spawned: `spawn cybernetic_test_arm`).
- Props: `prop_gem` (value 1), `prop_gem_large` (value 5), `prop_gem_glowing`, `prop_meat`,
  `prop_lift_part_zoology`, `prop_cart_standard`, `prop_crate`.
- Statuses: `status_burning`, `status_speed_boost`. Loot tables and `stock_zoology` vendor stock.

**Integration milestones** (merge often, play together after each):
1. One generated floor: walk from the start room to the lift, lift goes up to floor 2.
2. Combat: hit rats, they drop gems and meat; buy a crowbar at a vendor.
3. Upgrades and death: eat a glowing gem (Fly), die, get reprinted with meat, still a Fly.
4. Carts carry gems through doors and in the lift.
5. Five floors and the Giant Rat; back to the Break Room after a win or a wipe.

**Phase 1 is done when** 2 to 4 friends on Steam can play the slice start to finish, and the content
validation test passes.

## Phase 2: launch content and the rest of the systems
| Area | Systems / content | Parallel? |
|---|---|---|
| Departments | Botany (ent, flytrap, vines, spore shooter, Mushroom Man) and Robotics (roombas, turrets, flock cameras, drones, Robobrain); rooms, loot, stock. Mostly **content**; new enemy behaviours and boss attacks where needed. | Yes: one person per department |
| Objectives | objectives (M): keycards, hamster wheel, crane game | Yes |
| Looks and saving | save_load (S), cosmetics (M), break_room closet and art, ui closet screen | Yes, one person |
| Steam | achievements (S), rich presence polish, reconnects mid-run | Yes |
| Playtest tools | telemetry (S) | Any time |
| Polish | ui full pass, settings and accessibility, laser pointer (new item behaviour), more mutations, art pass (Meshy, Blender, Mixamo), sound (ElevenLabs) | Yes |
| Scale | Test with `max_players = 8` (local instances, then real PCs): voice load, host bandwidth, difficulty, tasks | Together |

## Phase 3: release and updates
- Steam App ID (Steam Direct fee), store page, **AI-content disclosure** (from `docs/AI_CONTENT_LOG.md`),
  real achievements, Steam Cloud for profiles, performance pass, public playtests with telemetry.
- **Update 1: Marine Biology.** This should be content only (a department folder plus new enemies,
  rooms and a boss). Any code change it needs is a sign a system broke the "add files, not code" rule.

## Who can work at the same time (summary)
- Phase 1a: 3 tracks fully parallel (networking, voice, physics), joined at the review.
- Phase 1b: 3 lanes (A: flow, levels, lift; B: combat, enemies, boss; C: inventory, physics, upgrades,
  economy, death, carts) with content made by anyone in between.
- Phase 2: almost everything is parallel, because most of it is new content.
