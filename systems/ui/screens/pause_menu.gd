extends Control
## The small Esc menu: Resume, Leave game, Quit. The game keeps running for everyone else.
## Settings come later with settings_input.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.55)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(300, 0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	var title := Label.new()
	title.text = "Paused (the game keeps going for others)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_add_button(column, "Resume", UI.close_screen)
	_add_button(column, "Leave game", UI.leave_game)
	_add_button(column, "Quit", func() -> void: get_tree().quit())


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)
