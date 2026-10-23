class_name EventSounds
extends Resource
## Which sound each game event makes (systems/audio/event_sounds.tres). Leave a field empty to use the
## generated placeholder; drag a real sound file (e.g. from ElevenLabs: log it in docs/AI_CONTENT_LOG.md)
## onto a field in the Inspector to replace it. No code needed. Spec: docs/systems/audio.md.

@export_group("Fighting")
## Something with health got hurt (at it).
@export var hit: AudioStream
## An enemy or boss died.
@export var enemy_death: AudioStream
## A player died.
@export var player_death: AudioStream
## A player used their item (swing, throw, drink).
@export var item_use: AudioStream

@export_group("Players")
## A dead player came out of the 3D printer.
@export var reprint: AudioStream
## A mutation was eaten or a cybernetic installed.
@export var upgrade: AudioStream
## Someone bought something from a vendor.
@export var purchase: AudioStream

@export_group("Lift and boss")
## The cargo lift starts moving (loops while it rides).
@export var lift_ride: AudioStream
## The lift arrived at a floor.
@export var lift_arrive: AudioStream
## A lift part was slotted in.
@export var lift_part: AudioStream
## The boss starts a new phase.
@export var boss_phase: AudioStream
## The boss is beaten.
@export var boss_defeated: AudioStream

@export_group("Music (used when a department or boss has no music of its own)")
@export var menu_music: AudioStream
@export var floor_music: AudioStream
@export var boss_music: AudioStream

## field name -> placeholder kind (PlaceholderSounds) used while the field is empty.
const PLACEHOLDERS: Dictionary = {
	"hit": &"thunk", "enemy_death": &"squeak", "player_death": &"low", "item_use": &"whoosh",
	"reprint": &"rise", "upgrade": &"sparkle", "purchase": &"chime",
	"lift_ride": &"hum", "lift_arrive": &"chime", "lift_part": &"clunk", "boss_phase": &"roar", "boss_defeated": &"fanfare",
	"menu_music": &"music_calm", "floor_music": &"music_floor", "boss_music": &"music_boss",
}


## The sound for an event field (the placeholder if it's empty).
func sound_for(field: StringName) -> AudioStream:
	var stream := get(field) as AudioStream
	if stream != null:
		return stream
	var kind: StringName = PLACEHOLDERS.get(String(field), &"blip")
	return PlaceholderSounds.get_sound(kind)
