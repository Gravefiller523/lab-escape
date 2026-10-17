class_name MicSensitivityPanel
extends VBoxContainer
## A "Mic sensitivity" slider with a live mic level bar. The white line on the bar is the
## threshold: talking that reaches past it is sent (open mic). Push-to-talk ignores the threshold.
## Other systems' menus can add one with MicSensitivityPanel.new(). While it is on screen the mic
## is switched on for the meter only (nothing is sent or recorded).

const METER_HEIGHT: float = 14.0
const THRESHOLD_LINE_WIDTH: float = 3.0

var _slider: HSlider
var _value_label: Label
var _meter: ProgressBar
var _threshold_line: ColorRect
var _sending_label: Label


func _ready() -> void:
	var title_row := HBoxContainer.new()
	add_child(title_row)
	var title := Label.new()
	title.text = "Mic sensitivity"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_value_label = Label.new()
	title_row.add_child(_value_label)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = Voice.get_mic_sensitivity()
	_slider.custom_minimum_size = Vector2(260, 24)
	_slider.value_changed.connect(_on_slider_changed)
	add_child(_slider)

	_meter = ProgressBar.new()
	_meter.max_value = 1.0
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(260, METER_HEIGHT)
	add_child(_meter)
	_threshold_line = ColorRect.new()
	_threshold_line.color = Color.WHITE
	_threshold_line.size = Vector2(THRESHOLD_LINE_WIDTH, METER_HEIGHT)
	_meter.add_child(_threshold_line)

	_sending_label = Label.new()
	add_child(_sending_label)
	_on_slider_changed(_slider.value)
	visibility_changed.connect(_update_mic_test)
	_update_mic_test()


func _exit_tree() -> void:
	Voice.set_mic_test(false)


func _process(_delta: float) -> void:
	# Follow changes made elsewhere (e.g. keys in a test scene).
	if not is_equal_approx(_slider.value, Voice.get_mic_sensitivity()):
		_slider.set_value_no_signal(Voice.get_mic_sensitivity())
		_value_label.text = "%d%%" % int(Voice.get_mic_sensitivity() * 100.0)
	_meter.value = Voice.get_input_level()
	_threshold_line.position.x = Voice.get_threshold_meter_position() * _meter.size.x - THRESHOLD_LINE_WIDTH / 2.0
	if Voice.is_push_to_talk():
		_sending_label.text = "Push-to-talk: hold V to talk (sensitivity doesn't matter)"
	elif Voice.get_input_level() >= Voice.get_threshold_meter_position():
		_sending_label.text = "Your voice is being picked up"
	else:
		_sending_label.text = "Talk until the bar passes the white line"


func _on_slider_changed(value: float) -> void:
	Voice.set_mic_sensitivity(value)
	_value_label.text = "%d%%" % int(value * 100.0)


func _update_mic_test() -> void:
	Voice.set_mic_test(is_visible_in_tree())
