class_name HurtVignette
extends ColorRect
## The red at the edges of your screen when you get hurt (NEW 2026-11-11, roadmap WP7, mock-up approved by Zachary).
## Starts at Config.feel.hits.hurt_vignette_strength and fades over hurt_vignette_seconds. Reads the local body's
## HealthComponent (damage). Spec: docs/systems/ui.md.

const SHADER_CODE: String = """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	float edge = smoothstep(0.35, 0.75, distance(UV, vec2(0.5)));
	COLOR = vec4(0.8, 0.05, 0.05, edge * strength);
}
"""

var _strength: float = 0.0
var _health: HealthComponent
var _last: float = 0.0
var _body: Node
var _use_test_body: bool = false


## For tests only: watch this body's health instead of the local player's.
func use_body(body: Node) -> void:
	_body = body
	_use_test_body = true


## How red the edges are now (0 to 1).
func get_strength() -> float:
	return _strength


func _ready() -> void:
	name = "HurtVignette"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	material = shader_material
	_apply()


func _process(delta: float) -> void:
	var body: Node = _body if _use_test_body else PlayerCharacter.find(Net.local_player_id())
	var health: HealthComponent = HealthComponent.of(body) if body != null and is_instance_valid(body) else null
	if health != _health:
		_health = health
		_last = health.get_current() if health != null else 0.0
	if health != null:
		var current: float = health.get_current()
		if current < _last and current > 0.0:
			_strength = Config.feel.hits.hurt_vignette_strength
		_last = current
	if _strength > 0.0:
		var seconds: float = maxf(Config.feel.hits.hurt_vignette_seconds, 0.01)
		_strength = maxf(_strength - delta * Config.feel.hits.hurt_vignette_strength / seconds, 0.0)
		_apply()


func _apply() -> void:
	(material as ShaderMaterial).set_shader_parameter(&"strength", _strength)
	visible = _strength > 0.0
