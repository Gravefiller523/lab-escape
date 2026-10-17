class_name VoiceCodec
extends RefCounted
## Turns microphone audio into small packets and back, for local mode (no Steam).
## Packets are 16 kHz, mono, 16-bit: about 32 KB/s per speaker, fine on one PC or a LAN.
## Over Steam, Steam compresses voice itself and this isn't used for sending.

const SAMPLE_RATE: int = 16000
const BYTES_PER_SAMPLE: int = 2


## Stereo frames at `from_rate` (the mixer's rate) -> 16 kHz mono 16-bit bytes.
static func encode(frames: PackedVector2Array, from_rate: float) -> PackedByteArray:
	var step: float = from_rate / float(SAMPLE_RATE)
	var count: int = int(float(frames.size()) / step)
	var bytes := PackedByteArray()
	bytes.resize(count * BYTES_PER_SAMPLE)
	for index: int in count:
		var frame: Vector2 = frames[mini(int(float(index) * step), frames.size() - 1)]
		var mono: float = clampf((frame.x + frame.y) * 0.5, -1.0, 1.0)
		bytes.encode_s16(index * BYTES_PER_SAMPLE, int(mono * 32767.0))
	return bytes


## 16-bit mono bytes (any sample rate) -> frames for an AudioStreamGenerator at that rate.
static func decode(bytes: PackedByteArray) -> PackedVector2Array:
	var count: int = int(bytes.size() / BYTES_PER_SAMPLE)
	var frames := PackedVector2Array()
	frames.resize(count)
	for index: int in count:
		var sample: float = float(bytes.decode_s16(index * BYTES_PER_SAMPLE)) / 32768.0
		frames[index] = Vector2(sample, sample)
	return frames


## How loud some audio is, 0 to 1 (root mean square).
static func level(frames: PackedVector2Array) -> float:
	if frames.is_empty():
		return 0.0
	var total: float = 0.0
	for frame: Vector2 in frames:
		total += frame.x * frame.x
	return sqrt(total / float(frames.size()))
