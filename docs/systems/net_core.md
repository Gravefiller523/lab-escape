# net_core

Folder: `res://systems/net_core/` · Autoload: `Net` · Size: M · Phase 1a

## Purpose
Keeps track of who is playing (the **roster**), gives every system simple host/client helpers, applies
joining rules (only while in the Break Room), and handles disconnects and reconnects. On the host it
keeps a **PlayerRecord** for every player of the current run (mutations, cybernetics, alive or dead,
outfit), so a player who drops and rejoins gets everything back.

**Not responsible for:** Steam calls (steam_session), spawning player bodies (player), syncing props
(physics_props), applying upgrades (upgrades).

## Public API
```gdscript
signal roster_changed()

func is_host() -> bool                     # true in solo too
func is_online() -> bool                   # false in solo (no clients and no lobby)
func local_player_id() -> int
func get_player_ids() -> Array[int]        # connected players, in join order. Never assume 4.
func get_player_count() -> int
func get_peer_id(player_id: int) -> int    # 0 if not connected
func get_player_id_for_peer(peer_id: int) -> int
func sender_player_id() -> int             # inside an RPC handler: who sent it (0 if unknown)
func get_display_name(player_id: int) -> String
func get_slot_index(player_id: int) -> int # 0..max_players-1, stable for the session; used for colours and voice buses
func get_record(player_id: int) -> PlayerRecord   # host: the truth; clients: synced read-only copy
func update_record(player_id: int, field: StringName, value: Variant) -> void   # host only; syncs to clients
func set_joining_open(open: bool) -> void  # host; game_flow calls this
func is_joining_open() -> bool
func clear_run_records() -> void           # host; at run start and end
func kick(player_id: int) -> void          # host
```

`PlayerRecord` (`systems/net_core/player_record.gd`, `class_name PlayerRecord extends RefCounted`):
```gdscript
var player_id: int
var display_name: String
var slot_index: int
var connected: bool
var is_alive: bool = true
var upgrade_ids: Array[StringName] = []        # written by upgrades (repeated ids = stacks)
var cosmetic_loadout: Dictionary = {}          # slot -> cosmetic id, written by cosmetics
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> PlayerRecord
```
Other systems add fields here only by asking (foundation-style change to net_core).

## EventBus
- Emits: `player_joined`, `player_left`, `player_reconnected`.
- Listens: `game_state_changed` (to know when joining is allowed), `run_ended` (clear records).

## Data it owns and saves
Owns PlayerRecords during a session. Saves nothing to disk.

## Adding content
None.

## Multiplayer
- The host owns the roster and records, and sends the full roster to each new peer, then changes as they happen (reliable RPCs).
- **Joining rule:** a new peer is accepted only when `is_joining_open()` is true (the Break Room).
  Otherwise the host disconnects them with a "Run in progress" message.
- **Reconnecting:** during a run, a peer whose Steam ID matches an existing record is accepted even
  though joining is closed: the record is marked connected again, `player_reconnected` fires, the
  player system spawns them at the lift (or as a ghost if they were dead), and upgrades re-applies
  their upgrades from the record.
- A player who leaves keeps their record (marked disconnected) until the run ends. Items they carried drop like a death (death_respawn listens to `player_left`).
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

## Acceptance criteria
- [ ] Every system can call `Net.is_host()` and `Net.get_player_ids()` in solo with no setup.
- [ ] Joining during a run is refused; reconnecting players get their record back.
- [ ] Works with `max_players` set to 8 (tested with local instances).
- [ ] No system other than net_core and steam_session touches `multiplayer.multiplayer_peer`.

## Open design questions
- DEFAULT: only the Break Room accepts new players; reconnects are allowed mid-run.
- DEFAULT: if the **host** disconnects, the run ends for everyone (no host migration; too complex for now).

## Changelog
- 2026-10-07: spec created.
