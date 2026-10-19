class_name DamageInfo
extends RefCounted
## One hit: how much, what kind, who did it. Passed to HealthComponent.apply_damage (host only).
## Damage types are free-form names (&"blunt", &"sharp", &"fire", &"electric", &"poison"): a new type
## needs no code, only multipliers that mention it. Spec: docs/systems/damage.md.

var amount: float = 0.0
var damage_type: StringName = &""
## What hit you (a weapon, an enemy, a prop). May be null.
var source: Node
## The player behind the hit (their Steam ID), or 0 if not a player.
var source_player_id: int = 0
var hit_position: Vector3 = Vector3.ZERO
## Push given to the target (metres per second for players, an impulse for physics bodies).
var knockback: Vector3 = Vector3.ZERO
## Status effect to apply on hit (a StatusEffectData id), or &"".
var status_id: StringName = &""


static func make(amount_: float, damage_type_: StringName, source_: Node = null) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_
	info.damage_type = damage_type_
	info.source = source_
	var player := PlayerCharacter.of(source_) if source_ != null else null
	if player != null:
		info.source_player_id = player.player_id
	return info


## A copy with a different amount (weak spots, multipliers).
func scaled(factor: float) -> DamageInfo:
	var copy := DamageInfo.make(amount * factor, damage_type, source)
	copy.source_player_id = source_player_id
	copy.hit_position = hit_position
	copy.knockback = knockback
	copy.status_id = status_id
	return copy
