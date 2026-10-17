extends GutTest
## Tests for voice (docs/systems/voice.md). Uses made-up test tones, never the real microphone,
## and a fake Net so any number of players can be pretended.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")


## Pretends a roster: players with slot indexes 0, 1, 2...
class FakeNet:
	extends NetService
	var ids: Array[int] = []

	func get_player_ids() -> Array[int]:
		return ids.duplicate()

	func get_player_count() -> int:
		return ids.size()

	func get_slot_index(player_id: int) -> int:
		return ids.find(player_id)

	func local_player_id() -> int:
		return ids[0] if not ids.is_empty() else 0


var _net: FakeNet
var _config: GameConfig
var _voice: VoiceService


func before_each() -> void:
	_net = FakeNet.new()
	_net.ids = [11, 22] as Array[int]
	_config = GameConfig.new()
	_config.voice_full_volume_distance = 4.0
	_config.voice_max_distance = 30.0
	_voice = VoiceService.new()
	_voice.use_test_setup(_net, _config, "TestVoice_")
	add_child_autofree(_voice)


func after_each() -> void:
	_net.ids = [] as Array[int]
	_voice.sync_players()
	_net.free()


func _tone(seconds: float = 0.1, frequency: float = 440.0, loudness: float = 0.5) -> PackedVector2Array:
	var frames := PackedVector2Array()
	for index: int in int(seconds * VoiceCodec.SAMPLE_RATE):
		var sample: float = sin(TAU * frequency * float(index) / VoiceCodec.SAMPLE_RATE) * loudness
		frames.append(Vector2(sample, sample))
	return frames


func _fly(pitch: float = 1.5, preset: StringName = &"") -> VoiceEffectData:
	var effect := VoiceEffectData.new()
	effect.pitch_scale = pitch
	effect.effect_preset = preset
	return effect


func _bus_effects(player_id: int) -> Array[AudioEffect]:
	var effects: Array[AudioEffect] = []
	var index: int = AudioServer.get_bus_index(_voice.get_bus_name(player_id))
	for effect_index: int in AudioServer.get_bus_effect_count(index):
		effects.append(AudioServer.get_bus_effect(index, effect_index))
	return effects


func test_bus_created_per_player_and_freed() -> void:
	assert_eq(_voice.get_bus_name(11), &"TestVoice_0")
	assert_eq(_voice.get_bus_name(22), &"TestVoice_1")
	assert_gte(AudioServer.get_bus_index(&"TestVoice_1"), 0)
	_net.ids = [11] as Array[int]
	_voice.sync_players()
	assert_eq(_voice.get_bus_name(22), &"", "player 22 left")
	assert_lt(AudioServer.get_bus_index(&"TestVoice_1"), 0, "their bus is gone")


func test_bus_count_follows_player_count() -> void:
	_net.ids = [1, 2, 3, 4, 5, 6, 7, 8] as Array[int]
	_voice.sync_players()
	for player_id: int in _net.ids:
		assert_gte(AudioServer.get_bus_index(_voice.get_bus_name(player_id)), 0)
	assert_eq(_voice.get_bus_name(8), &"TestVoice_7")


func test_effect_applies_pitch_on_that_bus_only() -> void:
	_voice.set_voice_effect(11, &"mutation_fly", _fly(1.5))
	var effects: Array[AudioEffect] = _bus_effects(11)
	assert_eq(effects.size(), 1)
	assert_almost_eq((effects[0] as AudioEffectPitchShift).pitch_scale, 1.5, 0.001)
	assert_eq(_bus_effects(22).size(), 0, "the other player sounds normal")


func test_clear_effect_restores_bus() -> void:
	_voice.set_voice_effect(11, &"mutation_fly", _fly(1.5, &"buzz"))
	_voice.clear_voice_effect(11, &"mutation_fly")
	assert_eq(_bus_effects(11).size(), 0)


