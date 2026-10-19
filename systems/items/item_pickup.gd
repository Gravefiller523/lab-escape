class_name ItemPickup
extends Node
## Marks an item's world scene (root is a NetProp) as a pickup: look at it and press E to take it into
## your inventory (it swaps with your selected item when you're full). HeldItemController does the
## asking; the host checks and moves it. Spec: docs/systems/items.md.

const NODE_NAME: String = "ItemPickup"


## The pickup a node belongs to (the NetProp with an ItemPickup child), or null.
static func prop_of(node: Node) -> NetProp:
	var prop: NetProp = NetProp.of(node) if node != null else null
	if prop == null or prop.get_node_or_null(NodePath(NODE_NAME)) == null:
		return null
	return prop


## The item a pickup is (its content id), or null.
static func item_of(prop: NetProp) -> ItemData:
	return ContentRegistry.get_content(prop.content_id) as ItemData if prop != null else null


## How many uses the item lying here has left (a fresh one has ItemData.uses).
static func uses_left_of(prop: NetProp) -> int:
	var item: ItemData = item_of(prop)
	var fresh: int = item.uses if item != null else -1
	var uses: int = prop.extra.get("uses_left", fresh)
	return uses if uses != -1 else fresh
