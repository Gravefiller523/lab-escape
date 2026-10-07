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
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: String)
signal connection_lost()                       # we were the client and the host vanished

func is_steam_running() -> bool
func get_local_steam_id() -> int               # in local mode: a fake id (1, 2, 3...) per window
func get_persona_name(steam_id: int) -> String
func get_avatar(steam_id: int) -> Texture2D    # may return null first, then a cached texture
func host_lobby() -> void                      # friends-only, max members = Config.game.max_players
func join_lobby(lobby_id: int) -> void
func leave_lobby() -> void
func get_lobby_id() -> int                     # 0 when not in a lobby
func get_lobby_member_ids() -> Array[int]
func set_lobby_joinable(joinable: bool) -> void   # host; net_core closes joining during a run
func open_invite_overlay() -> void
func set_rich_presence(key: String, value: String) -> void
func host_local(port: int = 7777) -> void      # testing without Steam
func join_local(address: String = "127.0.0.1", port: int = 7777) -> void
func is_local_mode() -> bool
```
Rich presence keys used: `status` ("In the Break Room", "Zoology, floor 3", "Fighting the Giant Rat").
`steam_display` uses localisation tokens set up later on the Steamworks site.

## EventBus
- Emits: none (its own signals above are for net_core and ui).
- Listens: `game_state_changed`, `floor_ready`, `boss_floor_started` → updates rich presence.

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

## Dependencies and stubs
- GodotSteam (GDExtension or the pre-built editor) matching Godot 4.7, **including
  SteamMultiplayerPeer** (check whether your GodotSteam download includes it; for the GDExtension it
  may be a separate add-on).
- Stub for others: local mode *is* the stub. Every other system tests with `host_local()`/`join_local()`.

## Test scene and GUT tests
Test scene `systems/steam_session/test/lobby_test.tscn`: buttons for Host (Steam), Join by id,
Invite, Host local, Join local, and a label listing lobby members. Run 2 instances.
GUT tests (`tests/unit/steam_session/`):
- `test_local_host_and_join_connect`: two peers in one test via ENet, client gets `connected_to_server`.
- `test_is_steam_running_false_without_steam`: no crash when Steam isn't running; local mode still works.
- `test_lobby_size_uses_config`: the max-members argument comes from `Config.game.max_players` (inject a config with 8).

## Acceptance criteria
- [ ] Two PCs on different Steam accounts: host creates a lobby, invites, friend joins from the overlay.
- [ ] Two local windows connect with `host_local`/`join_local`.
- [ ] Lobby size follows `max_players`; nothing assumes 4.
- [ ] Rich presence shows in the Steam friends list.
- [ ] Host quitting sends the client back to the menu without errors.

## Open design questions
- DEFAULT: lobbies are friends-only (no public browser).
- Which exact GodotSteam build (GDExtension vs. pre-built editor) works best with GUT and exports? Decide in Phase 1a.

## Changelog
- 2026-10-07: spec created.
