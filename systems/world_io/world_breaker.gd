class_name WorldBreaker
extends WorldDevice
## NEW 2026-10-31 (floor generation step 4c): a breaker box with a lever, the power puzzle for a door with no
## power. Pull the lever (E) and it fires "pulled" and stays down (wire it to the door: unlock, open). With
## `needs_cell`, its power cell is missing: bring a power cell (the prop `cell_prop_id`) to its slot first
## (the host takes it, "cell_inserted"); until then the lever gives the "can't use" buzz. Face along +Z.
## Outputs: cell_inserted, pulled. Inputs: none (besides enable, disable).

@export var needs_cell: bool = false
@export var cell_prop_id: StringName = &"prop_power_cell"

const BOX_SIZE: Vector3 = Vector3(0.6, 0.8, 0.2)
const POWERED_COLOR: Color = Color(0.2, 0.9, 0.3)
const DEAD_COLOR: Color = Color(0.9, 0.2, 0.1)

var _has_cell: bool = false
var _pulled: bool = false
var _lever: Node3D
var _lamp_material: StandardMaterial3D
var _cell_mesh: MeshInstance3D
var _interactable: Interactable


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BOX_SIZE
	shape.shape = box
	body.add_child(shape)
	body.add_child(_box_mesh(BOX_SIZE, Color(0.35, 0.37, 0.4)))
	_lever = Node3D.new()
	_lever.name = "Lever"
	_lever.position = Vector3(0.12, 0.05, BOX_SIZE.z / 2.0)
	var handle := _box_mesh(Vector3(0.05, 0.3, 0.05), Color(0.85, 0.15, 0.1))
	handle.position.y = 0.15
	_lever.add_child(handle)
	body.add_child(_lever)
	var lamp := _box_mesh(Vector3(0.08, 0.08, 0.03), DEAD_COLOR)
	lamp.position = Vector3(-0.18, 0.28, BOX_SIZE.z / 2.0)
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	_lamp_material.emission_energy_multiplier = 2.0
	lamp.material_override = _lamp_material
	body.add_child(lamp)
	_cell_mesh = _box_mesh(Vector3(0.12, 0.25, 0.12), Color(0.2, 0.6, 0.95))
	_cell_mesh.position = Vector3(-0.15, -0.15, BOX_SIZE.z / 2.0 + 0.04)
	body.add_child(_cell_mesh)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.use_condition = func(_player_id: int) -> bool: return not _pulled and (_has_cell or not needs_cell)
	_interactable.used.connect(_on_used)
	body.add_child(_interactable)
	add_child(body)
	var slot := Area3D.new()
	slot.name = "Slot"
	slot.collision_layer = 0
	slot.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.HELD_PROPS)
	var slot_shape := CollisionShape3D.new()
	var slot_box := BoxShape3D.new()
	slot_box.size = Vector3(0.8, 1.0, 0.7)
	slot_shape.shape = slot_box
	slot_shape.position.z = 0.35
	slot.add_child(slot_shape)
	slot.body_entered.connect(_on_slot_body_entered)
	add_child(slot)
	_show()


func is_pulled() -> bool:
	return _pulled


func has_power() -> bool:
	return _has_cell or not needs_cell


func get_interactable() -> Interactable:
	return _interactable


## Host: someone pulled the lever.
func _on_used(player_id: int) -> void:
	if not _is_host() or _pulled or not has_power() or not _enabled:
		return
	_pulled = true
	push_state()
	_play(&"button_press")
	fire_output(&"pulled", player_id)


func _on_slot_body_entered(body: Node3D) -> void:
	if not _is_host() or not needs_cell or _has_cell:
		return
	var prop := body as NetProp
	if prop == null or prop.data == null or prop.data.id != cell_prop_id or prop.is_queued_for_deletion():
		return
	if prop.get_spawner() != null:
		prop.get_spawner().release_all(prop)
	var player_id: int = prop.last_holder_id
	Props.despawn(prop)
	_has_cell = true
	push_state()
	fire_output(&"cell_inserted", player_id)


func get_state() -> Array:
	return [_has_cell, _pulled]


func _apply_state(state: Array) -> void:
	if state.size() < 2:
		return
	_has_cell = state[0]
	_pulled = state[1]
	_show()


func _show() -> void:
	if _lever == null:
		return
	_lever.rotation.z = -1.2 if _pulled else 0.0
	var shown: Color = POWERED_COLOR if has_power() else DEAD_COLOR
	_lamp_material.albedo_color = shown
	_lamp_material.emission = shown
	_cell_mesh.visible = not needs_cell or _has_cell
	if _interactable != null:
		if _pulled:
			_interactable.prompt_text = "Power on"
		elif has_power():
			_interactable.prompt_text = "Pull lever"
		else:
			_interactable.prompt_text = "No power: needs a power cell"
