class_name VoiceService
extends Node
## Autoload "Voice". Proximity voice chat where mutations change how you sound.
##
## Every player gets their own audio bus ("Voice_<slot>") with their effects (pitch, presets like
## Fly's "buzz"), so effects apply to that player only. Remote voices play from the speaker's head
## in 3D. Over Steam, Steam records and compresses the mic; in local mode (no Steam) Godot records the
## mic and sends plain 16 kHz audio. Nothing is ever saved to disk. Spec: docs/systems/voice.md.

const MIC_BUS: StringName = &"VoiceMic"
## audio owns this bus; until it exists, voices go to Master.
const OUTPUT_BUS: StringName = &"Voice"
const FALLBACK_BUS: StringName = &"Master"
const PRESETS_FOLDER: String = "res://systems/voice/presets/"
## A player counts as "speaking" for this long after their last voice packet.
const SPEAKING_HOLD_SECONDS: float = 0.3
## Seconds of audio each listener can buffer (more = smoother, but more delay).
const BUFFER_SECONDS: float = 0.3
## Byte budgets for Steam's getVoice/decompressVoice.
const STEAM_VOICE_BUFFER: int = 8192
const STEAM_DECOMPRESSED_BUFFER: int = 32768
## Steam's "OK" result for voice calls.
const STEAM_VOICE_OK: int = 0
const NODE_NAME_3D: String = "VoiceSpeaker"
## The muffle filter when nothing is in the way (above what people can hear).
const OPEN_CUTOFF_HZ: float = 20000.0
## How fast muffling fades in and out (full change in 1 / this seconds).
const MUFFLE_FADE_PER_SECOND: float = 3.0
## How fast a voice glides to a new spot (e.g. a doorway) when you walk round a corner.
const SOURCE_GLIDE_SPEED: float = 8.0

var _net: NetService
var _config: GameConfig
var _bus_prefix: String = "Voice_"
## Off in tests: no microphone, no sending.
var _live: bool = true
var _buses: Dictionary[int, StringName] = {}
## player_id -> {source_id: VoiceEffectData}
var _effects: Dictionary[int, Dictionary] = {}
var _speakers: Dictionary[int, Node] = {}
var _playbacks: Dictionary[int, AudioStreamGeneratorPlayback] = {}
var _muted: Dictionary[int, bool] = {}
var _last_heard_msec: Dictionary[int, int] = {}
var _speaking: Dictionary[int, bool] = {}
var _presets: Dictionary[StringName, Callable] = {}
var _preset_objects: Array[VoicePreset] = []
var _push_to_talk: bool = false
var _reduce_effects: bool = false
var _loopback: bool = false
## A flat AudioStreamPlayer, or an AudioStreamPlayer3D when the loopback has an anchor.
var _loopback_player: Node
var _loopback_playback: AudioStreamGeneratorPlayback
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _steam_recording: bool = false
var _input_level: float = 0.0
var _open_mic_hold: float = 0.0
var _transmitting: bool = false
var _muffle_filters: Dictionary[int, AudioEffectLowPassFilter] = {}
## Latest hearing check per player (from _physics_process), and the smoothed muffle now.
var _hearing: Dictionary[int, VoiceHearing] = {}
var _muffle_now: Dictionary[int, float] = {}
var _hearing_timer: float = 0.0


## For tests only: a fake Net and config, a different bus name prefix, and no microphone.
## Call before adding the node to the tree.
func use_test_setup(net: NetService, config: GameConfig, bus_prefix: String) -> void:
	_net = net
	_config = config
	_bus_prefix = bus_prefix
	_live = false


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	_push_to_talk = _config.voice_push_to_talk_default
	_net.roster_changed.connect(sync_players)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.settings_changed.connect(_on_settings_changed)
	sync_players()


func _exit_tree() -> void:
	for player_id: int in _buses.keys():
		_remove_player(player_id)
	_stop_mic()


# --- Public API -------------------------------------------------------------------------------

func is_speaking(player_id: int) -> bool:
	return _speaking.get(player_id, false)


## 0 to 1: how loud the local microphone is right now.
func get_input_level() -> float:
	return _input_level


