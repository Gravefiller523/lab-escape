class_name UpgradeMachine
extends Node3D
## The mutation machine (systems/upgrades/upgrade_machine.tscn; the booth is made in code with fixed node
## names). One spawns at a random spot on every floor. Spec: docs/systems/upgrades.md.
## - Load it: drop a DNA vial (a mutation) or a data drive (a cybernetic) into the hopper on its side, or
##   press E at the machine while holding one. Several can wait in line.
## - Step into the booth and stand still for Config.game.upgrade_machine_seconds: the first one in line is
##   applied to you (Upgrades.grant). If you already have it (and it can't stack) you're told so and it
##   stays loaded for someone else.
## The host decides; the line and the "applied" flash reach every PC (and joiners).

signal loaded_changed()
signal applied(player_id: int, upgrade_id: StringName)

const GROUP: StringName = &"upgrade_machines"
const BOOTH_SIZE: Vector3 = Vector3(2.0, 2.6, 2.0)
const WALL: float = 0.15
const HOPPER_OFFSET: Vector3 = Vector3(1.35, 1.0, 0.3)
## The host accepts "insert" requests from this far away (metres).
const INSERT_REACH: float = 3.5
const MSG_HAVE: String = "You already have %s."
const MSG_EMPTY: String = "The machine is empty: put a DNA vial or data drive in first."
const MSG_APPLIED: String = "%s: %s!"

var _queue: Array[StringName] = []
var _booth: Area3D
var _hopper: Area3D
var _screen: Label3D
var _light: OmniLight3D
var _pad: MeshInstance3D
## Host: player_id -> seconds stood in the booth (this visit).
var _inside_for: Dictionary[int, float] = {}
## Host: players already told "you have it" this visit (no spam).
var _told: Dictionary[int, bool] = {}


func _ready() -> void:
	add_to_group(GROUP)
	_build()
	_refresh()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


static func current() -> UpgradeMachine:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var machine := node as UpgradeMachine
		if machine != null and machine.is_inside_tree() and not machine.is_queued_for_deletion():
			return machine
	return null


## The machine a node belongs to (its booth walls, its hopper), or null.
static func of(node: Node) -> UpgradeMachine:
	var current_node: Node = node
	while current_node != null:
		var machine := current_node as UpgradeMachine
		if machine != null:
			return machine
		current_node = current_node.get_parent()
	return null


## What's waiting in line (first = the next one applied).
func get_loaded() -> Array[StringName]:
	return _queue.duplicate()


## Local: put the carrier prop you hold into the machine (the host checks it).
func request_insert(prop: NetProp) -> void:
	if prop == null:
		return
	if multiplayer.is_server():
		_insert_from(Net.local_player_id(), prop)
	else:
		_request_insert_rpc.rpc_id(1, prop.net_id)


## Host: load an upgrade straight in (tests, the hopper).
func load_upgrade(upgrade_id: StringName) -> void:
	if not multiplayer.is_server() or not ContentRegistry.get_content(upgrade_id) is UpgradeData:
		return
	_queue.append(upgrade_id)
	_send_state()


## Host: a carrier prop goes in (despawned) and its upgrade joins the line. True if it went in.
func insert_prop(prop: NetProp) -> bool:
	var carrier: UpgradeCarrier = UpgradeCarrier.of(prop)
	if not multiplayer.is_server() or carrier == null or carrier.get_upgrade() == null or prop.is_queued_for_deletion():
		return false
	var upgrade_id: StringName = carrier.upgrade_id
	if prop.get_spawner() != null:
		prop.get_spawner().release_all(prop)
	Props.despawn(prop)
	load_upgrade(upgrade_id)
	return true


