extends Node
## NEW 2026-11-12 (roadmap WP11, decision D4): the Night-Vision Eye cybernetic's rule. Only on your own PC: a soft
## green light at your eyes lights up dark, damaged rooms for you (nobody else sees it). Params: range (14 m),
## energy (0.8). Added under the player's body on every PC; only the owner's copy makes the light.

const LIGHT_COLOR: Color = Color(0.55, 1.0, 0.6)

var light: OmniLight3D


func _ready() -> void:
	var body := get_parent() as PlayerCharacter
	if body == null or not body.is_local():
		return
	light = OmniLight3D.new()
	light.name = "NightVision"
	light.light_color = LIGHT_COLOR
	light.omni_range = UpgradeBehaviourParams.number(self, "range", 14.0)
	light.light_energy = UpgradeBehaviourParams.number(self, "energy", 0.8)
	light.shadow_enabled = false
	light.position = Vector3.UP * 1.6
	body.add_child.call_deferred(light)


func _exit_tree() -> void:
	if light != null and is_instance_valid(light):
		light.queue_free()
