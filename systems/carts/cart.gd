class_name Cart
extends NetProp
## A pushable cart (the root of a cart scene; cart types are props: content/props/prop_cart_*.tres).
## Spec: docs/systems/carts.md.
## - Look at it and press E to push it (one pusher at a time); E again lets go. The cart rolls along in
##   front of you (the host pulls it towards a spot in front of the pusher).
## - Props dropped or thrown into the basket snap into a slot and ride along frozen. Look at one and press
##   E to take it out (physics on again). Carts can't hold carts or props with cart_allowed = false.
## The host runs the cart's physics (keep_on_host) so everything in it follows one copy; contents and
## the pusher reach every PC.

signal contents_changed()

const MSG_BUSY: String = "Someone is pushing this cart."
## Grid of slots in the basket (columns x rows x layers), made in code.
const SLOT_COLUMNS: int = 3
const SLOT_ROWS: int = 4
const SLOT_LAYERS: int = 2
const SLOT_SPACING: Vector3 = Vector3(0.3, 0.25, 0.32)
const SLOT_ORIGIN: Vector3 = Vector3(-0.3, 0.6, -0.48)
## Where the cart wants to be: this far in front of the pusher (metres).
const PUSH_DISTANCE: float = 1.3
const PUSH_STIFFNESS: float = 40.0
const PUSH_DAMPING: float = 8.0
const TURN_SPEED: float = 6.0
## The pusher lets go if the cart gets this far away (stuck).
const PUSH_BREAK_DISTANCE: float = 3.5

## Most props it holds; 0 = Config.game.cart_capacity.
@export var capacity_override: int = 0

var _contents: Dictionary[int, NetProp] = {}
## Host: net id -> the slot it rides in.
var _slot_by_id: Dictionary[int, Marker3D] = {}
var _slots: Array[Marker3D] = []
var _pusher_id: int = 0
var _basket: Area3D


func _ready() -> void:
	keep_on_host = true
	super._ready()
	collision_layer = PhysicsLayers.bit(PhysicsLayers.CARTS)
	_make_slots()
	_basket = get_node_or_null(^"Basket") as Area3D
	if _basket != null:
		_basket.collision_layer = 0
		_basket.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.HELD_PROPS)
		_basket.body_entered.connect(_on_basket_body_entered)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_cart_state_rpc.rpc_id(1)


## The cart a prop rides in, or null.
static func cart_of(prop: NetProp) -> Cart:
	if prop == null:
		return null
	for node: Node in prop.get_tree().get_nodes_in_group(&"carts"):
		var cart := node as Cart
		if cart != null and cart.has_prop(prop):
			return cart
	return null


func _enter_tree() -> void:
	add_to_group(&"carts")


func get_contents() -> Array[NetProp]:
	var list: Array[NetProp] = []
	for prop: NetProp in _contents.values():
		if is_instance_valid(prop):
			list.append(prop)
	return list


func has_prop(prop: NetProp) -> bool:
	return prop != null and _contents.has(prop.net_id)


func get_capacity() -> int:
	var wanted: int = capacity_override if capacity_override > 0 else Config.game.cart_capacity
	return mini(wanted, _slots.size())


## Would it take this prop? (allowed in carts, not full, not a cart, not held.)
func can_accept(prop: NetProp) -> bool:
	if prop == null or prop == self or prop is Cart or has_prop(prop) or prop.is_held() or prop.is_attached():
		return false
	if prop.data != null and not prop.data.cart_allowed:
		return false
	return get_contents().size() < get_capacity()


func get_pusher_id() -> int:
	return _pusher_id


## Local: start or stop pushing (the host checks nobody else is).
func request_push(start: bool) -> void:
	if multiplayer.is_server():
		_set_pusher(Net.local_player_id(), start)
	else:
		_request_push_rpc.rpc_id(1, start)


## Local: take a prop out of this cart (the host checks it; then grab it as usual).
func request_take_out(prop: NetProp) -> void:
	if prop == null:
		return
	if multiplayer.is_server():
		remove_prop(prop)
	else:
		_request_take_out_rpc.rpc_id(1, prop.net_id)


## Host: snap a prop into the next free slot. False if it doesn't fit.
func add_prop(prop: NetProp) -> bool:
	if not multiplayer.is_server() or not can_accept(prop):
		return false
	var slot: Marker3D = _free_slot()
	if slot == null:
		return false
	prop.attach_to(slot)
	add_collision_exception_with(prop)
	_contents[prop.net_id] = prop
	_slot_by_id[prop.net_id] = slot
	prop.tree_exiting.connect(_on_content_gone.bind(prop.net_id), CONNECT_ONE_SHOT)
	_send_contents()
	return true


## Host: take a prop out (physics back on).
func remove_prop(prop: NetProp) -> void:
	if not multiplayer.is_server() or not has_prop(prop):
		return
	_contents.erase(prop.net_id)
	_slot_by_id.erase(prop.net_id)
	prop.detach()
	remove_collision_exception_with(prop)
	_send_contents()


