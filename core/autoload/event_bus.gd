extends Node
## Autoload "EventBus". A notice board for "something just happened" messages.
##
## Rules (see CLAUDE.md for the full version):
## - EventBus is LOCAL. It never sends anything over the network. Each PC emits
##   events itself: the host when it decides something, clients when the synced
##   result reaches them. Each signal below says where it fires.
## - Emit an event only from the system that owns it (named in [brackets]).
## - Events report facts that already happened. To ASK a system to do something,
##   call its public API instead.
## - player_id is always the player's Steam ID (stable across reconnects).
##   peer_id is Godot's network id and is only used inside networking code.
## - Adding a signal is a foundation change: add it here, document it in
##   docs/systems/event_bus.md, and say so in your merge notes.
## Signals are emitted from other scripts, so Godot thinks they are unused here.
@warning_ignore_start("unused_signal")

# --- Game flow [game_flow] -------------------------------------------------
## Fires on: all. States are GameFlow.State values.
signal game_state_changed(old_state: int, new_state: int)
## Fires on: all, when the elevator leaves the Break Room.
signal run_started(run_seed: int)
## Fires on: all. result is &"escaped", &"wiped" or &"abandoned".
signal run_ended(result: StringName)
## Fires on: all, before a floor is built. floor_number counts from 1 for the whole run.
signal floor_loading(floor_number: int, department_id: StringName)
## Fires on: all, when the floor is built and every player is placed.
signal floor_ready(floor_number: int, department_id: StringName)
## Fires on: all, when the players step out of the lift onto a boss floor.
signal boss_floor_started(boss_id: StringName)

# --- Players and network [net_core] ----------------------------------------
## Fires on: all.
signal player_joined(player_id: int)
## Fires on: all. The host keeps the player's run state in case they come back.
signal player_left(player_id: int)
## Fires on: all, when a player who left during this run returns.
signal player_reconnected(player_id: int)
## Fires on: all, when a player's body is created in the current scene. [player]
signal player_spawned(player_id: int, player_node: Node3D)
## Fires on: the local PC only, for its own player. [player]
signal local_player_spawned(player_node: Node3D)

# --- Damage and death [damage] [death_respawn] -----------------------------
## Fires on: host. target is the node that owns the HealthComponent.
signal damage_dealt(target: Node, amount: float, damage_type: StringName, source: Node)
## Fires on: all. [damage]
signal status_effect_applied(target: Node, status_id: StringName)
## Fires on: all. [death_respawn]
signal player_died(player_id: int, death_position: Vector3)
## Fires on: all. [death_respawn]
signal player_reprinted(player_id: int)
## Fires on: all, when every player is dead at once. The run ends next. [death_respawn]
signal team_wiped()

# --- Enemies and bosses [enemies] [bosses] ----------------------------------
## Fires on: host. killer_player_id is 0 if no player made the kill. [enemies]
signal enemy_killed(enemy_id: StringName, death_position: Vector3, killer_player_id: int)
## Fires on: all. [bosses]
signal boss_phase_changed(boss_id: StringName, phase_index: int)
## Fires on: all. [bosses]
signal boss_defeated(boss_id: StringName)

# --- Upgrades [upgrades] -----------------------------------------------------
## Fires on: all.
signal upgrade_gained(player_id: int, upgrade_id: StringName)
## Fires on: all (replaced by a clash, or removed by a cheat or future item).
signal upgrade_lost(player_id: int, upgrade_id: StringName)

# --- Items and inventory [inventory] [items] --------------------------------
## Fires on: all.
signal inventory_changed(player_id: int)
## Fires on: all. [items]
signal item_used(player_id: int, item_id: StringName)

# --- Physics props and carts [physics_props] [carts] ------------------------
## Fires on: all.
signal prop_grabbed(player_id: int, prop: Node3D)
## Fires on: all. thrown is true for a throw, false for a gentle drop.
signal prop_released(player_id: int, prop: Node3D, thrown: bool)
## Fires on: all, when a key object fell out of the world and was put back.
signal key_object_respawned(prop: Node3D)
## Fires on: all. [carts]
signal cart_contents_changed(cart: Node3D)

# --- Loot and vendors [loot] [vendors] ---------------------------------------
## Fires on: host, after drops are spawned. [loot]
signal loot_dropped(source_id: StringName, drop_position: Vector3)
## Fires on: all. [vendors]
signal vendor_purchase(player_id: int, item_id: StringName, price: int)

# --- Progression [cargo_lift] [objectives] ---------------------------------
## Fires on: all. [cargo_lift]
signal lift_part_delivered(parts_delivered: int, parts_needed: int)
## Fires on: all, when the lift has every part it needs. [cargo_lift]
signal lift_ready()
## Fires on: all, when the lift starts moving to the next floor. [cargo_lift]
signal lift_departed(floor_number: int)
## Fires on: all. [objectives]
signal floor_task_completed(task_id: StringName)
## Fires on: all. [objectives]
signal door_unlocked(door: Node3D)

# --- Break Room and cosmetics [break_room] [cosmetics] -----------------------
## Fires on: all, when the host accepts the elevator button. [break_room]
signal elevator_start_accepted()
## Fires on: all, when a player's chosen look changes. [cosmetics]
signal cosmetics_changed(player_id: int)
## Fires on: local PC only. [cosmetics]
signal cosmetic_unlocked(cosmetic_id: StringName)

# --- Voice [voice] -----------------------------------------------------------
## Fires on: local PC, as it plays each player's voice.
signal player_speaking_changed(player_id: int, speaking: bool)

# --- Steam extras [achievements] ---------------------------------------------
## Fires on: local PC only.
signal achievement_unlocked(achievement_id: StringName)

# --- Settings and UI [settings_input] [ui] -----------------------------------
## Fires on: local PC only. section is e.g. &"audio", &"video", &"controls".
signal settings_changed(section: StringName)
## Fires on: local PC only. Any system may emit this to show a short message. [ui]
signal toast_requested(text: String)

@warning_ignore_restore("unused_signal")
