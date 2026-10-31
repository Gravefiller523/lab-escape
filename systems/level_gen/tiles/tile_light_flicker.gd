class_name TileLightFlicker
extends Node
## NEW 2026-10-30 (Zachary): makes one tile's lights behave like its damage level. Put one next to (or in)
## a tile and call setup(). Numbers come from Config.floor_gen ("Damage lighting"):
## - pristine: every light steady.
## - light: some lights flicker now and then, the rest stay on.
## - heavy: some lights are dead; the rest are dim, stay dark for a while, then flicker. Emergency light steady.
## - destroyed: most lights are dead; the rest flicker faintly once in a long while. The red emergency light
##   stays on and now and then flickers.
## CHANGED 2026-10-31 (Zachary: "way more random"): each light has its own speed, a flicker is either one
## quick blink or a stuttering burst, switches don't strictly alternate, and every flash has its own brightness.
## Looks only: never sent over the network. Each light's pattern is seeded by its node path and the damage
## level, so every PC shows the same pattern (each on its own clock).

const BASE_ENERGY_META: StringName = &"base_energy"

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
		flicker.step(delta)


func _process(delta: float) -> void:
	step(delta)


func _new_flicker(light: Light3D, level: StringName) -> _Flicker:
	if not light.has_meta(BASE_ENERGY_META):
		light.set_meta(BASE_ENERGY_META, light.light_energy)
	var rng: RandomNumberGenerator = SeededRng.make(hash(str(light.get_path())), &"tile_light_flicker", hash(level))
	return _Flicker.new(light, rng, _tuning)


func _ceiling_light(light: Light3D, level: StringName) -> _Flicker:
	var flicker: _Flicker = _new_flicker(light, level)
	var base: float = light.get_meta(BASE_ENERGY_META)
	match level:
		&"light":
			if flicker.rng.randf() < _tuning.light_flicker_share:
				flicker.flickering(true, base, _tuning.light_on_seconds, _tuning.light_flicker_seconds)
			else:
				flicker.steady(true, base)
		&"heavy":
			if flicker.rng.randf() < _tuning.heavy_dead_share:
				flicker.steady(false, base)
			else:
				flicker.flickering(false, base * _tuning.heavy_energy, _tuning.heavy_dark_seconds,
					_tuning.heavy_flicker_seconds)
		&"destroyed":
			if flicker.rng.randf() < _tuning.destroyed_dead_share:
				flicker.steady(false, base)
			else:
				flicker.flickering(false, base * _tuning.destroyed_energy, _tuning.destroyed_dark_seconds,
					_tuning.destroyed_flicker_seconds)
		_:
			flicker.steady(true, base)
	return flicker


func _emergency_light(light: Light3D, level: StringName) -> _Flicker:
	var flicker: _Flicker = _new_flicker(light, level)
	var base: float = light.get_meta(BASE_ENERGY_META)
	if level == &"destroyed":
		flicker.flickering(true, base, _tuning.emergency_on_seconds, _tuning.emergency_flicker_seconds)
	else:
		flicker.steady(true, base)
	return flicker


## One light: either steady (on or off), or resting (on or off) for a while, then flickering for a while.
## A flicker is one quick blink, or a burst of random switches at random brightness.
class _Flicker:
	extends RefCounted

	var light: Light3D
	var rng: RandomNumberGenerator
	var tuning: FloorGenTuning
	var animated: bool = false
	var energy: float = 1.0
	## This light's own speed: every wait is multiplied by it.
	var speed: float = 1.0
	var rest_on: bool = true
	var rest_seconds: Vector2 = Vector2.ONE
	var flicker_seconds: Vector2 = Vector2.ONE
	var in_flicker: bool = false
	var single_blink: bool = false
	var phase_left: float = 0.0
	var toggle_left: float = 0.0

	func _init(for_light: Light3D, seeded: RandomNumberGenerator, numbers: FloorGenTuning) -> void:
		light = for_light
		rng = seeded
		tuning = numbers

	func steady(on: bool, brightness: float) -> void:
		animated = false
		energy = brightness
		_show(on, true)

	func flickering(resting_on: bool, brightness: float, rest: Vector2, flicker: Vector2) -> void:
		animated = true
		energy = brightness
		rest_on = resting_on
		rest_seconds = rest
		flicker_seconds = flicker
		speed = rng.randf_range(tuning.flicker_light_speed.x, tuning.flicker_light_speed.y)
		in_flicker = false
		_show(rest_on, true)
		# Start part way through a rest, so the lights don't all flicker at the same moment.
		phase_left = rng.randf_range(0.0, rest.y) * speed

	func step(delta: float) -> void:
		if not animated or not is_instance_valid(light):
			return
		phase_left -= delta
		if phase_left <= 0.0:
			in_flicker = not in_flicker
			if in_flicker:
				_start_flicker()
			else:
				phase_left = rng.randf_range(rest_seconds.x, rest_seconds.y) * speed
				_show(rest_on, true)
		elif in_flicker and not single_blink:
			toggle_left -= delta
			if toggle_left <= 0.0:
				toggle_left = _toggle_wait()
				_show(rng.randf() < tuning.flicker_on_chance, false)

	func _start_flicker() -> void:
		single_blink = rng.randf() < tuning.flicker_single_blink_chance
		if single_blink:
			# One quick blink the other way, then back to resting.
			phase_left = _toggle_wait()
			_show(not rest_on, false)
		else:
			phase_left = rng.randf_range(flicker_seconds.x, flicker_seconds.y) * speed
			toggle_left = _toggle_wait()
			_show(not light.visible, false)

	func _toggle_wait() -> float:
		return rng.randf_range(tuning.flicker_toggle_seconds.x, tuning.flicker_toggle_seconds.y) * speed

	## full: the light's brightness for its level; otherwise a random share of it (a flash).
	func _show(on: bool, full: bool) -> void:
		light.visible = on
		if on:
			var share: float = 1.0 if full else rng.randf_range(tuning.flicker_brightness.x, tuning.flicker_brightness.y)
			light.light_energy = energy * share
