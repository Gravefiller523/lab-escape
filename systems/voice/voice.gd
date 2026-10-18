class_name VoiceService
extends Node
## Autoload "Voice". Proximity voice chat where mutations change how you sound.
##
## Every player gets their own audio bus ("Voice_<slot>") with their effects (pitch, presets like
## Fly's "buzz"), so effects apply to that player only. Remote voices play from the speaker's head
## in 3D. Godot records the mic and sends plain 16 kHz audio, in local mode and over Steam. Steam's own
## recording can be switched on with Config.game.voice_use_steam_recording. Nothing is ever saved to disk. Spec: docs/systems/voice.md.

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
## Used when no config is given: how quiet a voice is at the far end, just before silence.
const DEFAULT_FAR_VOLUME_DB: float = -40.0
## The last part of the range (as a fraction) where the faint tail fades to true silence.
const FINAL_FADE_PART: float = 0.1
## The treble cut-off never goes below this (Hz), so voices stay understandable-ish.
const MIN_CUTOFF_HZ: float = 300.0
## The faint far echo repeats the voice this long after (milliseconds).
const ECHO_DELAY_MS: float = 280.0
## Open mic loudness needed at sensitivity 0 and 1 (0 to 1 scale, root-mean-square of the mic).
const MIC_THRESHOLD_LEAST_SENSITIVE: float = 0.06
const MIC_THRESHOLD_MOST_SENSITIVE: float = 0.002
## The mic meter's range (mic RMS): empty at the first, full at the second.
const METER_QUIETEST_RMS: float = 0.001
const METER_LOUDEST_RMS: float = 0.3
## How fast the distance-based sound (volume, echo, treble) follows a change, per second.
const DISTANCE_GLIDE_SPEED: float = 6.0
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
var _mic_sensitivity: float = 0.7
## A mic meter is on screen: listen to the mic (for the meter only).
var _mic_test: bool = false
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
var _distance_now: Dictionary[int, float] = {}
## player_id -> [AudioEffectReverb, AudioEffectDelay] on their bus.
var _echo_effects: Dictionary[int, Array] = {}
var _hearing_timer: float = 0.0
## For the console's `voice` command: what happened so far (helps find problems on real Steam).
var _sent_packets: int = 0
var _received_packets: Dictionary[int, int] = {}
var _last_get_voice_result: int = -1
var _last_decompress_result: int = -1


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
	_mic_sensitivity = _config.voice_mic_sensitivity
	_net.roster_changed.connect(sync_players)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.settings_changed.connect(_on_settings_changed)
	sync_players()
	if _live:
		_register_console_command.call_deferred()


func _notification(what: int) -> void:
	# Closing the window: let go of the mic while the audio engine is still running.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_mic()


func _exit_tree() -> void:
	for player_id: int in _buses.keys():
		_remove_player(player_id)
	# The game may be quitting, when queue_free never happens: free the microphone right away.
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.free()
		_mic_player = null


# --- Public API -------------------------------------------------------------------------------

func is_speaking(player_id: int) -> bool:
	return _speaking.get(player_id, false)


## 0 to 1: how loud the local microphone is right now, on the mic meter's scale (see meter_position).
func get_input_level() -> float:
	return _input_level


## Where on a 0 to 1 mic meter a loudness (mic RMS) sits. The meter is even in decibels, from
## METER_QUIETEST_RMS (empty) to METER_LOUDEST_RMS (full), like most mic meters.
static func meter_position(rms: float) -> float:
	if rms <= METER_QUIETEST_RMS:
		return 0.0
	return clampf(log(rms / METER_QUIETEST_RMS) / log(METER_LOUDEST_RMS / METER_QUIETEST_RMS), 0.0, 1.0)


## Where the open-mic threshold sits on the mic meter (talking above this line is sent).
func get_threshold_meter_position() -> float:
	return meter_position(get_open_mic_threshold())


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
	if is_instance_valid(_loopback_player):
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
## The fade between the two distances follows `curve` (GameConfig.voice_distance_curve: x = 0 at
## full_distance to 1 at max_distance, y = volume). Without a curve it fades evenly in decibels down
## to DEFAULT_FAR_VOLUME_DB. Either way the last FINAL_FADE_PART fades the faint tail to silence.
static func distance_gain(distance: float, full_distance: float, max_distance: float,
		curve: Curve = null) -> float:
	if max_distance <= 0.0 or distance <= full_distance:
		return 1.0
	if distance >= max_distance:
		return 0.0
	var t: float = distance_fraction(distance, full_distance, max_distance)
	var gain: float = clampf(curve.sample(t), 0.0, 1.0) if curve != null else db_to_linear(DEFAULT_FAR_VOLUME_DB * t)
	var final_fade_start: float = 1.0 - FINAL_FADE_PART
	if t > final_fade_start:
		gain *= 1.0 - smoothstep(final_fade_start, 1.0, t)
	return gain


