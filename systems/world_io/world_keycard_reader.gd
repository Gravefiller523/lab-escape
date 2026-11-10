class_name WorldKeycardReader
extends WorldDevice
## NEW 2026-10-31 (floor generation step 4c): a card reader on the wall beside a locked door, with a light in
## its colour. Bring the matching keycard (the prop `keycard_prop_id`) to its slot (touching is enough, held or
## thrown): the host takes the card, the light turns green and it fires "accepted" (wire it to the door:
## unlock, open). Its face points along +Z. Looking at it says which card it needs.
## Outputs: accepted. Inputs: none (besides enable, disable).

@export var keycard_prop_id: StringName = &""
@export var color: Color = Color(0.85, 0.15, 0.15)
## What the prompt calls the card, e.g. "red keycard".
@export var card_name: String = "keycard"

const BODY_SIZE: Vector3 = Vector3(0.28, 0.4, 0.08)
const ACCEPTED_COLOR: Color = Color(0.2, 0.9, 0.3)

var _accepted: bool = false
var _lamp_material: StandardMaterial3D
var _interactable: Interactable


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	body.add_child(shape)
	body.add_child(_box_mesh(BODY_SIZE, Color(0.2, 0.21, 0.24)))
	var lamp := _box_mesh(Vector3(0.12, 0.06, 0.03), color)
	lamp.position = Vector3(0, 0.12, BODY_SIZE.z / 2.0)
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = color
	_lamp_material.emission_enabled = true
	_lamp_material.emission = color
	_lamp_material.emission_energy_multiplier = 2.0
	lamp.material_override = _lamp_material
	body.add_child(lamp)
	var slit := _box_mesh(Vector3(0.18, 0.02, 0.03), Color(0.02, 0.02, 0.02))
	slit.position = Vector3(0, -0.05, BODY_SIZE.z / 2.0)
	body.add_child(slit)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt_text = "Needs the %s" % card_name
	_interactable.use_condition = func(_player_id: int) -> bool: return false
	body.add_child(_interactable)
	add_child(body)
	var slot := Area3D.new()
	slot.name = "Slot"
	slot.collision_layer = 0
	slot.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.HELD_PROPS)
	var slot_shape := CollisionShape3D.new()
	var slot_box := BoxShape3D.new()
	slot_box.size = Vector3(0.6, 0.7, 0.6)
	slot_shape.shape = slot_box
	slot_shape.position.z = 0.3
	slot.add_child(slot_shape)
	slot.body_entered.connect(_on_slot_body_entered)
	add_child(slot)


func is_accepted() -> bool:
	return _accepted


func get_interactable() -> Interactable:
	return _interactable


func _on_slot_body_entered(body: Node3D) -> void:
	if not _is_host() or _accepted or not _enabled:
		return
	var prop := body as NetProp
	if prop == null or prop.data == null or prop.data.id != keycard_prop_id or prop.is_queued_for_deletion():
		return
	if prop.get_spawner() != null:
		prop.get_spawner().release_all(prop)
	var player_id: int = prop.last_holder_id
	Props.despawn(prop)
	_accepted = true
	push_state()
	_play(&"button_press")
	fire_output(&"accepted", player_id)


func get_state() -> Array:
	return [_accepted]


func _apply_state(state: Array) -> void:
	if state.is_empty():
		return
	_accepted = state[0]
	if _lamp_material != null:
		var shown: Color = ACCEPTED_COLOR if _accepted else color
		_lamp_material.albedo_color = shown
		_lamp_material.emission = shown
	if _interactable != null:
		_interactable.prompt_text = "Unlocked" if _accepted else "Needs the %s" % card_name
