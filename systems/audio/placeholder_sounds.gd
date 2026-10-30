class_name PlaceholderSounds
extends RefCounted
## Simple generated sounds (beeps, thumps, whooshes, a drone) so the game isn't silent before real sound
## files exist. Each kind is made once and kept. Replace them by putting real AudioStreams into
## systems/audio/event_sounds.tres (see docs/systems/audio.md). Spec: docs/systems/audio.md.

const MIX_RATE: int = 22050

static var _made: Dictionary[StringName, AudioStreamWAV] = {}


## A placeholder for a kind of sound: &"blip", &"thunk", &"whoosh", &"chime", &"squeak", &"low", &"rise",
## &"hum", &"roar", &"sparkle", &"clunk", &"fanfare", &"music_calm", &"music_floor", &"music_boss",
## and for surfaces (NEW 2026-10-29): &"step_concrete", &"land_concrete", &"step_metal", &"land_metal",
## &"impact_concrete", &"impact_metal", &"impact_wood", &"impact_glass", &"impact_flesh", and looping
## &"scrape_rough", &"scrape_metal".
static func get_sound(kind: StringName) -> AudioStreamWAV:
	if not _made.has(kind):
		_made[kind] = _make(kind)
	return _made[kind]


static func _make(kind: StringName) -> AudioStreamWAV:
	match kind:
		&"thunk":
			return _render(0.18, func(t: float) -> float: return _noise(t) * 0.6 * exp(-t * 30.0) + sin(TAU * 90.0 * t) * exp(-t * 20.0))
		&"whoosh":
			return _render(0.25, func(t: float) -> float: return _noise(t) * 0.35 * sin(PI * t / 0.25))
		&"chime":
			return _render(0.6, func(t: float) -> float: return (sin(TAU * 880.0 * t) + sin(TAU * 1320.0 * t)) * 0.3 * exp(-t * 5.0))
		&"squeak":
			return _render(0.2, func(t: float) -> float: return sin(TAU * (900.0 + 1500.0 * t) * t) * 0.4 * exp(-t * 10.0))
		&"low":
			return _render(0.8, func(t: float) -> float: return sin(TAU * (220.0 - 120.0 * t) * t) * 0.5 * exp(-t * 3.0))
		&"rise":
			return _render(0.7, func(t: float) -> float: return sin(TAU * (200.0 + 500.0 * t) * t) * 0.4 * sin(PI * t / 0.7))
		&"hum":
			return _render(2.0, func(t: float) -> float: return (sin(TAU * 55.0 * t) + 0.5 * sin(TAU * 110.0 * t)) * 0.3, true)
		&"roar":
			return _render(0.9, func(t: float) -> float: return (_noise(t) * 0.4 + sin(TAU * 70.0 * t) * 0.5) * sin(PI * t / 0.9))
		&"sparkle":
			return _render(0.5, func(t: float) -> float: return sin(TAU * (1200.0 + 600.0 * sin(TAU * 8.0 * t)) * t) * 0.25 * exp(-t * 4.0))
		&"clunk":
			return _render(0.25, func(t: float) -> float: return (sin(TAU * 140.0 * t) + _noise(t) * 0.3) * 0.5 * exp(-t * 18.0))
		&"fanfare":
			return _render(1.2, func(t: float) -> float: return _chord(t, [523.0, 659.0, 784.0]) * 0.25 * exp(-t * 1.5))
		&"step_concrete":
			return _render(0.09, func(t: float) -> float: return _noise(t) * 0.5 * exp(-t * 60.0) + sin(TAU * 120.0 * t) * 0.3 * exp(-t * 50.0))
		&"land_concrete":
			return _render(0.2, func(t: float) -> float: return _noise(t) * 0.6 * exp(-t * 30.0) + sin(TAU * 80.0 * t) * 0.6 * exp(-t * 25.0))
		&"step_metal":
			return _render(0.18, func(t: float) -> float: return (sin(TAU * 520.0 * t) + sin(TAU * 1310.0 * t) * 0.6) * 0.3 * exp(-t * 25.0) + _noise(t) * 0.3 * exp(-t * 80.0))
		&"land_metal":
			return _render(0.35, func(t: float) -> float: return (sin(TAU * 310.0 * t) + sin(TAU * 870.0 * t) * 0.7) * 0.4 * exp(-t * 12.0) + _noise(t) * 0.4 * exp(-t * 40.0))
		&"impact_concrete":
			return _render(0.22, func(t: float) -> float: return _noise(t) * 0.7 * exp(-t * 35.0) + sin(TAU * 70.0 * t) * 0.5 * exp(-t * 22.0))
		&"impact_wood":
			return _render(0.25, func(t: float) -> float: return (sin(TAU * 180.0 * t) + sin(TAU * 410.0 * t) * 0.5) * 0.45 * exp(-t * 24.0) + _noise(t) * 0.4 * exp(-t * 60.0))
		&"impact_metal":
			return _render(0.5, func(t: float) -> float: return (sin(TAU * 430.0 * t) + sin(TAU * 1150.0 * t) * 0.6 + sin(TAU * 2310.0 * t) * 0.3) * 0.3 * exp(-t * 8.0) + _noise(t) * 0.4 * exp(-t * 70.0))
		&"impact_glass":
			return _render(0.3, func(t: float) -> float: return (sin(TAU * 2600.0 * t) + sin(TAU * 3900.0 * t) * 0.5) * 0.25 * exp(-t * 18.0) + _noise(t) * 0.2 * exp(-t * 90.0))
		&"impact_flesh":
			return _render(0.2, func(t: float) -> float: return sin(TAU * (110.0 - 200.0 * t) * t) * 0.6 * exp(-t * 20.0) + _noise(t) * 0.25 * exp(-t * 30.0))
		&"scrape_rough":
			return _render(1.0, func(t: float) -> float: return _noise(t) * 0.3 * (0.75 + 0.25 * sin(TAU * 7.0 * t)), true)
		&"scrape_metal":
			return _render(1.0, func(t: float) -> float: return (_noise(t) * 0.2 + sin(TAU * 1700.0 * t) * 0.08) * (0.75 + 0.25 * sin(TAU * 5.0 * t)), true)
		&"music_calm":
			return _render(8.0, func(t: float) -> float: return _chord(t, [130.8, 196.0, 261.6]) * 0.12 * (0.7 + 0.3 * sin(TAU * t / 8.0)), true)
		&"music_floor":
			return _render(8.0, func(t: float) -> float: return _chord(t, [110.0, 130.8, 164.8]) * 0.12 * (0.6 + 0.4 * absf(sin(TAU * t / 2.0))), true)
		&"music_boss":
			return _render(4.0, func(t: float) -> float: return (_chord(t, [73.4, 87.3, 110.0]) * 0.15 + sin(TAU * 2.0 * t) * _noise(t) * 0.05), true)
		_:
			return _render(0.08, func(t: float) -> float: return sin(TAU * 660.0 * t) * 0.4)


static func _chord(t: float, notes: Array) -> float:
	var total: float = 0.0
	for note: Variant in notes:
		var hz: float = note
		total += sin(TAU * hz * t)
	return total / float(notes.size())


## Repeatable "noise" (no random numbers: the same sound every time).
static func _noise(t: float) -> float:
	return fposmod(sin(t * 12345.678) * 43758.5453, 2.0) - 1.0


static func _render(seconds: float, wave: Callable, loop: bool = false) -> AudioStreamWAV:
	var count: int = int(seconds * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for index: int in count:
		var t: float = float(index) / float(MIX_RATE)
		var raw: float = wave.call(t)
		var value: float = clampf(raw, -1.0, 1.0)
		bytes.encode_s16(index * 2, int(value * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	return stream