## Adds or replaces one source's effect (usually an upgrade id) on a player's voice.
## Call it on every PC: each PC applies the speaker's effects itself.
func set_voice_effect(player_id: int, source_id: StringName, effect: VoiceEffectData) -> void:
	if not _effects.has(player_id):
		_effects[player_id] = {}
	_effects[player_id][source_id] = effect
	_rebuild_bus(player_id)


func clear_voice_effect(player_id: int, source_id: StringName) -> void:
	if _effects.has(player_id):
		_effects[player_id].erase(source_id)
	_rebuild_bus(player_id)


## Local only: stop hearing one player.
func set_player_muted(player_id: int, muted: bool) -> void:
	_muted[player_id] = muted


func is_player_muted(player_id: int) -> bool:
	return _muted.get(player_id, false)


## Hear your own voice with your own effects (mirror, settings). With an anchor, your voice plays
## from that spot in the world and fades with distance like another player's would (echo dummy).
func set_loopback(enabled: bool, anchor: Node3D = null) -> void:
	_loopback = enabled
	if _loopback_player != null:
		_loopback_player.queue_free()
		_loopback_player = null
		_loopback_playback = null
	if enabled:
		if anchor != null:
			var speaker_3d := AudioStreamPlayer3D.new()
			_setup_distance_fade(speaker_3d)
			anchor.add_child(speaker_3d)
			_loopback_player = speaker_3d
		else:
			var flat := AudioStreamPlayer.new()
			add_child(flat)
			_loopback_player = flat
		_loopback_player.name = "Loopback"
		_loopback_player.set(&"stream", _make_generator())
		_loopback_player.call(&"play")
		_loopback_playback = _loopback_player.call(&"get_stream_playback") as AudioStreamGeneratorPlayback
	_route_loopback()


## How loud a voice is at this distance, 0 to 1: full volume up to `full_distance`, then fading
## smoothly to silence at `max_distance`. max_distance 0 means everyone hears everyone at full volume.
static func distance_gain(distance: float, full_distance: float, max_distance: float) -> float:
	if max_distance <= 0.0 or distance <= full_distance:
		return 1.0
	if distance >= max_distance:
		return 0.0
	var t: float = (distance - full_distance) / maxf(max_distance - full_distance, 0.001)
	return 1.0 - smoothstep(0.0, 1.0, t)


## How loud a player's voice is for you right now (0 to 1): distance (the long way round through
## doors when walls are in the way) and muffling. 1 for voices with no position.
func get_voice_volume(player_id: int) -> float:
	var hearing: VoiceHearing = get_hearing(player_id)
	if hearing == null:
		return 1.0
	return _gain(hearing, hearing.muffle)


## How you hear a player right now (distance, muffle, where it comes from), worked out fresh.
## Null for voices with no position.
func get_hearing(player_id: int) -> VoiceHearing:
	var speaker: AudioStreamPlayer3D = _speakers_3d().get(player_id)
	return _compute_hearing(speaker) if speaker != null else null


## The low-pass filter that muffles a player's voice (last effect on their bus). Null if none.
func get_muffle_filter(player_id: int) -> AudioEffectLowPassFilter:
	return _muffle_filters.get(player_id)


func is_loopback() -> bool:
	return _loopback


## The bus a player's voice plays through, e.g. &"Voice_0". &"" if they have none.
func get_bus_name(player_id: int) -> StringName:
	return _buses.get(player_id, &"")


## Adds a preset by code. builder: func(bus_index: int, strength: float) -> void.
## Presets in systems/voice/presets/<name>_preset.gd are found without this.
func register_preset(preset: StringName, builder: Callable) -> void:
	_presets[preset] = builder


## STUB until settings_input: switch push-to-talk on or off (default from Config).
func set_push_to_talk(enabled: bool) -> void:
	_push_to_talk = enabled


func is_push_to_talk() -> bool:
	return _push_to_talk


## Makes sure every player in the roster has a bus, and removes buses of players who left.
## Runs by itself when the roster changes.
func sync_players() -> void:
	var wanted: Array[int] = _net.get_player_ids()
	# Remove first, so a freed slot's bus name can be reused by a new player.
	for player_id: int in _buses.keys():
		if not wanted.has(player_id):
			_remove_player(player_id)
	for player_id: int in wanted:
		if not _buses.has(player_id):
			_create_bus(player_id)
	_route_loopback()


