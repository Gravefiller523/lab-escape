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
## The mode used while climbing a ladder (over any mutation's mode).
const LADDER_MODE: StringName = &"ladder"

var _modifiers: Dictionary[StringName, MovementEffectData] = {}
var _mode_name: StringName = &""
var _mode: MovementMode
## Set by the active mode each frame.
var _grounded: bool = false
## 0 = standing, 1 = fully crouched. Smoothly changed by the mode.
var crouch_amount: float = 0.0

## Ladders whose climb area the body is in (Ladder adds and removes itself).
var _ladders: Array[Ladder] = []
var _ladder_mode: MovementMode
var _on_ladder: bool = false
## Ladders can't grab the body again until then (after jumping off).
var _ladder_free_msec: int = 0


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


## The mode actually running: "ladder" while climbing one, else the wanted mode (walk when the wanted mode has
## no file).
func get_active_mode() -> StringName:
	if _on_ladder:
		return LADDER_MODE
	if _mode == null:
		_update_mode()
	return _mode_name


## Fastest the body can move sideways now (the host's speed check). Ladders are slower than any mode.
func get_top_speed() -> float:
	var body := get_parent() as PlayerCharacter
	if body == null:
		return 0.0
	if _mode == null:
		_update_mode()
	return _mode.top_speed(body) if _mode != null else body.tuning.sprint_speed * get_speed_multiplier()


## The movement mode object running now (tests look at a mode's state, e.g. hover's gliding).
func get_mode_object() -> MovementMode:
	return _ladder_mode if _on_ladder else _mode


## Ladder calls these when the body enters or leaves its climb area.
func add_ladder(ladder: Ladder) -> void:
	if not _ladders.has(ladder):
		_ladders.append(ladder)


func remove_ladder(ladder: Ladder) -> void:
	_ladders.erase(ladder)


## The ladder the body can climb now, or null (none near, or it just jumped off one).
func get_ladder() -> Ladder:
	if Time.get_ticks_msec() < _ladder_free_msec:
		return null
	for index: int in range(_ladders.size() - 1, -1, -1):
		if is_instance_valid(_ladders[index]) and _ladders[index].is_inside_tree():
			return _ladders[index]
		_ladders.remove_at(index)
	return null


func is_on_ladder() -> bool:
	return _on_ladder


## Let go of the ladder (jumping off): ladders can't grab the body for ladder_regrab_seconds.
func let_go_of_ladder() -> void:
	var body := get_parent() as PlayerCharacter
	var seconds: float = body.tuning.ladder_regrab_seconds if body != null else 0.4
	_ladder_free_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	_set_on_ladder(false)


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
	if body == null:
		return
	var ladder: Ladder = get_ladder()
	var climb: bool = ladder != null and (_on_ladder or LadderMovementMode.wants_to_climb(body, input))
	# Standing at the bottom and not climbing up: walk off normally.
	if climb and _on_ladder and body.is_on_floor() and not LadderMovementMode.wants_to_climb(body, input):
		climb = false
	_set_on_ladder(climb)
	if _on_ladder:
		_ladder_mode.physics_update(body, input, delta)
	elif _mode != null:
		_mode.physics_update(body, input, delta)


func _set_on_ladder(on_ladder: bool) -> void:
	if on_ladder == _on_ladder:
		return
	if on_ladder and _ladder_mode == null:
		_ladder_mode = load_mode(LADDER_MODE)
	_on_ladder = on_ladder and _ladder_mode != null
	mode_changed.emit(get_active_mode())


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
