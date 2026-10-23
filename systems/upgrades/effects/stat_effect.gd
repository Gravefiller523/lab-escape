extends UpgradeEffect
## A number on the player (max_health, melee_damage, move_speed...) -> StatsComponent.add_modifier.
## Every PC adds it (stats are local data; health itself follows the host).


func apply(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void:
	var stats: StatsComponent = StatsComponent.of(player)
	if stats != null:
		stats.add_modifier(source_id, data as StatEffectData)


func remove(player: PlayerCharacter, _data: UpgradeEffectData, source_id: StringName) -> void:
	var stats: StatsComponent = StatsComponent.of(player)
	if stats != null:
		stats.remove_modifiers(source_id)
