class_name SwoopBehaviour
extends EnemyBehaviour
## Bat: flies high, then dives down to your head height to bite, then climbs back up.

## Height above the ground it dives to (about a player's head).
@export var dive_height: float = 1.3


func on_state_changed(enemy: Enemy, state: StringName) -> void:
	if not enemy.multiplayer.is_server():
		return
	enemy.altitude_override = dive_height if state == &"attack_melee" else -1.0