## Plays voice audio from a player (frames at VoiceCodec.SAMPLE_RATE). Returns false if it was
## dropped (muted, or no bus). Used by the network code and by tests.
func feed_voice(player_id: int, frames: PackedVector2Array) -> bool:
	if is_player_muted(player_id) or not _buses.has(player_id):
		return false
	var playback: AudioStreamGeneratorPlayback = _ensure_speaker(player_id)
	_last_heard_msec[player_id] = Time.get_ticks_msec()
	if playback != null:
		_push_frames(playback, frames)
	return true


## Whether the local mic should send right now. Push-to-talk: only while the key is held.
## Open mic: while loud enough (plus a short hold so words don't get cut).
func would_send(level: float, push_to_talk_held: bool) -> bool:
	if _push_to_talk:
		return push_to_talk_held
	return level >= _config.voice_open_mic_threshold or _open_mic_hold > 0.0


## True while the local mic is being sent.
func is_transmitting() -> bool:
	return _transmitting


## Loads a preset by name from presets/<name>_preset.gd. Null if there is none.
static func load_preset(preset: StringName) -> VoicePreset:
	var path: String = PRESETS_FOLDER + String(preset) + "_preset.gd"
	if not ResourceLoader.exists(path):
		return null
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		return null
	return script.new() as VoicePreset


# --- Buses and effects ------------------------------------------------------------------------

func _create_bus(player_id: int) -> void:
	var slot: int = _net.get_slot_index(player_id)
	var bus_name := StringName(_bus_prefix + (str(slot) if slot >= 0 else "p%d" % player_id))
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	var index: int = AudioServer.get_bus_index(bus_name)
	var output: StringName = OUTPUT_BUS if AudioServer.get_bus_index(OUTPUT_BUS) >= 0 else FALLBACK_BUS
	AudioServer.set_bus_send(index, output)
	_buses[player_id] = bus_name
	_rebuild_bus(player_id)


func _remove_player(player_id: int) -> void:
	var speaker: Node = _speakers.get(player_id)
	if speaker != null and is_instance_valid(speaker):
		speaker.queue_free()
	_speakers.erase(player_id)
	_playbacks.erase(player_id)
	_last_heard_msec.erase(player_id)
	_muffle_filters.erase(player_id)
	_hearing.erase(player_id)
	_muffle_now.erase(player_id)
	if _speaking.get(player_id, false):
		EventBus.player_speaking_changed.emit(player_id, false)
	_speaking.erase(player_id)
	var bus_name: StringName = _buses.get(player_id, &"")
	_buses.erase(player_id)
	var index: int = AudioServer.get_bus_index(bus_name) if bus_name != &"" else -1
	if index > 0:
		AudioServer.remove_bus(index)


## Clears a player's bus and adds their effects again: pitch (all sources multiplied) then presets.
func _rebuild_bus(player_id: int) -> void:
	var index: int = AudioServer.get_bus_index(get_bus_name(player_id))
	if index < 0:
		return
	for effect_index: int in range(AudioServer.get_bus_effect_count(index) - 1, -1, -1):
		AudioServer.remove_bus_effect(index, effect_index)
	var sources: Dictionary = _effects.get(player_id, {})
	var pitch: float = 1.0
	for effect: VoiceEffectData in sources.values():
		pitch *= effect.pitch_scale
	if not is_equal_approx(pitch, 1.0):
		var shift := AudioEffectPitchShift.new()
		shift.pitch_scale = clampf(pitch, 0.01, 16.0)
		AudioServer.add_bus_effect(index, shift)
	for effect: VoiceEffectData in sources.values():
		if effect.effect_preset == &"":
			continue
		var builder: Callable = _preset_builder(effect.effect_preset)
		if builder.is_valid():
			var strength: float = effect.effect_strength * (0.5 if _reduce_effects else 1.0)
			builder.call(index, strength)
		else:
			print("Voice: no preset called '%s' yet." % effect.effect_preset)
	# Always last: the muffle filter, opened and closed by _update_volumes().
	var muffle := AudioEffectLowPassFilter.new()
	muffle.cutoff_hz = OPEN_CUTOFF_HZ
	AudioServer.add_bus_effect(index, muffle)
	_muffle_filters[player_id] = muffle


