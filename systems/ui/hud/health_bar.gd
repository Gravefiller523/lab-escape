class_name HealthBar
extends VBoxContainer
## Your health (bottom left of the HUD) with your status effects above it ("Burning 3s"). NEW 2026-11-11 (roadmap WP5).
## Reads the local body's HealthComponent and StatusEffectComponent (damage). Spec: docs/systems/ui.md.

const BAR_SIZE: Vector2 = Vector2(260, 18)
## Below these fractions the bar turns amber, then red.
const WARN_FRACTION: float = 0.5
const BAD_FRACTION: float = 0.25

var _statuses: HBoxContainer
var _value: Label
var _bar: ProgressBar
var _body: Node
var _use_test_body: bool = false


## For tests only: show this body's health instead of the local player's.
func use_body(body: Node) -> void:
	_body = body
	_use_test_body = true


## "72 / 100", or "" when hidden.
func get_text() -> String:
	return _value.text if visible else ""


## The status chips on show, e.g. ["Burning 3s"].
func get_status_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for child: Node in _statuses.get_children():
		texts.append((child as Label).text)
	return texts


func _ready() -> void:
	name = "HealthBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_statuses = HBoxContainer.new()
	_statuses.name = "Statuses"
	_statuses.add_theme_constant_override("separation", 6)
	_statuses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_statuses)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title: Label = HudStyle.label("Title")
	title.text = "Health"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_value = HudStyle.label("Value")
	row.add_child(_value)
	add_child(row)
	_bar = HudStyle.bar("Bar", BAR_SIZE, HudStyle.GOOD)
	add_child(_bar)


func _process(_delta: float) -> void:
	var body: Node = _body if _use_test_body else PlayerCharacter.find(Net.local_player_id())
	var health: HealthComponent = HealthComponent.of(body) if body != null and is_instance_valid(body) else null
	visible = health != null and not health.is_dead()
	if not visible:
		return
	var fraction: float = health.get_fraction()
	_bar.value = fraction
	_value.text = "%d / %d" % [ceili(health.get_current()), roundi(health.get_max())]
	HudStyle.set_bar_color(_bar, HudStyle.BAD if fraction <= BAD_FRACTION else (HudStyle.WARN if fraction <= WARN_FRACTION
		else HudStyle.GOOD))
	_refresh_statuses(StatusEffectComponent.of(body))


func _refresh_statuses(statuses: StatusEffectComponent) -> void:
	var texts := PackedStringArray()
	if statuses != null:
		for status_id: StringName in statuses.get_active():
			var data := ContentRegistry.get_content(status_id) as StatusEffectData
			var title: String = data.display_name if data != null and not data.display_name.is_empty() else String(status_id)
			texts.append("%s %ds" % [title, ceili(statuses.get_time_left(status_id))])
	if texts == get_status_texts():
		return
	for child: Node in _statuses.get_children():
		_statuses.remove_child(child)
		child.queue_free()
	for text: String in texts:
		var chip: Label = HudStyle.label("Status", HudStyle.SMALL_FONT_SIZE)
		chip.text = text
		chip.add_theme_color_override("font_color", HudStyle.WARN)
		_statuses.add_child(chip)
