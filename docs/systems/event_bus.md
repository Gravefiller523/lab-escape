# event_bus

Folder: `res://core/autoload/event_bus.gd` · Size: done · Phase 0

## Purpose
A global notice board. When something happens that several systems may care about (a player died,
a boss was beaten), the owning system emits one signal on `EventBus`, and anyone can listen without
the two systems knowing about each other. This keeps systems independent, so they can be built separately.

**Not responsible for:** sending anything over the network, asking systems to do things (call their
public API instead), or storing state.

## Rules
1. **Local only.** EventBus never crosses the network. The "Fires on" column says on which PCs the
   owning system emits it: `host` (only on the host), `all` (on every PC, once the change is synced),
   `local` (only the PC it concerns).
2. **Only the owner emits.** Each signal has one owning system.
3. **Facts, not commands.** Names are past tense. Emitted after the change has happened.
4. **Ids, not objects**, where possible: `player_id` (Steam ID), content ids (`&"mutation_fly"`).
   Nodes are passed only when listeners need the node itself.
5. **Listeners must be cheap and must not assume order.** Don't emit another EventBus signal inside
   a listener for the same event in a way that depends on order.
6. Connect in `_ready()` with typed handlers: `EventBus.player_died.connect(_on_player_died)`.
   Disconnect in `_exit_tree()` if your node can be freed before the game ends.
7. **Adding a signal:** add it to `event_bus.gd` under the owner's section with a "Fires on" comment,
   add it to the table below, and list it in your merge notes. Never rename or remove one without the user's OK.

## Signals

| Signal | Owner | Fires on |
|---|---|---|
| `game_state_changed(old_state: int, new_state: int)` | game_flow | all |
| `run_started(run_seed: int)` | game_flow | all |
| `run_ended(result: StringName)` (`&"escaped"`, `&"wiped"`, `&"abandoned"`) | game_flow | all |
| `floor_loading(floor_number: int, department_id: StringName)` | game_flow | all |
| `floor_ready(floor_number: int, department_id: StringName)` | game_flow | all |
| `boss_floor_started(boss_id: StringName)` | game_flow | all |
| `player_joined(player_id: int)` | net_core | all |
| `player_left(player_id: int)` | net_core | all |
| `player_reconnected(player_id: int)` | net_core | all |
| `player_spawned(player_id: int, player_node: Node3D)` | player | all |
| `local_player_spawned(player_node: Node3D)` | player | local |
| `damage_dealt(target: Node, amount: float, damage_type: StringName, source: Node)` | damage | host |
| `status_effect_applied(target: Node, status_id: StringName)` | damage | all |
| `player_died(player_id: int, death_position: Vector3)` | death_respawn | all |
| `player_reprinted(player_id: int)` | death_respawn | all |
| `team_wiped()` | death_respawn | all |
| `enemy_killed(enemy_id: StringName, death_position: Vector3, killer_player_id: int)` | enemies | host |
| `boss_phase_changed(boss_id: StringName, phase_index: int)` | bosses | all |
| `boss_defeated(boss_id: StringName)` | bosses | all |
| `upgrade_gained(player_id: int, upgrade_id: StringName)` | upgrades | all |
| `upgrade_lost(player_id: int, upgrade_id: StringName)` | upgrades | all |
| `inventory_changed(player_id: int)` | inventory | all |
| `item_used(player_id: int, item_id: StringName)` | items | all |
| `prop_grabbed(player_id: int, prop: Node3D)` | physics_props | all |
| `prop_released(player_id: int, prop: Node3D, thrown: bool)` | physics_props | all |
| `key_object_respawned(prop: Node3D)` | physics_props | all |
| `cart_contents_changed(cart: Node3D)` | carts | all |
| `loot_dropped(source_id: StringName, drop_position: Vector3)` | loot | host |
| `vendor_purchase(player_id: int, item_id: StringName, price: int)` | vendors | all |
| `lift_part_delivered(parts_delivered: int, parts_needed: int)` | cargo_lift | all |
| `lift_ready()` | cargo_lift | all |
| `lift_departed(floor_number: int)` | cargo_lift | all |
| `floor_task_completed(task_id: StringName)` | objectives | all |
| `door_unlocked(door: Node3D)` | objectives | all |
| `elevator_start_accepted()` | break_room | all |
| `cosmetics_changed(player_id: int)` | cosmetics | all |
| `cosmetic_unlocked(cosmetic_id: StringName)` | cosmetics | local |
| `player_speaking_changed(player_id: int, speaking: bool)` | voice | local |
| `achievement_unlocked(achievement_id: StringName)` | achievements | local |
| `settings_changed(section: StringName)` | settings_input | local |
| `toast_requested(text: String)` | ui (anyone may emit) | local |

## Multiplayer
How an "all" event reaches clients: the owning system syncs its state (RPC or synchronizer), and when
the client receives it, the owning system emits the event on that client too.

## Dependencies
None.

## Tests
- Foundation check: every signal above exists on `EventBus` (headless check done in planning).
- Each owning system's GUT tests use `watch_signals(EventBus)` and `assert_signal_emitted` to prove it emits its events.

## Acceptance criteria
- [x] All signals declared with typed arguments; the file has no warnings.
- [ ] Each owning system has a GUT test proving it emits its signals.

## Open design questions
- DEFAULT: `damage_dealt` and `enemy_killed` fire on host only, because only the host simulates
  combat. If a client-side listener needs them (hit markers in the HUD), the owning system adds an
  "all" version.

## Changelog
- 2026-10-07: created with the initial signal list.