func _preset_builder(preset: StringName) -> Callable:
	if _presets.has(preset):
		return _presets[preset]
	var loaded: VoicePreset = load_preset(preset)
	if loaded == null:
		return Callable()
	# Keep the preset object alive: a Callable alone doesn't.
	_preset_objects.append(loaded)
	_presets[preset] = loaded.build
	return _presets[preset]


# --- Playing voices ---------------------------------------------------------------------------

func _make_generator() -> AudioStreamGenerator:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = VoiceCodec.SAMPLE_RATE
	generator.buffer_length = BUFFER_SECONDS
	return generator


## The speaker node for a remote player: 3D at their head if they have a body, flat otherwise.
func _ensure_speaker(player_id: int) -> AudioStreamGeneratorPlayback:
	var existing: Node = _speakers.get(player_id)
	if existing != null and is_instance_valid(existing):
		return _playbacks.get(player_id)
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var player: Node
	if body != null:
		var speaker_3d := AudioStreamPlayer3D.new()
		speaker_3d.name = NODE_NAME_3D
		speaker_3d.stream = _make_generator()
		speaker_3d.bus = get_bus_name(player_id)
		_setup_distance_fade(speaker_3d)
		var head: Node3D = body.get_attach_point(&"head")
		(head if head != null else body).add_child(speaker_3d)
		speaker_3d.play()
		player = speaker_3d
		_playbacks[player_id] = speaker_3d.get_stream_playback() as AudioStreamGeneratorPlayback
	else:
		var flat := AudioStreamPlayer.new()
		flat.stream = _make_generator()
		flat.bus = get_bus_name(player_id)
		add_child(flat)
		flat.play()
		player = flat
		_playbacks[player_id] = flat.get_stream_playback() as AudioStreamGeneratorPlayback
	_speakers[player_id] = player
	return _playbacks.get(player_id)


## Godot's own distance falloff is switched off; _update_volumes() sets the volume from
## distance_gain() and the muffle, so the fade and the silent cut-off are exactly the numbers in
## Config. The speaker floats free of its parent (top_level) so it can be moved to a doorway.
func _setup_distance_fade(speaker: AudioStreamPlayer3D) -> void:
	speaker.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	speaker.top_level = true
	if _config.voice_max_distance > 0.0:
		speaker.max_distance = _config.voice_max_distance


## Every positioned voice by player id (other players' voices, plus your echo dummy loopback).
func _speakers_3d() -> Dictionary[int, AudioStreamPlayer3D]:
	var result: Dictionary[int, AudioStreamPlayer3D] = {}
	for player_id: int in _speakers.keys():
		var speaker := _speakers[player_id] as AudioStreamPlayer3D
		if speaker != null and is_instance_valid(speaker) and speaker.is_inside_tree():
			result[player_id] = speaker
	var loopback := _loopback_player as AudioStreamPlayer3D
	if loopback != null and is_instance_valid(loopback) and loopback.is_inside_tree():
		result[_net.local_player_id()] = loopback
	return result


## Hearing for one speaker, from the listener's camera to the speaker's real spot (its parent).
func _compute_hearing(speaker: AudioStreamPlayer3D) -> VoiceHearing:
	var camera: Camera3D = speaker.get_viewport().get_camera_3d()
	var anchor := speaker.get_parent() as Node3D
	if camera == null or anchor == null:
		return null
	return VoiceHearing.compute(camera.global_position, anchor.global_position, speaker.get_world_3d(), _config)


func _gain(hearing: VoiceHearing, muffle: float) -> float:
	return hearing_gain(hearing.distance, muffle, _config)


## Volume (0 to 1) for a voice that travels `distance` metres with this much muffle (0 to 1).
static func hearing_gain(distance: float, muffle: float, config: GameConfig) -> float:
	var gain: float = distance_gain(distance, config.voice_full_volume_distance, config.voice_max_distance)
	return gain * lerpf(1.0, config.voice_muffle_volume, muffle)


