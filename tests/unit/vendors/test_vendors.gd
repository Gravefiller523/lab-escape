extends GutTest
## Tests for vendors (docs/systems/vendors.md). Solo: this PC is the host, with a floor, a PropSpawner
## and a vending machine at the origin (front facing +z). Test stock is registered in code.

const VENDING_SCENE: PackedScene = preload("res://systems/vendors/vending_machine.tscn")
const PORT: int = 18180
const WAIT: float = 5.0

var _world: Node3D
var _pcs: Array[Node] = []


func before_all() -> void:
	_stock(&"stock_test_two", [[&"item_crowbar", 3, 1], [&"item_energy_drink", 2, 0]], 2)
	_stock(&"stock_test_mixed", [[&"prop_gem", 1, 1], [&"item_knife", 4, 1]], 2)


func _stock(id: StringName, entries: Array, shown: int) -> void:
	if ContentRegistry.has_content(id):
		return
	var stock := VendorStockData.new()
	stock.id = id
	stock.slots_shown = shown
	var list: Array[VendorEntryData] = []
	for values: Array in entries:
		var entry := VendorEntryData.new()
		entry.item_id = values[0]
		entry.price = values[1]
		entry.stock_count = values[2]
		list.append(entry)
	stock.entries = list
	ContentRegistry.register_content(stock)


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_floor(_world)
	var props := PropSpawner.new()
	props.name = "Props"
	_world.add_child(props)


func after_each() -> void:
	var paths: Array[NodePath] = []
	var peers: Array[MultiplayerPeer] = []
	for pc: Node in _pcs:
		paths.append(pc.get_path())
		peers.append(pc.multiplayer.multiplayer_peer)
		pc.free()
	for index: int in paths.size():
		if peers[index] != null:
			peers[index].close()
		get_tree().set_multiplayer(null, paths[index])
	_pcs.clear()


func _add_floor(parent: Node) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	parent.add_child(floor_body)


func _vendor(stock_id: StringName = &"stock_test_two", run_seed: int = 1, parent: Node = null) -> Vendor:
	var vendor := VENDING_SCENE.instantiate() as Vendor
	vendor.name = "Vendor"
	vendor.stock_id = stock_id
	vendor.use_seed(run_seed)
	(parent if parent != null else _world).add_child(vendor)
	return vendor


func _offer_index(vendor: Vendor, item_id: StringName) -> int:
	var offers: Array[VendorOffer] = vendor.get_offers()
	for index: int in offers.size():
		if offers[index].item_id == item_id:
			return index
	return -1


func _gem_value_lying_around() -> int:
	var total: int = 0
	for prop: NetProp in Props.get_props():
		if prop.data != null:
			total += prop.data.gem_value
	return total


func test_gem_credits_last_holder() -> void:
	var vendor := _vendor()
	var gem: NetProp = Props.spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, Vector3(0.3, 2.0, 0.55)))
	gem.last_holder_id = 7
	await wait_until(func() -> bool: return vendor.get_credit(7) == 1, WAIT)
	assert_eq(vendor.get_credit(7), 1, "the gem fell into the slot: player 7 has 1")
	assert_eq(Props.get_props(&"prop_gem").size(), 0, "the gem is inside now")


## Playtest 2026-10-24: a gem carried into the slot and let go there never went in.
func test_gem_let_go_inside_the_slot_goes_in() -> void:
	var vendor := _vendor()
	await wait_physics_frames(2)
	var slot_shape := vendor.get_node("CoinSlot").get_child(0) as CollisionShape3D
	var gem: NetProp = Props.spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, slot_shape.global_position))
	gem.freeze = true
	gem.apply_holders([7], 7)
	await wait_physics_frames(10)
	assert_eq(vendor.get_credit(7), 0, "still in the player's hands: not taken")
	gem.apply_holders([], 0)
	gem.freeze = true
	await wait_until(func() -> bool: return vendor.get_credit(7) == 1, WAIT)
	assert_eq(vendor.get_credit(7), 1, "let go inside the slot: it goes in")


func test_buy_with_exact_credit() -> void:
	var vendor := _vendor()
	vendor.add_credit(7, 3)
	watch_signals(EventBus)
	assert_true(vendor.buy(7, _offer_index(vendor, &"item_crowbar")))
	assert_eq(Props.get_props(&"item_crowbar").size(), 1, "the crowbar is in the tray")
	assert_eq(vendor.get_credit(7), 0)
	assert_signal_emitted_with_parameters(EventBus, "vendor_purchase", [7, &"item_crowbar", 3])


