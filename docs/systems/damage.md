# damage

Folder: `res://systems/damage/` · Size: M · Phase 1b

## Purpose
Everything about getting hurt, shared by players, enemies, bosses and breakable props: a
`HealthComponent`, a `DamageInfo` message, damage types (blunt, sharp, fire...), a
`StatusEffectComponent` for timed effects like burning, a `StatsComponent` that holds numbers upgrades
can change (max health, melee damage, speed), and `Hurtbox` areas that receive hits.

**Not responsible for:** what happens at death (death_respawn for players, enemies/bosses for monsters), weapons (items), enemy attacks (enemies).

## Public API
```gdscript
class_name DamageInfo extends RefCounted
var amount: float
var damage_type: StringName          # &"blunt", &"sharp", &"fire", &"electric", &"poison" (free-form; new types need no code)
var source: Node                     # may be null
var source_player_id: int            # 0 if not a player
var hit_position: Vector3
var knockback: Vector3
var status_id: StringName            # status to apply on hit, or &""
static func make(amount: float, damage_type: StringName, source: Node = null) -> DamageInfo
func scaled(factor: float) -> DamageInfo    # NEW 2026-10-19: a copy with amount x factor (weak spots)

class_name HealthComponent extends Node
signal health_changed(current: float, maximum: float)
signal died(info: DamageInfo)
signal revived()                                 # NEW 2026-10-19: back from 0 (every PC)
@export var max_health: float = 100.0
@export var damage_multipliers: Dictionary = {}   # damage type -> multiplier, e.g. {"fire": 2.0} for the ent
var invulnerable: bool = false                    # god mode, spawn protection
func apply_damage(info: DamageInfo) -> void       # host only
func heal(amount: float) -> void                  # host only
func revive(health_fraction: float = 1.0) -> void # host only
func get_current() -> float
func get_max() -> float
func is_dead() -> bool
func get_fraction() -> float                      # NEW 2026-10-19: current / max
static func of(node: Node) -> HealthComponent

class_name StatusEffectComponent extends Node
signal status_added(status_id: StringName)
signal status_removed(status_id: StringName)
func apply(status_id: StringName, source_player_id: int = 0) -> void   # host only
func remove(status_id: StringName) -> void                            # host only
func has_status(status_id: StringName) -> bool
func get_active() -> Array[StringName]
func get_time_left(status_id: StringName) -> float   # NEW 2026-10-19, host: seconds left (-1 = until removed)
static func of(node: Node) -> StatusEffectComponent

class_name StatsComponent extends Node
signal stat_changed(stat: StringName, value: float)
func set_base(stat: StringName, value: float) -> void
func get_value(stat: StringName, default: float = 0.0) -> float   # CHANGED 2026-10-19: base (or `default` if never set), plus all adds, times all multiplies
func get_base(stat: StringName, default: float = 0.0) -> float    # NEW 2026-10-19
func has_modifiers(source_id: StringName) -> bool                  # NEW 2026-10-19
func add_modifier(source_id: StringName, modifier: StatEffectData) -> void
func remove_modifiers(source_id: StringName) -> void
static func of(node: Node) -> StatsComponent

class_name Hurtbox extends Area3D                  # on PhysicsLayers.HITBOXES
@export var health: HealthComponent
@export var multiplier: float = 1.0                # weak spots
func receive_hit(info: DamageInfo) -> void         # host only
func get_health() -> HealthComponent             # NEW 2026-10-19

# NEW 2026-10-19: autoload Damage (systems/damage/damage.gd, class DamageService)
func hit(target: Node, info: DamageInfo) -> bool  # host: through its Hurtbox if given one, else its HealthComponent
static func give_components(target: Node3D, max_health: float, hurtbox_radius: float = 0.4, hurtbox_height: float = 1.8) -> void
# Fixed child names: "Stats", "Health", "Statuses", "Hurtbox" (each class has NODE_NAME). of(node) finds them on the
# node, as its child, or up the parents.
```
Known stats: `max_health`, `move_speed`, `melee_damage`, `throw_strength`, `carry_strength` (extra kg
you can lift), `damage_taken` (multiplier). Unknown stat names simply have base 0 / multiplier 1, so
new stats need no code here.

NEW 2026-10-19: every player body gets "Stats", "Health" (`Config.game.player_max_health`, 100), "Statuses" and a
"Hurtbox" capsule from the Damage autoload when it spawns (the player scene isn't edited). `damage_taken` defaults
to 1 (`get_value(&"damage_taken", 1.0)`). A sibling StatsComponent's `max_health` stat (base = the component's
`max_health`) sets max health, keeping the same fraction when it changes. Damage of 0 or less does nothing (knockback
still pushes). A dead target loses its statuses. Console (cheats): `hurt [amount] [type]`, `heal [amount]`, `god`,
`status <id>`, `revive`.

## EventBus
- Emits: `damage_dealt` (host), `status_effect_applied` (all).
- Listens: none.

