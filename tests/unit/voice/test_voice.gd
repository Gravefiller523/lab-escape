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


## A player's voice effects, leaving out the muffle filter that is always last.
func _bus_effects(player_id: int) -> Array[AudioEffect]:
	var effects: Array[AudioEffect] = []
	var index: int = AudioServer.get_bus_index(_voice.get_bus_name(player_id))
	for effect_index: int in AudioServer.get_bus_effect_count(index):
		var effect: AudioEffect = AudioServer.get_bus_effect(index, effect_index)
		if effect != _voice.get_muffle_filter(player_id) and not _voice.get_echo_effects(player_id).has(effect):
			effects.append(effect)
	return effects


## A separate 3D world (own physics and navigation) holding the two test rooms.
func _rooms(navmesh: bool) -> Array:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var door: SoundDoor = VoiceTestRooms.build(root, navmesh)
	return [root.get_world_3d(), door]


func _head(spot: Vector3) -> Vector3:
	return spot + Vector3(0, 1.6, 0)


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
	assert_false(_voice.would_send(_voice.get_open_mic_threshold() * 0.5, false))
	assert_true(_voice.would_send(_voice.get_open_mic_threshold() * 2.0, false))


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


func test_muffle_lowers_volume_and_cutoff() -> void:
	var clear_gain: float = VoiceService.hearing_gain(10.0, 0.0, _config)
	var muffled_gain: float = VoiceService.hearing_gain(10.0, 1.0, _config)
	assert_lt(muffled_gain, clear_gain, "muffled voices are quieter")
	assert_gt(muffled_gain, 0.0, "but still heard")
	assert_gt(VoiceService.muffle_cutoff(0.0, _config), 15000.0, "clear = filter wide open")
	assert_almost_eq(VoiceService.muffle_cutoff(1.0, _config), _config.voice_muffle_cutoff_hz, 1.0)


func test_clear_line_of_sight_is_not_muffled() -> void:
	var parts: Array = _rooms(false)
	await wait_physics_frames(3)
	var world: World3D = parts[0]
	var hearing := VoiceHearing.compute(_head(Vector3(-3, 0, -2)), _head(VoiceTestRooms.ROOM_A_CENTER), world, _config)
	assert_eq(hearing.muffle, 0.0)
	assert_false(hearing.used_path)


func test_wall_without_navmesh_is_fully_muffled() -> void:
	var parts: Array = _rooms(false)
	await wait_physics_frames(3)
	var world: World3D = parts[0]
	var listener: Vector3 = _head(VoiceTestRooms.ROOM_B_CENTER)
	var speaker: Vector3 = _head(VoiceTestRooms.ROOM_A_CENTER)
	var hearing := VoiceHearing.compute(listener, speaker, world, _config)
	assert_eq(hearing.muffle, 1.0, "no way round: straight through the wall")
	assert_almost_eq(hearing.distance, listener.distance_to(speaker), 0.01)
	assert_false(hearing.used_path, "no navmesh: falls back cleanly")


func test_route_through_doorway_is_longer_and_comes_from_the_doorway() -> void:
	var parts: Array = _rooms(true)
	await wait_physics_frames(5)
	var world: World3D = parts[0]
	var listener: Vector3 = _head(VoiceTestRooms.ROOM_B_CENTER)
	var speaker: Vector3 = _head(VoiceTestRooms.ROOM_A_CENTER)
	var hearing := VoiceHearing.compute(listener, speaker, world, _config)
	assert_true(hearing.used_path, "goes the long way round")
	assert_gt(hearing.distance, listener.distance_to(speaker) + 1.0, "the route is longer than the straight line")
	assert_lt(hearing.muffle, 0.6, "only lightly muffled (corners), not through-the-wall")
	assert_gt(hearing.source.z, 2.5, "the voice seems to come from the hallway side")


func test_closed_door_muffles_open_door_does_not() -> void:
	var parts: Array = _rooms(true)
	await wait_physics_frames(5)
	var world: World3D = parts[0]
	var door: SoundDoor = parts[1]
	var listener: Vector3 = _head(VoiceTestRooms.ROOM_B_CENTER)
	var speaker: Vector3 = _head(VoiceTestRooms.ROOM_A_CENTER)
	var open_hearing := VoiceHearing.compute(listener, speaker, world, _config)
	door.is_open = false
	var closed_hearing := VoiceHearing.compute(listener, speaker, world, _config)
	door.is_open = true
	var reopened := VoiceHearing.compute(listener, speaker, world, _config)
	assert_eq(open_hearing.closed_doors, 0)
	assert_eq(closed_hearing.closed_doors, 1, "the route goes through the closed door")
	assert_gt(closed_hearing.muffle, open_hearing.muffle, "closed door muffles more")
	assert_lt(closed_hearing.muffle, 1.0 + 0.001)
	assert_lt(VoiceService.hearing_gain(closed_hearing.distance, closed_hearing.muffle, _config),
		VoiceService.hearing_gain(open_hearing.distance, open_hearing.muffle, _config), "and is quieter")
	assert_lt(VoiceService.muffle_cutoff(closed_hearing.muffle, _config),
		VoiceService.muffle_cutoff(open_hearing.muffle, _config), "and duller")
	assert_almost_eq(reopened.muffle, open_hearing.muffle, 0.001, "opening it again goes back")


