class_name VoicePreset
extends RefCounted
## Base for voice effect presets (building blocks). A preset called "buzz" lives in
## systems/voice/presets/buzz_preset.gd, so a new preset is one new file and no list to edit.
## It adds Godot AudioEffects to one player's voice bus.


## Adds this preset's effects to the bus. strength is 0 to 1 (VoiceEffectData.effect_strength).
func build(_bus_index: int, _strength: float) -> void:
	pass
