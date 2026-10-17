extends Node3D
## Voice proof scene (run alone with F6). A grey room where you can hear yourself and others.
##
## Keys (while walking around):
##   F  = Fly voice on/off for yourself (everyone in the game hears the change)
##   L  = loopback on/off: hear your own voice (with your effects) as if through headphones
##   K  = echo dummy on/off: your own voice plays from the dummy in the room, so you can walk
##        away from it and hear yourself fade out, and go silent past the max distance
##   P  = switch between open mic and push-to-talk (hold V to talk)
## Buttons at the top host/join (click them before clicking into the game, or press Esc first).
## Launch options after "--": "host", "join", "port=7790".

const FLY_SOURCE: StringName = &"test_fly"
const FLY_PITCH: float = 1.5
const FLY_PRESET: StringName = &"buzz"
const FLY_STRENGTH: float = 0.6
const DUMMY_POSITION: Vector3 = Vector3(0, 0, -6)

var _fly_on: Dictionary[int, bool] = {}
var _echo_on: bool = false
var _dummy_head: Node3D
var _overview: Camera3D
var _status: Label
var _meter: ProgressBar
var _speakers: Label


func _ready() -> void:
	_build_world()
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 14, 14)
	_overview.rotation_degrees = Vector3(-45, 0, 0)
	add_child(_overview)
	_build_ui()
	_run_launch_options.call_deferred()


func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = 7777
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			port = arg.trim_prefix("port=").to_int()
	if args.has("host"):
		SteamSession.host_local(port)
	elif args.has("join"):
		SteamSession.join_local("127.0.0.1", port)


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	_meter.value = Voice.get_input_level()
	var me: int = Net.local_player_id()
	_status.text = "%s | players: %d | mic: %s | loopback: %s | echo dummy: %s | my Fly voice: %s" % [
		"HOST" if Net.is_host() else "CLIENT", Net.get_player_count(),
		"push-to-talk (hold V)" if Voice.is_push_to_talk() else "open mic",
		_on_off(Voice.is_loopback() and not _echo_on), _on_off(_echo_on), _on_off(_fly_on.get(me, false))]
	var lines: PackedStringArray = ["Players (speaking shows ((( ))) ):"]
	for player_id: int in Net.get_player_ids():
		var speaking: String = "  ((( talking )))" if Voice.is_speaking(player_id) else ""
		var fly: String = "  [Fly]" if _fly_on.get(player_id, false) else ""
		lines.append("  %s%s%s%s" % [Net.get_display_name(player_id), " (you)" if player_id == me else "", fly, speaking])
	_speakers.text = "\n".join(lines)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F:
			_toggle_fly(Net.local_player_id())
		KEY_L:
			_echo_on = false
			Voice.set_loopback(not Voice.is_loopback())
		KEY_K:
			_echo_on = not _echo_on
			Voice.set_loopback(_echo_on, _dummy_head if _echo_on else null)
		KEY_P:
			Voice.set_push_to_talk(not Voice.is_push_to_talk())


## Asks every PC (including this one) to switch Fly voice for a player.
func _toggle_fly(player_id: int) -> void:
	_set_fly.rpc(player_id, not _fly_on.get(player_id, false))


## STUB for upgrades: in the game, upgrades calls Voice.set_voice_effect on every PC.
@rpc("any_peer", "call_local", "reliable")
func _set_fly(player_id: int, enabled: bool) -> void:
	_fly_on[player_id] = enabled
	if enabled:
		var fly := VoiceEffectData.new()
		fly.pitch_scale = FLY_PITCH
		fly.effect_preset = FLY_PRESET
		fly.effect_strength = FLY_STRENGTH
		Voice.set_voice_effect(player_id, FLY_SOURCE, fly)
	else:
		Voice.clear_voice_effect(player_id, FLY_SOURCE)


func _on_off(value: bool) -> String:
	return "ON" if value else "off"


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.5, 0.56, 0.64)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	# A long floor so you can walk well past the 30 m silence distance.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.52)
	box_mesh.material = material
	mesh.mesh = box_mesh
	floor_body.add_child(mesh)
	floor_body.position = Vector3(0, -0.5, 30)
	add_child(floor_body)
	# Distance markers every 10 m.
	for metres: int in [10, 20, 30, 40, 50, 60]:
		var marker := Label3D.new()
		marker.text = "%d m from the dummy" % metres
		marker.font_size = 64
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.position = DUMMY_POSITION + Vector3(0, 1.5, float(metres))
		add_child(marker)
	# The echo dummy.
	var dummy := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	var dummy_material := StandardMaterial3D.new()
	dummy_material.albedo_color = Color(0.95, 0.75, 0.2)
	capsule.material = dummy_material
	dummy.mesh = capsule
	dummy.position = DUMMY_POSITION + Vector3(0, 1.0, 0)
	add_child(dummy)
	_dummy_head = Node3D.new()
	_dummy_head.position = Vector3(0, 0.6, 0)
	dummy.add_child(_dummy_head)
	var dummy_label := Label3D.new()
	dummy_label.text = "Echo dummy (press K)"
	dummy_label.font_size = 48
	dummy_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dummy_label.position = Vector3(0, 1.4, 0)
	dummy.add_child(dummy_label)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_button(row, "Host local", func() -> void: SteamSession.host_local())
	_add_button(row, "Join local", func() -> void: SteamSession.join_local())
	_add_button(row, "Host (Steam)", SteamSession.host_lobby)
	_add_button(row, "Invite", SteamSession.open_invite_overlay)
	_add_button(row, "Leave", SteamSession.leave_lobby)
	_status = Label.new()
	column.add_child(_status)
	var meter_row := HBoxContainer.new()
	column.add_child(meter_row)
	var meter_label := Label.new()
	meter_label.text = "Mic level: "
	meter_row.add_child(meter_label)
	_meter = ProgressBar.new()
	_meter.max_value = 1.0
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(200, 16)
	meter_row.add_child(_meter)
	var help := Label.new()
	help.text = "F = Fly voice   L = hear yourself   K = echo dummy   P = open mic / push-to-talk (hold V)"
	column.add_child(help)
	_speakers = Label.new()
	column.add_child(_speakers)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
