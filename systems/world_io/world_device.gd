class_name WorldDevice
extends Node3D
## NEW 2026-10-30 (HL2 feel step 4.2): the base of the world wiring kit (like Half-Life 2's inputs and
## outputs). Spec: docs/systems/world_io.md.
## A device has outputs (events such as "pressed" or "opened") and inputs (actions such as "open" or
## "lock"). Its `outputs` list wires them: "when this event happens, do that action on that device, after
## so many seconds". Every device also takes the inputs "enable" and "disable".
## Only the host fires wires and changes devices; each device sends its own state to every PC and to
## players who join later. Kinds: WorldButton, WorldTrigger, WorldDoor, WorldRelay, WorldCounter, WorldCrank.
## A new kind overrides _build, get_inputs, _on_input, and (if PCs must see it) get_state / _apply_state.

## Host: an event happened (before its wires run). For tests and code that wants to listen.
signal output_fired(event: StringName, activator_id: int)

const GROUP: StringName = &"world_devices"

## The wires: when one of this device's events happens, do something to another device.
@export var outputs: Array[IOConnection] = []
## Off at the start: it ignores everything until something sends it "enable".
@export var start_enabled: bool = true

var _enabled: bool = true
## Wires marked `once` that have already run (index in `outputs`).
var _fired_once: Dictionary[int, bool] = {}


func _ready() -> void:
	add_to_group(GROUP)
	_enabled = start_enabled
	_build()
	_apply_enabled()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


func is_enabled() -> bool:
	return _enabled


## Host: switch it on or off (a disabled device ignores its inputs and can't be used).
func set_enabled(on: bool) -> void:
	if not _is_host() or _enabled == on:
		return
	_enabled = on
	_apply_enabled()
	push_state()


## Host: do an input (from a wire, a test or code). `activator_id` is the player who set it off (0 = none).
func receive(action: StringName, activator_id: int = 0) -> void:
	if not _is_host():
		return
	match action:
		&"enable":
			set_enabled(true)
		&"disable":
			set_enabled(false)
		_:
			if not get_inputs().has(action):
				push_warning("%s has no input '%s' (it takes: %s)" % [name, action, ", ".join(get_inputs())])
				return
			if _enabled:
				_on_input(action, activator_id)


## Host: one of this device's events happened: run its wires.
func fire_output(event: StringName, activator_id: int = 0) -> void:
	if not _is_host():
		return
	output_fired.emit(event, activator_id)
	for index: int in outputs.size():
		var connection: IOConnection = outputs[index]
		if connection == null or connection.event != event:
			continue
		if connection.once and _fired_once.has(index):
			continue
		_fired_once[index] = true
		var target := get_node_or_null(connection.target) as WorldDevice
		if target == null:
			push_warning("%s: wire '%s' points at '%s', which isn't a world device" % [name, event, connection.target])
			continue
		if connection.delay <= 0.0:
			target.receive(connection.action, activator_id)
		else:
			var action: StringName = connection.action
			get_tree().create_timer(connection.delay, false).timeout.connect(func() -> void:
				if is_instance_valid(target) and target.is_inside_tree():
					target.receive(action, activator_id))


## Wiring from code (the same as adding an output in the Inspector).
func wire(event: StringName, target: WorldDevice, action: StringName, delay: float = 0.0, once: bool = false) -> IOConnection:
	var connection := IOConnection.new()
	connection.event = event
	connection.target = get_path_to(target) if is_inside_tree() and target.is_inside_tree() else NodePath()
	connection.action = action
	connection.delay = delay
	connection.once = once
	if connection.target.is_empty():
		push_warning("wire(): add both devices to the tree first")
	outputs.append(connection)
	return connection


## Host: send this device's state to every other PC.
func push_state() -> void:
	if _is_host() and is_inside_tree() and multiplayer.has_multiplayer_peer():
		_state_rpc.rpc(_enabled, get_state())


# --- For each kind of device to fill in ---------------------------------------------------------------

## Build its bodies, meshes and Interactables (called once, from _ready).
func _build() -> void:
	pass


## The inputs it takes besides enable and disable.
func get_inputs() -> PackedStringArray:
	return PackedStringArray()


## Host: do one of its inputs (only called when enabled and the input is in get_inputs()).
func _on_input(_action: StringName, _activator_id: int) -> void:
	pass


## What other PCs need to see it right (sent by push_state and to joiners).
func get_state() -> Array:
	return []


## Other PCs: show the state the host sent.
func _apply_state(_state: Array) -> void:
	pass


## Every PC: show whether it is enabled (e.g. hide its use prompt).
func _apply_enabled() -> void:
	pass


# --- Helpers -------------------------------------------------------------------------------------------

func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.is_server()


## A sound from event_sounds.tres at this device, on this PC.
func _play(field: StringName, volume_db: float = 0.0, at: Vector3 = Vector3.INF) -> void:
	if is_inside_tree():
		Sound.play_3d(Sound.event_sound(field), global_position if at == Vector3.INF else at, volume_db)


## A plain coloured box mesh.
static func _box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	return mesh


## A box collision shape.
static func _box_shape(size: Vector3, offset: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	return shape


# --- Network -------------------------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _state_rpc(enabled: bool, state: Array) -> void:
	_enabled = enabled
	_apply_enabled()
	_apply_state(state)


## A PC that just built this device asks the host what it looks like now.
@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if not multiplayer.is_server():
		return
	_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), _enabled, get_state())
