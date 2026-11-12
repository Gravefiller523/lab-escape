extends Node
## NEW 2026-11-12 (roadmap WP10): the Photosynthesis mutation's rule. Host: once you haven't been hurt for a while,
## you slowly heal (like a plant in the light). Params: heal_per_second (1), calm_seconds (4). Added under the
## player's body by the upgrade's BehaviourEffectData.

var _body: PlayerCharacter
var _health: HealthComponent
var _last: float = 0.0
var _calm_for: float = 0.0


func _ready() -> void:
	_body = get_parent() as PlayerCharacter


func _physics_process(delta: float) -> void:
	if _body == null or not multiplayer.is_server():
		return
	if _health == null:
		_health = HealthComponent.of(_body)
		if _health == null:
			return
		_last = _health.get_current()
	var current: float = _health.get_current()
	_calm_for = 0.0 if current < _last else _calm_for + delta
	_last = current
	if _health.is_dead() or _calm_for < UpgradeBehaviourParams.number(self, "calm_seconds", 4.0):
		return
	if current < _health.get_max():
		_health.heal(UpgradeBehaviourParams.number(self, "heal_per_second", 1.0) * delta)
		_last = _health.get_current()
