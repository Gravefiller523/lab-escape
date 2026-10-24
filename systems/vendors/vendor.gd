class_name Vendor
extends Node3D
## A vending machine (systems/vendors/vending_machine.tscn; the geometry is made in code with fixed node
## names). Spec: docs/systems/vendors.md.
## - Drop or throw physical gems into the coin slot: each gem's value is credited to the player who last
##   held it (gems nobody held credit nobody, and only come back out on a refund).
## - Each offer has a button: pressing it buys the item if your credit covers the price. The item pops out
##   of the tray, and the rest of your credit pops back out as gems (vendors keep no credit).
## - The refund lever (hold E) gives everyone's credit back as gems.
## The host decides everything; offers and credits reach every PC (and joiners).

signal credit_changed(player_id: int, credit: int)
signal offers_changed()

const GROUP: StringName = &"vendors"
const BODY_SIZE: Vector3 = Vector3(1.2, 2.0, 0.8)
const SLOT_SIZE: Vector3 = Vector3(0.22, 0.2, 0.3)
const TRAY_OFFSET: Vector3 = Vector3(0.0, 0.5, 0.75)
const BUTTON_SIZE: Vector3 = Vector3(0.18, 0.18, 0.08)
const REFUND_HOLD_SECONDS: float = 1.0
## Credit that belongs to nobody (gems rolled in that nobody held).
const NOBODY: int = 0
const EJECT_IMPULSE: float = 1.2
const MSG_POOR: String = "Not enough gems: %s costs %d, you have %d."
const MSG_SOLD_OUT: String = "Sold out."

## Empty = the current department's stock_id (STUB: the first stock there is).
@export var stock_id: StringName = &""
## Which vendor this is on the floor (its offers are rolled with SeededRng(run_seed, &"vendor", index)).
@export var vendor_index: int = 0
@export var screen_title: String = "VENDING"

var _offers: Array[VendorOffer] = []
var _credits: Dictionary[int, int] = {}
var _screen: Label3D
var _buttons: Array[Interactable] = []
var _button_labels: Array[Label3D] = []
var _slot: Area3D
var _rolled: bool = false
var _run_seed_override: int = -1


func _ready() -> void:
	add_to_group(GROUP)
	_build()
	if multiplayer.is_server():
		roll_offers()
	elif multiplayer.has_multiplayer_peer():
		_request_state_rpc.rpc_id(1)


## For tests: roll offers with this seed instead of the run's.
func use_seed(run_seed: int) -> void:
	_run_seed_override = run_seed


func get_offers() -> Array[VendorOffer]:
	return _offers.duplicate()


func get_credit(player_id: int) -> int:
	return _credits.get(player_id, 0)


## The stock this vendor sells from.
func get_stock() -> VendorStockData:
	var id: StringName = stock_id
	if id == &"":
		var department: DepartmentData = GameFlow.get_current_department()
		id = department.stock_id if department != null else &""
	var stock := ContentRegistry.get_content(id) as VendorStockData
	if stock == null:
		var all: Array[ContentData] = ContentRegistry.get_all(&"stock")
		stock = all[0] as VendorStockData if not all.is_empty() else null
	return stock


## Local: the buy button for an offer (the host checks it).
func request_buy(offer_index: int) -> void:
	if multiplayer.is_server():
		buy(Net.local_player_id(), offer_index)
	else:
		_request_buy_rpc.rpc_id(1, offer_index)


## Local: the refund lever.
func request_refund() -> void:
	if multiplayer.is_server():
		refund_all()
	else:
		_request_refund_rpc.rpc_id(1)


## Host: pick slots_shown offers from the stock (weighted, no repeats, items only).
func roll_offers() -> void:
	if not multiplayer.is_server():
		return
	_offers.clear()
	var stock: VendorStockData = get_stock()
	if stock != null:
		var rng: RandomNumberGenerator = SeededRng.make(_seed(), &"vendor", vendor_index)
		var pool: Array[VendorEntryData] = []
		for entry: VendorEntryData in stock.entries:
			var item := ContentRegistry.get_content(entry.item_id) as ItemData
			if item != null and item.enabled:
				pool.append(entry)
		for slot: int in stock.slots_shown:
			var weights: PackedFloat32Array = []
			for entry: VendorEntryData in pool:
				weights.append(entry.weight)
			var picked: int = SeededRng.pick_weighted(rng, weights)
			if picked < 0:
				break
			var chosen: VendorEntryData = pool[picked]
			pool.remove_at(picked)
			_offers.append(VendorOffer.make(chosen.item_id, chosen.price, chosen.stock_count if chosen.stock_count > 0 else -1))
	_rolled = true
	_send_state()


## Host: add gem value to a player's credit (0 = nobody).
func add_credit(player_id: int, value: int) -> void:
	if not multiplayer.is_server() or value <= 0:
		return
	_credits[player_id] = get_credit(player_id) + value
	_send_state()


