class_name VoiceEffectData
extends UpgradeEffectData
## Changes how the player sounds in voice chat.

## 1.0 = normal. Fly uses a higher number for a higher voice.
@export var pitch_scale: float = 1.0
## Name of an effect preset from the voice system, e.g. "buzz", "robot", "gurgle".
## Empty = pitch change only.
@export var effect_preset: StringName = &""
## 0.0 to 1.0, how strong the preset is.
@export_range(0.0, 1.0) var effect_strength: float = 0.5
