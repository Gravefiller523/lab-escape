class_name WorldTrigger
extends WorldDevice
## NEW 2026-10-30 (HL2 feel step 4.2): an invisible box (centred on this node) that notices players walking
## in, and if ticked props or enemies too. It fires "entered" when the first one gets in and "exited" when
## the last one leaves. The host decides; there is nothing for other PCs to see.
## Outputs: entered, exited. Inputs: none besides enable and disable.

@export var size: Vector3 = Vector3(2, 2, 2)
@export var notices_players: bool = true
@export var notices_props: bool = false
@export var notices_enemies: bool = false
## Only fire "entered" once, ever.
@export var once: bool = false

var _area: Area3D
## Instance ids of the bodies inside that count.
var _inside: Dictionary[int, bool] = {}
var _done: bool = false


func _build() -> void:
	_area = Area3D.new()
	_area.name = "Area"
	_area.collision_layer = 0
	var mask: int = 0
	if notices_players:
		mask |= PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	if notices_props:
		mask |= PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.HELD_PROPS)
	if notices_enemies:
		mask |= PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	_area.collision_mask = mask
	_area.monitorable = false
	_area.add_child(_box_shape(size))
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	add_child(_area)


## How many counted bodies are inside now (host).
func get_inside_count() -> int:
	return _inside.size()


func _on_body_entered(body: Node3D) -> void:
	if not _is_host() or not _counts(body):
		return
	var first: bool = _inside.is_empty()
	_inside[body.get_instance_id()] = true
	if first and _enabled and not _done:
		_done = once
		var player := body as PlayerCharacter
		fire_output(&"entered", player.player_id if player != null else 0)


func _on_body_exited(body: Node3D) -> void:
	if not _is_host() or not _inside.has(body.get_instance_id()):
		return
	_inside.erase(body.get_instance_id())
	if _inside.is_empty() and _enabled:
		var player := body as PlayerCharacter
		fire_output(&"exited", player.player_id if player != null else 0)


func _counts(body: Node3D) -> bool:
	if body is PlayerCharacter:
		return notices_players
	if body is Enemy:
		return notices_enemies
	return notices_props and body is RigidBody3D
