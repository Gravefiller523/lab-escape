class_name TileLightFlicker
extends Node
## NEW 2026-10-30 (Zachary): makes one tile's lights behave like its damage level. Put one next to (or in)
## a tile and call setup(). Numbers come from Config.floor_gen ("Damage lighting"):
## - pristine: every light steady.
## - light: some lights flicker now and then, the rest stay on.
## - heavy: some lights are dead; the rest are dim, stay dark for a while, then flicker. Emergency light steady.
## - destroyed: most lights are dead; the rest flicker faintly once in a long while. The red emergency light
##   stays on and now and then flickers.
## Looks only: never sent over the network. Each light's pattern is seeded by its node path and the damage
## level, so every PC shows the same pattern (each on its own clock).

var _flickers: Array[_Flicker] = []
var _tuning: FloorGenTuning


## Collects the tile's lights (groups tile_light and tile_emergency_light) and starts the level's behaviour.
func setup(tile: Node, level: StringName, tuning: FloorGenTuning = null) -> void:
	_tuning = tuning if tuning != null else Config.floor_gen
	_flickers.clear()
	for node: Node in RoomShape.all_children(tile):
		var light := node as Light3D
		if light == null:
			continue
		if light.is_in_group(TileStandards.LIGHT_GROUP):
			_flickers.append(_ceiling_light(light, level))
		elif light.is_in_group(TileStandards.EMERGENCY_LIGHT_GROUP):
			_flickers.append(_emergency_light(light, level))


## Moves every light's pattern on by delta seconds (called every frame; tests call it directly).
func step(delta: float) -> void:
	for flicker: _Flicker in _flickers:
		flicker.step(delta, _tuning.flicker_toggle_seconds)


func _process(delta: float) -> void:
	step(delta)


func _ceiling_light(light: Light3D, level: StringName) -> _Flicker:
	var rng: RandomNumberGenerator = SeededRng.make(hash(str(light.get_path())), &"tile_light_flicker", hash(level))
	var flicker := _Flicker.new(light, rng)
	if not light.has_meta(&"base_energy"):
		light.set_meta(&"base_energy", light.light_energy)
	var base: float = light.get_meta(&"base_energy")
	match level:
		&"light":
			light.light_energy = base
			if rng.randf() < _tuning.light_flicker_share:
				flicker.flickering(true, _tuning.light_on_seconds, _tuning.light_flicker_seconds)
			else:
				flicker.steady(true)
		&"heavy":
			light.light_energy = base * _tuning.heavy_energy
			if rng.randf() < _tuning.heavy_dead_share:
				flicker.steady(false)
			else:
				flicker.flickering(false, _tuning.heavy_dark_seconds, _tuning.heavy_flicker_seconds)
		&"destroyed":
			light.light_energy = base * _tuning.destroyed_energy
			if rng.randf() < _tuning.destroyed_dead_share:
				flicker.steady(false)
			else:
				flicker.flickering(false, _tuning.destroyed_dark_seconds, _tuning.destroyed_flicker_seconds)
		_:
			light.light_energy = base
			flicker.steady(true)
	return flicker


func _emergency_light(light: Light3D, level: StringName) -> _Flicker:
	var rng: RandomNumberGenerator = SeededRng.make(hash(str(light.get_path())), &"tile_light_flicker", hash(level))
	var flicker := _Flicker.new(light, rng)
	if level == &"destroyed":
		flicker.flickering(true, _tuning.emergency_on_seconds, _tuning.emergency_flicker_seconds)
	else:
		flicker.steady(true)
	return flicker


## One light: either steady (on or off), or resting (on or off) for a while, then flickering for a while.
class _Flicker:
	extends RefCounted

	var light: Light3D
	var rng: RandomNumberGenerator
	var animated: bool = false
	var rest_on: bool = true
	var rest_seconds: Vector2 = Vector2.ONE
	var flicker_seconds: Vector2 = Vector2.ONE
	var in_flicker: bool = false
	var phase_left: float = 0.0
	var toggle_left: float = 0.0

	func _init(for_light: Light3D, seeded: RandomNumberGenerator) -> void:
		light = for_light
		rng = seeded

	func steady(on: bool) -> void:
		animated = false
		light.visible = on

	func flickering(resting_on: bool, rest: Vector2, flicker: Vector2) -> void:
		animated = true
		rest_on = resting_on
		rest_seconds = rest
		flicker_seconds = flicker
		in_flicker = false
		light.visible = rest_on
		# Start part way through a rest, so the lights don't all flicker at the same moment.
		phase_left = rng.randf_range(0.0, rest.y)

	func step(delta: float, toggle_seconds: Vector2) -> void:
		if not animated or not is_instance_valid(light):
			return
		phase_left -= delta
		if phase_left <= 0.0:
			in_flicker = not in_flicker
			if in_flicker:
				phase_left = rng.randf_range(flicker_seconds.x, flicker_seconds.y)
				toggle_left = 0.0
			else:
				phase_left = rng.randf_range(rest_seconds.x, rest_seconds.y)
				light.visible = rest_on
		if in_flicker:
			toggle_left -= delta
			if toggle_left <= 0.0:
				toggle_left = rng.randf_range(toggle_seconds.x, toggle_seconds.y)
				light.visible = not light.visible