## The muffle filter's cutoff (Hz) for this much muffle: wide open at 0, config's cutoff at 1.
static func muffle_cutoff(muffle: float, config: GameConfig) -> float:
	return exp(lerpf(log(OPEN_CUTOFF_HZ), log(config.voice_muffle_cutoff_hz), clampf(muffle, 0.0, 1.0)))


## Walls, doors and routes are re-checked a few times a second (not every frame, to stay cheap).
func _physics_process(delta: float) -> void:
	_hearing_timer -= delta
	if _hearing_timer > 0.0:
		return
	_hearing_timer = 1.0 / maxf(_config.voice_hearing_updates_per_second, 1.0)
	var speakers: Dictionary[int, AudioStreamPlayer3D] = _speakers_3d()
	for player_id: int in speakers.keys():
		var hearing: VoiceHearing = _compute_hearing(speakers[player_id])
		if hearing != null:
			_hearing[player_id] = hearing


## Every frame: glide each voice's volume, muffle and position toward the latest hearing check,
## so doors opening and walking round corners never pop.
func _update_volumes(delta: float) -> void:
	var speakers: Dictionary[int, AudioStreamPlayer3D] = _speakers_3d()
	for player_id: int in speakers.keys():
		var speaker: AudioStreamPlayer3D = speakers[player_id]
		var hearing: VoiceHearing = _hearing.get(player_id)
		if hearing == null:
			hearing = _compute_hearing(speaker)
			if hearing == null:
				continue
			_hearing[player_id] = hearing
			speaker.global_position = hearing.source
		var muffle: float = move_toward(_muffle_now.get(player_id, hearing.muffle), hearing.muffle,
			MUFFLE_FADE_PER_SECOND * delta)
		_muffle_now[player_id] = muffle
		var weight: float = 1.0 - exp(-SOURCE_GLIDE_SPEED * delta)
		speaker.global_position = speaker.global_position.lerp(hearing.source, weight)
		var gain: float = _gain(hearing, muffle)
		speaker.volume_db = linear_to_db(gain) if gain > 0.0 else -80.0
		var filter: AudioEffectLowPassFilter = _muffle_filters.get(player_id)
		if filter != null:
			filter.cutoff_hz = muffle_cutoff(muffle, _config)


func _push_frames(playback: AudioStreamGeneratorPlayback, frames: PackedVector2Array) -> void:
	var room: int = playback.get_frames_available()
	if room <= 0:
		return
	if frames.size() > room:
		frames = frames.slice(frames.size() - room)
	playback.push_buffer(frames)


func _on_player_spawned(player_id: int, _player_node: Node3D) -> void:
	# Move this player's voice onto their (new) body next time they speak.
	var speaker: Node = _speakers.get(player_id)
	if speaker != null and is_instance_valid(speaker):
		speaker.queue_free()
	_speakers.erase(player_id)
	_playbacks.erase(player_id)


func _route_loopback() -> void:
	if _loopback_player != null:
		var bus_name: StringName = get_bus_name(_net.local_player_id())
		_loopback_player.set(&"bus", bus_name if bus_name != &"" else FALLBACK_BUS)


# --- Microphone and sending -------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_speaking()
	_update_volumes(delta)
	if not _live:
		return
	_open_mic_hold = maxf(_open_mic_hold - delta, 0.0)
	var wants_mic: bool = _loopback or _net.get_player_count() > 1
	var push_held: bool = Input.is_action_pressed(InputActions.PUSH_TO_TALK)
	if _use_steam_voice():
		_stop_mic()
		_process_steam(wants_mic, push_held)
	else:
		_stop_steam()
		_process_local(wants_mic, push_held)


func _use_steam_voice() -> bool:
	return SteamSession.is_steam_running() and multiplayer.multiplayer_peer is SteamMultiplayerPeer


