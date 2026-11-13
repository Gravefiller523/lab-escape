class_name Lure
extends Node3D
## Something certain enemies can't resist (NEW 2026-11-12, roadmap WP14): a laser pointer's dot, a bag of trash, a
## player with the Fly mutation. An enemy whose EnemyData.lure_kinds lists this lure's `kind` and that is within
## `radius` (and can see it, if `needs_sight`) drops what it was doing and goes to it ("lured" state), or, when the
## lure is a player, goes after that player rather than anyone else. Lures are made through the Enemies autoload
## (place_lure, attach_lure) or by tagging a prop `lure_<kind>`. Only the host's AI reads them.
## Spec: docs/systems/enemies.md.

const GROUP: StringName = &"lures"
## Enemies look at the lure from this high above their feet, and a wall this close to the lure doesn't hide it
## (a laser dot sits on the wall it was pointed at).
const EYE_HEIGHT: float = 0.5
const SURFACE_SLACK: float = 0.6

## What it is: &"laser", &"trash", &"fly_player". Enemies list the kinds they fall for.
var kind: StringName = &""
## How far away (m) it draws enemies.
var radius: float = 10.0
## Must the enemy have a clear line to it?
var needs_sight: bool = true
## Set when the lure is a player: enemies go after them instead of walking up to a spot.
var player: PlayerCharacter
## Seconds left before it disappears (below 0 = stays until freed).
var seconds_left: float = -1.0

var _follow: WeakRef
var _follows: bool = false


func _ready() -> void:
	add_to_group(GROUP)


## Stay on top of this node (a prop, a player) and disappear when it does.
func follow(node: Node3D) -> void:
	_follow = weakref(node)
	_follows = true
	if node.is_inside_tree():
		global_position = node.global_position


func _physics_process(delta: float) -> void:
	if _follows:
		var target := _follow.get_ref() as Node3D
		if target == null or not target.is_inside_tree() or target.is_queued_for_deletion():
			queue_free()
			return
		global_position = target.global_position
	if seconds_left >= 0.0:
		seconds_left -= delta
		if seconds_left <= 0.0:
			queue_free()


## Is it still there and still drawing `enemy` (same world, in reach, of a kind it falls for)?
func draws(enemy: Enemy) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or enemy.data == null:
		return false
	if not enemy.data.lure_kinds.has(String(kind)) or get_world_3d() != enemy.get_world_3d():
		return false
	if player != null and (not is_instance_valid(player) or player.is_ghost()):
		return false
	return global_position.distance_to(enemy.global_position) <= radius


## Can `enemy` see it (no wall in between)? Always true for lures that don't need to be seen.
func seen_by(enemy: Enemy) -> bool:
	if not needs_sight:
		return true
	var from: Vector3 = enemy.global_position + Vector3.UP * EYE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, global_position, PhysicsLayers.bit(PhysicsLayers.WORLD))
	var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(global_position) <= SURFACE_SLACK


## The closest lure that draws `enemy` and that it can see, or null.
static func nearest_for(enemy: Enemy) -> Lure:
	if enemy == null or not enemy.is_inside_tree() or enemy.data == null or enemy.data.lure_kinds.is_empty():
		return null
	var best: Lure = null
	var best_distance: float = INF
	for node: Node in enemy.get_tree().get_nodes_in_group(GROUP):
		var lure := node as Lure
		if lure == null or not lure.draws(enemy):
			continue
		var distance: float = lure.global_position.distance_to(enemy.global_position)
		if distance < best_distance and lure.seen_by(enemy):
			best_distance = distance
			best = lure
	return best
