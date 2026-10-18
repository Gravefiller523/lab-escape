# steam_session

Folder: `res://systems/steam_session/` · Autoload: `SteamSession` · Size: M · Phase 1a

## Purpose
Talks to Steam through GodotSteam: starts Steam, creates and joins lobbies, opens the friend-invite
overlay, handles "Join game" from the Steam friends list, sets rich presence, and creates the network
connection (a `SteamMultiplayerPeer`) that Godot's multiplayer uses. It also has a **local mode**
(ENet on 127.0.0.1) so everyone can test multiplayer with two Godot windows and no Steam.

**Not responsible for:** who is in the game or join rules (net_core), voice (voice), achievements
(achievements), any gameplay.

## Public API
```gdscript
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)             # CHANGED 2026-10-17: fires once the network connection to the host is up
signal lobby_join_failed(reason: String)
signal connection_lost()                       # we were the client and the host vanished

func is_steam_running() -> bool
func get_local_steam_id() -> int               # CHANGED 2026-10-17: in local mode, our network peer id (host = 1, clients a random ENet number)
func get_steam_id_for_peer(peer_id: int) -> int   # NEW 2026-10-17: network peer id -> Steam ID (same number in local mode); 0 if unknown
func get_peer_for_steam_id(steam_id: int) -> int  # NEW 2026-10-17: Steam ID -> network peer id; 0 if not connected
func get_persona_name(steam_id: int) -> String
func get_avatar(steam_id: int) -> Texture2D    # may return null first, then a cached texture
func host_lobby() -> void                      # friends-only, max members = Config.game.max_players
func join_lobby(lobby_id: int) -> void
func leave_lobby() -> void
func get_lobby_id() -> int                     # 0 when not in a lobby
func get_lobby_member_ids() -> Array[int]
func get_lobby_max_members() -> int            # NEW 2026-10-17: Config.game.max_players
func set_lobby_joinable(joinable: bool) -> void   # host. CHANGED 2026-10-17: lobbies stay joinable during runs (mid-run joining); use it only to close a lobby
func open_invite_overlay() -> void
func set_rich_presence(key: String, value: String) -> void
func host_local(port: int = 7777) -> void      # testing without Steam
func join_local(address: String = "127.0.0.1", port: int = 7777) -> void
func is_local_mode() -> bool
const LOCAL_LOBBY_ID: int = 1                  # NEW 2026-10-17: what get_lobby_id() returns in local mode
func use_backend(api: SteamApi, config: GameConfig) -> void   # NEW 2026-10-17: tests only; call before adding the node to the tree
```
NEW 2026-10-17: the autoload script is `systems/steam_session/steam_session.gd` with
`class_name SteamSessionService` (a class can't have the same name as its autoload). Every Steam call
goes through `SteamApi` (`steam_api.gd`) so tests can swap in a fake. **Headless runs (GUT tests,
servers) never start Steam**, so running tests doesn't show you as "playing Spacewar".

Rich presence keys used: `status` ("In the Break Room", "Zoology, floor 3", "Fighting the Giant Rat"),
plus (NEW 2026-10-17) `steam_player_group` and `connect` (`+connect_lobby <id>`), so friends see you
as a group and can click "Join game".
`steam_display` uses localisation tokens set up later on the Steamworks site.

## EventBus
- Emits: none (its own signals above are for net_core and ui).
- Listens: `game_state_changed`, `floor_ready`, `boss_floor_started`, `run_ended` (NEW 2026-10-17) → updates rich presence.

## Data it owns and saves
Owns no content. Saves nothing. Reads `steam_appid.txt` (480 = Spacewar during development).

## Adding content
None.

## Multiplayer
- Host: `Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, Config.game.max_players)`, then creates a
  `SteamMultiplayerPeer` as server and assigns it to `multiplayer.multiplayer_peer`.
- Client: joins the lobby, creates a `SteamMultiplayerPeer` as client connecting to the lobby owner.
- Handles `join_requested` (friend clicked "Join game") and the `+connect_lobby <id>` launch argument.
- If the host leaves, emits `connection_lost`; game_flow returns the client to the main menu.
- NEW 2026-10-17: the lobby stays joinable during a run (mid-run joining, decided 2026-10-17). A
  mid-run joiner spectates like a dead player and spawns at the start of the next floor; that
  part is net_core's and player's job, not steam_session's.
- NEW 2026-10-17: in local mode, a host that leaves sends every client a proper "disconnect" first,
  so they get `connection_lost` straight away instead of after ENet's long timeout.

## Dependencies and stubs
- GodotSteam: use **"GodotSteam GDExtension 4.4+"** from the AssetLib tab, version 4.23 or newer
  (checked 2026-10-07). It includes `SteamMultiplayerPeer` (merged in 4.17; no separate download) and
  the voice functions (`getVoice`, `decompressVoice`, `getVoiceOptimalSampleRate`). Don't mix it with
  GodotSteam's pre-compiled editors.
- Stub for others: local mode *is* the stub. Every other system tests with `host_local()`/`join_local()`.

## Test scene and GUT tests
Test scene `systems/steam_session/test/lobby_test.tscn`: buttons for Host (Steam), Join by id,
Invite, Host local, Join local, and a label listing lobby members. Run 2 instances.
Also (NEW 2026-10-17): Copy lobby id, Leave, Ping everyone (an RPC every window logs), and launch
options: put `-- host` or `-- join` in a run instance's launch arguments to host or join locally
by itself (join also pings once).
GUT tests (`tests/unit/steam_session/test_steam_session.gd`, with `fake_steam_api.gd`):
- `test_local_host_and_join_connect`: two peers in one test via ENet, client gets `connected_to_server`.
- `test_is_steam_running_false_without_steam`: no crash when Steam isn't running; local mode still works.
- `test_lobby_size_uses_config`: the max-members argument comes from `Config.game.max_players` (inject a config with 8).
- NEW 2026-10-17: `test_host_leaving_sends_connection_lost`, `test_second_host_while_in_lobby_is_refused`,
  `test_connect_lobby_launch_argument`, `test_rich_presence_follows_floors`.

## Acceptance criteria
- [x] Two PCs on different Steam accounts: host creates a lobby, invites, friend joins from the overlay.
  *Checked by Zachary on 2 PCs (2026-10-18), after the overlay fix (Steam starts at startup in exported builds).*
- [x] Two local windows connect with `host_local`/`join_local`. *(Checked with 2 instances of the test scene, including a ping RPC.)*
- [x] Lobby size follows `max_players`; nothing assumes 4. *(GUT test with 8.)*
- [ ] Rich presence shows in the Steam friends list. *Code done; needs a friend on another account to look.*
- [x] Host quitting sends the client back to the menu without errors. *(Client gets `connection_lost` in local
  mode; the "back to the menu" part is game_flow's. Over Steam this still needs the two-PC test.)*

## Open design questions
- DEFAULT: lobbies are friends-only (no public browser).
- DEFAULT: the GDExtension build (works with Godot's normal export templates).
- STUB: rich presence listens to `game_state_changed` and checks for `GameFlow.State.BREAK_ROOM`
  using a copied number (2, from game_flow's spec), because game_flow isn't built yet. Swap it for
  the real enum when game_flow is merged.
- In local mode the "Steam ID" is the network peer id, so clients get big random numbers, not 1, 2, 3.
  Good enough for testing; net_core should only ever use `get_steam_id_for_peer()`.

## Changelog
- 2026-10-07: spec created.
- 2026-10-17: built. Added `get_steam_id_for_peer`, `get_peer_for_steam_id`, `get_lobby_max_members`,
  `LOCAL_LOBBY_ID` and the test-only `use_backend`. `lobby_joined` now means "connected to the host".
  Local-mode ids are peer ids. Lobbies stay joinable during runs (mid-run joining decision). Headless
  runs skip Steam. Rich presence also listens to `run_ended` and sets `steam_player_group`/`connect`.
- 2026-10-18: Steam overlay (Shift+Tab) didn't open in the 2-PC test. Exported builds now let GodotSteam start
  Steam at startup, before the game window (project.godot `[steam]`: `app_id=480`,
  `initialize_on_startup.template=true`), as GodotSteam recommends for the overlay with Forward+. `SteamApi.init` then
  only checks it worked, and SteamSession runs Steam's callbacks each frame (`SteamApi.run_callbacks`, NEW).
  Editor and test runs are unchanged.

## HANDOFF
**Done:** the SteamSession autoload, with Steam lobbies (host, join by id, invites, "Join game" from the
friends list, `+connect_lobby` launch argument), a SteamMultiplayerPeer for host and client, local
ENet mode, names, avatars, rich presence, host-left detection, the test scene, and 7 GUT tests (all pass).

**Known bugs / untested:** nothing failing. Checked 2026-10-18: a real Steam join between two PCs, invites through the overlay, and a client
staying error-free when the host quits. Not yet tested: rich presence in a friend's list, and what happens on a client when the Steam host quits.
Two windows on one PC can't both be signed in to Steam, so all of that needs a second PC with
another Steam account.

**Stubbed:** the `GameFlow.State.BREAK_ROOM` number (see Open design questions). Nothing else.

**For net_core (next):**
- Wait for `lobby_created` (host) or `lobby_joined` (client) before sending RPCs; the peer is
  already set on `multiplayer.multiplayer_peer` by then.
- Turn sender peer ids into player ids with `SteamSession.get_steam_id_for_peer(multiplayer.get_remote_sender_id())`.
- `get_lobby_member_ids()` is Steam's lobby list, not the game roster. In local mode a client only
  sees itself and the host. net_core's roster is the real list.
- Don't close the lobby during runs: mid-run joiners are allowed now. net_core's own spec still says
  "only the Break Room accepts new players" and needs updating to match.
- On `connection_lost`, SteamSession has already left the lobby and set an `OfflineMultiplayerPeer`.

**Fixes made while building net_core (2026-10-17, no API change):**
- Leaving a lobby now sets an `OfflineMultiplayerPeer` instead of no peer at all. With no peer,
  `multiplayer.get_unique_id()` printed errors everywhere. Test: `test_leaving_leaves_an_offline_peer`.
- In local mode a leaving *client* now also says goodbye, so the host notices at once (needed for
  net_core's reconnect test). Test: `test_client_leaving_is_noticed_by_host`.
