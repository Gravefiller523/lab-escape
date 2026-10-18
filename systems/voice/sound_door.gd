class_name SoundDoor
extends Area3D
## How doors tell the voice system whether sound can get through. Put one on every door (the
## doors/keycards system will, later) with a BoxShape3D child covering the doorway, and keep
## `is_open` up to date. Voice checks the doors a voice travels through:
## - open: nothing extra (just the normal "around a corner" muffle);
## - closed: the voice is muffled (quieter and duller), but still heard. Not a solid wall.
## The door's own solid body (if any) should be on the sound-blocker layer too.

const GROUP: StringName = &"sound_doors"

signal open_changed(is_open: bool)

@export var is_open: bool = true:
	set(value):
		if is_open != value:
			is_open = value
			open_changed.emit(value)


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = PhysicsLayers.bit(PhysicsLayers.TRIGGERS)
	collision_mask = 0
	monitoring = false
	monitorable = false


## True if the straight line from `from` to `to` passes through this doorway.
func blocks_segment(from: Vector3, to: Vector3) -> bool:
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var box := shape_node.shape as BoxShape3D
		if box == null:
			continue
		var into_shape: Transform3D = shape_node.global_transform.affine_inverse()
		var bounds := AABB(-box.size * 0.5, box.size)
		if bounds.intersects_segment(into_shape * from, into_shape * to):
			return true
	return false