## 0 at full volume distance, 1 at the max distance.
static func distance_fraction(distance: float, full_distance: float, max_distance: float) -> float:
	if max_distance <= 0.0:
		return 0.0
	return clampf((distance - full_distance) / maxf(max_distance - full_distance, 0.001), 0.0, 1.0)


## How much reverb (wet, 0 to 1) a voice gets at this distance: voice_near_reverb up close (the
## underground-facility sound), rising to voice_far_reverb at the max distance.
static func distance_reverb(distance: float, config: GameConfig) -> float:
	var t: float = distance_fraction(distance, config.voice_full_volume_distance, config.voice_max_distance)
	return lerpf(config.voice_near_reverb, config.voice_far_reverb, t)


## How loud (0 to 1) the faint echo is at this distance: none up close, voice_far_echo at the max.
static func distance_echo(distance: float, config: GameConfig) -> float:
	return config.voice_far_echo * distance_fraction(distance, config.voice_full_volume_distance, config.voice_max_distance)


## The treble cut-off (Hz) for a voice: lowered by distance (air) and by muffling (walls, doors).
static func voice_cutoff(muffle: float, distance: float, config: GameConfig) -> float:
	var t: float = distance_fraction(distance, config.voice_full_volume_distance, config.voice_max_distance)
	var air: float = exp(lerpf(log(OPEN_CUTOFF_HZ), log(config.voice_far_cutoff_hz), t))
	return clampf(air * muffle_cutoff(muffle, config) / OPEN_CUTOFF_HZ, MIN_CUTOFF_HZ, OPEN_CUTOFF_HZ)


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


## The distance effects on a player's bus: [reverb, echo]. Empty if none.
func get_echo_effects(player_id: int) -> Array[AudioEffect]:
	var effects: Array[AudioEffect] = []
	var found: Array = _echo_effects.get(player_id, [])
	effects.assign(found)
	return effects


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


## Open mic sensitivity, 0 to 1 (higher = quieter talking is picked up). STUB until settings_input
## saves it; starts at Config.game.voice_mic_sensitivity.
func set_mic_sensitivity(sensitivity: float) -> void:
	_mic_sensitivity = clampf(sensitivity, 0.0, 1.0)


func get_mic_sensitivity() -> float:
	return _mic_sensitivity


## Turns the mic on just for a level meter (MicSensitivityPanel). Nothing is sent or saved.
func set_mic_test(enabled: bool) -> void:
	_mic_test = enabled


## How loud (0 to 1) the mic must be for open mic to send, from the sensitivity.
func get_open_mic_threshold() -> float:
	return sensitivity_to_threshold(_mic_sensitivity)


## Sensitivity 0 needs a loud voice (MIC_THRESHOLD_LEAST_SENSITIVE), 1 picks up a whisper
## (MIC_THRESHOLD_MOST_SENSITIVE). Evenly spaced in loudness, so the slider feels even.
static func sensitivity_to_threshold(sensitivity: float) -> float:
	return exp(lerpf(log(MIC_THRESHOLD_LEAST_SENSITIVE), log(MIC_THRESHOLD_MOST_SENSITIVE), clampf(sensitivity, 0.0, 1.0)))


## Whether the local mic should send right now. Push-to-talk: only while the key is held.
## Open mic: while loud enough (plus a short hold so words don't get cut).
func would_send(level: float, push_to_talk_held: bool) -> bool:
	if _push_to_talk:
		return push_to_talk_held
	return level >= get_open_mic_threshold() or _open_mic_hold > 0.0


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
	# Variant, not Node: the speaker may already be freed with its body, and a freed object can't be
	# put in a typed variable or cast.
	var speaker: Variant = _speakers.get(player_id)
	if is_instance_valid(speaker):
		(speaker as Node).queue_free()
	_speakers.erase(player_id)
	_playbacks.erase(player_id)
	_last_heard_msec.erase(player_id)
	_muffle_filters.erase(player_id)
	_hearing.erase(player_id)
	_muffle_now.erase(player_id)
	_distance_now.erase(player_id)
	_echo_effects.erase(player_id)
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
	# Distance effects, set by _update_volumes(): reverb (spread out) and a faint echo.
	var reverb := AudioEffectReverb.new()
	# Concrete corridors: a short pre-delay, a medium room, and damped highs so speech stays clear.
	reverb.predelay_msec = 20.0
	reverb.room_size = 0.55
	reverb.damping = 0.7
	reverb.spread = 0.8
	reverb.hipass = 0.1
	reverb.dry = 1.0
	reverb.wet = 0.0
	AudioServer.add_bus_effect(index, reverb)
	var echo := AudioEffectDelay.new()
	echo.dry = 1.0
	echo.tap1_active = true
	echo.tap1_delay_ms = ECHO_DELAY_MS
	echo.tap1_level_db = -80.0
	echo.tap2_active = false
	echo.feedback_active = false
	AudioServer.add_bus_effect(index, echo)
	_echo_effects[player_id] = [reverb, echo] as Array[AudioEffect]
	# Always last: the treble filter (muffling and distance), set by _update_volumes().
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
	var existing: Variant = _speakers.get(player_id)
	if is_instance_valid(existing):
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
		# The speaker sits on the player's body, so it is freed with it (scene changes): check first.
		var entry: Variant = _speakers[player_id]
		if not is_instance_valid(entry):
			continue
		var speaker := entry as AudioStreamPlayer3D
		if speaker != null and speaker.is_inside_tree():
			result[player_id] = speaker
	var loopback: AudioStreamPlayer3D = null
	if is_instance_valid(_loopback_player):
		loopback = _loopback_player as AudioStreamPlayer3D
	if loopback != null and loopback.is_inside_tree():
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
	return hearing_gain(hearing.distance, muffle, _config, hearing.closed_doors)


