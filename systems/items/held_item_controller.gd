class_name HeldItemController
extends Node
## Child "HeldItem" of every player body (added by the Items autoload). Spec: docs/systems/items.md.
## - Shows the item in your hand: in front of your camera for you, at the right arm for everyone else.
## - On your PC: left click (PRIMARY) / right click (SECONDARY) uses the item's behaviour for that button.
##   The swing plays at once; the host checks the cooldown, the item and where you aimed, then runs the
##   real effect (damage, throw, drink, use on an object). Everyone then sees the swing.
## - On your PC (CHANGED 2026-10-19, Zachary): E picks an item up like any prop (carry it, throw it); F equips it
##   into your inventory (the one you look at, or the one you carry), swapping when full.
## Nothing happens while you hold a prop (the left click throws it) or a menu is open.

signal item_action(item_id: StringName, trigger: int)

const NODE_NAME: String = "HeldItem"
## Above physics_props' grab (50), so the prompt can add the F hint (E itself is left to grabbing).
const PROMPT_PRIORITY: int = 60
## The prompt over an item pickup: grabbing's text plus the F hint.
const PROMPT_EQUIP: String = "%s %s   [F] Equip"
## The host allows this much extra distance between where you say you aimed from and your eyes (lag).
const AIM_TOLERANCE: float = 1.5
## The host allows this much early use (seconds) for network timing.
const COOLDOWN_TOLERANCE: float = 0.1
const PICKUP_REACH: float = 3.0
const VIEW_OFFSET: Vector3 = Vector3(0.3, -0.3, -0.6)
const SWING_SECONDS: float = 0.25

var _body: PlayerCharacter
var _model: Node3D
var _model_item: StringName = &"__none"
## trigger -> when it can next be used (seconds, Time.get_ticks_msec() / 1000).
var _ready_at: Dictionary[int, float] = {}
var _swing: Tween


func _ready() -> void:
	name = NODE_NAME
	_body = get_parent() as PlayerCharacter
	if _body == null:
		return
	if _body.is_local():
		_hook_into_interaction.call_deferred()


func _hook_into_interaction() -> void:
	var interaction: InteractionController = InteractionService.controller_of(_body)
	if interaction == null:
		return
	interaction.register_prompt_provider(PROMPT_PRIORITY, _prompt_for)


## The item in this player's hand (fists when the slot is empty or holstered). Null if unknown.
func get_active_item() -> ItemData:
	var inventory: InventoryComponent = InventoryComponent.of(_body)
	var item_id: StringName = inventory.get_active_item_id() if inventory != null else Config.game.unarmed_item_id
	return ContentRegistry.get_content(item_id) as ItemData


func is_on_cooldown(trigger: int) -> bool:
	return _now() < _ready_at.get(trigger, 0.0)


## Local: use the held item's behaviour for a button (what clicking does).
func use(trigger: int) -> void:
	var item: ItemData = get_active_item()
	var behaviour_data: ItemBehaviourData = _behaviour_for(item, trigger)
	if behaviour_data == null or is_on_cooldown(trigger):
		return
	var behaviour: ItemBehaviour = ItemBehaviour.for_data(behaviour_data)
	if behaviour == null or not behaviour.can_use(_body, behaviour_data):
		return
	_ready_at[trigger] = _now() + behaviour_data.cooldown
	behaviour.use_local(_body, behaviour_data)
	_play_swing(trigger)
	var inventory: InventoryComponent = InventoryComponent.of(_body)
	var slot_index: int = -1 if inventory == null or inventory.is_using_fists() else inventory.get_active_index()
	if multiplayer.is_server():
		_host_use(trigger, item.id, slot_index, _body.get_aim_origin(), _body.get_aim_direction(), true)
	else:
		_use_rpc.rpc_id(1, trigger, item.id, slot_index, _body.get_aim_origin(), _body.get_aim_direction())


func _unhandled_input(event: InputEvent) -> void:
	if _body == null or not _body.is_local() or UI.is_screen_open():
		return
	if event.is_action_pressed(InputActions.EQUIP):
		if equip_target():
			get_viewport().set_input_as_handled()
		return
	if _holding_prop():
		return
	if event.is_action_pressed(InputActions.PRIMARY):
		use(ItemBehaviourData.Trigger.PRIMARY)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.SECONDARY):
		use(ItemBehaviourData.Trigger.SECONDARY)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _body == null:
		return
	var item: ItemData = get_active_item()
	var item_id: StringName = item.id if item != null else &""
	if item_id != _model_item:
		_show_model(item)


# --- Picking up ---------------------------------------------------------------------------------

## NEW 2026-10-19, local: F. Equip the item pickup you carry, or else the one you look at. False if neither.
func equip_target() -> bool:
	var grab: GrabController = PropsService.grab_of(_body)
	var prop: NetProp = ItemPickup.prop_of(grab.get_held()) if grab != null and grab.get_held() != null else null
	if prop != null:
		grab.drop()
	elif not _holding_prop():
		var interaction: InteractionController = InteractionService.controller_of(_body)
		prop = ItemPickup.prop_of(interaction.get_target()) if interaction != null else null
	return equip(prop)


## Local: put this item pickup in your inventory (the host checks it). False if it isn't one.
func equip(prop: NetProp) -> bool:
	if ItemPickup.item_of(prop) == null:
		return false
	if multiplayer.is_server():
		_host_take(prop.net_id, true)
	else:
		_take_rpc.rpc_id(1, prop.net_id)
	return true


## E prompt over an item pickup: what grabbing would say, plus the F hint.
func _prompt_for(target: Node3D) -> String:
	var grab: GrabController = PropsService.grab_of(_body)
	var held: NetProp = grab.get_held() if grab != null else null
	var prop: NetProp = ItemPickup.prop_of(held if held != null else target)
	var item: ItemData = ItemPickup.item_of(prop)
	if item == null:
		return ""
	var grab_text: String = GrabController.PROMPT_DROP if held != null else GrabController.PROMPT_PICK_UP
	return PROMPT_EQUIP % [grab_text, item.display_name]


