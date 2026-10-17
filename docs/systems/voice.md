# voice

Folder: `res://systems/voice/` · Autoload: `Voice` · Size: L · Phase 1a (proof), 1b (full) · **High risk**

## Purpose
Proximity voice chat where **mutations change how you sound**. Records the local microphone through
Steam, sends it to the other players, and plays each player's voice from their body in 3D, through
their **own audio bus** so effects (higher pitch for Fly, buzz, robot) apply only to them. Supports
push-to-talk or open mic, per-player mute, and a "hear yourself" test.

**Not responsible for:** deciding which effects a player has (upgrades calls this API), the bus layout
for music and SFX (audio), the mic setting UI (ui + settings_input).

## Public API
```gdscript
func is_speaking(player_id: int) -> bool
func get_input_level() -> float                       # 0..1, local mic meter
func set_voice_effect(player_id: int, source_id: StringName, effect: VoiceEffectData) -> void
func clear_voice_effect(player_id: int, source_id: StringName) -> void
func set_player_muted(player_id: int, muted: bool) -> void   # local only
func is_player_muted(player_id: int) -> bool
func set_loopback(enabled: bool) -> void              # hear your own voice with your effects (Break Room mirror, settings)
func get_bus_name(player_id: int) -> StringName       # &"Voice_<slot_index>"
## New effect presets register themselves (a preset = a function that adds AudioEffects to a bus):
func register_preset(preset: StringName, builder: Callable) -> void   # builder: func(bus_index: int, strength: float) -> void
# NEW 2026-10-17:
func set_loopback(enabled: bool, anchor: Node3D = null) -> void   # CHANGED: with an anchor, your voice plays from that spot (echo dummy)
func is_loopback() -> bool
func set_push_to_talk(enabled: bool) -> void        # STUB until settings_input; default Config.game.voice_push_to_talk_default
func is_push_to_talk() -> bool
func is_transmitting() -> bool                      # the local mic is being sent right now
func would_send(level: float, push_to_talk_held: bool) -> bool   # the push-to-talk / open-mic gate
func sync_players() -> void                         # runs by itself on Net.roster_changed
func feed_voice(player_id: int, frames: PackedVector2Array) -> bool   # play voice audio (network code, tests)
func get_voice_volume(player_id: int) -> float      # 0..1 how loud that voice is for you now
func get_hearing(player_id: int) -> VoiceHearing    # distance, muffle, source, used_path, closed_doors
func get_muffle_filter(player_id: int) -> AudioEffectLowPassFilter
func get_echo_effects(player_id: int) -> Array[AudioEffect]   # NEW: [reverb, echo] on their bus
static func distance_gain(distance: float, full_distance: float, max_distance: float, curve: Curve = null) -> float
static func distance_reverb(distance: float, config: GameConfig) -> float      # NEW
static func distance_echo(distance: float, config: GameConfig) -> float        # NEW
static func voice_cutoff(muffle: float, distance: float, config: GameConfig) -> float   # NEW: distance + walls
static func hearing_gain(distance: float, muffle: float, config: GameConfig) -> float
static func muffle_cutoff(muffle: float, config: GameConfig) -> float
static func load_preset(preset: StringName) -> VoicePreset
func use_test_setup(net: NetService, config: GameConfig, bus_prefix: String) -> void   # tests only

class_name SoundDoor extends Area3D                 # NEW 2026-10-17: put one on every door
@export var is_open: bool                           # keep this up to date; voice reads it
signal open_changed(is_open: bool)
func blocks_segment(from: Vector3, to: Vector3) -> bool   # BoxShape3D children = the doorway
const GROUP: StringName = &"sound_doors"
```
NEW 2026-10-17: the autoload script is `systems/voice/voice.gd` (`class_name VoiceService`). Presets
extend `VoicePreset` (`voice_preset.gd`) and override `build(bus_index, strength)`. Launch presets built
so far: `buzz` (Fly: band-pass + light distortion + fast chorus) and `deep`.