func test_closed_door_on_direct_line_without_navmesh() -> void:
	var parts: Array = _rooms(false)
	await wait_physics_frames(3)
	var world: World3D = parts[0]
	var door: SoundDoor = parts[1]
	# Standing either side of the doorway, nothing solid in between (the stub door has no body here).
	var listener: Vector3 = _head(VoiceTestRooms.DOOR_CENTER + Vector3(0, 0, 1.5))
	var speaker: Vector3 = _head(VoiceTestRooms.DOOR_CENTER + Vector3(0, 0, -2))
	assert_eq(VoiceHearing.compute(listener, speaker, world, _config).muffle, 0.0, "open door: clear")
	door.is_open = false
	assert_almost_eq(VoiceHearing.compute(listener, speaker, world, _config).muffle,
		_config.voice_closed_door_muffle, 0.001, "closed door: muffled")


func test_long_quiet_tail_with_the_default_curve() -> void:
	var config := GameConfig.new()
	assert_eq(config.voice_max_distance, 46.0)
	assert_eq(VoiceService.hearing_gain(9.5, 0.0, config), 1.0, "full volume up to 10 m")
	var near: float = VoiceService.hearing_gain(14.0, 0.0, config)
	var middle: float = VoiceService.hearing_gain(22.0, 0.0, config)
	var far: float = VoiceService.hearing_gain(40.0, 0.0, config)
	assert_lt(near, 1.0)
	assert_lt(middle, near)
	assert_lt(far, middle, "keeps getting quieter")
	assert_gt(far, 0.01, "but far voices are still there")
	assert_eq(VoiceService.hearing_gain(46.5, 0.0, config), 0.0, "silent beyond 46 m")


func test_reverb_and_echo_grow_with_distance() -> void:
	var config := GameConfig.new()
	assert_gt(VoiceService.distance_reverb(0.0, config), 0.0, "some underground reverb even up close")
	assert_gt(VoiceService.distance_reverb(35.0, config), VoiceService.distance_reverb(15.0, config))
	assert_gt(VoiceService.distance_echo(35.0, config), VoiceService.distance_echo(10.0, config))


func test_far_voices_lose_treble() -> void:
	var config := GameConfig.new()
	var close: float = VoiceService.voice_cutoff(0.0, 2.0, config)
	var far: float = VoiceService.voice_cutoff(0.0, 38.0, config)
	assert_gt(close, 15000.0, "full sound up close")
	assert_lt(far, close, "duller far away")
	assert_lt(VoiceService.voice_cutoff(1.0, 38.0, config), far, "walls still muffle on top of distance")


func test_bus_has_distance_effects() -> void:
	var echo_effects: Array[AudioEffect] = _voice.get_echo_effects(11)
	assert_eq(echo_effects.size(), 2)
	assert_true(echo_effects[0] is AudioEffectReverb)
	assert_true(echo_effects[1] is AudioEffectDelay)


func test_closed_door_silences_past_15_metres() -> void:
	var config := GameConfig.new()
	var muffle: float = config.voice_closed_door_muffle
	assert_gte(muffle, 0.7, "a closed door muffles at least 70%")
	assert_gt(VoiceService.hearing_gain(12.0, muffle, config, 1), 0.0, "still heard at 12 m through a closed door")
	assert_eq(VoiceService.hearing_gain(15.5, muffle, config, 1), 0.0, "silent past 15 m through a closed door")
	assert_gt(VoiceService.hearing_gain(15.5, 0.0, config, 0), 0.0, "without a door it carries further")


func test_mic_sensitivity_changes_what_counts_as_speech() -> void:
	_voice.set_push_to_talk(false)
	var quiet_voice: float = 0.01
	_voice.set_mic_sensitivity(0.0)
	assert_false(_voice.would_send(quiet_voice, false), "low sensitivity ignores quiet talking")
	_voice.set_mic_sensitivity(1.0)
	assert_true(_voice.would_send(quiet_voice, false), "high sensitivity picks it up")
	assert_lt(VoiceService.sensitivity_to_threshold(0.9), VoiceService.sensitivity_to_threshold(0.1))
	_voice.set_push_to_talk(true)
	_voice.set_mic_sensitivity(0.0)
	assert_true(_voice.would_send(0.0, true), "push-to-talk always sends while V is held")


func test_closed_door_starts_fading_sooner() -> void:
	var config := GameConfig.new()
	assert_eq(VoiceService.hearing_gain(8.0, 0.0, config, 0), 1.0, "no door: still full volume at 8 m")
	assert_lt(VoiceService.hearing_gain(8.0, 0.0, config, 1), 1.0, "closed door: fading from 4 m")
