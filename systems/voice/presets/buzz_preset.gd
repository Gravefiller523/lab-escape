extends VoicePreset
## Fly: a thin, buzzy voice. A band-pass filter makes it sound small and tinny, a light distortion
## adds the buzz, and a fast chorus gives it a wobble like wings.


func build(bus_index: int, strength: float) -> void:
	var band := AudioEffectBandPassFilter.new()
	band.cutoff_hz = 1800.0
	band.resonance = 0.4 + 0.4 * strength
	AudioServer.add_bus_effect(bus_index, band)
	var buzz := AudioEffectDistortion.new()
	buzz.mode = AudioEffectDistortion.MODE_OVERDRIVE
	buzz.drive = 0.2 + 0.5 * strength
	buzz.post_gain = -4.0
	AudioServer.add_bus_effect(bus_index, buzz)
	var wobble := AudioEffectChorus.new()
	wobble.voice_count = 2
	wobble.set_voice_rate_hz(0, 12.0)
	wobble.set_voice_rate_hz(1, 17.0)
	wobble.wet = 0.3 + 0.4 * strength
	AudioServer.add_bus_effect(bus_index, wobble)
