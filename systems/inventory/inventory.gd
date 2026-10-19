class_name InventoryService
extends Node
## Autoload "Inventory". Gives every player body an InventoryComponent (child "Inventory") as soon as it
## spawns, so the player scene doesn't need editing. Console: give, slots, inv. Spec: docs/systems/inventory.md.


func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	DebugConsole.register_command(&"give", _cmd_give, "give <item_id>: put an item in your inventory (swaps if full)")
	DebugConsole.register_command(&"slots", _cmd_slots, "slots <extra>: give yourself extra inventory slots (0 = none)")
	DebugConsole.register_command(&"inv", _cmd_inv, "inv: what's in your inventory", false)


## The local player's inventory, or null if you have no body right now.
func get_local() -> InventoryComponent:
	return InventoryComponent.of(PlayerCharacter.find(Net.local_player_id()))


func _on_player_spawned(_player_id: int, player_node: Node3D) -> void:
	if player_node.is_queued_for_deletion() or InventoryComponent.of(player_node) != null:
		return
	player_node.add_child(InventoryComponent.new())


func _inventory_of(player_id: int) -> InventoryComponent:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	return InventoryComponent.of(body) if body != null else null


func _cmd_give(args: PackedStringArray, player_id: int) -> String:
	var inventory: InventoryComponent = _inventory_of(player_id)
	if inventory == null:
		return "You have no body right now."
	if args.is_empty():
		return "Usage: give <item_id>. Try: list item"
	var data := ContentRegistry.get_content(StringName(args[0])) as ItemData
	if data == null:
		return "No item called '%s'. Try: list item" % args[0]
	inventory.pick_up(data.id, data.uses)
	return "Gave you %s." % data.display_name


func _cmd_slots(args: PackedStringArray, player_id: int) -> String:
	var inventory: InventoryComponent = _inventory_of(player_id)
	if inventory == null:
		return "You have no body right now."
	var extra: int = args[0].to_int() if args.size() > 0 and args[0].is_valid_int() else 1
	inventory.set_bonus_slots(&"console", extra)
	return "You have %d slots." % inventory.get_slot_count()


func _cmd_inv(_args: PackedStringArray, player_id: int) -> String:
	var inventory: InventoryComponent = _inventory_of(player_id)
	if inventory == null:
		return "You have no body right now."
	var lines: PackedStringArray = []
	for index: int in inventory.get_slot_count():
		var slot: InventorySlot = inventory.get_slot(index)
		var text: String = "(empty)" if slot == null else "%s x%d (uses %d)" % [slot.item_id, slot.count, slot.uses_left]
		lines.append("%s%d: %s" % [">" if index == inventory.get_active_index() else " ", index + 1, text])
	lines.append("In hand: %s%s" % [inventory.get_active_item_id(), " (holstered)" if inventory.is_holstered() else ""])
	return "\n".join(lines)
