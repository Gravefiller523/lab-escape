extends Node3D
## The scene the host sits in for a moment while everyone changes scene (see GameFlow._transition).
## A dark backdrop with "Loading..." in the middle.


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.09, 0.11)
	add_child(environment)
	add_child(Camera3D.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "Loading..."
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", 32)
	layer.add_child(label)