## Data it owns and saves
Uses `StatusEffectData` content. Saves nothing.

## Adding content
New status effects are `.tres` files in `content/status_effects/` (duration, tick damage, stat modifiers, visual). New damage types are just new names.

## Multiplayer
- Only the host changes health and statuses. Health (current, max) and active status ids are synced to
  all with a `MultiplayerSynchronizer` on the owner node; the `health_changed`/`died` signals fire on clients when synced values change.
  CHANGED 2026-10-19: synced with host -> everyone RPCs instead (health on every change, the list of active status
  ids when it changes), and each copy asks the host for the current state when it appears (joiners, late spawns).
  The node must have the same path on every PC (it does for players, and for anything spawned by a MultiplayerSpawner).
  `died` fires once on every PC (the host's copy has the source node; others get amount, type, player, position).
- Player knockback is forwarded to the owning PC through `PlayerMovement.apply_knockback`.

## Dependencies and stubs
Foundation only. Easiest system to build alone.

## Test scene and GUT tests
Test scene: a dummy target with health bar, buttons to deal each damage type and apply burning.
GUT tests: `test_damage_reduces_health`, `test_multiplier_by_type`, `test_died_emitted_once`,
`test_invulnerable_ignores_damage`, `test_status_ticks_damage_then_expires`, `test_reapply_refreshes_timer`,
`test_stats_add_then_multiply`, `test_remove_modifiers_by_source`, `test_client_cannot_apply_damage`.
DONE 2026-10-19: `systems/damage/test/damage_test.tscn` (a dummy with fire x2 and a weak-spot head, buttons to hurt it,
burn it, revive it, hurt / burn / speed-boost / heal yourself; your health top-left). GUT (`tests/unit/damage/test_damage.gd`,
19): every test above plus `test_damage_dealt_event_on_host`, `test_hurtbox_weak_spot_multiplies`,
`test_max_health_stat_keeps_the_fraction`, `test_damage_taken_stat_multiplies_damage`,
`test_status_stat_modifiers_and_visual_come_and_go`, `test_burning_content_shows_its_fire`,
`test_dead_targets_lose_their_statuses`, `test_player_bodies_get_damage_components`,
`test_health_is_the_same_on_host_and_client`, `test_late_client_copy_asks_for_the_health`.

## Acceptance criteria
- [ ] Players, enemies and a breakable crate all take damage through the same component.
  *Players and the test dummy do (2026-10-19); enemies and breakable props come with their systems.*
- [x] A new status effect file works with no code changes. *(`status_burning`, `status_speed_boost`; GUT registers more)*
- [ ] Health is consistent on host and 2 clients. *Host and 1 client match (GUT and 2 game copies, 2026-10-19).*

## Open design questions
- DEFAULT: no friendly fire from melee; thrown objects and fire can hurt teammates (it's funny). Tune in playtests.

## Changelog
- 2026-10-07: spec created.
- 2026-10-19: built (Phase 1b). Changes marked above: RPC syncing instead of a MultiplayerSynchronizer, the Damage
  autoload, `revived`, `get_fraction`, `scaled`, `get_base`, `has_modifiers`, `get_time_left`, `get_health`, fixed
  node names. New GameConfig `player_max_health` (100). Content: `status_burning`, `status_speed_boost`.

## HANDOFF
**Built (2026-10-19):** `DamageInfo`, `HealthComponent`, `StatsComponent`, `StatusEffectComponent`, `Hurtbox`, the
`Damage` autoload (`DamageService`: player components, `hit()`, console commands), a burning particle visual, two
status effects, the test scene and 19 GUT tests. Checked with 2 game copies: the host hurt the client's player and
the dummy, and both PCs showed the same health and statuses.

**Foundation / project.godot changes:** autoload line `Damage` (after DebugConsole). GameConfig `player_max_health`.
No new EventBus signals (emits `damage_dealt` on the host, `status_effect_applied` on every PC).

**STUB:** a player at 0 health gets a toast and is revived by the host after 3 s (`DamageService.STUB_REVIVE_SECONDS`)
until death_respawn exists.

**For the next systems:**
- **death_respawn:** listen to `HealthComponent.of(body).died` (or `player_died` once you emit it), replace the stub
  in `DamageService._on_player_died`, use `revive(fraction)` for reprints.
- **player:** read `StatsComponent.of(self).get_value(&"move_speed", 1.0)` as a speed multiplier (the speed boost
  status changes it; movement ignores it today), and `carry_strength` / `throw_strength` for physics_props.
- **items / enemies:** attack with `Damage.hit(hurtbox_or_node, DamageInfo.make(...))` on the host; clients send a
  request to the host first. Set `source_player_id` for kill credit; `status_id` to burn on hit.
- **ui:** a health bar in the HUD's `HealthSlot` from `HealthComponent.of(local body)` (`health_changed`).
- **physics_props:** breakable props can use `DamageService.give_components(prop, health)`.
