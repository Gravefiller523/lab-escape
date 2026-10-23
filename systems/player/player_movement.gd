class_name PlayerMovement
extends Node
## Child "Movement" of every player. Combines movement modifiers from upgrades and runs the active
## movement mode. Modifiers are set on every PC (the owner needs them to move, others for height).
##
## How modifiers combine: multipliers multiply, can_jump is false if any modifier says false, and the
## movement mode with the highest mode_priority wins.

signal mode_changed(mode: StringName)

const DEFAULT_MODE: StringName = &"walk"
const MODES_FOLDER: String = "res://systems/player/movement_modes/"

var _modifiers: Dictionary[StringName, MovementEffectData] = {}
var _mode_name: StringName = &""
var _mode: MovementMode
## Set by the active mode each frame.
var _grounded: bool = false
## 0 = standing, 1 = fully crouched. Smoothly changed by the mode.
var crouch_amount: float = 0.0


## Adds or replaces the modifier from one source (usually an upgrade id).
func set_modifier(source_id: StringName, effect: MovementEffectData) -> void:
	_modifiers[source_id] = effect
	_update_mode()


func remove_modifier(source_id: StringName) -> void:
	_modifiers.erase(source_id)
	_update_mode()


## CHANGED 2026-10-23 (upgrades branch): also x the body's "move_speed" stat (damage's StatsComponent; the
## energy drink's speed boost and upgrades change it). No StatsComponent = 1.
func get_speed_multiplier() -> float:
	var total: float = 1.0
	for effect: MovementEffectData in _modifiers.values():
		total *= effect.speed_multiplier
	var stats: StatsComponent = StatsComponent.of(get_parent()) if get_parent() != null else null
	if stats != null:
		total *= stats.get_value(&"move_speed", 1.0)
	return total


func get_jump_multiplier() -> float:
	var total: float = 1.0
	for effect: MovementEffectData in _modifiers.values():
		total *= effect.jump_multiplier
	return total


func get_gravity_multiplier() -> float:
	var total: float = 1.0
	for effect: MovementEffectData in _modifiers.values():
		total *= effect.gravity_multiplier
	return total


func get_height_multiplier() -> float:
	var total: float = 1.0
	for effect: MovementEffectData in _modifiers.values():
		total *= effect.height_multiplier
	return total


func can_jump() -> bool:
	for effect: MovementEffectData in _modifiers.values():
		if not effect.can_jump:
			return false
	return true


## The mode the modifiers ask for (highest mode_priority), even if its file doesn't exist yet.
func get_wanted_mode() -> StringName:
	var best: StringName = DEFAULT_MODE
	var best_priority: int = -2147483648
	for effect: MovementEffectData in _modifiers.values():
		if effect.movement_mode != &"" and effect.mode_priority > best_priority:
			best = effect.movement_mode
			best_priority = effect.mode_priority
	return best


## The mode actually running. Falls back to walk when the wanted mode has no file.
func get_active_mode() -> StringName:
	if _mode == null:
		_update_mode()
	return _mode_name


func get_height() -> float:
	var body := get_parent() as PlayerCharacter
	if body == null:
		return 0.0
	return lerpf(body.tuning.stand_height, body.tuning.crouch_height, crouch_amount) * get_height_multiplier()


func is_crouching() -> bool:
	return crouch_amount > 0.5


func is_grounded() -> bool:
	return _grounded


## Movement modes call this each frame.
func set_grounded(grounded: bool) -> void:
	_grounded = grounded


## Host calls. Pushes the player; the owning PC applies it.
func apply_knockback(impulse: Vector3) -> void:
	var body := get_parent() as PlayerCharacter
	if body != null:
		body.request_knockback(impulse)


## Runs the active mode for one physics frame (owner only; PlayerCharacter calls this).
func physics_update(input: PlayerInputState, delta: float) -> void:
	if _mode == null:
		_update_mode()
	var body := get_parent() as PlayerCharacter
	if body != null and _mode != null:
		_mode.physics_update(body, input, delta)


## Loads a mode by name from movement_modes/<name>_mode.gd. Null if there is no such file.
static func load_mode(mode_name: StringName) -> MovementMode:
	var path: String = MODES_FOLDER + String(mode_name) + "_mode.gd"
	if not ResourceLoader.exists(path):
		return null
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		return null
	return script.new() as MovementMode


func _update_mode() -> void:
	var wanted: StringName = get_wanted_mode()
	var next_name: StringName = wanted
	var next: MovementMode = load_mode(wanted) if wanted != _mode_name or _mode == null else _mode
	if next == null:
		if wanted != DEFAULT_MODE:
			# Not a warning: modes from later phases (wall_climb, slide...) don't exist yet and that's expected.
			print("PlayerMovement: no movement mode file for '%s' yet, walking instead." % wanted)
		next_name = DEFAULT_MODE
		next = _mode if _mode_name == DEFAULT_MODE and _mode != null else load_mode(DEFAULT_MODE)
	if next_name == _mode_name and _mode != null:
		return
	var body := get_parent() as PlayerCharacter
	if _mode != null and body != null:
		_mode.exit(body)
	_mode = next
	_mode_name = next_name
	if _mode != null and body != null:
		_mode.enter(body)
	mode_changed.emit(_mode_name)
