class_name AttackTickets
extends RefCounted
## NEW 2026-10-30 (HL2 feel step 3.4): who may attack whom right now, like Half-Life 2's squad slots.
## Each player has Config.feel.ai.attack_tickets_per_player tickets. An enemy must hold enough of a
## player's tickets (EnemyData.attack_tickets) to start an attack on them; the rest circle and wait, so
## only a couple of enemies bite at once and fights stay readable. Host only (the AI runs there), so
## nothing is synced. Tickets are handed back after an attack, when the holder dies or leaves, or after
## Config.feel.ai.ticket_max_hold seconds.

## Player instance id -> Array of holds: {"enemy": enemy instance id, "count": tickets, "until": seconds}.
static var _holds: Dictionary[int, Array] = {}
## Player instance id -> when (seconds) the last ticket for them was given out.
static var _last_grant: Dictionary[int, float] = {}


## Host: try to take `enemy`'s tickets for `player`. True if it holds them now. If it already did, its hold
## starts again (an attack that is under way keeps its tickets).
static func claim(enemy: Enemy, player: PlayerCharacter) -> bool:
	if enemy == null or player == null:
		return false
	var key: int = player.get_instance_id()
	var now: float = _now()
	var held: Array = _tidy(key, now)
	var tuning: AiTuning = Config.feel.ai
	for hold: Dictionary in held:
		if hold["enemy"] == enemy.get_instance_id():
			hold["until"] = now + tuning.ticket_max_hold
			return true
	var wanted: int = maxi(enemy.data.attack_tickets if enemy.data != null else 1, 1)
	var used: int = 0
	for hold: Dictionary in held:
		used += int(hold["count"])
	if used + wanted > maxi(tuning.attack_tickets_per_player, wanted):
		return false
	if now - float(_last_grant.get(key, -1000.0)) < tuning.ticket_grant_gap:
		return false
	release(enemy)
	held = _tidy(key, now)
	held.append({"enemy": enemy.get_instance_id(), "count": wanted, "until": now + tuning.ticket_max_hold})
	_holds[key] = held
	_last_grant[key] = now
	return true


## Host: hand back whatever tickets `enemy` holds.
static func release(enemy: Enemy) -> void:
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	for key: int in _holds.keys():
		var kept: Array = []
		for hold: Dictionary in _holds[key]:
			if hold["enemy"] != id:
				kept.append(hold)
		_holds[key] = kept


## Does `enemy` hold tickets for `player` right now?
static func holds(enemy: Enemy, player: PlayerCharacter) -> bool:
	if enemy == null or player == null:
		return false
	for hold: Dictionary in _tidy(player.get_instance_id(), _now()):
		if hold["enemy"] == enemy.get_instance_id():
			return true
	return false


## How many of `player`'s tickets are taken.
static func used_for(player: PlayerCharacter) -> int:
	var used: int = 0
	if player != null:
		for hold: Dictionary in _tidy(player.get_instance_id(), _now()):
			used += int(hold["count"])
	return used


## Tests: forget everything.
static func clear() -> void:
	_holds.clear()
	_last_grant.clear()


## The player's holds without expired ones or ones whose enemy is gone or dead.
static func _tidy(key: int, now: float) -> Array:
	var kept: Array = []
	for hold: Dictionary in _holds.get(key, []):
		var holder := instance_from_id(int(hold["enemy"])) as Enemy
		if holder != null and not holder.is_dead() and float(hold["until"]) > now:
			kept.append(hold)
	_holds[key] = kept
	return kept


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