## Owner -> host: "put that item pickup in my inventory".
@rpc("any_peer", "call_remote", "reliable")
func _take_rpc(net_id: int) -> void:
	if is_inside_tree() and multiplayer.is_server():
		_host_take(net_id, false)


func _host_take(net_id: int, local_call: bool) -> void:
	if not local_call and multiplayer.get_remote_sender_id() != _body.get_multiplayer_authority():
		return
	var prop: NetProp = Props.get_prop(net_id)
	var item: ItemData = ItemPickup.item_of(prop)
	if item == null or prop.global_position.distance_to(_body.get_aim_origin()) > PICKUP_REACH:
		return
	# Carried by someone else: not yours to take. Carried by you: let go first.
	var holders: Array[int] = prop.get_holder_ids()
	if not holders.is_empty() and holders != [_body.player_id]:
		return
	if not holders.is_empty():
		prop.get_spawner().release_all(prop)
	var inventory: InventoryComponent = InventoryComponent.of(_body)
	if inventory == null:
		return
	var uses_left: int = ItemPickup.uses_left_of(prop)
	Props.despawn(prop)
	inventory.pick_up(item.id, uses_left)


# --- Using (host) -------------------------------------------------------------------------------

## Owner -> host: "I used my item". The host checks it and does the real thing.
@rpc("any_peer", "call_remote", "reliable")
func _use_rpc(trigger: int, item_id: StringName, slot_index: int, aim_origin: Vector3, aim_dir: Vector3) -> void:
	if is_inside_tree() and multiplayer.is_server():
		_host_use(trigger, item_id, slot_index, aim_origin, aim_dir, false)


func _host_use(trigger: int, item_id: StringName, slot_index: int, aim_origin: Vector3, aim_dir: Vector3,
		local_call: bool) -> void:
	if not local_call:
		if multiplayer.get_remote_sender_id() != _body.get_multiplayer_authority():
			return
		# The host keeps its own cooldown for clients (the owner's PC already set it for itself).
		if _now() < _ready_at.get(trigger, 0.0) - COOLDOWN_TOLERANCE:
			return
	var item: ItemData = get_active_item()
	if item == null or item.id != item_id:
		return
	var inventory: InventoryComponent = InventoryComponent.of(_body)
	var expected_slot: int = -1 if inventory == null or inventory.is_using_fists() else inventory.get_active_index()
	if slot_index != expected_slot:
		return
	if aim_origin.distance_to(_body.get_aim_origin()) > AIM_TOLERANCE or aim_dir.is_zero_approx():
		return
	var health: HealthComponent = HealthComponent.of(_body)
	if health != null and health.is_dead():
		return
	var behaviour_data: ItemBehaviourData = _behaviour_for(item, trigger)
	var behaviour: ItemBehaviour = ItemBehaviour.for_data(behaviour_data)
	if behaviour == null or not behaviour.can_use(_body, behaviour_data):
		return
	if not local_call:
		_ready_at[trigger] = _now() + behaviour_data.cooldown
	behaviour.use_host(_body, behaviour_data, aim_origin, aim_dir.normalized(), item, slot_index)
	_used_rpc.rpc(item_id, trigger)


## Host -> everyone: it was used (others see the swing; item_used fires everywhere).
@rpc("authority", "call_local", "reliable")
func _used_rpc(item_id: StringName, trigger: int) -> void:
	if not is_inside_tree():
		return
	if not _body.is_local():
		_play_swing(trigger)
	item_action.emit(item_id, trigger)
	EventBus.item_used.emit(_body.player_id, item_id)


# --- Inside -------------------------------------------------------------------------------------

func _behaviour_for(item: ItemData, trigger: int) -> ItemBehaviourData:
	if item == null:
		return null
	for behaviour: ItemBehaviourData in item.behaviours:
		if behaviour != null and int(behaviour.trigger) == trigger:
			return behaviour
	return null


func _holding_prop() -> bool:
	var grab: GrabController = PropsService.grab_of(_body)
	return grab != null and grab.get_held() != null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The held model: in front of your camera (you), at the right arm (everyone else).
func _show_model(item: ItemData) -> void:
	_model_item = item.id if item != null else &""
	if _model != null:
		# Out of the tree now, so the new one can take the name "HeldModel".
		if _model.get_parent() != null:
			_model.get_parent().remove_child(_model)
		_model.queue_free()
		_model = null
	if item == null or item.held_scene == null:
		return
	_model = item.held_scene.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "HeldModel"
	if _body.is_local():
		var camera: Camera3D = _body.get_camera()
		if camera == null:
			return
		camera.add_child(_model)
		_model.position = VIEW_OFFSET
	else:
		var arm: Node3D = _body.get_attach_point(&"right_arm")
		(arm if arm != null else _body as Node3D).add_child(_model)


func _play_swing(trigger: int) -> void:
	if _model == null:
		return
	if _swing != null and _swing.is_valid():
		_swing.kill()
	var rest: Vector3 = Vector3.ZERO
	var swing: Vector3 = Vector3(deg_to_rad(-70.0), 0.0, 0.0) if trigger == ItemBehaviourData.Trigger.PRIMARY \
		else Vector3(0.0, deg_to_rad(40.0), deg_to_rad(-30.0))
	_model.rotation = rest
	_swing = _model.create_tween()
	_swing.tween_property(_model, "rotation", swing, SWING_SECONDS * 0.4)
	_swing.tween_property(_model, "rotation", rest, SWING_SECONDS * 0.6)
