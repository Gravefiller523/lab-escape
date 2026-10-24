class_name Printer3D
extends Node3D
## A 3D printer that reprints dead players (systems/death_respawn/printer_3d.tscn; the geometry is made
## in code with fixed node names). Spec: docs/systems/death_respawn.md.
## Drop meat (props tagged `meat`) into the hopper on top; when there is enough (Death.get_reprint_cost())
## press the print button: the player who has been dead longest comes out of the front. Extra meat stays
## in for the next reprint. The host decides; the meat count reaches every PC (and joiners).

signal meat_changed(inserted: int, needed: int)

const GROUP: StringName = &"printers"
const MEAT_TAG: String = "meat"
const BODY_SIZE: Vector3 = Vector3(1.4, 1.6, 1.2)
## Where reprinted players appear, in front of the printer.
const OUTPUT_OFFSET: Vector3 = Vector3(0.0, 0.1, 1.4)
const MSG_NEED_MEAT: String = "The printer needs %d meat (it has %d)."
const MSG_NOBODY_DEAD: String = "Nobody needs reprinting."
const MSG_TOO_SOON: String = "Not yet: %s can be reprinted in a moment."

var _meat: int = 0
var _screen: Label3D
var _hopper: Area3D


func _ready() -> void:
	add_to_group(GROUP)
	_build()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


func get_meat_inserted() -> int:
	return _meat


## Enough meat and someone dead who has waited long enough (host).
func can_print() -> bool:
	return _meat >= Death.get_reprint_cost() and Death.next_to_reprint() != 0


## Local: the print button (the host checks it).
func request_print() -> void:
	if multiplayer.is_server():
		print_now(Net.local_player_id())
	else:
		_request_print_rpc.rpc_id(1)


## Where a reprinted player comes out.
func get_output_transform() -> Transform3D:
	return Transform3D(global_basis, global_transform * OUTPUT_OFFSET)


## Host: add meat (tests and the hopper).
func add_meat(count: int) -> void:
	if not multiplayer.is_server() or count <= 0:
		return
	_meat += count
	_send_state()


## Host: reprint the player dead longest. True if someone came out. `asked_by` hears why not.
func print_now(asked_by: int) -> bool:
	if not multiplayer.is_server():
		return false
	var next: int = Death.next_to_reprint()
	if next == 0:
		var waiting: int = Death.longest_dead()
		Death.tell(asked_by, MSG_TOO_SOON % Net.get_display_name(waiting) if waiting != 0 else MSG_NOBODY_DEAD)
		return false
	var cost: int = Death.get_reprint_cost()
	if _meat < cost:
		Death.tell(asked_by, MSG_NEED_MEAT % [cost, _meat])
		return false
	_meat -= cost
	Death.reprint(next, get_output_transform())
	_send_state()
	return true


## Host: also check what is already in the hopper. Meat carried into it and then let go never "enters" again.
func _physics_process(_delta: float) -> void:
	if _hopper == null or not multiplayer.is_server():
		return
	for body: Node3D in _hopper.get_overlapping_bodies():
		_on_hopper_body_entered(body)


func _on_hopper_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var prop := body as NetProp
	if prop == null or prop.data == null or not prop.data.tags.has(MEAT_TAG) or prop.is_held() or prop.is_queued_for_deletion():
		return
	Props.despawn(prop)
	add_meat(1)


func _process(_delta: float) -> void:
	if _screen == null:
		return
	var dead: Array[int] = Death.get_dead_players()
	var next_name: String = Net.get_display_name(dead[0]) if not dead.is_empty() else ""
	_screen.text = "3D PRINTER\nMeat %d / %d\n%s" % [_meat, Death.get_reprint_cost(),
		"Next: %s" % next_name if not next_name.is_empty() else "Nobody to reprint"]


func _send_state() -> void:
	_state_rpc.rpc(_meat)


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	shape.position.y = BODY_SIZE.y / 2.0
	body.add_child(shape)
	body.add_child(_mesh(BODY_SIZE, Vector3(0, BODY_SIZE.y / 2.0, 0), Color(0.85, 0.85, 0.82)))
	add_child(body)
	# The hopper: a red tray on top. Meat dropped onto it goes in.
	_hopper = Area3D.new()
	_hopper.name = "Hopper"
	_hopper.collision_layer = 0
	_hopper.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.HELD_PROPS)
	var hopper_shape := CollisionShape3D.new()
	var hopper_box := BoxShape3D.new()
	hopper_box.size = Vector3(1.0, 0.5, 0.8)
	hopper_shape.shape = hopper_box
	hopper_shape.position = Vector3(0, BODY_SIZE.y + 0.25, 0)
	_hopper.add_child(hopper_shape)
	_hopper.add_child(_mesh(Vector3(0.9, 0.05, 0.7), Vector3(0, BODY_SIZE.y + 0.03, 0), Color(0.7, 0.2, 0.2)))
	_hopper.body_entered.connect(_on_hopper_body_entered)
	add_child(_hopper)
	_screen = Label3D.new()
	_screen.name = "Screen"
	_screen.font_size = 30
	_screen.pixel_size = 0.004
	_screen.position = Vector3(0, 1.2, BODY_SIZE.z / 2.0 + 0.01)
	add_child(_screen)
	# The output pad in front, and the print button.
	add_child(_mesh(Vector3(1.0, 0.04, 1.0), OUTPUT_OFFSET - Vector3(0, 0.08, 0), Color(0.2, 0.6, 0.9)))
	var button := StaticBody3D.new()
	button.name = "PrintButton"
	button.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	var button_shape := CollisionShape3D.new()
	var button_box := BoxShape3D.new()
	button_box.size = Vector3(0.3, 0.3, 0.15)
	button_shape.shape = button_box
	button.add_child(button_shape)
	button.add_child(_mesh(Vector3(0.24, 0.24, 0.08), Vector3.ZERO, Color(0.2, 0.85, 0.3)))
	button.position = Vector3(0.45, 0.6, BODY_SIZE.z / 2.0 + 0.05)
	var use := Interactable.new()
	use.name = "Interactable"
	use.prompt_text = "Print (reprint a dead teammate)"
	use.used.connect(func(player_id: int) -> void: print_now(player_id))
	button.add_child(use)
	add_child(button)


func _mesh(size: Vector3, where: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = where
	return mesh


@rpc("authority", "call_local", "reliable")
func _state_rpc(meat: int) -> void:
	if not is_inside_tree():
		return
	_meat = meat
	meat_changed.emit(_meat, Death.get_reprint_cost())


@rpc("any_peer", "call_remote", "reliable")
func _request_print_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		print_now(Net.get_player_id_for_peer(multiplayer.get_remote_sender_id()))


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), _meat)
