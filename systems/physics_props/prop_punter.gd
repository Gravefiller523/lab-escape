class_name PropPunter
extends Node
## NEW 2026-10-30 (HL2 feel step 4.3): the punt, like Half-Life 2's gravity gun. The punt arm cybernetic
## (content/cybernetics/cybernetic_punt_arm.tres) adds systems/upgrades/behaviours/punt_arm.tscn, whose root
## is this node, under the player on every PC. On the PC that owns the body, right click (SECONDARY)
## launches the prop you are holding, or else the loose prop you aim at within Config.feel.props.punt_range.
## With nothing to punt, the click goes on to the item in your hand as usual. NEW 2026-10-30 (Zachary): punting
## an enemy shoves it away (less for heavy ones) and never hurts it. The host checks it and
## applies it (PropSpawner.request_punt); whoever punted gets the credit for its hits, as with a throw.
## NEW 2026-10-30 (pull, Zachary's idea): holding E on a prop that is too far to pick up (within pull_range, 8 m)
## drags it towards you like a magnet (it tumbles along, it doesn't hover), and it is picked up as soon as it is in reach (which the arm makes
## pull_grab_bonus longer). Heavy props that need helpers aren't pulled.
## Spec: docs/systems/physics_props.md.

## Local: we punted this prop (the host may still refuse it).
signal punted(prop: NetProp)
## Local (NEW 2026-10-30, Zachary): we punted an enemy. It gets shoved, never hurt.
signal punted_enemy(enemy: Enemy)

## Use handler priority: below grabbing (50), so a prop in reach is just picked up.
const PULL_PRIORITY: int = 40
## How often (per second) a pull is sent while E is held.
const PULL_SEND_RATE: float = 20.0
## A pulled prop is drawn towards this point: this far in front of the eyes (metres).
const PULL_HOLD_DISTANCE: float = 1.6

var _body: PlayerCharacter
var _ready_at_msec: int = 0
var _pulling: NetProp
## True when the use key started the pull (it stops when the key comes up); tests pull without it.
var _pull_by_key: bool = false
var _pull_send_left: float = 0.0


func _ready() -> void:
	_body = get_parent() as PlayerCharacter
	if _body != null and _body.is_local():
		_hook_into_interaction.call_deferred()


func _hook_into_interaction() -> void:
	var interaction: InteractionController = InteractionService.controller_of(_body) if is_inside_tree() else null
	if interaction != null:
		interaction.register_use_handler(PULL_PRIORITY, _on_use)


## The upgrade was removed: E goes back to normal.
func _exit_tree() -> void:
	stop_pull()
	var interaction: InteractionController = InteractionService.controller_of(_body) if _body != null else null
	if interaction != null:
		interaction.unregister_use_handler(_on_use)


## The punter under a body, or null (no punt arm).
static func of(body: Node) -> PropPunter:
	if body == null:
		return null
	for child: Node in body.get_children():
		if child is PropPunter:
			return child as PropPunter
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _body == null or not _body.is_local() or UI.is_screen_open():
		return
	# This node is added after the held item's, so it hears the click first.
	if event.is_action_pressed(InputActions.SECONDARY) and try_punt():
		get_viewport().set_input_as_handled()


## Local: punt what we hold, or else what we aim at. False if there is nothing to punt or it is too soon.
func try_punt() -> bool:
	if _body == null or Time.get_ticks_msec() < _ready_at_msec:
		return false
	var spawner: PropSpawner = Props.spawner_for(_body)
	if spawner == null:
		return false
	var grab: GrabController = PropsService.grab_of(_body)
	var prop: NetProp = grab.get_held() if grab != null else null
	var held: bool = prop != null
	if not held:
		prop = find_target()
		# NEW 2026-10-30: an enemy nearer the middle of the view than any prop gets shoved instead.
		var enemy: Enemy = find_enemy()
		if enemy != null and (prop == null or _aim_dot(_middle_of(enemy)) >= _aim_dot(prop.global_position)):
			return _punt_enemy(enemy, spawner)
	if prop == null or prop.is_attached() or prop.get_spawner() == null:
		return false
	if not held and prop.is_held():
		return false
	if Config.feel.props.no_grab_while_stood_on and spawner.is_under_a_player(prop):
		return false
	_ready_at_msec = Time.get_ticks_msec() + int(Config.feel.props.punt_cooldown * 1000.0)
	var direction: Vector3 = _body.get_aim_direction()
	if held:
		grab.drop()
	else:
		direction = spawner.punt_direction(prop, direction)
	# If our PC runs it, launch it now (no waiting for the host), like a throw.
	var predicted: bool = prop.is_simulated_here() and not _body.multiplayer.is_server()
	if predicted:
		prop.punt_now(direction, spawner.punt_strength(prop))
	spawner.request_punt(prop, direction, predicted)
	Sound.play_3d(Sound.event_sound(&"punt"), prop.global_position)
	punted.emit(prop)
	return true


func _punt_enemy(enemy: Enemy, spawner: PropSpawner) -> bool:
	_ready_at_msec = Time.get_ticks_msec() + int(Config.feel.props.punt_cooldown * 1000.0)
	spawner.request_punt_enemy(enemy, _body.get_aim_direction())
	Sound.play_3d(Sound.event_sound(&"punt"), _middle_of(enemy))
	punted_enemy.emit(enemy)
	return true


