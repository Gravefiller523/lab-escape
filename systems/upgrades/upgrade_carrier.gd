class_name UpgradeCarrier
extends Node
## Child of glowing-gem and robot-part prop scenes: the upgrade the prop holds comes from its
## NetProp.extra["upgrade_id"] (loot sets it). Hold the prop and press E to eat / install it.
## Spec: docs/systems/upgrades.md.

const NODE_NAME: String = "UpgradeCarrier"

var upgrade_id: StringName:
	get:
		var prop := get_parent() as NetProp
		return StringName(str(prop.extra.get("upgrade_id", ""))) if prop != null else &""


func _ready() -> void:
	name = NODE_NAME


func get_upgrade() -> UpgradeData:
	return ContentRegistry.get_content(upgrade_id) as UpgradeData


## The carrier of a prop (or any node inside it), or null.
static func of(node: Node) -> UpgradeCarrier:
	var prop: NetProp = NetProp.of(node) if node != null else null
	return prop.get_node_or_null(NodePath(NODE_NAME)) as UpgradeCarrier if prop != null else null
