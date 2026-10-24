extends Node3D
## Test scene for audio (run alone with F6). Keys:
##   1 menu music   2 floor music   3 boss music   4 stop music
##   5 every event sound in turn (hit, deaths, item use, reprint, upgrade, purchase, lift, boss)
##   6 200 sounds at once around you (the pool reuses 32 players; the frame rate should stay smooth)
## Every sound is a generated placeholder until real files go into systems/audio/event_sounds.tres.

const EVENTS: Array[StringName] = [&"hit", &"enemy_death", &"player_death", &"item_use", &"reprint", &"upgrade",
	&"purchase", &"lift_arrive", &"lift_part", &"boss_phase", &"boss_defeated"]

var _info: Label
var _next_event: int = 0


func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 4)
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	var help := Label.new()
	help.position = Vector2(12, 12)
	help.text = "1 menu music   2 floor music   3 boss music   4 stop music   5 next event sound   6 200 sounds at once"
	layer.add_child(help)
	_info = Label.new()
	_info.position = Vector2(12, 40)
	layer.add_child(_info)


func _process(_delta: float) -> void:
	_info.text = "FPS %d   3D sounds playing: %d / %d" % [Engine.get_frames_per_second(), Sound.get_playing_3d(),
		Sound.get_pool_size_3d()]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			Sound.play_music(Sound.event_sound(&"menu_music"))
		KEY_2:
			Sound.play_music(Sound.event_sound(&"floor_music"))
		KEY_3:
			Sound.play_music(Sound.event_sound(&"boss_music"))
		KEY_4:
			Sound.stop_music()
		KEY_5:
			var field: StringName = EVENTS[_next_event % EVENTS.size()]
			_next_event += 1
			Sound.play_3d(Sound.event_sound(field), Vector3(0, 1, 0))
			_info.text = "Played: %s" % field
		KEY_6:
			for index: int in 200:
				var angle: float = TAU * float(index) / 200.0
				Sound.play_3d(Sound.event_sound(&"hit"), Vector3(cos(angle) * 6.0, 1.0, sin(angle) * 6.0), -12.0)
		_:
			return
	get_viewport().set_input_as_handled()