func _process_local(wants_mic: bool, push_held: bool) -> void:
	if not wants_mic:
		_stop_mic()
		_set_transmitting(false)
		_input_level = 0.0
		return
	_start_mic()
	if _capture == null:
		return
	var available: int = _capture.get_frames_available()
	if available <= 0:
		return
	var frames: PackedVector2Array = _capture.get_buffer(available)
	_input_level = clampf(VoiceCodec.level(frames) * 4.0, 0.0, 1.0)
	if not _push_to_talk and VoiceCodec.level(frames) >= _config.voice_open_mic_threshold:
		_open_mic_hold = SPEAKING_HOLD_SECONDS
	var sending: bool = would_send(VoiceCodec.level(frames), push_held)
	_set_transmitting(sending)
	if not sending:
		return
	var bytes: PackedByteArray = VoiceCodec.encode(frames, AudioServer.get_mix_rate())
	if _net.get_player_count() > 1:
		_receive_voice.rpc(bytes, false)
	if _loopback_playback != null:
		_push_frames(_loopback_playback, VoiceCodec.decode(bytes))


func _process_steam(wants_mic: bool, push_held: bool) -> void:
	var allowed: bool = wants_mic and (push_held if _push_to_talk else true)
	if allowed and not _steam_recording:
		Steam.startVoiceRecording()
		_steam_recording = true
	elif not allowed and _steam_recording:
		_stop_steam()
	if not _steam_recording:
		_set_transmitting(false)
		return
	var voice: Dictionary = Steam.getVoice(STEAM_VOICE_BUFFER)
	var written: int = int(voice.get("written", 0))
	if int(voice.get("result", -1)) != STEAM_VOICE_OK or written <= 0:
		_set_transmitting(false)
		return
	var bytes: PackedByteArray = voice.get("buffer", PackedByteArray())
	bytes = bytes.slice(0, written)
	_set_transmitting(true)
	_input_level = 1.0
	if _net.get_player_count() > 1:
		_receive_voice.rpc(bytes, true)
	if _loopback_playback != null:
		_push_frames(_loopback_playback, _decompress(bytes))


func _start_mic() -> void:
	if _mic_player != null:
		return
	if AudioServer.get_bus_index(MIC_BUS) < 0:
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, MIC_BUS)
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.2
		AudioServer.add_bus_effect(index, _capture)
		# The capture effect still hears the mic; turning the bus down keeps it out of your speakers.
		AudioServer.set_bus_volume_db(index, -80.0)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "Microphone"
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = MIC_BUS
	add_child(_mic_player)
	_mic_player.play()


func _stop_mic() -> void:
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null


func _stop_steam() -> void:
	if _steam_recording:
		Steam.stopVoiceRecording()
		_steam_recording = false


func _decompress(bytes: PackedByteArray) -> PackedVector2Array:
	var result: Dictionary = Steam.decompressVoice(bytes, VoiceCodec.SAMPLE_RATE, STEAM_DECOMPRESSED_BUFFER)
	if int(result.get("result", -1)) != STEAM_VOICE_OK:
		return PackedVector2Array()
	var raw: PackedByteArray = result.get("uncompressed", PackedByteArray())
	var size: int = int(result.get("size", raw.size()))
	return VoiceCodec.decode(raw.slice(0, size))


## Voice from another player (Steam-compressed, or plain 16 kHz in local mode).
## Voice is the speaker's own data, not game state, so it goes straight to everyone.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_voice(bytes: PackedByteArray, compressed: bool) -> void:
	var player_id: int = _net.sender_player_id()
	if player_id == 0 or player_id == _net.local_player_id():
		return
	feed_voice(player_id, _decompress(bytes) if compressed else VoiceCodec.decode(bytes))


func _set_transmitting(sending: bool) -> void:
	_transmitting = sending
	if sending:
		_last_heard_msec[_net.local_player_id()] = Time.get_ticks_msec()


func _update_speaking() -> void:
	var now: int = Time.get_ticks_msec()
	for player_id: int in _last_heard_msec.keys():
		var speaking: bool = now - _last_heard_msec[player_id] < int(SPEAKING_HOLD_SECONDS * 1000.0)
		if speaking != _speaking.get(player_id, false):
			_speaking[player_id] = speaking
			EventBus.player_speaking_changed.emit(player_id, speaking)


## STUB until settings_input: nothing to read yet (push-to-talk, mic device, volume, reduce effects).
func _on_settings_changed(_section: StringName) -> void:
	pass