func test_change_pops_out_as_gems() -> void:
	var vendor := _vendor()
	vendor.add_credit(7, 9)
	assert_true(vendor.buy(7, _offer_index(vendor, &"item_crowbar")))
	assert_eq(vendor.get_credit(7), 0, "vendors keep no credit")
	assert_eq(_gem_value_lying_around(), 6, "9 - 3 = 6 back out as gems")
	assert_eq(Props.get_props(&"prop_gem_large").size(), 1, "a 5 and a 1")


func test_not_enough_credit_refused() -> void:
	var vendor := _vendor()
	vendor.add_credit(7, 2)
	assert_false(vendor.buy(7, _offer_index(vendor, &"item_crowbar")))
	assert_eq(vendor.get_credit(7), 2, "nothing taken")
	assert_eq(Props.get_props(&"item_crowbar").size(), 0)


func test_refund_returns_all() -> void:
	var vendor := _vendor()
	vendor.add_credit(7, 4)
	vendor.add_credit(8, 3)
	vendor.add_credit(Vendor.NOBODY, 1)
	vendor.refund_all()
	assert_eq(vendor.get_credit(7) + vendor.get_credit(8) + vendor.get_credit(Vendor.NOBODY), 0)
	assert_eq(_gem_value_lying_around(), 8, "every gem came back out")


func test_two_players_credit_separately() -> void:
	var vendor := _vendor()
	vendor.add_credit(7, 3)
	vendor.add_credit(8, 1)
	assert_false(vendor.buy(8, _offer_index(vendor, &"item_crowbar")), "8 can't spend 7's gems")
	assert_true(vendor.buy(7, _offer_index(vendor, &"item_crowbar")))
	assert_eq(vendor.get_credit(8), 1, "8 still has theirs")


func test_stock_runs_out() -> void:
	var vendor := _vendor()
	var index: int = _offer_index(vendor, &"item_crowbar")
	vendor.add_credit(7, 6)
	assert_true(vendor.buy(7, index))
	vendor.add_credit(7, 3)
	assert_false(vendor.buy(7, index), "only one crowbar")
	assert_eq(vendor.get_offers()[index].remaining, 0)
	var drink: int = _offer_index(vendor, &"item_energy_drink")
	vendor.add_credit(7, 6)
	assert_true(vendor.buy(7, drink))
	assert_eq(vendor.get_offers()[drink].remaining, -1, "stock_count 0 = unlimited")


func test_offers_same_for_same_seed() -> void:
	var first := _vendor(&"stock_zoology_vending", 42)
	var a: Array[StringName] = []
	for offer: VendorOffer in first.get_offers():
		a.append(offer.item_id)
	first.free()
	var second := _vendor(&"stock_zoology_vending", 42)
	var b: Array[StringName] = []
	for offer: VendorOffer in second.get_offers():
		b.append(offer.item_id)
	assert_eq(a, b)
	assert_eq(a.size(), 3, "Zoology vending shows 3")


func test_only_items_can_be_offered() -> void:
	var vendor := _vendor(&"stock_test_mixed")
	assert_eq(vendor.get_offers().size(), 1, "the gem (a prop) isn't for sale")
	assert_eq(vendor.get_offers()[0].item_id, &"item_knife")


func test_credit_and_offers_reach_the_client() -> void:
	var host := _make_pc(true)
	var client := _make_pc(false)
	await wait_until(func() -> bool: return client.multiplayer.get_unique_id() > 1 \
		and host.multiplayer.get_peers().size() == 1, WAIT)
	var on_host := _vendor(&"stock_test_two", 1, host)
	var on_client := _vendor(&"stock_test_two", 1, client)
	await wait_until(func() -> bool: return on_client.get_offers().size() == 2, WAIT)
	on_host.add_credit(55, 4)
	await wait_until(func() -> bool: return on_client.get_credit(55) == 4, WAIT)
	assert_eq(on_client.get_credit(55), 4, "the client's screen shows the same credit")
	assert_eq(on_client.get_offers()[0].item_id, on_host.get_offers()[0].item_id, "and the same offers")


func _make_pc(hosting: bool) -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var peer := ENetMultiplayerPeer.new()
	if hosting:
		assert_eq(peer.create_server(PORT, 32), OK)
	else:
		peer.create_client("127.0.0.1", PORT)
	pc.multiplayer.multiplayer_peer = peer
	_pcs.append(pc)
	return pc
