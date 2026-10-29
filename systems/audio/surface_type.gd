class_name SurfaceType
extends Resource
## What a floor or object is made of, for footstep and landing sounds (NEW 2026-10-29, HL2 feel step 1.7).
## One file per material in systems/audio/surfaces/ (concrete.tres, metal.tres). Adding a material is adding a
## file. To say what something is made of, give its collision body (or any node above it) the metadata
## "surface" set to the file's name, e.g. "metal". Anything unmarked is concrete.
## Drag real sound files onto the fields in the Inspector; empty fields use a generated placeholder.

const FOLDER: String = "res://systems/audio/surfaces/"
const DEFAULT_ID: StringName = &"concrete"
const META_KEY: StringName = &"surface"

## A footstep on it (also played when jumping off it).
@export var step: AudioStream
## Landing on it from a fall.
@export var land: AudioStream
## Louder (positive) or quieter (negative) than normal, in dB.
@export var volume_db: float = 0.0
## Placeholder kinds (PlaceholderSounds) used while the fields above are empty.
@export var step_placeholder: StringName = &"step_concrete"
@export var land_placeholder: StringName = &"land_concrete"

static var _loaded: Dictionary[StringName, SurfaceType] = {}


## The surface with this id (its file in FOLDER), or concrete if there's no such file.
static func find(id: StringName) -> SurfaceType:
	if _loaded.has(id):
		return _loaded[id]
	var path: String = FOLDER + String(id) + ".tres"
	var surface: SurfaceType = load(path) as SurfaceType if ResourceLoader.exists(path) else null
	if surface == null:
		surface = find(DEFAULT_ID) if id != DEFAULT_ID else SurfaceType.new()
	_loaded[id] = surface
	return surface


## What `node` is made of: the first "surface" metadata on it or a node above it, else concrete.
static func of(node: Node) -> SurfaceType:
	var current: Node = node
	while current != null:
		if current.has_meta(META_KEY):
			return find(StringName(str(current.get_meta(META_KEY))))
		current = current.get_parent()
	return find(DEFAULT_ID)


func step_sound() -> AudioStream:
	return step if step != null else PlaceholderSounds.get_sound(step_placeholder)


func land_sound() -> AudioStream:
	return land if land != null else PlaceholderSounds.get_sound(land_placeholder)
