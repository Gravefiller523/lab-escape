class_name PlayerCharacter
extends CharacterBody3D
## One player's first-person body (systems/player/player.tscn). Spawned only by PlayerSpawner.
##
## The PC of the player it belongs to is its "multiplayer authority" and moves it instantly
## (the one exception to "the host decides", see CLAUDE.md section 6). That PC writes the sync_*
## values every frame; a MultiplayerSynchronizer sends them to everyone else ~30 times a second, and
## other PCs smoothly slide their copy of the body toward them. The host also checks nobody moves
## faster than possible.

const GROUP: StringName = &"players"
const ATTACH_POINTS: Array[StringName] = [&"head", &"face", &"back", &"left_arm", &"right_arm",
	&"legs", &"feet", &"body"]

## The player's Steam ID (or local test id). Set by PlayerSpawner before the body enters the tree.
var player_id: int = 0
@export var tuning: PlayerTuning = preload("res://systems/player/player_tuning.tres")

## Synced from the owner to everyone (see the Sync node). Don't write these from other code.
var sync_position: Vector3 = Vector3.ZERO
var sync_yaw: float = 0.0
var sync_pitch: float = 0.0
var sync_crouch: float = 0.0

var _input_enabled: bool = true
var _jump_queued: bool = false
var _input_override: PlayerInputState
## Host speed check: where and when this body was last seen at a believable spot.
var _checked_position: Vector3 = Vector3.ZERO
var _checked_msec: int = 0
var _has_checked: bool = false

@onready var _collision: CollisionShape3D = %Collision
@onready var _body_mesh: MeshInstance3D = %BodyMesh
@onready var _head: Node3D = %Head
@onready var _camera: Camera3D = %Camera
@onready var _hold_point: Node3D = %HoldPoint
@onready var _attach_points: Node3D = %AttachPoints
@onready var _movement: PlayerMovement = %Movement


## Climbs up from any node (a hitbox, a held item) to the player it belongs to. Null if none.
static func of(node: Node) -> PlayerCharacter:
	var current: Node = node
	while current != null:
		if current is PlayerCharacter:
			return current as PlayerCharacter
		current = current.get_parent()
	return null


## The spawned body of a player on this PC. Null if not spawned.
static func find(player_id: int) -> PlayerCharacter:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var body := node as PlayerCharacter
		if body != null and body.player_id == player_id and not body.is_queued_for_deletion():
			return body
	return null


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PLAYERS) \
		| PhysicsLayers.bit(PhysicsLayers.CARTS) | PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	# Each body needs its own shape and mesh so crouching one doesn't shrink everyone.
	_collision.shape = _collision.shape.duplicate()
	_body_mesh.mesh = _body_mesh.mesh.duplicate()
	sync_position = global_position
	sync_yaw = rotation.y
	_camera.fov = tuning.fov
	apply_height()

	var local: bool = is_local()
	_camera.current = local
	# You don't see your own body from inside it.
	_body_mesh.visible = not local
	if local and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.player_spawned.emit(player_id, self)
	if local:
		EventBus.local_player_spawned.emit(self)


## True on the PC that controls this body.
func is_local() -> bool:
	return is_multiplayer_authority()


func get_camera() -> Camera3D:
	return _camera


func get_aim_origin() -> Vector3:
	return _camera.global_position


func get_aim_direction() -> Vector3:
	return -_camera.global_transform.basis.z


## Where held props float (used by physics_props).
func get_hold_point() -> Node3D:
	return _hold_point


## &"head", &"face", &"back", &"left_arm", &"right_arm", &"legs", &"feet" or &"body". Null if unknown.
## The points are rough placeholders until there is a real character model.
func get_attach_point(point: StringName) -> Node3D:
	return _attach_points.get_node_or_null(NodePath(String(point))) as Node3D


func get_movement() -> PlayerMovement:
	return _movement


## Host calls. Tells the owning PC to move its body there.
func teleport(xform: Transform3D) -> void:
	if not multiplayer.is_server():
		push_error("PlayerCharacter.teleport: only the host can teleport players.")
		return
	_teleport_owner.rpc_id(get_multiplayer_authority(), xform)


## Local. Menus and the console turn movement and mouse look off.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if is_local() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE


## Hides the body (ghosts while dead). Your own body is always hidden from you.
func set_body_visible(body_visible: bool) -> void:
	_body_mesh.visible = body_visible and not is_local()


## For tests only: use this input instead of the keyboard. Null goes back to the keyboard.
func set_input_override(input: PlayerInputState) -> void:
	_input_override = input


