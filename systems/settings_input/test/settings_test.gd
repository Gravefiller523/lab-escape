extends Node3D
## Test scene (F6): the Settings screen on its own. Change things, close the game, run it again: they stay.
## Esc or Back closes it; press F1 to open it again.


func _ready() -> void:
	Settings.open(&"")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.physical_keycode == KEY_F1 and not UI.is_screen_open():
		Settings.open(&"")
