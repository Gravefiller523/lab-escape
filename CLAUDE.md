# Lab Escape: rules for every session

Lab Escape is a 1 to 4 player (configurable, maybe up to 8) online co-op roguelike for PC/Steam,
built in **Godot 4.7** with **GDScript (static typing everywhere)**, **GodotSteam** and **GUT** tests.
The team are beginners: explain decisions in plain language and define jargon.

Read these before writing code:
- `docs/ARCHITECTURE.md`: every system and how they connect.
- `docs/systems/<your_system>.md`: the spec for the system you are building. It is the contract.
- `docs/systems/foundation.md` and `docs/systems/event_bus.md`: the shared code everyone uses.
- `docs/BUILD_ORDER.md`: what to build when.
- `docs/ADDING_CONTENT.md`: how content files work.

## 1. Folder layout

```
res://
  core/                 Shared foundation (owner: foundation). Autoloads, data classes, helpers.
    autoload/           Config, EventBus, ContentRegistry
    config/             GameConfig class
    data/               Every content data class (MutationData, ItemData, ...)
    content/            ContentValidator
    input/ physics/ util/   InputActions, PhysicsLayers, SeededRng
  config/game_config.tres   The live tuning numbers
  content/<type>/       Content files (.tres), one folder per type. See ADDING_CONTENT.md.
  systems/<system>/     One folder per system: its scripts, scenes, UI, local assets.
    test/               That system's standalone test scene(s)
  assets/               Shared art and audio (models/, textures/, materials/, audio/music, audio/sfx, fonts/)
  addons/               Third-party plugins only (gut, godotsteam). Never edit them.
  tests/
    unit/<system>/      GUT unit tests (test_*.gd)
    integration/        GUT tests that use several systems together
    content/            The content validation test
  docs/                 Architecture, specs, guides
```

A system's own art that nobody else uses may live in `systems/<system>/`. Department art lives in
`assets/<kind>/<department>/`, e.g. `assets/models/zoology/`.

## 2. Ownership: never edit another system's folder without permission

- Each system owns `systems/<name>/`, `tests/unit/<name>/` and `docs/systems/<name>.md`.
- Only work inside the system you were asked to build. If you need something from another
  system that its public API doesn't offer, **stop and tell the user**. Write what you need in
  your spec's "Open design questions" and use a stub (a fake version) for now.
- `core/` and `project.godot` are shared. You may **add** to them (a new EventBus signal, a new
  field on a data class, a new GameConfig number, a new input action, an autoload line for your
  system). You may **never rename or remove** anything there without the user's OK, because
  that breaks other systems and existing content files. List every addition under
  "Foundation changes" in your merge notes.
- `content/` files can be added by anyone. Editing an existing content file is fine for tuning.
- Each `.tscn` scene has one owning system. Two people editing one scene causes merge conflicts
  that are very hard to fix, so never edit another system's scene.

## 3. Naming conventions

| Thing | Style | Example |
|---|---|---|
| Files and folders | snake_case | `grab_controller.gd`, `break_room.tscn` |
| class_name | PascalCase | `class_name GrabController` |
| Nodes in scenes | PascalCase | `Camera`, `HoldPoint` |
| Functions, variables | snake_case | `func try_grab() -> bool` |
| Private (internal) members | leading underscore | `var _held_prop: NetProp` |
| Constants and enum values | UPPER_SNAKE_CASE | `const MAX_REACH: float = 3.0` |
| Signals | past tense snake_case | `signal prop_grabbed(...)` |
| Content ids | `<type>_<name>`, lower snake case | `mutation_fly`, `enemy_rat`, `room_zoo_cages_m` |
| Content files | `<id>.tres` | `content/mutations/mutation_fly.tres` |
| Autoload names | PascalCase, one word if possible | `GameFlow`, `Net`, `Voice` |
| GUT test files | `test_<thing>.gd` | `tests/unit/inventory/test_slots.gd` |