## Host: a player buys an offer. True if it worked. Change pops out as gems.
func buy(player_id: int, offer_index: int) -> bool:
	if not multiplayer.is_server() or offer_index < 0 or offer_index >= _offers.size():
		return false
	var offer: VendorOffer = _offers[offer_index]
	if offer.remaining == 0:
		_tell(player_id, MSG_SOLD_OUT)
		return false
	var credit: int = get_credit(player_id)
	if player_id == NOBODY or credit < offer.price:
		var item := ContentRegistry.get_content(offer.item_id) as ItemData
		_tell(player_id, MSG_POOR % [item.display_name if item != null else String(offer.item_id), offer.price, credit])
		return false
	var data := ContentRegistry.get_content(offer.item_id) as ItemData
	Props.spawn_item(offer.item_id, _tray_transform(), data.uses if data != null else -1)
	if offer.remaining > 0:
		offer.remaining -= 1
	_credits[player_id] = credit - offer.price
	_eject(player_id)
	_purchase_rpc.rpc(player_id, offer.item_id, offer.price)
	_send_state()
	return true


## Host: everyone's credit comes back out as gems.
func refund_all() -> void:
	if not multiplayer.is_server():
		return
	for player_id: int in _credits.keys():
		_eject(player_id)
	_send_state()


## Host: also check what is already in the slot. A gem carried into it and then let go never "enters" again.
func _physics_process(_delta: float) -> void:
	if _slot == null or not multiplayer.is_server():
		return
	for body: Node3D in _slot.get_overlapping_bodies():
		_on_slot_body_entered(body)


## Host: a gem in the coin slot.
func _on_slot_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var prop := body as NetProp
	if prop == null or prop.data == null or prop.data.gem_value <= 0 or prop.is_held() or prop.is_queued_for_deletion():
		return
	var value: int = prop.data.gem_value
	var player_id: int = prop.last_holder_id
	Props.despawn(prop)
	add_credit(player_id, value)


## Host: a player's credit pops out of the tray as gems.
func _eject(player_id: int) -> void:
	var value: int = get_credit(player_id)
	_credits.erase(player_id)
	var index: int = 0
	for prop_id: StringName in LootService.gems_for_value(value):
		var xform: Transform3D = _tray_transform().translated(Vector3(0.1 * float(index % 3), 0.15 * floorf(float(index) / 3.0), 0.0))
		var gem: NetProp = Props.spawn_prop(prop_id, xform)
		if gem != null:
			Props.apply_impulse(gem, global_basis.z * EJECT_IMPULSE * gem.mass)
		index += 1


func _tray_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, global_transform * TRAY_OFFSET)


func _seed() -> int:
	if _run_seed_override >= 0:
		return _run_seed_override
	var run: RunState = GameFlow.get_run()
	return run.run_seed if run != null else 0


func _tell(player_id: int, text: String) -> void:
	var peer: int = Net.get_peer_id(player_id)
	if peer == multiplayer.get_unique_id() or peer == 0:
		EventBus.toast_requested.emit(text)
	else:
		_tell_rpc.rpc_id(peer, text)


func _send_state() -> void:
	_state_rpc.rpc(_offers_to_array(), _credits_to_dict())


func _offers_to_array() -> Array:
	var list: Array = []
	for offer: VendorOffer in _offers:
		list.append([String(offer.item_id), offer.price, offer.remaining])
	return list


func _credits_to_dict() -> Dictionary:
	var data: Dictionary = {}
	for player_id: int in _credits:
		data[player_id] = _credits[player_id]
	return data


# --- The machine -----------------------------------------------------------------------------------

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
	body.add_child(_box_mesh(BODY_SIZE, Vector3(0, BODY_SIZE.y / 2.0, 0), Color(0.2, 0.35, 0.6)))
	add_child(body)
	# Coin slot: a funnel on top-front; a gem dropped onto it falls in.
	_slot = Area3D.new()
	_slot.name = "CoinSlot"
	_slot.collision_layer = 0
	_slot.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.HELD_PROPS)
	var slot_shape := CollisionShape3D.new()
	var slot_box := BoxShape3D.new()
	slot_box.size = SLOT_SIZE + Vector3(0.1, 0.3, 0.1)
	slot_shape.shape = slot_box
	slot_shape.position = Vector3(0.42, 1.15, BODY_SIZE.z / 2.0 + 0.12)
	_slot.add_child(slot_shape)
	_slot.add_child(_box_mesh(SLOT_SIZE, slot_shape.position, Color(0.85, 0.75, 0.2)))
	_slot.body_entered.connect(_on_slot_body_entered)
	add_child(_slot)
	_add_label("SlotLabel", "GEMS IN", Vector3(0.42, 1.36, BODY_SIZE.z / 2.0 + 0.01), 20)
	_screen = _add_label("Screen", "", Vector3(0.0, 1.8, BODY_SIZE.z / 2.0 + 0.01), 26)
	# Tray marker (where items and change come out).
	add_child(_box_mesh(Vector3(0.6, 0.05, 0.3), TRAY_OFFSET - Vector3(0, 0.12, 0.1), Color(0.15, 0.15, 0.15)))
	var refund := _add_usable("Refund", Vector3(0.42, 0.75, BODY_SIZE.z / 2.0 + 0.04), Color(0.8, 0.2, 0.2), "Refund (hold)")
	refund.hold_seconds = REFUND_HOLD_SECONDS
	refund.used.connect(func(_player_id: int) -> void: refund_all())


