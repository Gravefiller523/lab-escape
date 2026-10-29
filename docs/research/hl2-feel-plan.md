# Making Lab Escape feel like Half-Life 2: research and plan

Status: **draft, waiting for Zachary's approval.** Nothing in the game has been changed yet.
Date: 2026-10-29. Covers Godot 4.7, GDScript, Jolt physics, host-authoritative co-op.

## Decisions (Zachary, 2026-10-29)
These override the recommendations further down where they differ.
1. **Air strafing / bunny hopping: full Source-style speed building.** No speed guard (`air_max_speed_factor` is effectively off). A landing jump on the exact landing tick skips friction, as in Source. Still not copied: ABH (the backwards-hop bug) and auto-hop when jump is held. The host speed check must be changed so fast bunny hoppers are not pulled back (see risks).
2. **Gravity 15.2 for the player and the world, jump height 0.9 m, crouch-jump on.**
3. **Collisions: do what HL2 does** (pending Zachary's confirmation). Props are solid to players. Light props get nudged when you walk into them and heavy ones block you. You can stand on props. Held props stay solid but weigh 1 kg while held, so they can't shove you, and standing on one drops it. That is the current spec, so the held_props layer change (step 2.3) is dropped. Players stay solid to each other. HL2 is single-player, so it has no rule for that.
4. **Throw force: 25.4 (HL2).**
5. **No sprinting while carrying (HL2).**
6. **Closest to HL2:** default FOV 74 vertical, which matches today's HL2 default of 90 on 4:3 (about 106° wide on 16:9). Default mouse 0.066°/pixel, the same as Source's default sensitivity of 3. View bob and strafe roll are **off by default**, like HL2, and can be turned on with tuning. The landing punch stays because HL2 has it.
7. **Gravity-gun punt: yes, as a later cybernetic upgrade.** Not in the base game. Built after step 2, when the upgrade system can unlock it.
8. **Nobody can pick up a prop that any player is standing on.** This stops "prop surfing" and launching a teammate by grabbing the crate under them. HL2 only stops *you* lifting what *you* stand on; we extend it to every player. The host checks it when deciding a grab (step 2, in the grab rules), and a prop someone steps onto while it is held is dropped, as now.

How this was made: one agent took an inventory of the project. Seven research agents then looked into (1) how Source movement works, (2) Godot character controllers, (3) HL2's props and pickup, (4) Godot physics settings, (5) NPC AI, (6) interaction and sound, and (7) how to organise the project. This file combines their findings. Links are at the end.

> **About Valve's code.** Some agents read Valve's wiki and the Source SDK to learn *numbers and behaviour*. The SDK's license only allows use inside the Source engine, so none of its code will be copied or adapted. Everything we build will be our own GDScript written from plain-language descriptions. The same applies to open-source Godot movement projects that look like ports of Quake or GoldSrc code (for example pmove-godot and GoldGdt). We can learn ideas from them but we won't copy them.

---

## Quick glossary

| Word | Plain meaning |
|---|---|
| **Tick** | One step of the physics simulation. Ours runs 60 times a second. |
| **Hammer unit (u)** | Valve's unit of length. For the player body, 1 u is about 1 inch (2.54 cm). HL2's player is 72 u tall, which matches our 1.8 m capsule. |
| **Acceleration / friction** | How fast you speed up when you press a key, and how fast you slow down when you let go. |
| **Air control / air strafing** | Steering while in the air. "Air strafing" is a Source trick: turning the mouse while holding a side key curves you and can build up speed. |
| **Bunny hopping (bhop)** | Jumping again the instant you land so friction never slows you, keeping or building speed. |
| **Coyote time** | A short grace period after walking off a ledge during which you can still jump. |
| **Jump buffer** | If you press jump slightly *before* landing, the game remembers it and jumps the moment you touch down. |
| **Step-up / stair stepping** | Walking up small ledges and stairs without jumping. |
| **Floor snap** | Pulling the player down onto the floor when walking downhill or down stairs so they don't "float" off each step. |
| **View bob / roll / punch** | Small camera movements: bobbing up and down while walking, tilting sideways when strafing, and a jolt when landing hard. |
| **Shadow control** | HL2's way of holding objects: every tick it sets the object's speed so it reaches the hold point, with limits. We already do this. |
| **Host-authoritative** | The host's PC has the final say on anything that matters (damage, deaths, who holds what). |
| **Owner** | The PC that runs the physics of something. Each player owns their own body; whoever holds a prop owns that prop. |
| **FSM (state machine)** | An enemy is always in one "state" (idle, chase, attack...) and switches between them by rules. Our enemies already work this way. |
| **Navmesh** | An invisible map of walkable floor that enemies use to find paths. |
| **Resource / .tres** | A Godot data file you can edit in the Inspector. Our tuning lives in these. |

---

## 1. What HL2 does, and why it feels that way

### 1.1 Movement and controls
- **Snappy start, crisp stop, momentum in the air.** Every tick Source runs three small functions: *Friction*, then *Accelerate* on the ground (or *AirAccelerate* in the air).
  - Accelerate adds speed in a straight line until you reach the speed cap, then stops adding. You hit full speed in about 0.13 s.
  - Friction removes speed quickly at high speed, and below a "stop speed" it removes a fixed amount, so you come to a dead stop instead of drifting. From a run, the whole stop takes about 0.4 s.
  - In the air nothing slows you down. Letting go of the keys doesn't brake you, so a jump keeps its momentum. Pressing a side key bends your path.
- **Numbers (HL2 defaults, converted at 1 u = 2.54 cm):** normal run 4.83 m/s, slow walk 3.81, sprint 8.13 (limited by suit power), crouch about 1.6. Gravity 15.2 m/s². Standing jump only about 0.53 m high; crouch-jumping clears about 1.4 m. Step height 0.46 m. Walkable slopes up to about 45°.
- **Crouch-jump.** Crouching in mid-air pulls your legs up (the body shrinks from the bottom), so you clear higher ledges.
- **The camera barely moves.** HL2 has no camera bob and no strafe roll. "Walking feel" comes from the weapon swaying on screen and footstep sounds. The camera only jolts on hard landings (falls of about 2.6 m and up) and when hurt.
- **Narrower field of view.** HL2 originally showed 75° horizontal on 4:3 screens (about 60° vertical). Godot's FOV number is *vertical*, so our default of 85 is about 117° horizontal on a 16:9 screen, which is much wider than HL2 and makes everything feel faster and more distorted.
- **Mouse.** Raw mouse input, no smoothing, no acceleration.

### 1.2 Physics props, pickup and throwing
- **Holding (+use).** Max 35 kg and 3.25 m in size. The object is held about 1.2 m in front of you plus its own size, moved by shadow control (max 25 m/s, max 3,600°/s spin). While held, its mass is set to 1 kg and its spin is heavily damped, so it can't shove you around. It drops if it gets about 30 cm away from where it should be (with a 1 s grace period after pickup) or if you stand on it.
- **Small touches that make it feel solid:** the held object's spin is throttled while it touches a wall, so it doesn't jitter; its movement slides along walls; it snaps to a tidy angle when picked up if it's nearly straight; you can't sprint while carrying; held objects do no damage (no ramming).
- **Throwing.** Throw strength is a fixed push scaled by a weight factor, so light objects fly fast and heavy ones lob. Release speed is capped at 1.5 × run speed before the throw is added. All objects are capped at about 51 m/s.
- **Gravity gun.** Punt (launch whatever you aim at within about 6 m), pull from up to about 25 m, hold objects up to 250 kg.
- **Impact damage.** Damage depends on how much kinetic energy was lost in the hit compared with the victim's mass, looked up in a table. Objects under 2 kg do no damage. A thrown 10 kg crate kills a small enemy but bounces off a big one. The player who last touched the prop gets the credit.
- **Breakables, sounds, ragdolls.** Props can have health and break into pieces. Impact sounds start at about 1.8 m/s, are full volume at 8 m/s, and at most one plays per object every 50 ms. Scrapes are looping sounds. Enemy ragdolls and gibs are cosmetic, simulated separately on each PC.

### 1.3 NPC behaviour
- **Senses → conditions → schedules.** NPCs see (with a view cone and range), hear (gunfire, impacts, footsteps each have a radius), remember where they last saw you, and choose a "schedule" (a short plan like *find cover, run there, reload*). A schedule only changes when it finishes or something important interrupts it, so NPCs commit to actions but still react.
- **Squad slots.** Only a couple of enemies attack at once; the rest circle or flank. This keeps fights readable and fair.
- **They announce intent.** Wind-ups, barks and sounds tell you what's coming, so predictable behaviour reads as intelligence.
- **Closest matches to our animals:** headcrabs (leap attacks, ambushes from hiding), zombies (slow groups that shove props), antlions (swarms that react to sounds).

### 1.4 Interaction and world
- Short use reach (about 2 m), a "denied" buzz when you can't use something, doors that swing away from you and reverse when blocked, buttons and triggers wired together with "when this happens, do that" connections (Valve's I/O system).

