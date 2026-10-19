extends GutTest
## Tests for inventory (docs/systems/inventory.md). Solo tests use a real player body (this PC is the
## host and owns it); the network test uses two "PCs" over real ENet, each with a PlayerSpawner.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const PORT: int = 18140
const WAIT: float = 5.0

var _pcs: Array[Node] = []


func before_all() -> void:
	_item(&"item_test_crowbar", 1, -1)
	_item(&"item_test_drink", 1, 1)
	_item(&"item_test_bolt", 3, 2)


func _item(id: StringName, max_stack: int, uses: int) -> void:
	if ContentRegistry.has_content(id):
		return
	var data := ItemData.new()
	data.id = id
	data.display_name = String(id)
	data.max_stack = max_stack
	data.uses = uses
	ContentRegistry.register_content(data)


func _body(player_id: int = 7) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = player_id
	body.name = str(player_id)
	add_child_autofree(body)
	return body


func _inventory(player_id: int = 7) -> InventoryComponent:
	return InventoryComponent.of(_body(player_id))


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


func test_starts_with_base_slots() -> void:
	var inventory := _inventory()
	assert_not_null(inventory, "the Inventory autoload gave the body an inventory")
	assert_eq(inventory.get_slot_count(), Config.game.base_inventory_slots)
	assert_eq(Config.game.base_inventory_slots, 2, "Zachary: 2 slots")
	assert_null(inventory.get_slot(0))


func test_active_item_is_fists_when_empty() -> void:
	var inventory := _inventory()
	assert_true(inventory.is_using_fists())
	assert_eq(inventory.get_active_item_id(), Config.game.unarmed_item_id)
	inventory.add_item(&"item_test_crowbar")
	assert_eq(inventory.get_active_item_id(), &"item_test_crowbar")
	inventory.request_select(1)
	assert_eq(inventory.get_active_item_id(), Config.game.unarmed_item_id, "an empty slot = fists")


func test_add_until_full() -> void:
	var inventory := _inventory()
	assert_true(inventory.add_item(&"item_test_crowbar"))
	assert_true(inventory.add_item(&"item_test_drink"))
	assert_false(inventory.has_free_slot())
	assert_false(inventory.add_item(&"item_test_drink"), "drinks don't stack: no room")
	assert_eq(inventory.find_item(&"item_test_drink"), 1)


func test_items_stack_up_to_max_stack() -> void:
	var inventory := _inventory()
	for count: int in 3:
		assert_true(inventory.add_item(&"item_test_bolt", 2))
	assert_eq(inventory.get_slot(0).count, 3, "three on one stack")
	assert_true(inventory.add_item(&"item_test_bolt", 2))
	assert_eq(inventory.get_slot(1).count, 1, "the fourth starts a new stack")


func test_full_inventory_swaps_with_the_selected_item() -> void:
	var inventory := _inventory()
	inventory.add_item(&"item_test_crowbar")
	inventory.add_item(&"item_test_drink")
	inventory.request_select(1)
	watch_signals(inventory)
	assert_true(inventory.pick_up(&"item_test_bolt", 2))
	assert_eq(inventory.get_slot(1).item_id, &"item_test_bolt", "the new item took the selected slot")
	assert_eq(inventory.get_slot(0).item_id, &"item_test_crowbar", "the other slot is untouched")
	assert_signal_emitted(inventory, "item_dropped", "the drink was dropped")
	var dropped: InventorySlot = get_signal_parameters(inventory, "item_dropped")[0]
	assert_eq(dropped.item_id, &"item_test_drink")


func test_pick_up_with_room_just_adds() -> void:
	var inventory := _inventory()
	watch_signals(inventory)
	assert_true(inventory.pick_up(&"item_test_crowbar"))
	assert_signal_not_emitted(inventory, "item_dropped")


func test_holster_puts_fists_out_and_back() -> void:
	var inventory := _inventory()
	inventory.add_item(&"item_test_crowbar")
	inventory.request_holster_toggle()
	assert_true(inventory.is_holstered())
	assert_eq(inventory.get_active_item_id(), Config.game.unarmed_item_id, "fists out")
	inventory.request_holster_toggle()
	assert_eq(inventory.get_active_item_id(), &"item_test_crowbar", "Alt again: crowbar back out")
	inventory.request_holster_toggle()
	inventory.request_select(0)
	assert_false(inventory.is_holstered(), "picking a slot takes it out of the holster")


func test_drop_removes_one_and_tells_listeners() -> void:
	var inventory := _inventory()
	inventory.add_item(&"item_test_bolt", 2)
	inventory.add_item(&"item_test_bolt", 2)
	watch_signals(inventory)
	inventory.request_drop()
	assert_signal_emitted(inventory, "item_dropped")
	assert_eq(inventory.get_slot(0).count, 1, "one dropped off the stack")
	inventory.request_drop()
	assert_null(inventory.get_slot(0))
	inventory.request_drop()
	assert_signal_emit_count(inventory, "item_dropped", 2, "nothing left to drop")