## Host: everything flies out (e.g. if the cart is hit hard).
func spill_all(impulse: float = 2.0) -> void:
	if not multiplayer.is_server():
		return
	var index: int = 0
	for prop: NetProp in get_contents():
		remove_prop(prop)
		var angle: float = TAU * float(index) / 6.0
		Props.apply_impulse(prop, (Vector3.UP + Vector3(cos(angle), 0, sin(angle)) * 0.5) * impulse * prop.mass)
		index += 1


func _free_slot() -> Marker3D:
	var used: Dictionary[Node, bool] = {}
	for slot: Marker3D in _slot_by_id.values():
		used[slot] = true
	for index: int in get_capacity():
		if not used.has(_slots[index]):
			return _slots[index]
	return null


func _make_slots() -> void:
	for layer: int in SLOT_LAYERS:
		for row: int in SLOT_ROWS:
			for column: int in SLOT_COLUMNS:
				var slot := Marker3D.new()
				slot.name = "Slot%d_%d_%d" % [layer, row, column]
				slot.position = SLOT_ORIGIN + Vector3(SLOT_SPACING.x * float(column), SLOT_SPACING.y * float(layer),
					SLOT_SPACING.z * float(row))
				add_child(slot)
				_slots.append(slot)


func _on_basket_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var prop := body as NetProp
	if prop != null and can_accept(prop):
		add_prop(prop)


func _on_content_gone(item_net_id: int) -> void:
	_contents.erase(item_net_id)
	_slot_by_id.erase(item_net_id)
	if is_inside_tree() and multiplayer.is_server():
		_send_contents.call_deferred()


func _set_pusher(player_id: int, start: bool) -> void:
	if start:
		if _pusher_id != 0 and _pusher_id != player_id:
			_tell(player_id, MSG_BUSY)
			return
		_pusher_id = player_id
	elif _pusher_id == player_id:
		_pusher_id = 0
	else:
		return
	_pusher_rpc.rpc(_pusher_id)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _pusher_id == 0 or not multiplayer.is_server():
		return
	var pusher: PlayerCharacter = PlayerCharacter.find(_pusher_id)
	var health: HealthComponent = HealthComponent.of(pusher) if pusher != null else null
	if pusher == null or (health != null and health.is_dead()):
		_set_pusher(_pusher_id, false)
		return
	var forward: Vector3 = pusher.get_aim_direction()
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	forward = forward.normalized()
	var target: Vector3 = pusher.global_position + forward * PUSH_DISTANCE
	var offset: Vector3 = target - global_position
	offset.y = 0.0
	if offset.length() > PUSH_BREAK_DISTANCE:
		_set_pusher(_pusher_id, false)
		return
	sleeping = false
	var flat_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_force((offset * PUSH_STIFFNESS - flat_velocity * PUSH_DAMPING) * mass)
	# Turn so its handle (+z side) faces the pusher.
	var wanted_yaw: float = atan2(forward.x, forward.z) + PI
	var turn: float = wrapf(wanted_yaw - rotation.y, -PI, PI)
	angular_velocity = Vector3(angular_velocity.x * 0.5, turn * TURN_SPEED, angular_velocity.z * 0.5)


func _send_contents() -> void:
	var ids: Array = []
	for item_net_id: int in _contents:
		ids.append(item_net_id)
	_contents_rpc.rpc(ids)


## Host -> everyone: what's in the cart (other PCs see the props through their snapshots).
@rpc("authority", "call_local", "reliable")
func _contents_rpc(ids: Array) -> void:
	if not is_inside_tree():
		return
	if not multiplayer.is_server():
		_contents.clear()
		for entry: Variant in ids:
			var item_net_id: int = entry
			var prop: NetProp = Props.get_prop(item_net_id)
			if prop != null:
				_contents[item_net_id] = prop
	contents_changed.emit()
	EventBus.cart_contents_changed.emit(self)


@rpc("authority", "call_local", "reliable")
func _pusher_rpc(player_id: int) -> void:
	if is_inside_tree():
		_pusher_id = player_id


@rpc("any_peer", "call_remote", "reliable")
func _request_push_rpc(start: bool) -> void:
	if is_inside_tree() and multiplayer.is_server():
		_set_pusher(Net.get_player_id_for_peer(multiplayer.get_remote_sender_id()), start)


@rpc("any_peer", "call_remote", "reliable")
func _request_cart_state_rpc() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var ids: Array = []
	for item_net_id: int in _contents:
		ids.append(item_net_id)
	_contents_rpc.rpc_id(multiplayer.get_remote_sender_id(), ids)
	_pusher_rpc.rpc_id(multiplayer.get_remote_sender_id(), _pusher_id)


## Host: a toast for one player.
func _tell(player_id: int, text: String) -> void:
	var peer: int = Net.get_peer_id(player_id)
	if peer == 0 or peer == multiplayer.get_unique_id():
		EventBus.toast_requested.emit(text)
	else:
		_tell_rpc.rpc_id(peer, text)


@rpc("authority", "call_remote", "reliable")
func _tell_rpc(text: String) -> void:
	if is_inside_tree():
		EventBus.toast_requested.emit(text)


@rpc("any_peer", "call_remote", "reliable")
func _request_take_out_rpc(item_net_id: int) -> void:
	if is_inside_tree() and multiplayer.is_server():
		remove_prop(Props.get_prop(item_net_id))