---

## 2. Each system: current state → what to change → how to do it in Godot

### 2.1 Player movement (`systems/player/`)

**Current state**
- `CharacterBody3D` with `move_and_slide()`, default floor settings (floor snap 0.1 m, no stair stepping).
- Speeding up and slowing down use a smooth "lerp" toward the target speed (ground 12, air 3). This is why it feels floaty-smooth: the speed eases in, eases out, and **in the air, letting go of the keys brakes you**.
- Walk 4.5, sprint 7.0 (forward only), crouch 2.5 m/s. Player gravity 20, but props and enemies use 9.8. Jump height 1.1 m.
- Jump presses are lost if they land even one tick before you touch the ground (no jump buffer, no coyote time). You can't jump while crouched. No crouch-jump.
- Movement modes (Fly hover, Frog hop, Octo wall climb, Slug slide, ladders) are separate files that extend the walk mode and change small "hooks": `_speed`, `_grip`, `_jump_speed`, `_jump`, `_fall`, `_after_move`. This is a good design and the plan keeps it.
- Your own body is simulated on your own PC (client-owned). The host checks you're not moving impossibly fast and pulls you back if you are.

**What to change**
1. Replace the lerp with Source-style **friction + accelerate + air-accelerate**, written by us as three small helper functions in `walk_mode.gd`. Keep all the mode hooks working:
   - `_grip` keeps its meaning ("lower = slippery") and now scales both acceleration and friction. Slug's 0.2 grip then gives a long glide automatically.
   - Hover and Hop keep their air-control multipliers.
2. **Air strafing that curves but doesn't gain speed.** You can steer in the air and keep momentum, but a "speed guard" stops air strafing or bunny hopping from making you faster than your mode's top speed. This protects the host's speed check and stops co-op groups getting split up. Frog leaps and Slug slides that are *already* fast keep their speed. A future "bhop" mutation could raise the limit with one number.
3. **Jump buffer (0.1 s) and coyote time (0.1 s).** Fixes lost jumps. Friction still applies on the landing tick, so the buffer can't be used for free bunny hopping. Jumping again needs a fresh press (no auto-hop when held).
4. **Allow jumping while crouched, and add crouch-jump.** In the air, crouching shrinks the capsule from the bottom and lifts the body by the same amount over about 0.1 s, so your eyes stay put and your feet rise. Smoothed, not instant, to avoid the camera popping and sync glitches Valve had.
5. **Stairs and slopes.** Add a small `StairStepper` helper that, after `move_and_slide()`, tests "move up 0.4 m, move forward, move down" against the real capsule shape (`PhysicsServer3D.body_test_motion`). It only steps onto world geometry, not props. Set floor snap to 0.4 m so walking down stairs stays grounded. Smooth the camera after each step so it doesn't pop. Set the other body settings once at spawn (table in section 4).
6. **Stop props launching the player.** Remove props and held props from the player's "platform floor layers", so a moving crate never carries or flings you. This is a known Jolt problem reported on Godot 4.6.1.
7. **Pushing props in script.** After `move_and_slide()`, push props you walk into with a small impulse along the ground (capped at about 30 kg worth of push), matching the current 0.9 × walk speed push.
8. **Retune numbers toward HL2** (see the table in section 4): run 4.8, sprint 7.5, crouch 1.9, gravity about 15 for *both* the player and the world, jump about 0.9 m.
9. Small fixes: apply mouse yaw to the body inside the physics tick (not in the input handler) to avoid rare jitter, use `screen_relative` for mouse motion, and require Godot **4.7.2 or later** (it fixes high-polling-rate mice on Windows).

