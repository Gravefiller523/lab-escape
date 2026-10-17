extends Node3D
## The game's start scene (Project Settings > Run > Main Scene): a dark backdrop with the main menu
## on top. STUB: game_flow will own the start scene later; for now it only opens the main menu.


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.17)
	add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 4)
	add_child(camera)
	UI.show_screen(UIService.SCREEN_MAIN_MENU)