## The buy buttons follow the offers (one per offer).
func _rebuild_buttons() -> void:
	for index: int in _offers.size():
		if index >= _buttons.size():
			var usable := _add_usable("Buy%d" % index, Vector3(-0.47, 1.45 - 0.25 * float(index), BODY_SIZE.z / 2.0 + 0.04),
				Color(0.3, 0.85, 0.4), "")
			usable.used.connect(func(player_id: int) -> void: buy(player_id, index))
			_buttons.append(usable)
			_button_labels.append(_add_label("BuyLabel%d" % index, "", Vector3(-0.05, 1.45 - 0.25 * float(index), BODY_SIZE.z / 2.0 + 0.01), 22))
		var offer: VendorOffer = _offers[index]
		var item := ContentRegistry.get_content(offer.item_id) as ItemData
		var title: String = item.display_name if item != null else String(offer.item_id)
		_buttons[index].prompt_text = "Buy %s (%d gems)" % [title, offer.price] if offer.remaining != 0 else "%s: sold out" % title
		_button_labels[index].text = "%s  %d%s" % [title, offer.price, "" if offer.remaining != 0 else "  SOLD OUT"]
	for index: int in range(_offers.size(), _buttons.size()):
		_buttons[index].enabled = false
		_button_labels[index].text = ""


func _process(_delta: float) -> void:
	if _screen == null:
		return
	_screen.text = "%s\nYour gems: %d" % [screen_title, get_credit(Net.local_player_id())]


func _add_usable(node_name: String, where: Vector3, color: Color, prompt: String) -> Interactable:
	var button := StaticBody3D.new()
	button.name = node_name
	button.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BUTTON_SIZE + Vector3(0.06, 0.06, 0.06)
	shape.shape = box
	button.add_child(shape)
	button.add_child(_box_mesh(BUTTON_SIZE, Vector3.ZERO, color))
	button.position = where
	var usable := Interactable.new()
	usable.name = "Interactable"
	usable.prompt_text = prompt
	button.add_child(usable)
	add_child(button)
	return usable


func _add_label(node_name: String, text: String, where: Vector3, size: int) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.position = where
	add_child(label)
	return label


func _box_mesh(size: Vector3, where: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = where
	return mesh


# --- Network ---------------------------------------------------------------------------------------

## Host -> everyone: what's for sale and who has how much credit.
@rpc("authority", "call_local", "reliable")
func _state_rpc(offer_list: Array, credit_data: Dictionary) -> void:
	if not is_inside_tree():
		return
	_offers.clear()
	for entry: Variant in offer_list:
		var values: Array = entry
		var item_id: String = values[0]
		var price: int = values[1]
		var remaining: int = values[2]
		_offers.append(VendorOffer.make(StringName(item_id), price, remaining))
	var old: Dictionary[int, int] = _credits.duplicate()
	_credits.clear()
	for key: Variant in credit_data:
		var player_id: int = key
		var credit: int = credit_data[key]
		_credits[player_id] = credit
	for player_id: int in old.keys() + _credits.keys():
		if old.get(player_id, 0) != _credits.get(player_id, 0):
			credit_changed.emit(player_id, _credits.get(player_id, 0))
	_rebuild_buttons()
	offers_changed.emit()


## Host -> everyone: someone bought something.
@rpc("authority", "call_local", "reliable")
func _purchase_rpc(player_id: int, item_id: StringName, price: int) -> void:
	if is_inside_tree():
		EventBus.vendor_purchase.emit(player_id, item_id, price)


@rpc("authority", "call_remote", "reliable")
func _tell_rpc(text: String) -> void:
	if is_inside_tree():
		EventBus.toast_requested.emit(text)


@rpc("any_peer", "call_remote", "reliable")
func _request_buy_rpc(offer_index: int) -> void:
	if is_inside_tree() and multiplayer.is_server():
		buy(Net.get_player_id_for_peer(multiplayer.get_remote_sender_id()), offer_index)


@rpc("any_peer", "call_remote", "reliable")
func _request_refund_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		refund_all()


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), _offers_to_array(), _credits_to_dict())
