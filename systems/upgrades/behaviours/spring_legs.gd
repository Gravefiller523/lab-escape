extends Node
## NEW 2026-11-12 (roadmap WP11, decision D4): the Spring Legs cybernetic's rule. Land hard (falling faster than
## `stomp_speed`) and you stomp: enemies within `radius` take `damage` and are knocked away. Your own PC sees the landing
## (it moves your body) and asks the host, which checks you are really there. Params: stomp_speed (7 m/s), radius
## (3 m), damage (15). Added under the player's body on every PC.

var _body: PlayerCharacter


func _ready() -> void:
	_body = get_parent() as PlayerCharacter
	if _body != null:
		_body.landed.connect(_on_landed)


func _on_landed(fall_speed: float) -> void:
	if not _body.is_local() or _body.is_ghost() or fall_speed < UpgradeBehaviourParams.number(self, "stomp_speed", 7.0):
		return
	if multiplayer.is_server():
		stomp()
	else:
		_request_stomp_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_stomp_rpc() -> void:
	if not multiplayer.is_server() or _body == null:
		return
	if Net.sender_player_id() != _body.player_id:
		return
	stomp()


## Host: hurt and shove every enemy around the body. Returns how many were hit.
func stomp() -> int:
	var radius: float = UpgradeBehaviourParams.number(self, "radius", 3.0)
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or enemy.global_position.distance_to(_body.global_position) > radius:
			continue
		var info := DamageInfo.make(UpgradeBehaviourParams.number(self, "damage", 15.0), &"blunt", _body)
		info.source_player_id = _body.player_id
		var away: Vector3 = enemy.global_position - _body.global_position
		away.y = 0.0
		info.knockback = away.normalized() * 6.0 + Vector3.UP * 3.0
		Damage.hit(enemy, info)
		count += 1
	EventBus.noise_made.emit(_body.global_position, radius * 3.0, _body.player_id)
	return count
