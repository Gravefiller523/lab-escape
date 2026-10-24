@tool
class_name Ladder
extends Area3D
## A ladder anyone can climb (systems/player/ladder.tscn). Put it in a room, a test scene, or grow it from
## something (the mutated plant). Its origin is the bottom middle; it goes up `height` metres. Climbers stand
## on its front (+Z, the blue arrow in the editor) or back and face it.
## While a player's body is inside the climb area, PlayerMovement can switch to the "ladder" mode (see
## movement_modes/ladder_mode.gd): forward climbs up (down when looking down), jump lets go.
## Only the owning PC moves a body, so nothing here is networked: every PC has the same ladder.

const GROUP: StringName = &"ladders"
## The climb area reaches this far above the top, so you can climb high enough to step off.
const TOP_EXTRA: float = 0.8
## How far in front of and behind the ladder the climb area reaches (metres).
const REACH: float = 0.7
const RUNG_SPACING: float = 0.3
const RAIL_THICKNESS: float = 0.06

@export var height: float = 3.0:
	set(value):
		height = maxf(value, 0.5)
		_rebuild()
@export var width: float = 0.7:
	set(value):
		width = maxf(value, 0.2)
		_rebuild()
@export var color: Color = Color(0.55, 0.45, 0.3):
	set(value):
		color = value
		_rebuild()

var _built: Node3D
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	monitorable = false
	_rebuild()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## The ladder a node is part of (or null).
static func of(node: Node) -> Ladder:
	var current: Node = node
	while current != null:
		if current is Ladder:
			return current as Ladder
		current = current.get_parent()
	return null


## Height of the top rung in the world.
func get_top_y() -> float:
	return global_position.y + height * global_basis.get_scale().y


## Which way the ladder's face points, flat (the side a climber stands on is this or its opposite).
func get_facing() -> Vector3:
	var facing: Vector3 = global_basis.z
	facing.y = 0.0
	return facing.normalized()


## Sideways along the rungs, flat.
func get_across() -> Vector3:
	var across: Vector3 = global_basis.x
	across.y = 0.0
	return across.normalized()


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerCharacter
	if player != null:
		player.get_movement().add_ladder(self)


func _on_body_exited(body: Node3D) -> void:
	var player := body as PlayerCharacter
	if player != null and is_instance_valid(player):
		player.get_movement().remove_ladder(self)


## The climb area and a simple grey-box look (two rails and rungs), made in code.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _built != null:
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built)
	# The shape must be a direct child of the area to count.
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "ClimbArea"
		add_child(_shape)
	var box := BoxShape3D.new()
	box.size = Vector3(width + 0.3, height + TOP_EXTRA, REACH * 2.0)
	_shape.shape = box
	_shape.position = Vector3(0, (height + TOP_EXTRA) / 2.0, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	for side: float in [-1.0, 1.0]:
		_part(Vector3(RAIL_THICKNESS, height, RAIL_THICKNESS), Vector3(side * width / 2.0, height / 2.0, 0), material)
	var rungs: int = floori(height / RUNG_SPACING)
	for index: int in range(1, rungs + 1):
		_part(Vector3(width, RAIL_THICKNESS * 0.8, RAIL_THICKNESS * 0.8), Vector3(0, RUNG_SPACING * float(index), 0), material)


func _part(size: Vector3, where: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = where
	_built.add_child(mesh)