## Volume (0 to 1) for a voice that travels `distance` metres with this much muffle (0 to 1).
## Through a closed door (closed_doors > 0) the voice goes silent sooner: at voice_closed_door_max_distance.
static func hearing_gain(distance: float, muffle: float, config: GameConfig, closed_doors: int = 0) -> float:
	var max_distance: float = config.voice_max_distance
	var full_distance: float = config.voice_full_volume_distance
	if closed_doors > 0:
		full_distance = minf(full_distance, config.voice_closed_door_full_volume_distance)
		max_distance = minf(max_distance, config.voice_closed_door_max_distance) if max_distance > 0.0 \
			else config.voice_closed_door_max_distance
	var gain: float = distance_gain(distance, full_distance, max_distance, config.voice_distance_curve)
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
		var muffle_before: float = _muffle_now.get(player_id, hearing.muffle)
		var muffle: float = move_toward(muffle_before, hearing.muffle,
			MUFFLE_FADE_PER_SECOND * delta)
		_muffle_now[player_id] = muffle
		var weight: float = 1.0 - exp(-SOURCE_GLIDE_SPEED * delta)
		speaker.global_position = speaker.global_position.lerp(hearing.source, weight)
		var distance_before: float = _distance_now.get(player_id, hearing.distance)
		var distance: float = lerpf(distance_before, hearing.distance,
			1.0 - exp(-DISTANCE_GLIDE_SPEED * delta))
		_distance_now[player_id] = distance
		var gain: float = hearing_gain(distance, muffle, _config, hearing.closed_doors)
		speaker.volume_db = linear_to_db(gain) if gain > 0.0 else -80.0
		var filter: AudioEffectLowPassFilter = _muffle_filters.get(player_id)
		if filter != null:
			filter.cutoff_hz = voice_cutoff(muffle, distance, _config)
		var echo_effects: Array[AudioEffect] = _echo_effects.get(player_id, [] as Array[AudioEffect])
		if echo_effects.size() == 2:
			(echo_effects[0] as AudioEffectReverb).wet = distance_reverb(distance, _config)
			var echo_level: float = distance_echo(distance, _config)
			(echo_effects[1] as AudioEffectDelay).tap1_level_db = linear_to_db(echo_level) if echo_level > 0.0 else -80.0


func _push_frames(playback: AudioStreamGeneratorPlayback, frames: PackedVector2Array) -> void:
	var room: int = playback.get_frames_available()
	if room <= 0:
		return
	if frames.size() > room:
		frames = frames.slice(frames.size() - room)
	playback.push_buffer(frames)


func _on_player_spawned(player_id: int, _player_node: Node3D) -> void:
	# Move this player's voice onto their (new) body next time they speak.
	# Variant, not Node: the speaker may already be freed with its body, and a freed object can't be
	# put in a typed variable or cast.
	var speaker: Variant = _speakers.get(player_id)
	if is_instance_valid(speaker):
		(speaker as Node).queue_free()
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
	var wants_mic: bool = _loopback or _mic_test or _net.get_player_count() > 1
	var push_held: bool = Input.is_action_pressed(InputActions.PUSH_TO_TALK)
	if _use_steam_voice():
		_stop_mic()
		_process_steam(wants_mic, push_held)
	else:
		_stop_steam()
		_process_local(wants_mic, push_held)