Never call a function or touch a variable that starts with `_` from outside its own script.

## 4. Static typing rules

The project treats an untyped variable as an **error** (Project Settings > Debug > GDScript).
- Type every variable, parameter and return value: `var speed: float = 3.0`,
  `func get_slot(index: int) -> ItemData:`. Functions that return nothing use `-> void`.
- `:=` is allowed when the type is obvious from the right side (`var rng := RandomNumberGenerator.new()`).
- Use typed arrays: `Array[StringName]`, `Array[ItemData]`. Prefer typed dictionaries
  (`Dictionary[int, PlayerRecord]`) in code. Data classes may use plain `Dictionary` for
  Inspector-edited fields.
- Use `StringName` (`&"name"`) for ids, action names, state names and tags. Use `String` for text shown to players.
- Cast with `as` and check for null when the type could be wrong: `var data := ContentRegistry.get_content(id) as ItemData`.
- Avoid `get_node("../../Something")` paths that climb the tree. Use `@export` node references,
  `%UniqueName` nodes inside your own scene, or a component's `of()` helper.

## 5. How systems talk to each other

There are exactly four ways, in this order of preference:

1. **Public API**: call functions listed under "Public API" in the other system's spec, usually on its
   autoload (`Upgrades.grant(player_id, &"mutation_fly")`) or on one of its components.
   Anything not listed there is private, even if GDScript lets you call it.
2. **EventBus** (`core/autoload/event_bus.gd`): for "something just happened" facts that many systems
   may care about (`EventBus.player_died.emit(...)`). Only the owning system emits an event.
   Listeners never assume who else is listening. **EventBus is local only**: it never crosses the network.
3. **Components**: small nodes added to an object, each with a static `of(node)` helper,
   e.g. `HealthComponent.of(enemy).apply_damage(info)`. A component's spec lists its API.
4. **Content ids**: systems refer to content by id string and look it up in `ContentRegistry`.

Never reach into another system's scene tree, and never send RPCs to another system's nodes.
If you need another machine to do something, call the owning system's API: it handles the networking.

## 6. Multiplayer authority rules

"Authority" means "the computer whose copy is the truth". "Host" is the player whose PC runs the
lobby; everyone else is a "client". Solo play is a host with no clients: **there is only one code path**.

1. **The host decides game state**: health, damage, deaths, loot rolls, glow rolls, inventory contents,
   upgrades, vendor purchases, enemy AI, boss phases, level layout, lift progress, door states, and
   all physics props.
2. **Clients send requests, never results.** A client calls a `request_...` function that sends an RPC
   to the host. The host checks it (is the player alive, close enough, does the object exist?), then
   applies it. The result reaches clients through syncing. Clients never change shared state directly.
3. **One exception, on purpose:** each player's own body movement and camera are decided by that
   player's PC (it is the "multiplayer authority" of its own player node) so walking feels instant.
   The host sanity-checks speed and position. Held objects use local prediction (see physics_props).
4. **Randomness only on the host**, with `SeededRng.make(run_seed, &"<stream name>", index)`.
   Every random roll in the game uses its own stream name.
5. **Only the host spawns networked things** (players, props, items, enemies), through the owning
   system's spawn API, which uses Godot's `MultiplayerSpawner`. Clients never `add_child` a networked node.
6. **RPC style:** requests are `@rpc("any_peer", "call_local", "reliable")` and must check
   `Net.is_host()` and the sender (`multiplayer.get_remote_sender_id()`). Host-to-client updates are
   `@rpc("authority", "call_local", ...)`. Fast-changing positions use `"unreliable_ordered"`.
7. **Identify players by `player_id` (their Steam ID)**, never by array position, and never assume 4.
   Loop over `Net.get_player_ids()`. Read the limit from `Config.game.max_players`.
8. Every system must work when testing locally with 2 Godot windows (Debug > Customize Run Instances),
   using `SteamSession.host_local()` / `join_local()` instead of Steam.

