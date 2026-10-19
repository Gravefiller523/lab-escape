class_name InventoryComponent
extends Node
## A player's inventory slots for weapons, tools and consumables (child "Inventory" of the player body,
## added by the Inventory autoload). Spec: docs/systems/inventory.md.
##
## Zachary's rules (2026-10-19):
## - Config.game.base_inventory_slots (2) slots, plus bonus slots from upgrades. An empty slot = fists.
## - Keys 1-9 pick a slot, the mouse wheel goes to the next / previous one, Alt holsters the item (fists
##   out; Alt again takes it back out), Q drops the selected item (when you aren't holding a prop).
## - Items stack up to ItemData.max_stack (1 for drinks and weapons today).
## - Picking something up with every slot full swaps it with the selected item (that one is dropped).
##
## The host owns the contents and sends them to every PC. Selecting is predicted on the owner's PC
## (instant) and confirmed by the host.

signal changed()
## The selected slot (0 to get_slot_count() - 1). Fists show when it's empty or holstered.
signal active_slot_changed(index: int)
## Host only: an item left the inventory to lie in the world (dropped with Q, swapped out, or a slot
## that was taken away). Item pickups listen to spawn it (Props.spawn_item is also called for you).
signal item_dropped(slot: InventorySlot, at: Transform3D)

const NODE_NAME: String = "Inventory"
## Dropped items appear this far in front of the player's eyes (metres).
const DROP_DISTANCE: float = 0.8

var _slots: Array[InventorySlot] = []
var _bonus: Dictionary[StringName, int] = {}
var _selected: int = 0
var _holstered: bool = false
var _body: PlayerCharacter


static func of(node: Node) -> InventoryComponent:
	var current: Node = node
	while current != null:
		var inventory := current as InventoryComponent
		if inventory != null:
			return inventory
		inventory = current.get_node_or_null(NodePath(NODE_NAME)) as InventoryComponent
		if inventory != null:
			return inventory
		current = current.get_parent()
	return null


func _ready() -> void:
	name = NODE_NAME
	_body = get_parent() as PlayerCharacter
	_resize()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


# --- Reading (every PC) ------------------------------------------------------------------------

func get_slot_count() -> int:
	return _slots.size()


## The slot's contents, or null if empty (or out of range).
func get_slot(index: int) -> InventorySlot:
	return _slots[index] if index >= 0 and index < _slots.size() else null


## CHANGED 2026-10-19: the selected slot (0 and up), even when it's empty or holstered. Use
## is_using_fists() or get_active_item_id() to know what's in your hand.
func get_active_index() -> int:
	return _selected


## The item in your hand: the selected slot's item, or Config.game.unarmed_item_id (fists) when that
## slot is empty or holstered.
func get_active_item_id() -> StringName:
	if is_using_fists():
		return Config.game.unarmed_item_id
	return _slots[_selected].item_id


## NEW 2026-10-19: true when your fists are out (holstered, or the selected slot is empty).
func is_using_fists() -> bool:
	return _holstered or get_slot(_selected) == null


## NEW 2026-10-19: true while Alt has put the item away.
func is_holstered() -> bool:
	return _holstered


func has_free_slot() -> bool:
	return _slots.has(null)


## The first slot holding that item, or -1.
func find_item(item_id: StringName) -> int:
	for index: int in _slots.size():
		if _slots[index] != null and _slots[index].item_id == item_id:
			return index
	return -1


## NEW 2026-10-19: true if add_item would fit it without swapping (a free slot or room on a stack).
func can_add(item_id: StringName) -> bool:
	return _stack_index(item_id) >= 0 or has_free_slot()


# --- Choosing (the owner's PC; predicted, then the host confirms) ------------------------------

