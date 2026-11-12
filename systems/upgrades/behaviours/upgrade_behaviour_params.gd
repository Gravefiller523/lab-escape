class_name UpgradeBehaviourParams
## NEW 2026-11-12 (roadmap WP10): reads a number from the params a BehaviourEffectData passes to its behaviour node
## (the node's "params" metadata), with a default when the content file doesn't set it.


static func number(node: Node, key: String, default: float) -> float:
	var params: Dictionary = node.get_meta(&"params", {})
	var value: Variant = params.get(key, default)
	return float(value) if value is float or value is int else default


static func text(node: Node, key: String, default: String) -> String:
	var params: Dictionary = node.get_meta(&"params", {})
	return str(params.get(key, default))