## Host: someone stood in the booth long enough: the first in line goes to them. True if it applied.
func apply_to(player_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if _queue.is_empty():
		return false
	var upgrade_id: StringName = _queue[0]
	var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
	var stacks: int = Upgrades.get_stack_count(player_id, upgrade_id)
	if upgrade != null and stacks > 0 and (upgrade.stack_rule == UpgradeData.StackRule.UNIQUE or stacks >= upgrade.max_stacks):
		if not _told.has(player_id):
			_told[player_id] = true
			Death.tell(player_id, MSG_HAVE % upgrade.display_name)
		return false
	_queue.pop_front()
	Upgrades.grant(player_id, upgrade_id)
	_applied_rpc.rpc(player_id, upgrade_id)
	_send_state()
	return true


func _insert_from(player_id: int, prop: NetProp) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if prop == null or body == null or body.global_position.distance_to(global_position) > INSERT_REACH:
		return
	if prop.is_held() and not prop.get_holder_ids().has(player_id):
		return
	insert_prop(prop)


func _on_hopper_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var prop := body as NetProp
	if prop != null and not prop.is_held() and UpgradeCarrier.of(prop) != null:
		insert_prop(prop)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _booth == null:
		return
	# A vial carried into the hopper and then let go never "enters" again, so check what is already in it.
	if _hopper != null:
		for body: Node3D in _hopper.get_overlapping_bodies():
			_on_hopper_body_entered(body)
	var inside: Dictionary[int, bool] = {}
	for body: Node3D in _booth.get_overlapping_bodies():
		var player := body as PlayerCharacter
		var health: HealthComponent = HealthComponent.of(player) if player != null else null
		if player == null or (health != null and health.is_dead()):
			continue
		inside[player.player_id] = true
		_inside_for[player.player_id] = _inside_for.get(player.player_id, 0.0) + delta
		if _inside_for[player.player_id] >= Config.game.upgrade_machine_seconds and not _queue.is_empty():
			if apply_to(player.player_id):
				_inside_for[player.player_id] = -INF
	for player_id: int in _inside_for.keys():
		if not inside.has(player_id):
			_inside_for.erase(player_id)
			_told.erase(player_id)


func _refresh() -> void:
	if _screen == null:
		return
	var next: String = "EMPTY: put a DNA vial or data drive in"
	var color := Color(0.4, 0.45, 0.5)
	if not _queue.is_empty():
		var upgrade := ContentRegistry.get_content(_queue[0]) as UpgradeData
		var title: String = UpgradesService.UNKNOWN_NAME
		if upgrade != null and Upgrades.is_known(upgrade.id):
			title = upgrade.display_name
		next = "LOADED: %s%s\nStep in and stand still" % [title, "  (+%d more)" % (_queue.size() - 1) if _queue.size() > 1 else ""]
		if upgrade != null:
			color = upgrade.glow_color
	_screen.text = "MUTATION MACHINE\n%s" % next
	_light.light_color = color
	_light.light_energy = 2.0 if not _queue.is_empty() else 0.4
	var pad_material := _pad.mesh.surface_get_material(0) as StandardMaterial3D
	pad_material.emission = color
	pad_material.emission_energy_multiplier = 1.5 if not _queue.is_empty() else 0.2


func _send_state() -> void:
	var ids: Array = []
	for upgrade_id: StringName in _queue:
		ids.append(String(upgrade_id))
	_state_rpc.rpc(ids)


# --- The booth -----------------------------------------------------------------------------------------

func _build() -> void:
	var size: Vector3 = BOOTH_SIZE
	var metal := Color(0.5, 0.55, 0.62)
	_add_wall("Back", Vector3(0, size.y / 2.0, -size.z / 2.0), Vector3(size.x, size.y, WALL), metal)
	_add_wall("Left", Vector3(-size.x / 2.0, size.y / 2.0, 0), Vector3(WALL, size.y, size.z), metal)
	_add_wall("Right", Vector3(size.x / 2.0, size.y / 2.0, 0), Vector3(WALL, size.y, size.z), metal)
	_add_wall("Roof", Vector3(0, size.y, 0), Vector3(size.x + WALL, WALL, size.z + WALL), metal)
	# A glowing pad on the floor inside.
	_pad = MeshInstance3D.new()
	_pad.name = "Pad"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.7
	pad_mesh.bottom_radius = 0.7
	pad_mesh.height = 0.04
	var pad_material := StandardMaterial3D.new()
	pad_material.albedo_color = Color(0.2, 0.22, 0.25)
	pad_material.emission_enabled = true
	pad_mesh.material = pad_material
	_pad.mesh = pad_mesh
	_pad.position.y = 0.02
	add_child(_pad)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position = Vector3(0, size.y - 0.3, 0)
	_light.omni_range = 4.0
	add_child(_light)
	# Who is standing inside.
	_booth = Area3D.new()
	_booth.name = "Booth"
	_booth.collision_layer = 0
	_booth.collision_mask = PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	_booth.monitorable = false
	var booth_shape := CollisionShape3D.new()
	var booth_box := BoxShape3D.new()
	booth_box.size = Vector3(size.x - 0.4, 2.0, size.z - 0.4)
	booth_shape.shape = booth_box
	booth_shape.position.y = 1.0
	_booth.add_child(booth_shape)
	add_child(_booth)
	# The hopper on the right side: vials and drives dropped onto it go in.
	_hopper = Area3D.new()
	_hopper.name = "Hopper"
	_hopper.collision_layer = 0
	_hopper.collision_mask = PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.HELD_PROPS)
	var hopper_shape := CollisionShape3D.new()
	var hopper_box := BoxShape3D.new()
	hopper_box.size = Vector3(0.6, 0.6, 0.6)
	hopper_shape.shape = hopper_box
	_hopper.add_child(hopper_shape)
	_hopper.position = HOPPER_OFFSET
	var funnel := MeshInstance3D.new()
	var funnel_mesh := CylinderMesh.new()
	funnel_mesh.top_radius = 0.3
	funnel_mesh.bottom_radius = 0.12
	funnel_mesh.height = 0.35
	var funnel_material := StandardMaterial3D.new()
	funnel_material.albedo_color = Color(0.85, 0.7, 0.2)
	funnel_mesh.material = funnel_material
	funnel.mesh = funnel_mesh
	_hopper.add_child(funnel)
	_hopper.body_entered.connect(_on_hopper_body_entered)
	add_child(_hopper)
	_screen = Label3D.new()
	_screen.name = "Screen"
	_screen.font_size = 28
	_screen.pixel_size = 0.004
	_screen.outline_size = 8
	_screen.position = Vector3(0, size.y + 0.35, size.z / 2.0)
	add_child(_screen)
	var hopper_label := Label3D.new()
	hopper_label.text = "DNA / DATA IN"
	hopper_label.font_size = 22
	hopper_label.pixel_size = 0.004
	hopper_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hopper_label.position = HOPPER_OFFSET + Vector3(0, 0.45, 0)
	add_child(hopper_label)