## Select a slot (also takes the item out of the holster). Out of range is ignored.
func request_select(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	_apply_selection(index, false)
	_send_selection(index, false)


## NEW 2026-10-19: Alt. Holster the item (fists out) or take it back out.
func request_holster_toggle() -> void:
	var holster: bool = not _holstered
	_apply_selection(_selected, holster)
	_send_selection(_selected, holster)


## NEW 2026-10-19: Q. Drop the selected item in front of you.
func request_drop() -> void:
	if get_slot(_selected) == null or _holstered:
		return
	if multiplayer.is_server():
		_drop_selected()
	else:
		_request_drop_rpc.rpc_id(1, _selected)


func _unhandled_input(event: InputEvent) -> void:
	if _body == null or not _body.is_local() or _slots.is_empty():
		return
	for number: int in range(1, mini(_slots.size(), InputActions.MAX_SLOT_KEYS) + 1):
		if event.is_action_pressed(InputActions.slot_action(number)):
			request_select(number - 1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(InputActions.SLOT_NEXT):
		request_select((_selected + 1) % _slots.size())
	elif event.is_action_pressed(InputActions.SLOT_PREV):
		request_select((_selected - 1 + _slots.size()) % _slots.size())
	elif event.is_action_pressed(InputActions.HOLSTER):
		request_holster_toggle()
	elif event.is_action_pressed(InputActions.DROP):
		# Q drops a held prop first (physics_props handles that); only an empty hand drops the item.
		var grab: GrabController = PropsService.grab_of(_body)
		if grab != null and grab.get_held() != null:
			return
		request_drop()
	else:
		return
	get_viewport().set_input_as_handled()


# --- Changing (host only) ----------------------------------------------------------------------

## Host: put an item in (on a stack with room, else the first free slot). False if it doesn't fit.
func add_item(item_id: StringName, uses_left: int = -1) -> bool:
	if not _is_host():
		return false
	var stack: int = _stack_index(item_id)
	if stack >= 0:
		_slots[stack].count += 1
		_send_state()
		return true
	var free: int = _slots.find(null)
	if free < 0:
		return false
	_slots[free] = InventorySlot.make(item_id, uses_left)
	_send_state()
	return true


## NEW 2026-10-19, host: what picking an item up does. Adds it if it fits; if every slot is full, it
## swaps with the selected item (the old one is dropped in front of the player) and takes it out of the
## holster. False only if there are no slots at all.
func pick_up(item_id: StringName, uses_left: int = -1) -> bool:
	if not _is_host():
		return false
	if add_item(item_id, uses_left):
		return true
	if _slots.is_empty():
		return false
	var old: InventorySlot = _slots[_selected]
	_slots[_selected] = InventorySlot.make(item_id, uses_left)
	_holstered = false
	if old != null:
		_drop(old)
	_send_state()
	return true


## Host: take a whole slot out. Returns what was there (null if empty).
func remove_item(index: int) -> InventorySlot:
	if not _is_host():
		return null
	var slot: InventorySlot = get_slot(index)
	if slot == null:
		return null
	_slots[index] = null
	_send_state()
	return slot


## NEW 2026-10-19 (items branch), host: take one item off a slot (throwing). Returns it, or null if empty.
func take_one(index: int) -> InventorySlot:
	var slot: InventorySlot = get_slot(index)
	if not _is_host() or slot == null:
		return null
	var one := InventorySlot.make(slot.item_id, slot.uses_left)
	slot.count -= 1
	if slot.count <= 0:
		_slots[index] = null
	_send_state()
	return one


## Host: one use of the item in a slot. At 0 uses one is used up (the slot empties when the last goes).
func spend_use(index: int) -> void:
	var slot: InventorySlot = get_slot(index)
	if not _is_host() or slot == null:
		return
	if slot.uses_left > 0:
		slot.uses_left -= 1
	if slot.uses_left == 0:
		slot.count -= 1
		if slot.count <= 0:
			_slots[index] = null
		else:
			var data := ContentRegistry.get_content(slot.item_id) as ItemData
			slot.uses_left = data.uses if data != null else -1
	_send_state()


## Host: extra slots from one source (an upgrade's SlotEffectData). Items in slots that go away are dropped.
func set_bonus_slots(source_id: StringName, count: int) -> void:
	if not _is_host():
		return
	_bonus[source_id] = maxi(count, 0)
	_resize()
	_send_state()


func clear_bonus_slots(source_id: StringName) -> void:
	if not _is_host() or not _bonus.has(source_id):
		return
	_bonus.erase(source_id)
	_resize()
	_send_state()


## Host: empties every slot (death). Returns what was there; death_respawn spawns the pickups.
func take_all() -> Array[InventorySlot]:
	var taken: Array[InventorySlot] = []
	if not _is_host():
		return taken
	for index: int in _slots.size():
		if _slots[index] != null:
			taken.append(_slots[index])
			_slots[index] = null
	_holstered = false
	_send_state()
	return taken


# --- Inside ------------------------------------------------------------------------------------

func _is_host() -> bool:
	return is_inside_tree() and multiplayer.is_server()


func _player_id() -> int:
	return _body.player_id if _body != null else 0


func _stack_index(item_id: StringName) -> int:
	var data := ContentRegistry.get_content(item_id) as ItemData
	var max_stack: int = data.max_stack if data != null else 1
	if max_stack <= 1:
		return -1
	for index: int in _slots.size():
		var slot: InventorySlot = _slots[index]
		if slot != null and slot.item_id == item_id and slot.count < max_stack:
			return index
	return -1


## Slot count = base + every bonus. Items in removed slots are dropped (host).
func _resize() -> void:
	var total: int = Config.game.base_inventory_slots
	for source_id: StringName in _bonus:
		total += _bonus[source_id]
	total = maxi(total, 0)
	while _slots.size() > total:
		var removed: InventorySlot = _slots.pop_back()
		if removed != null and _is_host():
			_drop(removed)
	while _slots.size() < total:
		_slots.append(null)
	_selected = clampi(_selected, 0, maxi(total - 1, 0))


func _drop_selected() -> void:
	var slot: InventorySlot = get_slot(_selected)
	if slot == null:
		return
	# One at a time off a stack.
	var dropped := InventorySlot.make(slot.item_id, slot.uses_left)
	slot.count -= 1
	if slot.count <= 0:
		_slots[_selected] = null
	_drop(dropped)
	_send_state()


## Host: an item leaves the inventory into the world in front of the player.
func _drop(slot: InventorySlot) -> void:
	var at := Transform3D.IDENTITY
	if _body != null:
		at.origin = _body.get_aim_origin() + _body.get_aim_direction() * DROP_DISTANCE
	item_dropped.emit(slot, at)
	var data := ContentRegistry.get_content(slot.item_id) as ItemData
	if data != null and data.world_scene != null:
		Props.spawn_item(slot.item_id, at, slot.uses_left)


func _apply_selection(index: int, holstered: bool) -> void:
	var changed_slot: bool = index != _selected
	var changed_holster: bool = holstered != _holstered
	_selected = index
	_holstered = holstered
	if changed_slot or changed_holster:
		active_slot_changed.emit(_selected)
		changed.emit()


func _send_selection(index: int, holstered: bool) -> void:
	if multiplayer.is_server():
		_send_state()
	else:
		_request_select_rpc.rpc_id(1, index, holstered)


func _send_state() -> void:
	var slot_data: Array = []
	for slot: InventorySlot in _slots:
		slot_data.append(slot.to_dict() if slot != null else {})
	_state_rpc.rpc(slot_data, _selected, _holstered)


## Owner -> host: "I selected this slot". The host checks it's theirs and in range.
@rpc("any_peer", "call_remote", "reliable")
func _request_select_rpc(index: int, holstered: bool) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	if _body == null or multiplayer.get_remote_sender_id() != _body.get_multiplayer_authority():
		return
	if index < 0 or index >= _slots.size():
		return
	_apply_selection(index, holstered)
	_send_state()


## Owner -> host: "drop what I have selected".
@rpc("any_peer", "call_remote", "reliable")
func _request_drop_rpc(index: int) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	if _body == null or multiplayer.get_remote_sender_id() != _body.get_multiplayer_authority():
		return
	if index != _selected or _holstered:
		return
	_drop_selected()


## Host -> everyone: the whole inventory (small: a few slots).
@rpc("authority", "call_local", "reliable")
func _state_rpc(slot_data: Array, selected: int, holstered: bool) -> void:
	if not is_inside_tree():
		return
	_slots.clear()
	for entry: Variant in slot_data:
		var data: Dictionary = entry
		_slots.append(InventorySlot.from_dict(data) if not data.is_empty() else null)
	var selection_changed: bool = selected != _selected or holstered != _holstered
	_selected = clampi(selected, 0, maxi(_slots.size() - 1, 0))
	_holstered = holstered
	if selection_changed:
		active_slot_changed.emit(_selected)
	changed.emit()
	EventBus.inventory_changed.emit(_player_id())


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var slot_data: Array = []
	for slot: InventorySlot in _slots:
		slot_data.append(slot.to_dict() if slot != null else {})
	_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), slot_data, _selected, _holstered)
