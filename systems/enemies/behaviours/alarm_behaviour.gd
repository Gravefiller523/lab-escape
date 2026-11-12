class_name AlarmBehaviour
extends EnemyBehaviour
## NEW 2026-11-12 (roadmap WP11): a watcher (Robotics' flock camera). When it notices a player it sounds the alarm:
## every other enemy within `alarm_radius` goes after that player, whatever kind it is. Host only.

## How far (m) the alarm reaches.
@export var alarm_radius: float = 18.0
## Seconds before it can sound the alarm again.
@export var cooldown_seconds: float = 8.0

var _ready_at_msec: int = 0


func _ready() -> void:
	var enemy := get_parent() as Enemy
	if enemy != null:
		enemy.noticed.connect(_on_noticed.bind(enemy))


func _on_noticed(player: PlayerCharacter, enemy: Enemy) -> void:
	if not enemy.multiplayer.is_server() or Time.get_ticks_msec() < _ready_at_msec:
		return
	_ready_at_msec = Time.get_ticks_msec() + int(cooldown_seconds * 1000.0)
	sound_alarm(enemy, player)


## Host: every other enemy within alarm_radius goes after `player`. Returns how many were told.
func sound_alarm(enemy: Enemy, player: PlayerCharacter) -> int:
	var told: int = 0
	for node: Node in enemy.get_tree().get_nodes_in_group(Enemy.GROUP):
		var other := node as Enemy
		if other == null or other == enemy or other.is_dead():
			continue
		if other.global_position.distance_to(enemy.global_position) > alarm_radius:
			continue
		other.alert_to(player)
		told += 1
	return told