## 7. Built for expansion

We will add content for years. **Adding content must mean adding files, not editing code.**

- Every kind of content is a `.tres` Resource file with a data class in `core/data/`
  (MutationData, ItemData, EnemyData, RoomData, DepartmentData, ...).
- Content lives in `content/<type>/`. `ContentRegistry` finds it automatically.
  **No system may keep a hand-written list of content.** Ask the registry
  (`ContentRegistry.get_all(&"mutation")`), or filter by `tags`.
- Departments are bundles (`DepartmentData`) pointing at rooms, enemies, boss, loot, stock, tasks,
  music and colours. A new department is a folder of content plus one DepartmentData file.
- Build reusable building blocks, not one-offs: upgrades are lists of effect pieces, items are lists
  of behaviour pieces, enemies are shared AI states plus small behaviour nodes. New content should
  be a new combination; only sometimes a new building block.
- **Stable ids**: every content file has a unique `id` like `mutation_fly`, matching its file name.
  Saves, network messages and loot tables use ids, never file paths or list positions.
  Never rename a shipped id.
- Loot tables, vendor stock, spawn weights, prices and all tuning numbers are data
  (content files or `config/game_config.tres`), never numbers typed into code.
- Save files carry a `save_version` number and an upgrade step for each old version.
- If a system can't follow these rules, its spec must say why.

## 8. Testing rules

- Every system ships GUT tests in `tests/unit/<system>/` covering its spec's test list, and a
  standalone test scene in `systems/<system>/test/` that runs alone with F6 using stubs.
- **Run the content validation test after adding or changing any content file**
  (`tests/content/test_content_validation.gd`). It checks ids, file names, required fields and
  that every `_id`/`_ids` field points at content that exists.
- Before asking to merge, run **all** GUT tests and make sure there are no errors or warnings in
  the Output panel. From a terminal:
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- Multiplayer features are tested with at least 2 local instances before merging, and with real
  Steam on 2 PCs before a phase is called done.
- Fix a failing test; never delete or skip it to get a green run without the user's OK.

## 9. Git workflow

- `main` always opens and runs. Never commit straight to `main`.
- One branch per system: `system/<system_name>` (e.g. `system/inventory`). Content-only work uses
  `content/<what>` (e.g. `content/zoology-rooms`).
- Before starting, update from `main`. Commit small steps with clear messages
  ("inventory: add slot swapping"). Push your branch.
- Systems are merged into `main` one at a time using the team's merge prompt (Prompt 3), after the
  tests pass. The merge notes list: what was built, foundation changes, project.godot changes,
  new EventBus signals, and anything left as a stub.
- Commit `.uid` files that Godot creates next to scripts. Never commit `.godot/`.
- Ask the user before committing, pushing, or merging.

## 10. When an interface changes

An "interface" is anything another system uses: public functions, signals, component APIs,
data class fields, EventBus signals, GameConfig fields, input actions.
1. Update the spec (`docs/systems/<name>.md`) **first**: the Public API section and a dated line in its
   "Changelog" section saying what changed and why.
2. Prefer adding over changing. If a function must change, keep the old one working and mark it
   `## @deprecated use X instead` until every caller has moved.
3. If you add an EventBus signal, add it to `docs/systems/event_bus.md` too.
4. If you add a data field or content type, update `docs/ADDING_CONTENT.md`.
5. If the change affects how systems connect, update `docs/ARCHITECTURE.md`.
6. Mention every interface change in your merge notes so the merge session can check callers.

## 11. Steam and assets

- Develop with Steam's test App ID 480 (Spacewar) until the game has its own App ID.
- Every asset made with AI tools (Meshy, ElevenLabs, etc.) gets a line in `docs/AI_CONTENT_LOG.md`
  (asset, tool, date) for Steam's AI-content disclosure. Check the tool's commercial licence first.
