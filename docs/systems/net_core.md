# net_core

Folder: `res://systems/net_core/` · Autoload: `Net` · Size: M · Phase 1a

## Purpose
Keeps track of who is playing (the **roster**), gives every system simple host/client helpers, applies
joining rules, and handles disconnects and reconnects. On the host it
keeps a **PlayerRecord** for every player of the current run (mutations, cybernetics, alive or dead,
outfit), so a player who drops and rejoins gets everything back.

**CHANGED 2026-10-17 (mid-run joining):** players can join during a run. A mid-run joiner is added
to the roster marked **waiting for the next floor**: they spectate like a dead player and spawn with
everyone when the next floor starts. net_core only keeps and syncs that flag; spectating and
spawning are done by player, death_respawn and game_flow (see Handoff).

**Not responsible for:** Steam calls (steam_session), spawning player bodies (player), syncing props
(physics_props), applying upgrades (upgrades), spectating (death_respawn/player).

## Public API
```gdscript
signal roster_changed()
signal record_changed(player_id: int, field: StringName)   # NEW 2026-10-17: on every PC when a synced record field changes
signal join_refused(reason: String)                        # NEW 2026-10-17: on a client the host turned away

func is_host() -> bool                     # true in solo too
func is_online() -> bool                   # false in solo (no clients and no lobby)
func local_player_id() -> int
func get_player_ids() -> Array[int]        # connected players, in join order. Never assume 4.
func get_player_count() -> int
func get_record_ids() -> Array[int]        # NEW 2026-10-17: everyone with a record, including players who dropped mid-run
func get_peer_id(player_id: int) -> int    # 0 if not connected
func get_player_id_for_peer(peer_id: int) -> int
func sender_player_id() -> int             # inside an RPC handler: who sent it (0 if unknown)
func get_display_name(player_id: int) -> String
func get_slot_index(player_id: int) -> int # 0..max_players-1, stable for the session; used for colours and voice buses
func get_record(player_id: int) -> PlayerRecord   # host: the truth; clients: synced read-only copy
func update_record(player_id: int, field: StringName, value: Variant) -> void   # host only; syncs to clients
func set_joining_open(open: bool) -> void  # host. CHANGED 2026-10-17: open by default, also during runs
func is_joining_open() -> bool
func is_run_active() -> bool               # NEW 2026-10-17: between run_started and run_ended
func is_waiting_for_next_floor(player_id: int) -> bool    # NEW 2026-10-17: mid-run joiner still spectating
func get_waiting_player_ids() -> Array[int]               # NEW 2026-10-17
func set_waiting_for_next_floor(player_id: int, waiting: bool) -> void   # NEW 2026-10-17: host only
func clear_run_records() -> void           # host; at run start and end
func kick(player_id: int) -> void          # host
func use_config(config: GameConfig) -> void   # NEW 2026-10-17: tests only; call before adding the node to the tree
```
NEW 2026-10-17: the autoload script is `systems/net_core/net.gd` with `class_name NetService` (a class
can't have the same name as its autoload). Net notices when steam_session changes the connection
and starts a fresh roster by itself; nobody needs to tell it.

`PlayerRecord` (`systems/net_core/player_record.gd`, `class_name PlayerRecord extends RefCounted`):
```gdscript
var player_id: int
var display_name: String
var slot_index: int
var connected: bool
var is_alive: bool = true
var waiting_for_next_floor: bool = false       # NEW 2026-10-17: joined mid-run, spawns at the next floor
var upgrade_ids: Array[StringName] = []        # written by upgrades (repeated ids = stacks)
var cosmetic_loadout: Dictionary = {}          # slot -> cosmetic id, written by cosmetics
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> PlayerRecord
func apply_dict(data: Dictionary) -> void      # NEW 2026-10-17: copies the fields found in data onto this record
```
Other systems add fields here only by asking (foundation-style change to net_core).

## EventBus
- Emits: `player_joined`, `player_left`, `player_reconnected` (on every PC, as its roster copy changes).
- Listens (CHANGED 2026-10-17): `run_started` (a run is active), `run_ended` (clear records),
  `floor_loading` (host: mid-run joiners stop waiting, so they spawn with everyone on that floor).
  No longer listens to `game_state_changed`: joining doesn't depend on the game state any more.

## Data it owns and saves
Owns PlayerRecords during a session. Saves nothing to disk.

## Adding content
None.

## Multiplayer
- The host owns the roster and records, and sends the full roster to each new peer, then changes as they happen (reliable RPCs).
- NEW 2026-10-17: a client says hello to the host once connected (its player id and name). Over
  Steam the host ignores the claimed id and uses `SteamSession.get_steam_id_for_peer()`. In local
  mode it trusts the claim, so each window keeps one player id for the whole run (reconnects work locally).
- **Joining rule (CHANGED 2026-10-17):** a new peer is accepted when `is_joining_open()` is true and
  there is room (`Config.game.max_players`, counting disconnected players who still hold a record
  during a run). Otherwise the host sends a reason and disconnects them (client gets `join_refused`).
  Joining stays open during runs. A player who joins while a run is active gets
  `waiting_for_next_floor = true`. When the next floor starts loading (`floor_loading`), the
  host sets it back to false for everyone.
- **Reconnecting:** during a run, a peer whose Steam ID matches an existing record is accepted even
  though joining is closed: the record is marked connected again, `player_reconnected` fires, the
  player system spawns them at the lift (or as a ghost if they were dead), and upgrades re-applies
  their upgrades from the record.
- A player who leaves keeps their record (marked disconnected) until the run ends. Items they carried drop like a death (death_respawn listens to `player_left`).
  Outside a run their record is removed and their slot freed.
- The roster size limit comes from `Config.game.max_players`.

## Dependencies and stubs
- steam_session (or its local mode). In unit tests, use Godot's `OfflineMultiplayerPeer` (solo) or two ENet peers.
- Stub for others: `Net` works in solo with no setup: `is_host()` true, one player with a fake id.

## Test scene and GUT tests
Test scene `systems/net_core/test/roster_test.tscn`: shows the roster, slot indexes and records;
buttons to fake a disconnect and reconnect. Run 2 to 3 instances.
GUT tests:
- `test_solo_is_host_with_one_player`
- `test_slot_indexes_unique_and_reused_after_leave`
- `test_join_refused_when_closed`
- `test_reconnect_restores_record` (same player id, upgrade_ids kept)
- `test_record_round_trips_to_dict`
- `test_roster_limit_follows_config` (set max_players to 8, accept 8, refuse the 9th)
- NEW 2026-10-17: `test_mid_run_joiner_waits_for_next_floor` (accepted during a run, waiting until `floor_loading`)
- NEW 2026-10-17: `test_joiner_before_run_does_not_wait`
All in `tests/unit/net_core/test_net.gd`. Each test "PC" is a node with its own multiplayer, so
several players connect over real ENet inside one test.

NEW 2026-10-17, test scene extras: "Start run", "Next floor" and "End run" buttons (STUB: they emit
game_flow's EventBus signals on that PC only; press them in the host window), "Give everyone Fly",
"Toggle joining", "Kick last player", and the launch options `-- host` / `-- join`.

## Acceptance criteria
- [x] Every system can call `Net.is_host()` and `Net.get_player_ids()` in solo with no setup. *(test_solo_is_host_with_one_player)*
- [x] CHANGED 2026-10-17: joining during a run is accepted with the joiner waiting for the next floor; reconnecting players get their record back. *(GUT tests; two-window check still to do by eye)*
- [x] Works with `max_players` set to 8 (tested with local instances). *(test_roster_limit_follows_config: 8 ENet players in one test; 3 separate windows also checked)*
- [x] No system other than net_core and steam_session touches `multiplayer.multiplayer_peer`. *(checked with a search, 2026-10-17)*
- [x] The same on real Steam between 2 PCs. *(Zachary, 2026-10-18)*

## Open design questions
- CHANGED 2026-10-17 (decided): new players can join any time there is room; mid-run joiners spectate until the next floor. Reconnects are allowed mid-run.
- DEFAULT: if the **host** disconnects, the run ends for everyone (no host migration; too complex for now).

## Changelog
- 2026-10-07: spec created.
- 2026-10-17: mid-run joining (Zachary's decision). Joining stays open during runs; added
  `waiting_for_next_floor` to PlayerRecord, `is_run_active`, `is_waiting_for_next_floor`,
  `get_waiting_player_ids`, `set_waiting_for_next_floor`, the `record_changed` and `join_refused`
  signals, and the client hello. Listens to `run_started`/`floor_loading` instead of `game_state_changed`.
- 2026-10-17: built. Also added `get_record_ids`, `PlayerRecord.apply_dict` and the test-only `use_config`.

## HANDOFF
**Done:** the `Net` autoload: roster, slot indexes (lowest free slot, reused), PlayerRecords synced
host -> clients, joining rules (open, room left, reconnects always allowed), mid-run joiners marked
`waiting_for_next_floor` until `floor_loading`, kick, refusal messages, solo with no setup, 8 GUT
tests (all pass), and the roster test scene. Checked with 3 local windows.

**Known bugs / limits:**
- Over Steam the host trusts Steam for player ids. In local mode it trusts the client's hello (fine for testing only).
- In local mode the "Steam ID" is a random ENet number, so names show as "Player 705903177".
- Checked on real Steam between two PCs (2026-10-18).
- If the host leaves, everyone's run ends (no host migration; spec default).

**Stubbed:** the test scene's run and floor buttons stand in for game_flow.

**What other systems must do for mid-run joining (decided 2026-10-17):**
- **game_flow:** emit `run_started` and `floor_loading` on every PC. Net clears the waiting flags on
  `floor_loading`, before `floor_ready`. Don't call `Net.set_joining_open(false)` for runs any more.
- **player:** on `player_joined`, if `Net.is_waiting_for_next_floor(id)`, don't spawn a body yet;
  spawn every connected player on `floor_ready` (waiting flags are already cleared by then).
  Listen to `Net.record_changed(id, &"waiting_for_next_floor")` if you need to react sooner.
- **death_respawn:** treat waiting players as spectators (ghost camera, like the dead), and leave
  them out of the team-wipe check: they aren't alive yet, but they aren't dead either.
- **ui:** show "Joined mid-run: you'll spawn on the next floor" when the local player is waiting.
- **upgrades / cosmetics:** write into records with `Net.update_record()`; read with `get_record()`.

**For everyone:** use `Net.sender_player_id()` inside RPC handlers, loop over `Net.get_player_ids()`,
and use `Net.get_slot_index()` for colours and voice buses. Records of players who dropped mid-run
are in `get_record_ids()` but not in `get_player_ids()`.