**Multiplayer notes**
- Movement stays client-owned. The only host-side change is the speed check: it must know about the new top speeds, the air-speed guard, and carts carrying a player.
- Step-ups move you up to 0.4 m in one tick. The host check is horizontal only, so this is fine, but it needs a test.

### 2.2 Camera and mouse

**Current state:** the camera follows the smoothed (interpolated) body position, with mouse look applied directly. This is the correct Godot pattern and stays. No bob, no roll, no landing effects. FOV 85 (vertical), mouse 0.25° per pixel. Settings already has "camera shake" and "reduce motion" options that nothing uses yet.

**What to change**
- Add a small `CameraFeel` node on the local camera only (never synced). It adds:
  - **Landing dip and punch:** a small drop (up to 12 cm) on every landing and a pitch jolt (up to 6°) on hard landings, springing back in about 0.3 s.
  - **Subtle view bob** (about 1 cm) and **strafe roll** (about 0.75°). HL2 has neither, but it relies on a swaying weapon model and footsteps, which we don't have yet. These are off-able and set low.
  - **Step smoothing** for stairs.
  - Optional sprint FOV kick (off by default, HL2 doesn't have one).
- All of it is scaled by the **camera shake** setting and switched off by **reduce motion**.
- **FOV default 70 (vertical)**, which is about 102° horizontal on 16:9. Show the horizontal number in the settings slider so it matches what players expect from other games.
- **Mouse default about 0.066° per pixel**, which equals Source sensitivity 3. The current 0.25 equals Source sensitivity 11, which is very fast. Players who already saved a setting keep theirs.

### 2.3 Footsteps and landing sounds (`systems/player/`, `systems/audio/`)

**Current state:** none. All sounds are generated placeholders.

**What to change**
- Add a `SurfaceType` data file per material (concrete, metal, tile...) with step, land, soft-impact, hard-impact and scrape sounds, and its speed thresholds. Adding a material = adding a file.
- `FootstepAudio` on each player: a step plays every 1.7 m walked (2.1 m sprinting, 1.2 m crouched), alternating left and right, plus landing and jump sounds. Volume depends on stance and fall speed.
- Every PC works out footsteps for every player from the synced movement, so nothing extra goes over the network.
- Change `Sound.play_3d` so when all 32 sound players are busy it drops the quietest sound, not the oldest, and add a global limit (6 impacts per 0.1 s).

### 2.4 Physics props, pickup and throwing (`systems/physics_props/`)

**Current state:** already close to HL2. Velocity-driven holding with a 1 kg held mass and spin damping 10, co-op heavy lifting (each helper supplies 30 kg), throw formula with HL2's weight factor, swept collision on, and a clever network model where the holder's PC runs the prop. Missing: impact damage, impact sounds, breakables beyond the fragile vacuum tube, ragdolls, and the small "solid feel" touches.

**What to change**

*Quick fixes*
- Jolt silently caps spin at 47 rad/s, so our 62.8 rad/s hold spin is never reached. Raise Jolt's `max_angular_velocity` to 62.83.
- Release cap 10.5 → about 6.75 m/s (1.5 × walk speed, as HL2).
- Throw force 34 → **25.4 (HL2) to 30**. Ours is 34% stronger than HL2; your call (see open questions). Cap all props at 50 m/s.
- While holding: no sprinting (HL2 rule), and the held prop never falls asleep (a sleeping prop can freeze in your hands).
- A plain drop while the prop touches something clears its speed (stops "drop-flinging"). Throws keep their speed.

*Hold polish (the big feel gain)*
- Move the hold code into the prop's `_integrate_forces` so it can see what it's touching each tick. Then:
  - throttle spin while touching walls or heavier things (no jitter against walls),
  - slide along walls instead of bouncing off them.
- Hold distance based on the prop's size along your view (about 1.2 m + its depth), pushed outside your own capsule.
- Snap to a tidy angle on pickup if within 30°. Optional per-prop "preferred carry angle" in `PropData`.
- Drop rule: a smoothed "how far off target" error above 0.45 m (looser than HL2's 0.3 m to allow for network lag), with 1 s grace after pickup. Only for fully lifted props, so co-op heavy lifts don't drop too easily.
- Grab a little more forgivingly: if the thin aim ray misses, accept a prop within a narrow cone.
- Use the **held_props layer** (it exists but nothing uses it). Recommended: players don't collide with held props, so nobody can "prop-fly" by standing on one and held props can't shove teammates. This changes the current spec rule ("held props stay solid to the holder"), so it is an open question below.

*Impact damage* (new)
- The PC that runs the prop detects hits (it has the real contacts) using the HL2 method: speed lost × mass compared with the victim's mass, looked up in a damage table. Each enemy and the player get an `impact_mass` (rat 5 kg, kangaroo 50, giant rat 300, player 85).
  - Example: a 10 kg crate thrown at 7 m/s into a rat does 50 damage (dead); the same throw does nothing to a kangaroo.
- The owner sends `report_impact` to the host. **The host validates and applies the damage** (owner check, distance check, speed cap, 0.25 s cooldown per pair) and credits the last player who held it.
- Held props do no damage. Objects under 2 kg do none either. Teammates take reduced damage (a "friendly physics damage" scale).
- We use speed change, not Jolt's contact impulse, because Jolt's impulse numbers are only estimates when several things touch.

*Impact sounds* (new)
- Silent below 1.8 m/s, full volume at 8 m/s, at most one per prop every 50 ms, soft or hard sound chosen by surface. Scrapes and rolls are looping sounds that follow sliding or spinning speed.
- Only the owner sees real contacts, so the owner adds a tiny "impact" event to the prop updates it already sends, and other PCs play the sound when it arrives. Pickup plays a soft impact sound, as in HL2.

*Breakables* (generalise "fragile")
- `PropData` gets `health`, `break_scene`, `impact_damage_scale` and optional explosion values.
- The host decides when something breaks and tells everyone. Each PC spawns the pieces locally on a new **debris** layer that only hits the world. Pieces fade after 5–8 s, with at most 64 at once.

*Held items* (`systems/items/`)
- Thrown inventory items (coffee, potted plant) currently check for hits once per tick without sweeping, so fast throws can pass through enemies. Route them through the same impact-damage path or a shape-cast sweep.

*Later, optional:* a gravity-gun style **punt** as a cybernetic upgrade (6.35 m range, 0.5 s cooldown, launches props at about 15 m/s plus extra for light objects).

### 2.5 Physics settings and collision layers (`project.godot`, `core/physics/`)

**Current state:** Jolt, 60 Hz, interpolation on. Nine layers. Player gravity 20, world gravity 9.8.

**What to change**
- Keep 60 Hz. 120 Hz would double the physics cost for little gain with our networking.
- Set the settings in the table in section 4 (jitter fix 0, Jolt max speed 100 → 50 m/s for props, max spin 62.83, sleep threshold 0.05, penetration slop 0.01, world gravity 15).
- Turn swept collision **off** for slow heavy props (heavy crate, counterweight, cart) to save work. Keep it on for light ones.
- Keep layers 1–9 as they are (scenes store them as numbers, so renumbering would break things). Add:
  - **10 debris** (gibs, only hits the world),
  - **11 ragdolls** (corpses, don't block players),
  - **12 player_clip** (invisible walls for players only),
  - **13 npc_clip** (invisible walls for enemies only).
- Build each room's floor and walls as one body with several box shapes, so rolling props and players don't catch on seams between separate floor pieces.
- For props imported from Meshy, use simple collision shapes (boxes and capsules first, then "Decompose Convex" with 4–8 hulls max). Never use a mesh-shaped (concave) collider on a moving prop.
- When a prop is removed, wake the props near it so stacks don't hang in mid-air (a known Jolt behaviour).

### 2.6 Enemies and AI (`systems/enemies/`, `systems/bosses/`)

**Current state:** a simple, tidy state machine that runs only on the host (idle, patrol, chase, swarm, attack, flee), plus jump-attack (kangaroo) and swoop (bat). Sight is a raycast every 0.2 s within 12–18 m. There's **no view cone and no hearing** (the docs say there are). The navmesh is baked for the whole floor in one go, which freezes the host briefly.

Bugs found:
- The attack cooldown is used up before checking range, so a missed attempt wastes it (`enemy.gd:252`).
- Chase and swarm follow the player's **live** position for 3 s after losing sight, so enemies can track you through walls. They should go to where they last saw you.
- Every enemy picks the nearest visible player, so one player gets mobbed while others are ignored.
- Swarm spacing checks every enemy against every other enemy every frame, which gets slow with big packs.

**What to change (keep the state machine; no behaviour-tree addon needed)**
1. **Fix the bugs above** (small).
2. **Perception:** add view cones (rat 140°, kangaroo 120°, bat and fly 360°, boss 160°) plus a short all-round "sense" range (2.5–4 m). Add a short "noticing" delay (0.3–0.6 s) with a squeak so players see and hear that they've been spotted. A central `PerceptionManager` runs at most 8–12 sight rays per tick, spread across enemies. Memory goes up to 5–6 s, then the enemy searches the last-known spot for 2–3 s.
3. **Hearing:** a `SoundBus` where noisy things report a position and radius: crouch step 2 m, walk 5, sprint 10, landing 7, prop impact 3–15 by force, door slam 12, enemy death squeal 15. Enemies get an **alert** state: walk to the noise, look around, then return to idle or attack.
4. **Interruptions:** states can be interrupted by events (took damage, heard a loud noise, lost target), except mid-leap.
5. **Fair co-op targeting:** score each visible player by distance and recent damage dealt, stick to the current target a bit, and **penalise players already being attacked by others**.
6. **Attack tokens** (HL2's squad slots): each player has a small number of "attack tickets" (2 for small biters, 1 for heavy leaps and boss slams). An enemy needs a ticket to start its wind-up; others circle at 3–5 m. This is the single best change for readable, fair fights.
7. **Telegraphs:** every attack gets a 0.3–0.5 s wind-up and a sound.
8. **Pack alert:** one rat that spots you alerts nearby rats within 12–15 m.
9. **Navigation:** bake the navmesh on a background thread (`bake_from_source_geometry_data_async`) with slightly coarser cells (0.3 m). Turn on Godot's built-in avoidance on the `NavigationAgent3D` (replacing the slow swarm spacing), with bigger enemies having priority. Add navigation links at ledges so kangaroos can leap across. Flyers follow the ground path at hover height instead of flying straight through walls.
10. **React to physics:** enemies dodge or flee from heavy thrown props, and prop impacts count as noises.
11. **Death:** cosmetic per-PC ragdolls or simple tumbling corpse bodies on the ragdoll layer, instead of tipping over 90°.

Multiplayer stays as it is: AI decisions on the host only, positions synced at 20 Hz. Tokens and hearing live only on the host and don't need syncing.

### 2.7 Interaction, doors and buttons (`systems/interaction/`)

**Current state:** a solid host-validated use system (look ray, prompts, hold-to-use). Missing: a "can't use" sound, continuous use (cranks), reach measured to a handle instead of the object's centre, a real door system, and a way to wire buttons to doors without code.

**What to change (later, after the three main areas)**
- Deny feedback, continuous-use mode, use points, and a slightly fatter aim check (a small sphere if the thin ray misses).
- A small "world I/O" kit: an `IOComponent` that lists "when *pressed*, call *open* on *that node*, after *0.5 s*", plus `WorldButton`, `WorldTrigger`, `Door` (swings away from the player, reverses when blocked), `Relay` and `Counter`. Only the host fires connections; clients copy the resulting door state.

### 2.8 Project organisation and testing

**Current state:** good bones. Strict typing, one `PlayerTuning` file, data files for content, and GUT tests that drive a real player with fake input. But feel numbers are spread across `PlayerTuning`, `GameConfig` and constants hard-coded in scripts (for example `MAX_HOLD_PITCH`, enemy `TURN_SPEED`, `TARGET_MEMORY`).

**What to change**
- **One place for all feel tuning** (you asked for this): a single `config/feel_tuning.tres` that you open in the Inspector. Inside it, four folding sections, each its own file so they stay manageable:
  - `player` → the existing `systems/player/player_tuning.tres` (movement, jumping, stairs, mutations), extended with the new values,
  - `camera` → new `CameraTuning` (FOV defaults, bob, roll, landing, step smoothing),
  - `props` → new `PropTuning` (hold, throw, impact damage, impact sounds, push). The ~12 grab and throw values move here from `GameConfig`,
  - `ai` → new `AiTuning` (cones, hearing, memory, tokens, turn speed).

  `GameConfig` keeps game *rules* (players, floors, loot). Per-enemy and per-item numbers stay in their content files.
- **Live tweaking:** debug console commands `tune player.walk_speed 5`, `tune_get`, `tune_save`, `tune_reload`, `tune_reset`, so you can change feel while the game runs (dev builds only).
- **Feel tests:** the accelerate and friction maths as pure functions with simple tests (time to full speed, stopping time). Simulation tests that check results in ranges (jump apex within 2%, step-up works at 0.2 and 0.4 m, a 0.5 m ledge blocks). One test that runs at both 60 and 120 Hz to catch frame-rate-dependent maths.
- Small cleanups: mark `MovementMode` and `EnemyState` as `@abstract` (Godot 4.5+), and add `Performance` monitors for awake props, enemies and network messages.

---

## 3. Implementation order

Effort is rough, in working sessions of about 1–2 hours each with Claude Code. **S** = 1 session, **M** = 2–4 sessions, **L** = about a week. Each step ends with a test **in the running game** (from the editor, not a build) before moving on. I'll only make a test build when you ask.

### Step 0: groundwork (S–M)
| # | Step | Effort | How to test |
|---|---|---|---|
| 0.1 | Create `config/feel_tuning.tres` with player/camera/props/ai sections; point existing code at it. No numbers change yet. | S | Game plays exactly as before; change `walk_speed` in the Inspector and see it take effect. |
| 0.2 | `tune` console commands. | S | Type `tune player.walk_speed 9` in the console and run fast. |
| 0.3 | Physics project settings (table in section 4, except gravity). | S | Throw gems at walls; spin a held crate; nothing tunnels or explodes. |
| 0.4 | Feel test harness (metrics printed per run). | S | GUT run prints time-to-top-speed, stop time, jump apex. |

### Step 1: movement and camera (first)
| # | Step | Effort | How to test |
|---|---|---|---|
| 1.1 | Source-style friction and accelerate on the ground. | M | Run and stop: snappy start, crisp stop, no drifting. Slug still glides. |
| 1.2 | Air accelerate with speed guard; jump buffer and coyote time; jump while crouched. | S–M | Jump and let go: momentum carries. Strafe in air: path curves, speed doesn't grow. Press jump just before landing: it jumps. Walk off a ledge and jump late: it works. |
| 1.3 | Retune speeds, gravity (player and world), jump height, FOV and mouse defaults. *Needs your decisions below.* | S | Compare side by side with the old values using `tune`. |
| 1.4 | Body settings, stair stepping, floor snap, camera step smoothing; stop props launching you; script-based prop pushing. | M | Walk up 0.2 m and 0.4 m stairs without jumping, get blocked by 0.5 m. Walk down without bouncing. Stand on a crate a teammate pushes: no launch. |
| 1.5 | Crouch-jump. | S–M | Clear a 1.4 m ledge only by crouch-jumping; no camera pop. |
| 1.6 | Camera feel (landing dip and punch, subtle bob, roll), hooked to camera-shake and reduce-motion settings. | S–M | Drop 3 m: jolt. Set camera shake to 0: nothing. |
| 1.7 | Surface types, footsteps, landing and jump sounds; sound pool priority. | M | Walk on two floor types and hear different steps; teammates' steps are audible. |
| 1.8 | Host speed check updated for new speeds and carts. Co-op test with 2 PCs. | S | Play co-op; no rubber-banding when running, hopping or riding a cart. |

### Step 2: pickup and physics props (second)
| # | Step | Effort | How to test |
|---|---|---|---|
| 2.1 | Quick fixes: spin cap, release cap, throw force, max speed, no sprint while holding, held props stay awake, drop clears speed in contact. | S | Throw each prop type; drop a crate against a wall: it stays put. |
| 2.2 | Hold polish: contact spin throttle and wall sliding in `_integrate_forces`, size-based hold distance, 30° snap, smoothed drop rule, grab cone. | M | Hold a crate against a wall and look around: no jitter. Pick up a slightly turned crate: it straightens. Retest co-op heavy lifting and passing a box between players. |
| 2.3 | held_props layer and collision decision. | S | Try to stand on a held crate: impossible. Swing a held crate at a teammate. |
| 2.4 | Impact sounds and scrapes, with the impact event relayed to other PCs. | M | Drop and throw props on different surfaces, on both host and client. |
| 2.5 | Impact damage (owner detects, host applies), `impact_mass` on enemies and players. | M | Throw a crate at a rat (dies) and at a kangaroo (barely hurt); check the thrower gets the kill credit. |
| 2.6 | Breakables and gibs on the debris layer. | M | Break a fragile prop; pieces scatter, fade, and stay within the cap. |
| 2.7 | Sweep thrown inventory items. | S | Throw coffee fast at a rat from close range: it always hits. |

### Step 3: NPCs (third)
| # | Step | Effort | How to test |
|---|---|---|---|
| 3.1 | Bug fixes: cooldown, last-known-position chase, swarm cost. | S | Break line of sight: enemies go to where you were, not straight through walls. |
| 3.2 | `PerceptionManager`: cones, noticing delay with squeak, staggered rays, longer memory and search. | M | Sneak behind a rat: it doesn't see you. Step in front: short delay, squeak, then it comes. |
| 3.3 | `SoundBus` hearing, alert state, interruptions, pack alert. | M | Sprint near a sleeping pack: they investigate. Crouch-walk: they don't. Throw a crate into a room: enemies come to look. |
| 3.4 | Co-op target scoring, attack tokens, attack wind-ups and telegraph sounds. | M | With 2 players, enemies split between you; only 2 rats bite at once, the rest circle. |
| 3.5 | Async navmesh baking, avoidance, navigation links for kangaroo leaps, better flyer paths. | M | No hitch when a floor loads; packs flow around each other; kangaroos leap gaps. |
| 3.6 | Dodge thrown props; cosmetic ragdolls or corpse bodies. | M | Throw a heavy crate at a kangaroo: it tries to dodge. Kill a rat: it tumbles. |

### Step 4: world interaction (after the three main areas)
| # | Step | Effort |
|---|---|---|
| 4.1 | Deny sound, continuous use, use points, fatter aim check. | S–M |
| 4.2 | World I/O kit: buttons, triggers, doors, relays, counters. | M–L |
| 4.3 | Optional gravity-gun punt upgrade. | M–L |

Rough total for steps 0–3: about 25–40 sessions.

---

## 4. Tunable values

All of these will be `@export` values in the feel tuning files (with tooltips and sensible slider ranges), editable in the Inspector and with `tune` while playing. "Current" is today's value; "Start at" is the recommended first value to try.

### Player movement (`player_tuning.tres`)
| Value | Current | Start at | Notes |
|---|---|---|---|
| walk_speed | 4.5 m/s | 4.8 | HL2 run is 4.83 |
| sprint_speed | 7.0 (forward only) | 7.5 | HL2 8.1 but limited by suit power; we have no stamina |
| crouch_speed | 2.5 | 1.9 | HL2's 1.6 feels sluggish |
| ground_acceleration | 12 (lerp rate) | 10 | **Meaning changes** to Source acceleration. Range 8–12 |
| ground_friction | *new* | 4 | Range 4–6 |
| stop_speed | *new* | 2.5 m/s | Below this, stops are crisp |
| air_acceleration | 3 (lerp rate) | 10 | Meaning changes, as above |
| air_wish_speed_cap | *new* | 0.76 m/s | How much air strafing can bend you. 0.6–1.0 |
| air_max_speed_factor | *new* | 1.0 | Air strafing can't exceed top speed × this |
| jump_forward_boost | *new* | 0 | HL2 used up to 0.5; keep at most 0.1, with a total-speed cap |
| gravity | 20 | 15.2 | HL2's value; world gravity should match |
| jump_height | 1.1 m | 0.9 | Decision below |
| max_fall_speed | 40 | 40 | |
| jump_buffer_seconds | *new* | 0.1 | |
| coyote_seconds | *new* | 0.1 | |
| allow_crouch_jump | *new* | true | |
| air_crouch_transition_speed | *new* | 15 /s | How fast your legs tuck in mid-air |
| crouch_transition_speed | 10 /s | 10 | |
| step_height | *new* | 0.4 m | HL2 0.46 |
| floor_snap_length | 0.1 (engine default) | 0.4 | Match step height |
| floor_max_angle | 45° (default) | 46° | |
| wall_min_slide_angle | 15° (default) | 5° | Slide along walls instead of stopping |
| push_mass_cap | *new* | 30 kg | Script-based prop pushing |
| Mutation values (hover, hop, wall climb, slide, ladders) | as now | as now | Retest after 1.1–1.2; `hop_air_control` meaning changes slightly |

### Camera (`camera_tuning.tres`)
| Value | Current | Start at | Notes |
|---|---|---|---|
| default_fov (vertical) | 85 | 70 | About 102° horizontal on 16:9 |
| default_mouse_sensitivity | 0.25 °/px | 0.066 | Source sensitivity 3 |
| bob_vertical / bob_lateral | none | 0.012 / 0.006 m | Phase follows footsteps |
| strafe_roll_degrees | none | 0.75° | Full roll at about 5 m/s sideways |
| landing_dip_per_speed / max | none | 0.015 m per m/s above 2 m/s / 0.12 m | |
| landing_punch_threshold / per_speed / max | none | 7 m/s / 0.5° per m/s / 6° | |
| punch_spring_stiffness / damping | none | 65 / 9 | |
| step_smooth_time | none | 0.08 s | Camera catch-up after a stair step |
| sprint_fov_add | none | 0 | Optional, e.g. 3 |

### Props (`prop_tuning.tres`, partly moved from `GameConfig`)
| Value | Current | Start at | Notes |
|---|---|---|---|
| grab_max_mass | 40 kg | 40 | HL2 35; co-op lifting above this |
| heavy_lift_per_holder | 30 kg | 30 | |
| grab_max_size | *new* | 3.25 m | |
| grab_reach | 2.5 m | 2.5 | |
| grab_cone_dot | *new* | 0.8 | Forgiving aim |
| hold_base_gap | 1.6 m (hold_distance) | 0.6 m + player radius + prop depth | About 1.2 m + depth |
| held_prop_track_speed | 20 m/s | 25 | |
| hold_max_spin | 62.8 rad/s (constant in code) | 62.8 | Needs Jolt cap raised |
| hold_contact_spin_min / rate | *new* | 0.1 / 2 per s | Wall jitter fix |
| carry_snap_angle | *new* | 30° | |
| hold_error_drop | 1.5 m for 0.4 s | 0.45 m smoothed | |
| hold_error_grace | *new* | 1.0 s | |
| held_prop_release_max_speed | 10.5 m/s | 6.75 | |
| throw_force | 34 | 25.4–30 | Decision below |
| throw_spin_per_factor | ±3 rad/s fixed | 0.5 rad/s per factor | |
| prop_max_speed | none (Jolt 500) | 50 m/s | |
| disable_sprint_while_holding | *new* | true | |
| drop_clears_velocity_on_contact | *new* | true | |
| impact_min_mass / small_mass / small_cap | *new* | 2 kg / 5 kg / 5 dmg | |
| impact_min_speed | *new* | 0.6 m/s | |
| npc / player impact damage tables | *new* | HL2 tables (in research notes) | |
| prop_self_damage_scale | *new* | 0.1 | For breakables |
| friendly_physics_damage_scale | *new* | 0.25 | |
| physics_attacker_window | *new* | 2 s | Who gets credit |
| impact_report_cooldown | *new* | 0.25 s | |
| impact_sound_min / full speed | *new* | 1.8 / 8.1 m/s | |
| impact_sound_debounce | *new* | 0.05 s | |
| max_gibs / gib_lifetime | *new* | 64 / 5–8 s | |

Per enemy (in content files): `impact_mass` (rat 5, bat 2, fly 0.5, kangaroo 50, giant rat 300; player 85). Per prop (in `PropData`): `health`, `surface`, `break_scene`, `carry_distance_offset`, `preferred_carry_rotation`.

### AI (`ai_tuning.tres`; per-enemy values in enemy content files)
| Value | Current | Start at |
|---|---|---|
| sight_cone_degrees | none (360°) | rat 140, kangaroo 120, bat/fly 360, boss 160 |
| close_sense_range | none | 2.5–4 m |
| notice_time | instant | 0.3–0.6 s |
| target_memory | 3 s | 5–6 s |
| search_time | none | 2–3 s |
| sight_rays_per_tick | unlimited (every 0.2 s each) | 8–12 |
| hearing radii | none | crouch 2, walk 5, sprint 10, land 7, door 12, death squeal 15 m; impacts 3–15 |
| pack_alert_radius | none | 12–15 m |
| attack_tokens per player | none | small 2, heavy 1 |
| token_max_hold / grant_gap | none | 2 s / 0.3–0.5 s |
| attack_windup | none | 0.3–0.5 s |
| target_stickiness / min_hold | none | 1.3× / 2 s |
| turn_speed | 8 (constant) | 8 |
| repath_interval | 0.25 s | 0.25 s + random offset |
| avoidance radius / neighbour distance / time horizon | none | 0.35–0.5 m / 3 m / 0.7 s |
| nav cell_size / cell_height | 0.25 | 0.3 / 0.25 |

### Project physics settings (`project.godot`)
| Setting | Current | Start at |
|---|---|---|
| physics_ticks_per_second | 60 | 60 |
| physics_jitter_fix | 0.5 (default) | 0 |
| 3d/default_gravity | 9.8 | 15.2 (match player) |
| jolt limits/max_linear_velocity | 500 | 100 (props capped at 50 in script) |
| jolt limits/max_angular_velocity | 47.12 | 62.83 |
| jolt sleep_velocity_threshold | 0.03 | 0.05 |
| jolt penetration_slop | 0.02 | 0.01 |
| everything else | default | default |

---

## 5. Risks and open questions

### Decisions I need from you (recommended option first)
1. **Air strafing and bunny hopping:** *curve but no speed gain* (recommended; protects co-op and the host speed check), or full Source-style speed building?
2. **Gravity and jump:** world and player gravity both ~15 with a 0.9 m jump and crouch-jump to ~1.5 m (recommended), or keep jump 1.1 m? Changing jump height matters if any room needs a 0.9–1.1 m jump.
3. **Held props and players:** held props pass through players (recommended: no prop-flying, no shoving teammates), or stay solid to everyone as the current spec says?
4. **Players bumping into each other:** keep players solid to each other (current), or let them pass through (avoids blocking doorways and glitches from laggy positions)? I lean towards keeping them solid for now and revisiting after co-op testing.
5. **Throw strength:** HL2's 25.4 or keep it punchier at about 30?
6. **Sprint while carrying:** disable it like HL2 (recommended), or allow it?
7. **FOV and mouse defaults:** 70 vertical (about 102° horizontal) and Source-sensitivity-3 mouse, OK?
8. **Gravity-gun punt** as a later cybernetic upgrade: yes or skip? *(Answered: yes.)*

### Risks
- **Rewriting movement touches every mutation.** Fly, Frog, Octo and Slug all build on the walk mode. Their tests must pass after steps 1.1–1.2, and each needs a quick play check.
- **Bunny hopping and the host speed check (decision 1).** Today the host pulls you back if you move faster than about 1.5 × your top speed. That would rubber-band bunny hoppers. Step 1.8 will change the check to allow speed that builds up gradually in the air (a cap on how fast speed can *grow* each second, plus an absolute safety cap of about 3 × sprint speed). Fast players may also outrun teammates and enemies, so watch for that in co-op tests.
- **Host speed check.** The new speeds, step-ups and cart rides must not cause rubber-banding. If a client edits its local tuning, the host's check uses different numbers; later we could send a tuning checksum when joining.
- **Jolt details we couldn't fully confirm:** whether "props don't collide with players" is really one-sided in Jolt (Godot normally makes two bodies collide if *either* one's mask matches the other), how sweeping works for very fast light props, and whether triggers detect doors. Each gets a small test scene before we rely on it.
- **Moving the hold code into `_integrate_forces`** changes timing. Passing a box between players and co-op heavy lifts must be retested.
- **Network timing for impact damage.** Hits are detected against enemy positions that are 50–100 ms old. Host checks must be lenient enough not to reject fair hits, and duplicate reports around an ownership hand-over must be ignored.
- **Crouch-jump and smooth camera** can cause a one-frame dip if not done carefully.
- **Performance at 4 players:** 200 props, gibs and ragdolls need caps (about 60 awake props, 64 gibs, 8 ragdolls). We'll watch the Godot monitors.
- **Engine version:** use Godot 4.7.2 or later (mouse fix). Check the installed GUT version matches 4.7 (GUT 9.7.x).
- **Sounds and licenses:** Kenney and Freesound CC0 are safe for commercial use; Freesound "non-commercial" sounds are not. ElevenLabs sound effects need a paid plan (Starter, about $6/month) for commercial use; the free plan is personal use only. Any AI-made sound or model must go in `docs/AI_CONTENT_LOG.md` and Steam's AI-content disclosure.
- **No third-party movement or AI code.** The open-source Godot controllers found are either unlicensed, abandoned, or possibly derived from Valve code. We'll write our own. If we ever need more structure for the boss AI, LimboAI (MIT) is the best fit, but it isn't needed now.

---

## 6. Sources

**Valve Developer Community and HL2**
- Dimensions (HL2): https://developer.valvesoftware.com/wiki/Dimensions_(Half-Life_2_and_Counter-Strike:_Source)
- HL2 console variables: https://developer.valvesoftware.com/wiki/List_of_Half-Life_2_console_commands_and_variables
- Duck jump fix: https://developer.valvesoftware.com/wiki/Duck_Jump_Fix
- View roll: https://developer.valvesoftware.com/wiki/View_roll · sv_friction: https://developer.valvesoftware.com/wiki/Sv_friction
- Gravity gun / weapon_physcannon: https://developer.valvesoftware.com/wiki/Weapon_physcannon · Player pickup: https://developer.valvesoftware.com/wiki/Player_pickup · Prop data: https://developer.valvesoftware.com/wiki/Prop_Data
- AI programming: https://developer.valvesoftware.com/wiki/AI_Programming · Squad slots: https://developer.valvesoftware.com/wiki/SquadSlot · ai_sound: https://developer.valvesoftware.com/wiki/Ai_sound · npc_headcrab / npc_antlion / npc_zombie / npc_combine_s pages
- Inputs and outputs: https://developer.valvesoftware.com/wiki/Inputs_and_outputs · func_door, prop_door_rotating, func_button, trigger_multiple, logic_relay, math_counter pages
- Adrian Biagioli, "Bunnyhopping from the Programmer's Perspective" (CC-BY 4.0): https://adrianb.io/2015/02/14/bunnyhop.html
- Accelerated back hopping (what not to copy): https://wiki.sourceruns.org/Accelerated-Back-Hopping.html

**Godot**
- CharacterBody3D: https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
- Using Jolt Physics: https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
- Physics interpolation: https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html
- Navigation meshes, agents, links, performance: https://docs.godotengine.org/en/stable/tutorials/navigation/
- Ragdoll system: https://docs.godotengine.org/en/stable/tutorials/physics/ragdoll_system.html
- Best practices (scene organisation, autoloads): https://docs.godotengine.org/en/stable/tutorials/best_practices/
- High-level multiplayer: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- Release notes 4.5 / 4.6 / 4.7: https://godotengine.org/releases/4.5/ · /4.6/ · /4.7/
- High-polling-rate mouse fix: https://godotengine.org/article/fixing-high-polling-rate-mice-on-windows/
- Step handling PR (not merged): https://github.com/godotengine/godot/pull/114447
- Jolt launch problem (4.6.1): https://forum.godotengine.org/t/jolt-physics-causing-insane-characterbody3d-and-rigidbody3d-launch-upon-collision/135988

**Reference projects (ideas only, licenses checked)**
- Stair-Step Demo (MIT): https://github.com/JheKWall/Godot-Stair-Step-Demo
- GodotCharacterStep (MIT): https://github.com/PantheraDigital/GodotCharacterStep
- GUT (MIT): https://github.com/bitwes/Gut · GdUnit4 (MIT): https://github.com/godot-gdunit-labs/gdUnit4
- LimboAI (MIT): https://github.com/limbonaut/limboai · Beehave (MIT): https://github.com/bitbrain/beehave · Godot State Charts (MIT): https://github.com/derkork/godot-statecharts
- Dialogue Manager (MIT): https://github.com/nathanhoad/godot_dialogue_manager

**Sound and licensing**
- Kenney (CC0): https://kenney.nl/support · Freesound licenses: https://freesound.org/help/faq/
- ElevenLabs sound effects terms: https://elevenlabs.io/sound-effects
- Steam content survey (AI disclosure): https://partner.steamgames.com/doc/gettingstarted/contentsurvey
