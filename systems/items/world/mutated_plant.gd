class_name MutatedPlant
extends StaticBody3D
## A mutated plant in a pot (systems/items/world/mutated_plant.tscn). Pour an energy drink on it (an item
## with the "water" use-on-object tag) and it shoots up into a tall vine with steps you can walk up.
## Its UseTarget child decides on the host and tells every PC; this script only shows it.
## STUB (player movement): the "ladder" is a spiral of steps until the player can climb ladders.

const STEP_COUNT: int = 10
const STEP_RISE: float = 0.35
const STEP_SIZE: Vector3 = Vector3(0.9, 0.12, 0.6)
const SPIRAL_RADIUS: float = 0.75
const STEP_TURN_DEGREES: float = 40.0
const GROW_SECONDS: float = 1.2
const VINE_COLOR: Color = Color(0.25, 0.75, 0.2)

var _vine: Node3D


func _ready() -> void:
	var target := get_node_or_null(NodePath(UseTarget.NODE_NAME)) as UseTarget
	if target != null:
		target.used_changed.connect(_on_used_changed)
		if target.is_used():
			_grow(false)


## True once it has grown.
func is_grown() -> bool:
	return _vine != null


func _on_used_changed(used: bool) -> void:
	if used:
		_grow(true)
	elif _vine != null:
		_vine.queue_free()
		_vine = null


func _grow(animate: bool) -> void:
	if _vine != null:
		return
	_vine = Node3D.new()
	_vine.name = "Vine"
	add_child(_vine)
	var material := StandardMaterial3D.new()
	material.albedo_color = VINE_COLOR
	var stalk := MeshInstance3D.new()
	var stalk_mesh := CylinderMesh.new()
	var height: float = STEP_RISE * float(STEP_COUNT + 1)
	stalk_mesh.top_radius = 0.12
	stalk_mesh.bottom_radius = 0.2
	stalk_mesh.height = height
	stalk_mesh.material = material
	stalk.mesh = stalk_mesh
	stalk.position.y = height / 2.0
	_vine.add_child(stalk)
	for index: int in STEP_COUNT:
		var step := StaticBody3D.new()
		step.name = "Step%d" % index
		step.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
		var angle: float = deg_to_rad(STEP_TURN_DEGREES * float(index))
		step.position = Vector3(cos(angle) * SPIRAL_RADIUS, STEP_RISE * float(index + 1), sin(angle) * SPIRAL_RADIUS)
		step.rotation.y = -angle
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = STEP_SIZE
		shape.shape = box
		step.add_child(shape)
		var mesh := MeshInstance3D.new()
		var leaf := BoxMesh.new()
		leaf.size = STEP_SIZE
		leaf.material = material
		mesh.mesh = leaf
		step.add_child(mesh)
		_vine.add_child(step)
	if animate:
		_vine.scale = Vector3(1.0, 0.05, 1.0)
		_vine.create_tween().tween_property(_vine, "scale", Vector3.ONE, GROW_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