func _add_wall(node_name: String, center: Vector3, size: Vector3, color: Color) -> void:
	var wall := StaticBody3D.new()
	wall.name = node_name
	wall.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	wall.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	wall.add_child(mesh)
	add_child(wall)


# --- Network -------------------------------------------------------------------------------------------

## Host -> everyone: what's loaded.
@rpc("authority", "call_local", "reliable")
func _state_rpc(ids: Array) -> void:
	if not is_inside_tree():
		return
	_queue.clear()
	for entry: Variant in ids:
		_queue.append(StringName(str(entry)))
	_refresh()
	loaded_changed.emit()


## Host -> everyone: it worked (a flash, and a message for everyone).
@rpc("authority", "call_local", "reliable")
func _applied_rpc(player_id: int, upgrade_id: StringName) -> void:
	if not is_inside_tree():
		return
	applied.emit(player_id, upgrade_id)
	var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
	EventBus.toast_requested.emit(MSG_APPLIED % [Net.get_display_name(player_id),
		upgrade.display_name if upgrade != null else String(upgrade_id)])
	if _light != null:
		var tween: Tween = _light.create_tween()
		tween.tween_property(_light, "light_energy", 8.0, 0.1)
		tween.tween_property(_light, "light_energy", 0.4, 0.6)


@rpc("any_peer", "call_remote", "reliable")
func _request_insert_rpc(net_id: int) -> void:
	if is_inside_tree() and multiplayer.is_server():
		_insert_from(Net.get_player_id_for_peer(multiplayer.get_remote_sender_id()), Props.get_prop(net_id))


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var ids: Array = []
	for upgrade_id: StringName in _queue:
		ids.append(String(upgrade_id))
	_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), ids)
