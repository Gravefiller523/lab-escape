extends VoicePreset
## A deep, boomy voice: lower pitch and more bass.


func build(bus_index: int, strength: float) -> void:
	var pitch := AudioEffectPitchShift.new()
	pitch.pitch_scale = 1.0 - 0.3 * strength
	AudioServer.add_bus_effect(bus_index, pitch)
	var bass := AudioEffectLowShelfFilter.new()
	bass.cutoff_hz = 300.0
	bass.gain = 1.0 + 1.5 * strength
	AudioServer.add_bus_effect(bus_index, bass)
