# audio

Folder: `res://systems/audio/` · Autoload: `Sound` · Size: S · Phase 1b

## Purpose
Music and sound effects: the audio bus layout (Master, Music, SFX, Voice, UI), music that follows the
department and boss, crossfades, and simple helpers to play 2D and 3D positional sounds with a limit on
how many play at once.

**Not responsible for:** voice chat (voice creates its own per-player buses under `Voice`), choosing
which sound an object makes (each object's scene or data holds its AudioStream).

## Public API
```gdscript
func play_music(stream: AudioStream, fade_seconds: float = 1.5) -> void
func stop_music(fade_seconds: float = 1.5) -> void
func play_ui(stream: AudioStream) -> void
func play_2d(stream: AudioStream, volume_db: float = 0.0, bus: StringName = &"SFX") -> void
func play_3d(stream: AudioStream, position: Vector3, volume_db: float = 0.0, pitch_variation: float = 0.05) -> void
func play_3d_attached(stream: AudioStream, parent: Node3D, volume_db: float = 0.0) -> AudioStreamPlayer3D
func set_volume(bus: StringName, linear: float) -> void   # NEW 2026-10-23 (settings_input will call it)
func get_volume(bus: StringName) -> float
func event_sound(field: StringName) -> AudioStream       # NEW: the sound for a game event (event_sounds.tres or a placeholder)
func get_music() -> AudioStream                          # NEW
func stop_effects() -> void                              # NEW
static func ensure_buses() -> void                       # NEW: Music, SFX, Voice, UI -> Master
```
Uses a pool of players (e.g. 32 3D players) so 100 gems landing at once doesn't create 100 nodes.

## EventBus
- Emits: none.
- Listens: `game_state_changed` (menu and Break Room music), `floor_ready` (department music),
  `boss_floor_started` (boss music from BossData), `boss_defeated`, `run_ended`, `settings_changed` (volumes).

## Data it owns and saves
Owns `res://default_bus_layout.tres`. Music comes from `DepartmentData.music` and `BossData.music`. Saves nothing.

## Adding content
New departments and bosses bring their own music in their data files. No code.

## Multiplayer
**Sounds are never sent over the network.** Each PC plays a sound when it sees the event locally
(a synced hit, a synced prop landing). This avoids extra traffic and keeps sounds in sync with visuals.

## Dependencies and stubs
settings_input (volumes; stub with 1.0). Music events from game_flow (stub by emitting EventBus signals in a test).

## Test scene and GUT tests
Test scene: buttons to switch department music, trigger boss music, spam 200 3D sounds.
GUT tests: `test_buses_exist`, `test_music_switches_on_floor_ready`, `test_pool_limit_respected`, `test_volume_setting_applies`.

## Acceptance criteria
- [ ] Department and boss music play and crossfade from data.
- [ ] 200 simultaneous sound requests don't drop the frame rate.

## Open design questions
- Music sources: ElevenLabs or licensed packs; check commercial licences and log AI-made audio in `docs/AI_CONTENT_LOG.md`.

## Changelog
- 2026-10-07: spec created.
- 2026-10-23: built (Phase 1b). Changes marked above. CHANGED: the buses are made at startup by `Sound.ensure_buses()`
  (no `default_bus_layout.tres` yet; voice chat's buses already send to `Voice`). NEW `EventSounds`
  (`systems/audio/event_sounds.tres`): one AudioStream field per game event (hit, enemy_death, player_death, item_use,
  reprint, upgrade, purchase, lift_ride, lift_arrive, lift_part, boss_phase, boss_defeated) and fallback music (menu,
  floor, boss); an empty field uses a generated placeholder (`PlaceholderSounds`: beeps, thumps, a drone; made in code,
  not AI, so nothing for the AI log). Drop a real file onto a field in the Inspector to replace it. Sounds play on every
  PC locally from what that PC sees: any HealthComponent getting hurt or dying (found with SceneTree.node_added),
  `item_used`, `player_reprinted`, `upgrade_gained`, `vendor_purchase`, `lift_departed` (a hum while riding),
  `floor_ready` (arrival), `lift_part_delivered`, `boss_phase_changed`, `boss_defeated`. Music: menu / Break Room,
  department (`DepartmentData.music`), boss (`BossData.music`), crossfaded. Pitch variety uses its own non-seeded
  RandomNumberGenerator (looks and sounds only, never gameplay). The autoload is `Sound` (before Voice).

## HANDOFF
**Built (2026-10-23):** the `Sound` autoload (`SoundService`), `EventSounds` + `event_sounds.tres`, `PlaceholderSounds`, the
test scene (`systems/audio/test/audio_test.tscn`) and 8 GUT tests (`tests/unit/audio/test_audio.gd`: the spec's list plus
`test_placeholders_fill_empty_event_sounds`, `test_a_real_sound_replaces_the_placeholder`, `test_department_music_from_data`,
`test_hits_make_a_sound_at_the_target`).

**Foundation / project.godot changes:** autoload line `Sound` (after Net, before Voice). No new EventBus signals.

**For the next steps:** real sounds and music (ElevenLabs or packs): check the licence, log each AI file in
`docs/AI_CONTENT_LOG.md`, then drop it onto `event_sounds.tres` (or a department's / boss's `music`). settings_input should
call `Sound.set_volume(bus, 0..1)`.
