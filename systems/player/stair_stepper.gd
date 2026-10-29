class_name StairStepper
extends RefCounted
## Walking up stairs and small ledges without jumping (NEW 2026-10-29, HL2 feel step 1.4).
## Before a normal move, the walk mode asks try_step: if the move would run into something low, "lift up,
## move forward, put down" with the real collision shape (PhysicsServer3D.body_test_motion). It only steps
## onto level geometry (the WORLD layer), never onto props, so a crate can't be climbed by walking into it.

## How far in from the edge the "is this a floor?" check looks, in metres.
const EDGE_INSET: float = 0.05


## If moving `motion` (flat, metres this tick) from where `body` is now would run into a ledge at most
## `max_height` high, moves the body up onto it (and forward) and returns how far up it went. Otherwise
## returns 0 and leaves the body alone, for the normal move.
static func try_step(body: CharacterBody3D, motion: Vector3, max_height: float) -> float:
	var flat := Vector3(motion.x, 0.0, motion.z)
	if flat.length() < 0.001 or max_height <= 0.0:
		return 0.0
	var from: Transform3D = body.global_transform
	var result := PhysicsTestMotionResult3D.new()
	# 0. The normal move: only a step if it hits something too steep to walk up.
	if not _test(body, from, flat, result):
		return 0.0
	if result.get_collision_normal().angle_to(Vector3.UP) <= body.floor_max_angle:
		return 0.0
	var blocked_travel: float = Vector3(result.get_travel().x, 0.0, result.get_travel().z).length()
	# 1. Up, as far as the ceiling allows.
	_test(body, from, Vector3.UP * max_height, result)
	var lifted: float = result.get_travel().y
	if lifted <= 0.01:
		return 0.0
	var raised: Transform3D = from.translated(result.get_travel())
	# 2. Forward. No further than the normal move: a wall too high to step.
	_test(body, raised, flat, result)
	var forward: Vector3 = result.get_travel()
	if Vector3(forward.x, 0.0, forward.z).length() <= blocked_travel + 0.001:
		return 0.0
	var ahead: Transform3D = raised.translated(forward)
	# 3. Down onto the step. Nothing underneath: it was a gap, not a step.
	if not _test(body, ahead, Vector3.DOWN * lifted, result):
		return 0.0
	var point: Vector3 = result.get_collision_point()
	var landing: Transform3D = ahead.translated(result.get_travel())
	var height: float = landing.origin.y - from.origin.y
	# The edge itself must be low enough (the rounded bottom of the capsule can rest higher than it).
	if height <= 0.01 or point.y - from.origin.y > max_height:
		return 0.0
	if not _is_world_floor(body, point, flat.normalized()):
		return 0.0
	body.global_position = landing.origin
	return height


static func _test(body: CharacterBody3D, from: Transform3D, motion: Vector3,
		result: PhysicsTestMotionResult3D) -> bool:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	params.margin = body.safe_margin
	return PhysicsServer3D.body_test_motion(body.get_rid(), params, result)


## The capsule touches a step's edge at an angle, so look straight down just inside the edge instead: is
## there walkable level geometry at that height?
static func _is_world_floor(body: CharacterBody3D, point: Vector3, inward: Vector3) -> bool:
	var probe: Vector3 = point + inward * EDGE_INSET
	var query := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.1, probe + Vector3.DOWN * 0.1,
		PhysicsLayers.bit(PhysicsLayers.WORLD))
	query.exclude = [body.get_rid()]
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit["normal"]
	var position: Vector3 = hit["position"]
	return normal.angle_to(Vector3.UP) <= body.floor_max_angle and absf(position.y - point.y) < 0.05
