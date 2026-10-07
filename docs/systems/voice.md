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
```
Launch presets in `systems/voice/presets/`: `buzz` (Fly: band-pass + tremolo), `robot` (cybernetic
voicebox: distortion + chorus), `gurgle` (Octo: low-pass + phaser), `slime` (Slug), `deep` (pitch down).
Preset files are found by name (`<preset>_preset.gd`), like movement modes.

## EventBus
- Emits: `player_speaking_changed` (local).
- Listens: `player_joined`/`player_left` (create/free buses and players), `player_spawned` (attach the
  3D voice player to the body's head), `settings_changed` (push-to-talk, mic device, voice volume, reduce_voice_effects).

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

## Acceptance criteria
- [ ] Two Steam PCs: talking is clear with under ~250 ms delay; with Fly, the listener hears a higher, buzzy voice from that player only.
- [ ] Voice gets quieter with distance and comes from the speaker's position.
- [ ] Push-to-talk and open mic both work; settings change them live.
- [ ] Works with 4 players; 8 tested with local instances (bus count, CPU).

## Open design questions
- DEFAULT: proximity voice with a 30 m cut-off; ghosts are heard by everyone at low volume. **Team to playtest.**
- Should listeners be able to turn off other players' voice effects (accessibility)? DEFAULT: `reduce_voice_effects` halves effect strength.
- Steam voice quality and delay at 8 players is unknown; measure in Phase 1.

## Changelog
- 2026-10-07: spec created.
