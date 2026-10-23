class_name BossArena
extends Node3D
## The fight rules for a boss arena room, added at runtime by the Bosses autoload as child "BossArena" of
## the arena room (so level_gen's room scene needs no editing). Spec: docs/systems/bosses.md.
## - The fight starts when the first player walks in.
## - Once every living player is inside, the doorways are blocked (bars appear) until the boss is beaten.
## The host decides; the door state reaches every PC (and joiners).

signal fight_started()
signal fight_ended()

const NODE_NAME: String = "BossArena"
const GROUP: StringName = &"boss_arena"
const BAR_THICKNESS: float = 0.3
const BAR_COLOR: Color = Color(0.75, 0.15, 0.1)

var _room: Node3D
var _size: Vector2 = Vector2.ZERO
var _area: Area3D
var _doors: Array[StaticBody3D] = []
var _locked: bool = false
var _started: bool = false
var _ended: bool = false


static func current() -> BossArena:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var arena := node as BossArena
		if arena != null and arena.is_inside_tree() and not arena.is_queued_for_deletion():
			return arena
	return null


## Before adding it: the room it guards, and its floor size (metres along +x and +z from the room's origin).
func setup(room: Node3D, size: Vector2) -> void:
	_room = room
	_size = size
	_area = Area3D.new()
	_area.name = "Inside"
	_area.collision_layer = 0
	_area.collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x - 1.0, 4.0, size.y - 1.0)
	shape.shape = box
	shape.position = Vector3(size.x / 2.0, 2.0, size.y / 2.0)
	_area.add_child(shape)
	add_child(_area)
	for child: Node in room.get_children():
		var doorway := child as RoomDoorway
		if doorway != null:
			_doors.append(_make_door(doorway))


func _ready() -> void:
	name = NODE_NAME
	add_to_group(GROUP)
	if _area != null:
		_area.body_entered.connect(func(_body: Node3D) -> void: _check())
	EventBus.boss_defeated.connect(_on_boss_defeated)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


func is_locked() -> bool:
	return _locked


func is_started() -> bool:
	return _started


## Host: block (or open) the doorways.
func lock_doors(locked: bool) -> void:
	if is_inside_tree() and multiplayer.is_server():
		_doors_rpc.rpc(locked)


## Where minions appear: the room's minion_spawn markers.
func get_minion_spawn_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	if _room == null:
		return points
	for child: Node in _room.get_children():
		var marker := child as RoomMarker
		if marker != null and marker.kind == &"minion_spawn":
			points.append(marker)
	return points


## NEW: a point moved inside the arena's floor (at least `margin` from the walls), in world space.
func clamp_inside(point: Vector3, margin: float) -> Vector3:
	if _room == null:
		return point
	var local: Vector3 = _room.global_transform.affine_inverse() * point
	local.x = clampf(local.x, margin, _size.x - margin)
	local.z = clampf(local.z, margin, _size.y - margin)
	return _room.global_transform * local


## Living players inside the arena now.
func get_players_inside() -> Array[PlayerCharacter]:
	var inside: Array[PlayerCharacter] = []
	if _area == null:
		return inside
	for body: Node3D in _area.get_overlapping_bodies():
		var player := body as PlayerCharacter
		var health: HealthComponent = HealthComponent.of(player) if player != null else null
		if player != null and (health == null or not health.is_dead()):
			inside.append(player)
	return inside


func _physics_process(_delta: float) -> void:
	if multiplayer.is_server() and _started and not _ended and not _locked:
		_check()


## Host: start the fight when someone comes in; lock up once everyone alive is in.
func _check() -> void:
	if not is_inside_tree() or not multiplayer.is_server() or _ended:
		return
	var inside: Array[PlayerCharacter] = get_players_inside()
	if inside.is_empty():
		return
	if not _started:
		_started = true
		var boss: Boss = Boss.current()
		if boss != null:
			boss.start_fight()
		fight_started.emit()
	var everyone_alive: int = 0
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var player := node as PlayerCharacter
		var health: HealthComponent = HealthComponent.of(player) if player != null else null
		if player != null and player.get_world_3d() == get_world_3d() and (health == null or not health.is_dead()):
			everyone_alive += 1
	if not _locked and inside.size() >= everyone_alive:
		lock_doors(true)


func _on_boss_defeated(_boss_id: StringName) -> void:
	if _ended:
		return
	_ended = true
	fight_ended.emit()
	lock_doors(false)


func _make_door(doorway: RoomDoorway) -> StaticBody3D:
	var door := StaticBody3D.new()
	door.name = "Bars_%s" % doorway.name
	door.collision_layer = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Doorways sit on the footprint's edge: on the x = 0 or x = size edge the bars run along z.
	var on_side: bool = absf(doorway.position.x) < 0.5 or absf(doorway.position.x - _size.x) < 0.5
	box.size = Vector3(BAR_THICKNESS, doorway.height, doorway.width) if on_side \
		else Vector3(doorway.width, doorway.height, BAR_THICKNESS)
	shape.shape = box
	shape.position.y = doorway.height / 2.0
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bars := BoxMesh.new()
	bars.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = BAR_COLOR
	bars.material = material
	mesh.mesh = bars
	mesh.position.y = doorway.height / 2.0
	door.add_child(mesh)
	door.visible = false
	add_child(door)
	# The arena node sits at the room's origin, like the doorway markers.
	door.position = doorway.position
	return door


@rpc("authority", "call_local", "reliable")
func _doors_rpc(locked: bool) -> void:
	if not is_inside_tree():
		return
	_locked = locked
	for door: StaticBody3D in _doors:
		door.visible = locked
		door.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD) if locked else 0


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_doors_rpc.rpc_id(multiplayer.get_remote_sender_id(), _locked)