func test_bonus_slots_add_and_remove() -> void:
	var inventory := _inventory()
	inventory.set_bonus_slots(&"mutation_octo", 2)
	assert_eq(inventory.get_slot_count(), 4)
	inventory.set_bonus_slots(&"cybernetic_arm", 1)
	assert_eq(inventory.get_slot_count(), 5)
	for count: int in 5:
		inventory.add_item(&"item_test_crowbar")
	watch_signals(inventory)
	inventory.clear_bonus_slots(&"mutation_octo")
	assert_eq(inventory.get_slot_count(), 3)
	assert_signal_emit_count(inventory, "item_dropped", 2, "items in the removed slots are dropped")


func test_spend_use_removes_at_zero() -> void:
	var inventory := _inventory()
	inventory.add_item(&"item_test_drink", 1)
	inventory.spend_use(0)
	assert_null(inventory.get_slot(0), "the drink is gone")
	inventory.add_item(&"item_test_bolt", 2)
	inventory.add_item(&"item_test_bolt", 2)
	inventory.spend_use(0)
	assert_eq(inventory.get_slot(0).uses_left, 1)
	inventory.spend_use(0)
	assert_eq(inventory.get_slot(0).count, 1, "one bolt used up, the next one has fresh uses")
	assert_eq(inventory.get_slot(0).uses_left, 2)
	inventory.add_item(&"item_test_crowbar")
	inventory.spend_use(1)
	assert_eq(inventory.get_slot(1).item_id, &"item_test_crowbar", "unlimited uses never run out")


func test_take_all_empties() -> void:
	var inventory := _inventory()
	inventory.add_item(&"item_test_crowbar")
	inventory.add_item(&"item_test_drink")
	var taken: Array[InventorySlot] = inventory.take_all()
	assert_eq(taken.size(), 2)
	assert_null(inventory.get_slot(0))
	assert_null(inventory.get_slot(1))


func test_select_out_of_range_ignored() -> void:
	var inventory := _inventory()
	inventory.request_select(1)
	inventory.request_select(5)
	inventory.request_select(-1)
	assert_eq(inventory.get_active_index(), 1)


func test_inventory_changed_event() -> void:
	var inventory := _inventory(31)
	watch_signals(EventBus)
	inventory.add_item(&"item_test_crowbar")
	assert_signal_emitted_with_parameters(EventBus, "inventory_changed", [31])


# --- Two PCs ------------------------------------------------------------------------------------

func _make_pc(hosting: bool) -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var config := GameConfig.new()
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	var players := Node3D.new()
	players.name = "Players"
	pc.add_child(players)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.use_net(net)
	players.add_child(spawner)
	var peer := ENetMultiplayerPeer.new()
	if hosting:
		assert_eq(peer.create_server(PORT, 32), OK)
	else:
		peer.create_client("127.0.0.1", PORT)
	pc.multiplayer.multiplayer_peer = peer
	_pcs.append(pc)
	return pc


func _client_inventory(pc: Node, client_id: int) -> InventoryComponent:
	var body := pc.get_node_or_null("Players/%d" % client_id) as PlayerCharacter
	return InventoryComponent.of(body) if body != null else null


func test_contents_match_on_host_and_client() -> void:
	var host := _make_pc(true)
	var client := _make_pc(false)
	var client_net := client.get_node("Net") as NetService
	await wait_until(func() -> bool: return client_net.local_player_id() != 0 \
		and _client_inventory(host, client_net.local_player_id()) != null \
		and _client_inventory(client, client_net.local_player_id()) != null, WAIT)
	var client_id: int = client_net.local_player_id()
	var on_host: InventoryComponent = _client_inventory(host, client_id)
	var on_client: InventoryComponent = _client_inventory(client, client_id)
	assert_true(on_host.add_item(&"item_test_crowbar"))
	await wait_until(func() -> bool: return on_client.get_slot(0) != null, WAIT)
	assert_eq(on_client.get_slot(0).item_id, &"item_test_crowbar", "the client sees what the host put in")
	on_client.request_select(1)
	assert_eq(on_client.get_active_index(), 1, "the owner's selection is instant")
	await wait_until(func() -> bool: return on_host.get_active_index() == 1, WAIT)
	assert_eq(on_host.get_active_index(), 1, "and the host agrees")
	on_client.add_item(&"item_test_drink")
	await wait_process_frames(5)
	assert_eq(on_host.find_item(&"item_test_drink"), -1, "a client can't add items itself")
