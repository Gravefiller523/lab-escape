class_name MutatedPlant
extends StaticBody3D
## A mutated plant in a pot (systems/items/world/mutated_plant.tscn). Pour an energy drink on it (an item
## with the "water" use-on-object tag) and it shoots up into a tall vine with a ladder you can climb (player's Ladder).
## Its UseTarget child decides on the host and tells every PC; this script only shows it.

const VINE_HEIGHT: float = 3.85
## The ladder stands just in front of the pot (the pot is 0.35 m wide from the middle), facing +Z.
const LADDER_OFFSET: Vector3 = Vector3(0.0, 0.0, 0.42)
const LADDER_WIDTH: float = 0.6
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
	var height: float = VINE_HEIGHT
	stalk_mesh.top_radius = 0.12
	stalk_mesh.bottom_radius = 0.2
	stalk_mesh.height = height
	stalk_mesh.material = material
	stalk.mesh = stalk_mesh
	stalk.position.y = height / 2.0
	_vine.add_child(stalk)
	if not animate:
		_add_ladder()
		return
	_vine.scale = Vector3(1.0, 0.05, 1.0)
	var tween: Tween = _vine.create_tween()
	tween.tween_property(_vine, "scale", Vector3.ONE, GROW_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The ladder comes once it has grown (a squashed climb area would confuse the physics engine).
	tween.finished.connect(_add_ladder)


func _add_ladder() -> void:
	if _vine == null or _vine.has_node(^"Ladder"):
		return
	var ladder := Ladder.new()
	ladder.name = "Ladder"
	ladder.height = VINE_HEIGHT
	ladder.width = LADDER_WIDTH
	ladder.color = VINE_COLOR
	ladder.position = LADDER_OFFSET
	_vine.add_child(ladder)
