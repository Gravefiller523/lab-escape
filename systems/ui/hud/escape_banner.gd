class_name EscapeBanner
extends Control
## The escape (NEW 2026-11-13, roadmap WP19, mock-up approved by Zachary). Two parts, both on every PC:
## - a white light that fills the screen while the lift rides up after the last boss (run_ended "escaped"), and fades
##   away when it comes out in the car park (EventBus.surface_reached);
## - "YOU ESCAPED" in big letters for Config.game.escape_banner_seconds once you are out.
## Spec: docs/systems/ui.md.

const FADE_OUT_SECONDS: float = 1.5
const BANNER_FONT_SIZE: int = 72

var _white: ColorRect
var _title: Label
var _fading_in: bool = false
var _fade_left: float = 0.0
var _banner_left: float = 0.0


## How white the screen is now (0 to 1).
func get_whiteness() -> float:
	return _white.color.a


## The big text on screen now ("" when hidden).
func get_text() -> String:
	return _title.text if _title.visible else ""


## Is "YOU ESCAPED" (or the light before it) still showing? The run summary waits for it.
func is_busy() -> bool:
	return _fading_in or _banner_left > 0.0


func _ready() -> void:
	name = "EscapeBanner"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white = ColorRect.new()
	_white.name = "White"
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.color = Color(1, 1, 1, 0)
	add_child(_white)
	_title = HudStyle.label("Title", BANNER_FONT_SIZE)
	_title.text = "YOU ESCAPED"
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", HudStyle.GOOD)
	_title.visible = false
	add_child(_title)
	EventBus.run_ended.connect(func(result: StringName) -> void:
		if result == GameFlowService.RESULT_ESCAPED:
			start_ride())
	EventBus.surface_reached.connect(arrive)
	EventBus.run_started.connect(func(_run_seed: int) -> void: _reset())


## The lift starts up for the last time: the light begins to fill the screen.
func start_ride() -> void:
	_fading_in = true
	_fade_left = maxf(Config.game.lift_ride_seconds, 0.1)
	_banner_left = 0.0
	_title.visible = false


## Out in the car park: the light fades and the big words show.
func arrive() -> void:
	_fading_in = false
	_fade_left = FADE_OUT_SECONDS
	_banner_left = Config.game.escape_banner_seconds
	_title.visible = true


func _reset() -> void:
	_fading_in = false
	_fade_left = 0.0
	_banner_left = 0.0
	_white.color.a = 0.0
	_title.visible = false


func _process(delta: float) -> void:
	if _fading_in:
		_fade_left = maxf(_fade_left - delta, 0.0)
		_white.color.a = 1.0 - _fade_left / maxf(Config.game.lift_ride_seconds, 0.1)
	elif _white.color.a > 0.0:
		_fade_left = maxf(_fade_left - delta, 0.0)
		_white.color.a = _fade_left / FADE_OUT_SECONDS
	if _banner_left > 0.0:
		_banner_left -= delta
		_title.modulate.a = clampf(_banner_left / 0.5, 0.0, 1.0)
		if _banner_left <= 0.0:
			_title.visible = false
