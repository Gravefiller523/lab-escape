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

class_name HealthComponent extends Node
signal health_changed(current: float, maximum: float)
signal died(info: DamageInfo)
@export var max_health: float = 100.0
@export var damage_multipliers: Dictionary = {}   # damage type -> multiplier, e.g. {"fire": 2.0} for the ent
var invulnerable: bool = false                    # god mode, spawn protection
func apply_damage(info: DamageInfo) -> void       # host only
func heal(amount: float) -> void                  # host only
func revive(health_fraction: float = 1.0) -> void # host only
func get_current() -> float
func get_max() -> float
func is_dead() -> bool
static func of(node: Node) -> HealthComponent

class_name StatusEffectComponent extends Node
signal status_added(status_id: StringName)
signal status_removed(status_id: StringName)
func apply(status_id: StringName, source_player_id: int = 0) -> void   # host only
func remove(status_id: StringName) -> void                            # host only
func has_status(status_id: StringName) -> bool
func get_active() -> Array[StringName]
static func of(node: Node) -> StatusEffectComponent

class_name StatsComponent extends Node
signal stat_changed(stat: StringName, value: float)
func set_base(stat: StringName, value: float) -> void
func get_value(stat: StringName) -> float          # base, plus all adds, times all multiplies
func add_modifier(source_id: StringName, modifier: StatEffectData) -> void
func remove_modifiers(source_id: StringName) -> void
static func of(node: Node) -> StatsComponent

class_name Hurtbox extends Area3D                  # on PhysicsLayers.HITBOXES
@export var health: HealthComponent
@export var multiplier: float = 1.0                # weak spots
func receive_hit(info: DamageInfo) -> void         # host only
```
Known stats: `max_health`, `move_speed`, `melee_damage`, `throw_strength`, `carry_strength` (extra kg
you can lift), `damage_taken` (multiplier). Unknown stat names simply have base 0 / multiplier 1, so
new stats need no code here.

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
- Player knockback is forwarded to the owning PC through `PlayerMovement.apply_knockback`.

## Dependencies and stubs
Foundation only. Easiest system to build alone.

## Test scene and GUT tests
Test scene: a dummy target with health bar, buttons to deal each damage type and apply burning.
GUT tests: `test_damage_reduces_health`, `test_multiplier_by_type`, `test_died_emitted_once`,
`test_invulnerable_ignores_damage`, `test_status_ticks_damage_then_expires`, `test_reapply_refreshes_timer`,
`test_stats_add_then_multiply`, `test_remove_modifiers_by_source`, `test_client_cannot_apply_damage`.

## Acceptance criteria
- [ ] Players, enemies and a breakable crate all take damage through the same component.
- [ ] A new status effect file works with no code changes.
- [ ] Health is consistent on host and 2 clients.

## Open design questions
- DEFAULT: no friendly fire from melee; thrown objects and fire can hurt teammates (it's funny). Tune in playtests.

## Changelog
- 2026-10-07: spec created.
