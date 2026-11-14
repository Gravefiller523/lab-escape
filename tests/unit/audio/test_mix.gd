extends GutTest
## The sound mix (NEW 2026-11-14, roadmap WP28): music ducks under voice chat, effects get a light room reverb,
## and a limiter keeps the game under its ceiling. Numbers come from GameConfig "Sound mix".


func _effect(bus: StringName, effect_class: String) -> AudioEffect:
	var index: int = AudioServer.get_bus_index(bus)
	for slot: int in AudioServer.get_bus_effect_count(index):
		var effect: AudioEffect = AudioServer.get_bus_effect(index, slot)
		if effect.is_class(effect_class):
			return effect
	return null


func _count(bus: StringName, effect_class: String) -> int:
	var index: int = AudioServer.get_bus_index(bus)
	var found: int = 0
	for slot: int in AudioServer.get_bus_effect_count(index):
		if AudioServer.get_bus_effect(index, slot).is_class(effect_class):
			found += 1
	return found


func test_music_ducks_under_voice_chat() -> void:
	SoundService.apply_mix(Config.game)
	var duck := _effect(&"Music", "AudioEffectCompressor") as AudioEffectCompressor
	assert_not_null(duck, "a compressor on the music")
	assert_eq(duck.sidechain, &"Voice", "listening to voice chat")
	assert_almost_eq(duck.ratio, Config.game.music_duck_ratio, 0.001)


func test_effects_get_the_room_reverb_and_master_a_limiter() -> void:
	SoundService.apply_mix(Config.game)
	var room := _effect(&"SFX", "AudioEffectReverb") as AudioEffectReverb
	assert_not_null(room, "room reverb on sound effects")
	assert_almost_eq(room.wet, Config.game.sfx_room_reverb, 0.001)
	assert_almost_eq(room.room_size, 0.55, 0.001, "the same room as voice chat")
	var limiter := _effect(&"Master", "AudioEffectHardLimiter") as AudioEffectHardLimiter
	assert_not_null(limiter, "a limiter on Master")
	assert_almost_eq(limiter.ceiling_db, Config.game.master_ceiling_db, 0.001)


func test_applying_the_mix_again_adds_nothing_twice() -> void:
	SoundService.apply_mix(Config.game)
	SoundService.apply_mix(Config.game)
	assert_eq(_count(&"Music", "AudioEffectCompressor"), 1)
	assert_eq(_count(&"SFX", "AudioEffectReverb"), 1)
	assert_eq(_count(&"Master", "AudioEffectHardLimiter"), 1)
