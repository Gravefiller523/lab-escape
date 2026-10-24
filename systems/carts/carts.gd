class_name CartsService
extends Node
## Autoload "Carts". The E key for carts on your PC (above grabbing): E on a cart pushes it (E again
## lets go), E on a prop riding in a cart takes it out and into your hands. The host spawns a cart at
## each `cart` marker on floor_ready (the marker's params.prop_id, or the first prop tagged "cart").
## Spec: docs/systems/carts.md.

## Above physics_props' grab (50), below upgrades (70).
const USE_PRIORITY: int = 55
const CART_TAG: String = "cart"
const PROMPT_PUSH: String = "Push cart"
const PROMPT_STOP: String = "Let go of the cart"
const PROMPT_TAKE: String = "Take out of the cart"
const PROMPT_BUSY: String = "Someone is pushing this cart"


func _ready() -> void:
	EventBus.player_spawned.connect(func(_player_id: int, body: Node3D) -> void:
		var player := body as PlayerCharacter
		if player != null and player.is_local():
			_hook.call_deferred(player))
	EventBus.floor_ready.connect(func(_floor_number: int, _department_id: StringName) -> void: spawn_floor_carts())


## The cart this player pushes, or null.
func pushed_by(player_id: int) -> Cart:
	for node: Node in get_tree().get_nodes_in_group(&"carts"):
		var cart := node as Cart
		if cart != null and cart.get_pusher_id() == player_id:
			return cart
	return null


## Host: a cart at each `cart` marker.
func spawn_floor_carts() -> Array[NetProp]:
	var spawned: Array[NetProp] = []
	if not multiplayer.is_server() or Props.get_spawner() == null:
		return spawned
	for marker: RoomMarker in Level.get_markers(&"cart"):
		var prop_id := StringName(str(marker.params.get("prop_id", "")))
		if prop_id == &"":
			prop_id = _first_cart_prop()
		if prop_id == &"":
			continue
		var cart: NetProp = Props.spawn_prop(prop_id, marker.global_transform.translated(Vector3.UP * 0.1))
		if cart != null:
			spawned.append(cart)
	return spawned


func _first_cart_prop() -> StringName:
	for content: ContentData in ContentRegistry.get_all(&"prop"):
		if content.tags.has(CART_TAG):
			return content.id
	return &""


func _hook(candidate: Variant) -> void:
	if not is_instance_valid(candidate):
		return
	var body := candidate as PlayerCharacter
	var interaction: InteractionController = InteractionService.controller_of(body) if body != null else null
	if interaction == null:
		return
	interaction.register_use_handler(USE_PRIORITY, func(target: Node3D) -> bool: return _on_use(body, target))
	interaction.register_prompt_provider(USE_PRIORITY, func(target: Node3D) -> String: return _prompt(body, target))


func _holding(body: PlayerCharacter) -> bool:
	var grab: GrabController = PropsService.grab_of(body)
	return grab != null and grab.get_held() != null


func _on_use(body: PlayerCharacter, target: Node3D) -> bool:
	if not is_instance_valid(body):
		return false
	var pushing: Cart = pushed_by(body.player_id)
	if pushing != null:
		pushing.request_push(false)
		return true
	if _holding(body):
		return false
	var prop: NetProp = NetProp.of(target) if target != null else null
	var cart := prop as Cart
	if cart != null:
		cart.request_push(true)
		return true
	var holder: Cart = Cart.cart_of(prop)
	if holder != null:
		holder.request_take_out(prop)
		PropsService.grab_of(body).try_grab(prop)
		return true
	return false


func _prompt(body: PlayerCharacter, target: Node3D) -> String:
	if not is_instance_valid(body):
		return ""
	if pushed_by(body.player_id) != null:
		return PROMPT_STOP
	if _holding(body):
		return ""
	var prop: NetProp = NetProp.of(target) if target != null else null
	var cart := prop as Cart
	if cart != null:
		return PROMPT_PUSH if cart.get_pusher_id() == 0 else PROMPT_BUSY
	return PROMPT_TAKE if Cart.cart_of(prop) != null else ""