## NEW 2026-10-30: the living enemy we aim at within punt_range: the one the look ray hits first, or else the one
## nearest the middle of the view (inside punt_cone_dot) that nothing solid hides. Null if none.
func find_enemy() -> Enemy:
	var tuning: PropTuning = Config.feel.props
	var origin: Vector3 = _body.get_aim_origin()
	var aim: Vector3 = _body.get_aim_direction()
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var mask: int = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS) \
		| PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * tuning.punt_range, mask, [_body.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var aimed: Enemy = Enemy.of(hit["collider"] as Node)
		if aimed != null and not aimed.is_dead():
			return aimed
	var best: Enemy = null
	var best_dot: float = tuning.punt_cone_dot
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or not enemy.is_inside_tree() or enemy.get_world_3d() != _body.get_world_3d():
			continue
		var middle: Vector3 = _middle_of(enemy)
		if origin.distance_to(middle) > tuning.punt_range:
			continue
		var dot: float = _aim_dot(middle)
		if dot <= best_dot:
			continue
		var sight := PhysicsRayQueryParameters3D.create(origin, middle, PhysicsLayers.bit(PhysicsLayers.WORLD))
		if not space.intersect_ray(sight).is_empty():
			continue
		best = enemy
		best_dot = dot
	return best


func _middle_of(enemy: Enemy) -> Vector3:
	return enemy.global_position + Vector3.UP * enemy.hurtbox_height * 0.5


## How close `point` is to the middle of our view (1 = dead centre).
func _aim_dot(point: Vector3) -> float:
	var to: Vector3 = point - _body.get_aim_origin()
	return _body.get_aim_direction().dot(to.normalized()) if not to.is_zero_approx() else 1.0


## Use handler: E on nothing usable while a prop is in pull range starts pulling it (while E is held).
func _on_use(target: Node3D) -> bool:
	if target != null and Interactable.of(target) != null:
		return false
	var grab: GrabController = PropsService.grab_of(_body)
	if grab != null and grab.get_held() != null:
		return false
	var prop: NetProp = find_target(Config.feel.props.pull_range)
	if prop == null or not can_pull(prop):
		return false
	pull(prop, true)
	return true


## Local: what the host would allow (decide_pull), as far as this PC knows.
func can_pull(prop: NetProp) -> bool:
	var spawner: PropSpawner = prop.get_spawner()
	return spawner != null and not prop.is_attached() and not prop.is_held() and not prop.needs_help() \
		and not (Config.feel.props.no_grab_while_stood_on and spawner.is_under_a_player(prop))


## Local: start pulling a prop towards us. `by_key`: stop when the use key comes up.
func pull(prop: NetProp, by_key: bool = false) -> void:
	_pulling = prop
	_pull_by_key = by_key
	_pull_send_left = 0.0


func stop_pull() -> void:
	_pulling = null
	_pull_by_key = false


## The prop we are pulling now, or null.
func get_pulled() -> NetProp:
	return _pulling if is_instance_valid(_pulling) else null


## Local: keep pulling while E is held, and pick it up once it is in reach.
func _physics_process(delta: float) -> void:
	if _pulling == null:
		return
	var prop: NetProp = get_pulled()
	var tuning: PropTuning = Config.feel.props
	if prop == null or not can_pull(prop) or (_pull_by_key and not Input.is_action_pressed(InputActions.USE)) \
			or _body.get_aim_origin().distance_to(prop.global_position) > tuning.pull_range + 1.0:
		stop_pull()
		return
	if _body.get_aim_origin().distance_to(prop.global_position) <= PropSpawner.grab_reach_of(_body):
		stop_pull()
		var grab: GrabController = PropsService.grab_of(_body)
		if grab != null:
			grab.try_grab(prop)
		return
	_pull_send_left -= delta
	if _pull_send_left <= 0.0:
		_pull_send_left = 1.0 / PULL_SEND_RATE
		var point: Vector3 = _body.get_aim_origin() + _body.get_aim_direction() * PULL_HOLD_DISTANCE
		prop.get_spawner().request_pull(prop, _body, point)


## The loose prop we aim at within `reach` (punt_range if not given): the one the look ray hits, or else the
## one nearest the middle of the view (inside punt_cone_dot) that nothing solid hides. Null if none.
func find_target(reach: float = -1.0) -> NetProp:
	var tuning: PropTuning = Config.feel.props
	if reach < 0.0:
		reach = tuning.punt_range
	var origin: Vector3 = _body.get_aim_origin()
	var aim: Vector3 = _body.get_aim_direction()
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var mask: int = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * reach, mask, [_body.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var aimed: NetProp = NetProp.of(hit["collider"] as Node)
		if aimed != null and not aimed.is_held():
			return aimed
	var spawner: PropSpawner = Props.spawner_for(_body)
	if spawner == null:
		return null
	var best: NetProp = null
	var best_dot: float = tuning.punt_cone_dot
	for prop: NetProp in spawner.get_props():
		if not is_instance_valid(prop) or prop.is_attached() or prop.is_held():
			continue
		var to_prop: Vector3 = prop.global_position - origin
		var distance: float = to_prop.length()
		if distance > reach or distance < 0.01:
			continue
		var dot: float = aim.dot(to_prop / distance)
		if dot <= best_dot:
			continue
		var sight := PhysicsRayQueryParameters3D.create(origin, prop.global_position, PhysicsLayers.bit(PhysicsLayers.WORLD))
		if not space.intersect_ray(sight).is_empty():
			continue
		best = prop
		best_dot = dot
	return best
