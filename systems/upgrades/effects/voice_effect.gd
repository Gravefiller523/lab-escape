extends UpgradeEffect
## How the player sounds -> Voice.set_voice_effect (every PC hears them through their own voice bus).


func apply(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void:
	Voice.set_voice_effect(player.player_id, source_id, data as VoiceEffectData)


func remove(player: PlayerCharacter, _data: UpgradeEffectData, source_id: StringName) -> void:
	Voice.clear_voice_effect(player.player_id, source_id)