## Host calls through PlayerMovement.apply_knockback().
func request_knockback(impulse: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_knockback_owner.rpc_id(get_multiplayer_authority(), impulse)


## Used by movement modes: is there room to stand up from the current height?
func has_headroom_to_stand() -> bool:
	var standing: float = tuning.stand_height * _movement.get_height_multiplier()
	var missing: float = standing - _movement.get_height()
	if missing <= 0.01:
		return true
	return not test_move(global_transform, Vector3.UP * missing)


## Resizes the collision capsule, body and camera to the current height (crouch, Giraffe).
func apply_height() -> void:
	var height: float = _movement.get_height()
	var radius: float = tuning.radius
	var capsule := _collision.shape as CapsuleShape3D
	if capsule != null:
		capsule.radius = radius
		capsule.height = maxf(height, radius * 2.0)
	_collision.position.y = height * 0.5
	var mesh := _body_mesh.mesh as CapsuleMesh
	if mesh != null:
		mesh.radius = radius
		mesh.height = maxf(height, radius * 2.0)
	_body_mesh.position.y = height * 0.5
	_head.position.y = height - tuning.eye_offset


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	if event.is_action_pressed(InputActions.PAUSE) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# STUB until ui has a pause menu: Esc just frees the mouse; clicking takes it back.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and _input_enabled \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not _input_enabled:
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-motion.relative.x * tuning.mouse_sensitivity))
		_head.rotation.x = clampf(_head.rotation.x - deg_to_rad(motion.relative.y * tuning.mouse_sensitivity),
			deg_to_rad(-tuning.max_pitch), deg_to_rad(tuning.max_pitch))
	if event.is_action_pressed(InputActions.JUMP):
		_jump_queued = true


func _physics_process(delta: float) -> void:
	if is_local():
		_movement.physics_update(_gather_input(), delta)
		sync_position = global_position
		sync_yaw = rotation.y
		sync_pitch = _head.rotation.x
		sync_crouch = _movement.crouch_amount
	else:
		_follow_synced(delta)
		if multiplayer.is_server():
			_check_speed()


func _gather_input() -> PlayerInputState:
	if _input_override != null:
		var forced: PlayerInputState = _input_override
		if forced.jump_pressed:
			_input_override = PlayerInputState.new()
			_input_override.move = forced.move
			_input_override.sprint = forced.sprint
			_input_override.crouch = forced.crouch
		return forced
	var input := PlayerInputState.new()
	if _input_enabled:
		input.move = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT,
			InputActions.MOVE_BACK, InputActions.MOVE_FORWARD)
		input.jump_pressed = _jump_queued
		input.sprint = Input.is_action_pressed(InputActions.SPRINT)
		input.crouch = Input.is_action_pressed(InputActions.CROUCH)
	_jump_queued = false
	return input


## Other players' bodies: slide smoothly toward the latest synced values.
func _follow_synced(delta: float) -> void:
	if global_position.distance_to(sync_position) > tuning.remote_snap_distance:
		global_position = sync_position
	else:
		var weight: float = 1.0 - exp(-tuning.remote_smoothing * delta)
		global_position = global_position.lerp(sync_position, weight)
		rotation.y = lerp_angle(rotation.y, sync_yaw, weight)
		_head.rotation.x = lerpf(_head.rotation.x, sync_pitch, weight)
	if not is_equal_approx(_movement.crouch_amount, sync_crouch):
		_movement.crouch_amount = sync_crouch
		apply_height()


## Host only: if a body moved further than its top speed allows, put it back.
func _check_speed() -> void:
	var now: int = Time.get_ticks_msec()
	if not _has_checked:
		_has_checked = true
		_checked_position = sync_position
		_checked_msec = now
		return
	if sync_position.is_equal_approx(_checked_position):
		_checked_msec = now
		return
	var seconds: float = maxf(float(now - _checked_msec) / 1000.0, 1.0 / 30.0)
	var top_speed: float = tuning.sprint_speed * _movement.get_speed_multiplier()
	var allowed: float = top_speed * tuning.speed_check_tolerance * seconds + tuning.speed_check_slack
	var moved := Vector2(sync_position.x - _checked_position.x, sync_position.z - _checked_position.z)
	if moved.length() > allowed:
		teleport(Transform3D(Basis(Vector3.UP, sync_yaw), _checked_position))
		sync_position = _checked_position
	else:
		_checked_position = sync_position
	_checked_msec = now


## Host -> owner: move there (spawn points, lift, anti-cheat).
@rpc("any_peer", "call_local", "reliable")
func _teleport_owner(xform: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_local():
		return
	global_transform = xform
	velocity = Vector3.ZERO
	sync_position = global_position
	sync_yaw = rotation.y


## Host -> owner: a push (explosions, enemy hits).
@rpc("any_peer", "call_local", "reliable")
func _knockback_owner(impulse: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_local():
		return
	velocity += impulse


## STUB until settings_input exists: nothing to read yet; tuning defaults are used.
func _on_settings_changed(_section: StringName) -> void:
	pass
