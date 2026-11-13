extends Node
## NEW 2026-11-12 (roadmap WP11, decision D4): the Magnet Hand cybernetic's rule. Host: loose gems within `radius`
## are tugged towards you (they roll and tumble over; you still pick them up yourself). Params: radius (6 m),
## strength (14: metres per second added each second, scaled by the gem's mass; it has to beat the floor's
## friction). Added under the player's body.

const TUG_SECONDS: float = 0.1
## A little upward pull, so a gem hops along instead of scraping on the floor.
const LIFT: float = 0.25

var _body: PlayerCharacter
var _left: float = 0.0


func _ready() -> void:
	_body = get_parent() as PlayerCharacter


func _physics_process(delta: float) -> void:
	if _body == null or not multiplayer.is_server() or _body.is_ghost():
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = TUG_SECONDS
	tug()


## Host: one tug on every loose gem in reach. Returns how many were tugged.
func tug() -> int:
	var radius: float = UpgradeBehaviourParams.number(self, "radius", 6.0)
	var strength: float = UpgradeBehaviourParams.number(self, "strength", 14.0)
	var count: int = 0
	for prop: NetProp in Props.get_props():
		if prop.data == null or prop.data.gem_value <= 0 or prop.is_held() or prop.is_attached():
			continue
		var offset: Vector3 = _body.global_position + Vector3.UP * 0.5 - prop.global_position
		if offset.length() > radius or offset.length() < 0.6:
			continue
		Props.apply_impulse(prop, (offset.normalized() + Vector3.UP * LIFT).normalized() * strength * TUG_SECONDS * prop.mass)
		count += 1
	return count