func _use_steam_voice() -> bool:
	return _config.voice_use_steam_recording and SteamSession.is_steam_running() and multiplayer.multiplayer_peer is SteamMultiplayerPeer


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
	_input_level = meter_position(VoiceCodec.level(frames))
	if not _push_to_talk and VoiceCodec.level(frames) >= get_open_mic_threshold():
		_open_mic_hold = SPEAKING_HOLD_SECONDS
	var sending: bool = would_send(VoiceCodec.level(frames), push_held)
	_set_transmitting(sending)
	if not sending:
		return
	var bytes: PackedByteArray = VoiceCodec.encode(frames, AudioServer.get_mix_rate())
	if _net.get_player_count() > 1:
		_receive_voice.rpc(bytes, false)
		_sent_packets += 1
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
	var written: int = voice.get("written", 0)
	_last_get_voice_result = voice.get("result", -1)
	if _last_get_voice_result != STEAM_VOICE_OK or written <= 0:
		_set_transmitting(false)
		return
	var bytes: PackedByteArray = voice.get("buffer", PackedByteArray())
	bytes = bytes.slice(0, written)
	_set_transmitting(true)
	_input_level = 1.0
	if _net.get_player_count() > 1:
		_receive_voice.rpc(bytes, true)
		_sent_packets += 1
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
		# Let go of the microphone stream now; queue_free alone can be too late when the game quits.
		_mic_player.stream = null
		_mic_player.queue_free()
		_mic_player = null


func _stop_steam() -> void:
	if _steam_recording:
		Steam.stopVoiceRecording()
		_steam_recording = false


func _decompress(bytes: PackedByteArray) -> PackedVector2Array:
	var result: Dictionary = Steam.decompressVoice(bytes, VoiceCodec.SAMPLE_RATE, STEAM_DECOMPRESSED_BUFFER)
	_last_decompress_result = result.get("result", -1)
	if _last_decompress_result != STEAM_VOICE_OK:
		return PackedVector2Array()
	var raw: PackedByteArray = result.get("uncompressed", PackedByteArray())
	var size: int = result.get("size", raw.size())
	return VoiceCodec.decode(raw.slice(0, size))


## Voice from another player (Steam-compressed, or plain 16 kHz in local mode).
## Voice is the speaker's own data, not game state, so it goes straight to everyone.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_voice(bytes: PackedByteArray, compressed: bool) -> void:
	var player_id: int = _net.sender_player_id()
	if player_id == 0 or player_id == _net.local_player_id():
		return
	_received_packets[player_id] = _received_packets.get(player_id, 0) + 1
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


# --- Console ---------------------------------------------------------------------------------

## Steam's voice result codes (EVoiceResult), for the `voice` command.
const STEAM_VOICE_RESULT_NAMES: PackedStringArray = ["OK", "not initialised", "not recording", "no data yet",
	"buffer too small", "data corrupted", "restricted (this Steam account can't use voice)", "unsupported codec",
	"receiver out of date", "receiver did not answer"]


func _register_console_command() -> void:
	DebugConsole.register_command(&"voice", _cmd_voice, "voice: voice chat status (to find problems)", false)


## The `voice` console command: how voice is set up here and what has been sent and received.
func _cmd_voice(_args: PackedStringArray, _player_id: int) -> String:
	var lines: PackedStringArray = []
	var steam: bool = _use_steam_voice()
	var over_steam: bool = multiplayer.multiplayer_peer is SteamMultiplayerPeer
	var mode: String = "Steam recording" if steam else ("Godot mic, sent over Steam" if over_steam else "Godot mic")
	lines.append("Voice mode: %s | push-to-talk: %s | sending now: %s" % [mode,
		"on (hold the key)" if _push_to_talk else "off (open mic)", "yes" if _transmitting else "no"])
	if steam:
		lines.append("Steam recording: %s | last getVoice: %s | last decompress: %s" % [
			"yes" if _steam_recording else "no", _steam_result_name(_last_get_voice_result),
			_steam_result_name(_last_decompress_result)])
	else:
		lines.append("Godot mic open: %s | level: %d%%" % ["yes" if _mic_player != null else "no", int(_input_level * 100.0)])
	lines.append("Voice packets sent: %d" % _sent_packets)
	for player_id: int in _net.get_player_ids():
		if player_id == _net.local_player_id():
			continue
		lines.append("  %s: received %d packets | speaker: %s | muted: %s | volume: %d%%" % [
			_net.get_display_name(player_id), _received_packets.get(player_id, 0),
			"yes" if _speakers.has(player_id) else "not yet", "yes" if is_player_muted(player_id) else "no",
			int(get_voice_volume(player_id) * 100.0)])
	return "\n".join(lines)


static func _steam_result_name(result: int) -> String:
	if result < 0:
		return "none yet"
	if result < STEAM_VOICE_RESULT_NAMES.size():
		return "%d (%s)" % [result, STEAM_VOICE_RESULT_NAMES[result]]
	return str(result)