func test_two_sources_combine() -> void:
	_voice.set_voice_effect(11, &"mutation_fly", _fly(1.5, &"buzz"))
	_voice.set_voice_effect(11, &"cybernetic_test", _fly(1.2))
	var effects: Array[AudioEffect] = _bus_effects(11)
	assert_almost_eq((effects[0] as AudioEffectPitchShift).pitch_scale, 1.8, 0.001, "pitches multiply")
	assert_gt(effects.size(), 1, "the buzz preset added its effects too")


func test_preset_found_by_name() -> void:
	assert_not_null(VoiceService.load_preset(&"buzz"))
	assert_not_null(VoiceService.load_preset(&"deep"))
	assert_null(VoiceService.load_preset(&"preset_that_does_not_exist"))


func test_muted_player_silent() -> void:
	assert_true(_voice.feed_voice(22, _tone()), "heard when not muted")
	_voice.set_player_muted(22, true)
	assert_false(_voice.feed_voice(22, _tone()), "dropped when muted")
	assert_true(_voice.is_player_muted(22))


func test_push_to_talk_gates_sending() -> void:
	_voice.set_push_to_talk(true)
	assert_false(_voice.would_send(0.5, false), "loud, but the key isn't held")
	assert_true(_voice.would_send(0.0, true), "key held")


func test_open_mic_sends_only_when_loud_enough() -> void:
	_voice.set_push_to_talk(false)
	assert_false(_voice.would_send(_config.voice_open_mic_threshold * 0.5, false))
	assert_true(_voice.would_send(_config.voice_open_mic_threshold * 2.0, false))


func test_speaking_follows_voice_packets() -> void:
	watch_signals(EventBus)
	_voice.feed_voice(22, _tone())
	await wait_process_frames(2)
	assert_true(_voice.is_speaking(22))
	assert_signal_emitted_with_parameters(EventBus, "player_speaking_changed", [22, true])
	await wait_seconds(VoiceService.SPEAKING_HOLD_SECONDS + 0.2)
	assert_false(_voice.is_speaking(22))


func test_codec_round_trip_keeps_the_tone() -> void:
	var tone: PackedVector2Array = _tone(0.1, 440.0, 0.5)
	var bytes: PackedByteArray = VoiceCodec.encode(tone, float(VoiceCodec.SAMPLE_RATE))
	var back: PackedVector2Array = VoiceCodec.decode(bytes)
	assert_eq(back.size(), tone.size())
	assert_almost_eq(VoiceCodec.level(back), VoiceCodec.level(tone), 0.01)


func test_distance_gain_fades_then_cuts_off() -> void:
	assert_eq(VoiceService.distance_gain(2.0, 4.0, 30.0), 1.0, "full volume up close")
	var near: float = VoiceService.distance_gain(8.0, 4.0, 30.0)
	var far: float = VoiceService.distance_gain(20.0, 4.0, 30.0)
	assert_lt(near, 1.0)
	assert_lt(far, near, "quieter the farther away")
	assert_gt(far, 0.0)
	assert_eq(VoiceService.distance_gain(30.5, 4.0, 30.0), 0.0, "silent past the max distance")
	assert_eq(VoiceService.distance_gain(500.0, 4.0, 0.0), 1.0, "max 0 = everyone hears everyone")


func test_voice_from_body_is_quieter_farther_and_silent_beyond_max() -> void:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 22
	body.name = "22"
	body.set_multiplayer_authority(99)
	add_child_autofree(body)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	assert_true(_voice.feed_voice(22, _tone()), "voice plays from player 22's body")

	camera.global_position = body.global_position + Vector3(0, 1.6, 2.0)
	var close: float = _voice.get_voice_volume(22)
	camera.global_position = body.global_position + Vector3(0, 1.6, 15.0)
	var middle: float = _voice.get_voice_volume(22)
	camera.global_position = body.global_position + Vector3(0, 1.6, 40.0)
	var beyond: float = _voice.get_voice_volume(22)
	assert_almost_eq(close, 1.0, 0.001, "full volume up close")
	assert_lt(middle, close, "quieter farther away")
	assert_eq(beyond, 0.0, "silent beyond the max distance")
