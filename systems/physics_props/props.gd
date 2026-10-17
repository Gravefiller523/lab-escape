class_name PropsService
extends Node
## Autoload "Props". The way other systems spawn and find props: it talks to the current level's
## PropSpawner. It also gives every player body a GrabController (child "Grab") when it spawns.
## Spec: docs/systems/physics_props.md.

## Local: the host refused one of our grabs (the GrabController lets go).
signal grab_refused(prop: NetProp, reason: String)

var _spawners: Array[PropSpawner] = []


func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)


## The current level's spawner (the most recently added one). Null if the level has none.
func get_spawner() -> PropSpawner:
	for index: int in range(_spawners.size() - 1, -1, -1):
		if is_instance_valid(_spawners[index]) and _spawners[index].is_inside_tree():
			return _spawners[index]
	return null


func register_spawner(spawner: PropSpawner) -> void:
	if not _spawners.has(spawner):
		_spawners.append(spawner)


func unregister_spawner(spawner: PropSpawner) -> void:
	_spawners.erase(spawner)


## Host: spawns a prop in the current level. Null if there is no PropSpawner or no such prop.
func spawn_prop(prop_id: StringName, xform: Transform3D, extra: Dictionary = {}) -> NetProp:
	var spawner: PropSpawner = get_spawner()
	if spawner == null:
		push_error("Props.spawn_prop: this level has no PropSpawner.")
		return null
	return spawner.spawn_prop(prop_id, xform, extra)


## Host: item pickups. STUB until the items system exists (it will provide ItemData.world_scene).
func spawn_item(item_id: StringName, _xform: Transform3D, _uses_left: int = -1) -> NetProp:
	push_warning("Props.spawn_item: item pickups come with the items system (asked for %s)." % item_id)
	return null


## Host: removes a prop for everyone.
func despawn(prop: NetProp) -> void:
	if prop != null and prop.get_spawner() != null:
		prop.get_spawner().despawn(prop)


func get_prop(net_id: int) -> NetProp:
	var spawner: PropSpawner = get_spawner()
	return spawner.get_prop(net_id) if spawner != null else null


func get_props(content_id: StringName = &"") -> Array[NetProp]:
	var spawner: PropSpawner = get_spawner()
	return spawner.get_props(content_id) if spawner != null else [] as Array[NetProp]


## Host: pushes a prop.
func apply_impulse(prop: NetProp, impulse: Vector3) -> void:
	if prop != null and prop.get_spawner() != null:
		prop.get_spawner().apply_impulse(prop, impulse)


func get_loose_count(content_id: StringName) -> int:
	var spawner: PropSpawner = get_spawner()
	return spawner.get_loose_count(content_id) if spawner != null else 0


## A body's grab controller, or null.
static func grab_of(body: PlayerCharacter) -> GrabController:
	return body.get_node_or_null(NodePath(GrabController.NODE_NAME)) as GrabController


func _on_player_spawned(_player_id: int, player_node: Node3D) -> void:
	var body := player_node as PlayerCharacter
	if body == null or grab_of(body) != null:
		return
	var controller := GrabController.new()
	controller.name = GrabController.NODE_NAME
	body.add_child(controller)
