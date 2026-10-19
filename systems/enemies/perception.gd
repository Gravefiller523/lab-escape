class_name Perception
extends Node
## Child "Perception" of every Enemy (added by Enemy). Which players it can see: alive, within
## EnemyData.sight_range, and with no wall in between. Host only (the AI runs there). Checked a few
## times a second, not every frame. Spec: docs/systems/enemies.md.

const NODE_NAME: String = "Perception"
const CHECK_SECONDS: float = 0.2
## Eyes this high above the enemy's origin (flying enemies look from their body).
const EYE_HEIGHT: float = 0.4
## Aim at the player's chest.
const PLAYER_CHEST: float = 1.0

## Test scenes: enemies ignore every player while true.
static var players_invisible: bool = false

var _enemy: Enemy
var _visible: Array[PlayerCharacter] = []
var _check_left: float = 0.0


func _ready() -> void:
	name = NODE_NAME
	_enemy = get_parent() as Enemy


func get_visible_players() -> Array[PlayerCharacter]:
	var alive: Array[PlayerCharacter] = []
	for player: PlayerCharacter in _visible:
		if is_valid_target(player):
			alive.append(player)
	return alive


## The closest player it can see, or null.
func get_nearest_visible_player() -> PlayerCharacter:
	var best: PlayerCharacter = null
	var best_distance: float = INF
	for player: PlayerCharacter in get_visible_players():
		var distance: float = player.global_position.distance_to(_enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## A player worth chasing: still here, alive, and not hidden by the test switch.
func is_valid_target(player: PlayerCharacter) -> bool:
	if players_invisible or not is_instance_valid(player) or not player.is_inside_tree() \
			or player.is_queued_for_deletion():
		return false
	var health: HealthComponent = HealthComponent.of(player)
	return health == null or not health.is_dead()


## Looks again now (tests; normally every CHECK_SECONDS).
func refresh() -> void:
	_visible.clear()
	if _enemy == null or not _enemy.is_inside_tree() or players_invisible:
		return
	var sight: float = _enemy.data.sight_range if _enemy.data != null else 15.0
	var eyes: Vector3 = _enemy.global_position + Vector3.UP * EYE_HEIGHT
	var space: PhysicsDirectSpaceState3D = _enemy.get_world_3d().direct_space_state
	for node: Node in _enemy.get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var player := node as PlayerCharacter
		if player == null or not is_valid_target(player) or player.get_world_3d() != _enemy.get_world_3d():
			continue
		var chest: Vector3 = player.global_position + Vector3.UP * PLAYER_CHEST
		if eyes.distance_to(chest) > sight:
			continue
		var query := PhysicsRayQueryParameters3D.create(eyes, chest, PhysicsLayers.bit(PhysicsLayers.WORLD))
		if space.intersect_ray(query).is_empty():
			_visible.append(player)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_SECONDS
		refresh()