### NEW 2026-10-17: how far voices carry (Zachary's request)
- **Distance fade (CHANGED 2026-10-17, after Zachary's playtest):** each player's voice plays from
  their head (`AudioStreamPlayer3D`). Godot's own falloff is off; voice sets the volume itself: full
  volume within `voice_full_volume_distance` (CHANGED: 10 m, was 4 m; through a closed door
  `voice_closed_door_full_volume_distance` = 4 m), then it follows `voice_distance_curve` (a Curve you
  can reshape in the Inspector): a fairly quick drop, then a **long, quiet tail** where far voices are
  barely there, and **complete silence at `voice_max_distance` (CHANGED: now 46 m; was 30, 60, then 40 m)**.
  0 = everyone hears everyone.
- **Sounding far away (NEW 2026-10-17):** far voices also lose treble (air absorption, down to
  `voice_far_cutoff_hz` = 2500 Hz at the max distance), get more reverb (`voice_far_reverb` = 0.45 at
  the max) and a faint echo ~0.3 s later (`voice_far_echo` = 0.2 at the max).
- **Underground facility sound (NEW 2026-10-17):** every voice has some reverb even up close
  (`voice_near_reverb` = 0.2, rising to `voice_far_reverb` with distance): 20 ms pre-delay, medium room
  (0.55), damped highs (0.7), so it sounds like concrete corridors while speech stays clear. Each player's bus has
  pitch/presets, then reverb, then echo, then the treble filter (distance and walls combined).
  Route distances (round corners, through doors) use the same curve and effects.
- **Walls muffle (step A):** about 10 times a second (`voice_hearing_updates_per_second`) each PC casts
  3 rays from the listener's camera to each speaker's head against the sound-blocker layer
  (`voice_sound_blocker_layer`, 1 = world). Blocked = muffled: quieter (`voice_muffle_volume`) and
  duller (a low-pass filter down to `voice_muffle_cutoff_hz`, always the last effect on the player's bus).
- **Through doors and hallways (step B):** when walls are in the way and the level has a navmesh,
  voice gets the walkable route (NavigationServer3D). The route length is used for the distance fade,
  the voice seems to come from the last corner before you (the doorway), and each real corner adds a
  light muffle (`voice_corner_muffle`, at most 0.4 in total). No route, or no navmesh at all (like
  the Break Room today): plain wall muffling from step A.
- **Doors:** a closed `SoundDoor` on the route adds `voice_closed_door_muffle` (quieter and duller, still
  heard). An open door adds nothing. Without a navmesh, a closed door on the straight line counts the same.
  CHANGED 2026-10-17 (Zachary): closed-door muffle 0.6 -> 0.7 (shows ~70-80% with corners), full muffle
  volume `voice_muffle_volume` 0.35 -> 0.25 and cutoff `voice_muffle_cutoff_hz` 700 -> 550 Hz, and a voice
  through a closed door is **silent past `voice_closed_door_max_distance` (15 m)** of route distance.
- **Mic sensitivity (NEW 2026-10-17):** open mic sends when the mic is louder than a threshold set by
  `set_mic_sensitivity(0..1)` (default `voice_mic_sensitivity` = 0.7; 0 needs a loud voice, 1 picks up a
  whisper). `MicSensitivityPanel` is a ready-made slider with a live level bar and the threshold line;
  it's in the voice test scene and the Esc menu. Push-to-talk (hold V) always sends, whatever the
  threshold. Over Steam, Steam decides when you're talking and the threshold doesn't apply.
- Everything changes smoothly (muffle fades, the voice glides to the doorway) and is worked out on
  each listener's PC: no extra network traffic. All numbers are in `config/game_config.tres`.
Launch presets in `systems/voice/presets/`: `buzz` (Fly: band-pass + tremolo), `robot` (cybernetic
voicebox: distortion + chorus), `gurgle` (Octo: low-pass + phaser), `slime` (Slug), `deep` (pitch down).
Preset files are found by name (`<preset>_preset.gd`), like movement modes.

## EventBus
- Emits: `player_speaking_changed` (local).
- Listens: `player_joined`/`player_left` (create/free buses and players), `player_spawned` (attach the
  3D voice player to the body's head), `settings_changed` (push-to-talk, mic device, voice volume, reduce_voice_effects).
  CHANGED 2026-10-17: buses follow `Net.roster_changed` (covers joins and leaves) instead of
  `player_joined`/`player_left`. `settings_changed` is a stub until settings_input exists.

## Data it owns and saves
Uses `VoiceEffectData` inside upgrades. Buses are created at runtime (never edit `default_bus_layout.tres`; audio owns it). Saves nothing.

## Adding content
New mutations use existing presets with no code. A new preset is one new file in `presets/` (a building block).

## Multiplayer
- **Capture:** `Steam.startVoiceRecording()`; each frame `Steam.getVoice()` returns compressed audio
  (only while talking, or while push-to-talk is held).
- **Send:** compressed packets go to every other player as `unreliable` messages (small, ~1-3 KB/s each).
  Voice is peer-to-peer data, not game state: the sender is the authority of its own voice.
- **Play:** each receiver calls `Steam.decompressVoice()` and pushes samples into an
  `AudioStreamGenerator` on an `AudioStreamPlayer3D` at the speaker's head, routed to bus `Voice_<slot>`.
  That bus has the speaker's effects (pitch shift from `pitch_scale` + preset). Distance falloff uses
  `voice_full_volume_distance` and `voice_max_distance` (0 = everyone hears everyone).
- Every PC applies the speaker's effects itself (upgrades calls `set_voice_effect` on every PC).
- Number of buses = number of players; works for any `max_players`.
- **Local mode (no Steam):** captures with `AudioStreamMicrophone` + `AudioEffectCapture` and sends
  16 kHz 16-bit audio (no compression, LAN only) so the rest can be tested with 2 windows on one PC.

## Dependencies and stubs
steam_session (Steam voice functions), net_core (ids, slot indexes), settings_input (push-to-talk, volume),
player (head attach point; stub: a Node3D per player).

## Test scene and GUT tests
**Phase 1 proof scene** `systems/voice/test/voice_proof.tscn`: two players in a grey-box room; buttons
to toggle Fly voice on either player; loopback toggle; a latency label. Test on 2 Steam PCs.
GUT tests: `test_bus_created_per_player_and_freed`, `test_bus_count_follows_player_count` (8 players),
`test_effect_applies_pitch_on_that_bus_only`, `test_clear_effect_restores_bus`, `test_two_sources_combine`,
`test_preset_found_by_name`, `test_muted_player_silent`, `test_push_to_talk_gates_sending`.
NEW 2026-10-17 (all with generated test tones, never the real mic): `test_open_mic_sends_only_when_loud_enough`,
`test_speaking_follows_voice_packets`, `test_codec_round_trip_keeps_the_tone`, `test_distance_gain_fades_then_cuts_off`,
`test_voice_from_body_is_quieter_farther_and_silent_beyond_max`, `test_muffle_lowers_volume_and_cutoff`,
`test_clear_line_of_sight_is_not_muffled`, `test_wall_without_navmesh_is_fully_muffled`,
`test_route_through_doorway_is_longer_and_comes_from_the_doorway`, `test_closed_door_muffles_open_door_does_not`,
`test_closed_door_on_direct_line_without_navmesh`.
NEW 2026-10-17 (distance tail): `test_long_quiet_tail_with_the_default_curve`, `test_reverb_and_echo_grow_with_distance`,
`test_far_voices_lose_treble`, `test_bus_has_distance_effects`. The test field now runs to 60 m with markers every 10 m.
CHANGED 2026-10-17, proof scene: two rooms joined by a hallway (`test/voice_test_rooms.gd`, also used by
the tests), a door between Room A and the hallway (E), a long field off Room B, a yellow echo dummy
(K on/off, J moves it to you), F = Fly voice for everyone, L = hear yourself, P = open mic / push-to-talk
(hold V), a mic meter, speaking indicators and a line showing the echo's distance and muffle. No latency
label yet (delay is judged by ear on 2 PCs).

## Acceptance criteria
- [ ] Two Steam PCs: talking is clear with under ~250 ms delay; with Fly, the listener hears a higher, buzzy voice from that player only.
  *Not tested yet: needs 2 PCs. Fly effect per player is unit-tested.*
- [x] Voice gets quieter with distance and comes from the speaker's position. *(GUT tests; Zachary to check by ear with the echo dummy)*
- [ ] Push-to-talk and open mic both work; settings change them live. *Both built (P toggles); "settings" waits for settings_input.*
- [ ] Works with 4 players; 8 tested with local instances (bus count, CPU). *8 buses unit-tested; CPU with 8 not measured yet.*
- [x] NEW: voices are muffled through walls and closed doors, and travel through open doors and hallways. *(GUT tests)*

## Open design questions
- DEFAULT: proximity voice with a 30 m cut-off; ghosts are heard by everyone at low volume. **Team to playtest.**
- Should listeners be able to turn off other players' voice effects (accessibility)? DEFAULT: `reduce_voice_effects` halves effect strength.
- Steam voice quality and delay at 8 players is unknown; measure in Phase 1.

## Changelog
- 2026-10-07: spec created.
- 2026-10-17: Phase 1a proof built. Added distance fade to silence, wall muffling, routes through
  doors and hallways, `SoundDoor`, `VoiceHearing`, the echo dummy loopback anchor, and the functions
  marked NEW above. New GameConfig numbers: `voice_open_mic_threshold`, `voice_sound_blocker_layer`,
  `voice_muffle_volume`, `voice_muffle_cutoff_hz`, `voice_corner_muffle`, `voice_closed_door_muffle`,
  `voice_hearing_updates_per_second`. Project setting `audio/driver/enable_input = true` (needed for the mic).
- 2026-10-17: after Zachary's playtest: `voice_max_distance` 30 -> 60 m; new `voice_distance_curve`,
  `voice_far_cutoff_hz`, `voice_far_reverb`, `voice_far_echo`; reverb and echo effects on every voice bus.
- 2026-10-17: after Zachary's second playtest: `voice_max_distance` 60 -> 40 m; closed doors silence
  voices past 15 m (`voice_closed_door_max_distance`) and muffle more (0.7; muffle volume 0.25, cutoff
  550 Hz); base "underground" reverb (`voice_near_reverb` 0.2); `voice_open_mic_threshold` replaced by
  `voice_mic_sensitivity` (0.7) with `set_mic_sensitivity`, `get_open_mic_threshold`, `set_mic_test`,
  `meter_position`, `get_threshold_meter_position` and `MicSensitivityPanel` (also added to ui's Esc menu).
- 2026-10-17: full volume (and no extra treble loss, reverb or echo) out to 10 m when no closed door is in
  the way (`voice_full_volume_distance` 4 -> 10); the same curve then runs 10 -> 46 m (`voice_max_distance` 40 -> 46, the same drop per metre as the old 4 -> 40 m). Through a closed
  door: full to 4 m (`voice_closed_door_full_volume_distance`), silent past 15 m.

## HANDOFF
**Done (Phase 1a proof):** the `Voice` autoload: one bus per player (`Voice_<slot>`) with pitch,
presets (`buzz`, `deep`) and the muffle filter; local-mode capture (Godot mic, 16 kHz, sent as
unreliable RPCs) and Steam capture (`startVoiceRecording`/`getVoice`/`decompressVoice`); push-to-talk
or open mic; mute; speaking events; loopback (flat or from an anchor); 3D voices from each head with
distance fade to silence; wall and closed-door muffling; routes through doors and hallways using the
navmesh. 19 GUT tests, all pass. Never records, saves or uploads mic audio.

**Known limits / not tested:** Steam voice between 2 PCs (needs the second PC); real delay; CPU with 8
players; the mic device choice and voice volume (settings_input); ghosts heard by everyone at low
volume (death_respawn, later). Late joiners don't learn effects set before they joined until upgrades
re-applies them from the player record (upgrades' job). Mic capture starts only while you are in a
game with others, loopback is on, or a mic sensitivity panel is on screen (meter only; nothing sent).
The mic sensitivity is kept for the session only; saving it to disk comes with settings_input. A
headless test run that quits while the mic is open may print "2 ObjectDB instances were leaked at
exit" (the mic stream); harmless, and closing the window normally lets go of the mic first.

**For audio (later):** reuse the voice reverb settings (20 ms pre-delay, room 0.55, damping 0.7, wet
about 0.2 up close) for footsteps and sound effects, so the whole facility sounds like one place.

**Stubbed:** settings (push-to-talk via `set_push_to_talk`), the test scene's Fly toggle (upgrades) and
door (doors system).

**How the door system plugs in:** give every door scene a `SoundDoor` child with a `BoxShape3D`
covering the doorway, set `is_open` whenever the door opens or closes, and put the door's solid body
on the sound-blocker layer (world). Don't carve the navmesh for closed doors: sound still goes through
them, just muffled. Keycard-locked doors are simply closed doors.

**What level_gen must provide:** walls and floors on the sound-blocker layer (world), and a baked
navmesh per floor (a `NavigationRegion3D`) that includes every doorway. Without a navmesh, voices still
work, but only with straight-line wall muffling.

**For the next systems:** upgrades calls `Voice.set_voice_effect(player_id, upgrade_id, effect)` on every PC
when a mutation is gained (and `clear_voice_effect` when lost); audio should create the `Voice` bus
(voice buses send to it, or to Master until it exists); settings_input calls `set_push_to_talk`.
