extends Node3D
## Voice proof scene (run alone with F6). Two rooms joined by a hallway (Room A has a door), and a
## long field south of Room B. You start in Room B; the yellow echo dummy stands in Room A.
##
## Keys (while walking around):
##   F  = Fly voice on/off for yourself (everyone in the game hears the change)
##   L  = loopback on/off: hear your own voice (with your effects) as if through headphones
##   K  = echo dummy on/off: your own voice plays from the dummy, so you hear yourself the way
##        others would hear you from there (through walls, round the hallway, fading with distance)
##   J  = move the echo dummy to where you're standing
##   E  = open or close the door (stand next to it)
##   P  = switch between open mic and push-to-talk (hold V to talk)
## Buttons at the top host/join (click them before clicking into the game).
## Launch options after "--": "host", "join", "port=7790".

const FLY_SOURCE: StringName = &"test_fly"
const FLY_PITCH: float = 1.5
const FLY_PRESET: StringName = &"buzz"
const FLY_STRENGTH: float = 0.6
## How close you must be to the door to open or close it (metres).
const DOOR_REACH: float = 3.0
## How much [ and ] change the mic sensitivity.
const SENSITIVITY_STEP: float = 0.05

var _fly_on: Dictionary[int, bool] = {}
var _echo_on: bool = false
var _dummy: Node3D
var _dummy_head: Node3D
var _door: SoundDoor
var _door_body: StaticBody3D
var _overview: Camera3D
var _status: Label
var _hearing_label: Label
var _speakers: Label


func _ready() -> void:
	_build_world()
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	var points: Array[Node3D] = []
	for index: int in 8:
		var point := Marker3D.new()
		point.position = VoiceTestRooms.ROOM_B_CENTER + Vector3(float(index % 4) - 1.5, 0.1, floorf(float(index) / 4.0) * 1.5 - 0.75)
		add_child(point)
		points.append(point)
	spawner.spawn_points = points
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 16, 14)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
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
	var me: int = Net.local_player_id()
	var fly_on: bool = _fly_on.get(me, false)
	_status.text = "%s | players: %d | mic: %s | loopback: %s | echo dummy: %s | Fly: %s | door: %s" % [
		"HOST" if Net.is_host() else "CLIENT", Net.get_player_count(),
		"push-to-talk (hold V)" if Voice.is_push_to_talk() else "open mic",
		_on_off(Voice.is_loopback() and not _echo_on), _on_off(_echo_on), _on_off(fly_on),
		"open" if _door.is_open else "CLOSED"]
	_hearing_label.text = ""
	if _echo_on:
		var hearing: VoiceHearing = Voice.get_hearing(me)
		if hearing != null:
			_hearing_label.text = "Echo dummy: %.0f m away%s | muffled %d%% | volume %.1f%% | reverb %d%% | treble up to %d Hz%s" % [
				hearing.distance, " (the long way round)" if hearing.used_path else "",
				int(hearing.muffle * 100.0), Voice.get_voice_volume(me) * 100.0,
				int(VoiceService.distance_reverb(hearing.distance, Config.game) * 100.0),
				int(VoiceService.voice_cutoff(hearing.muffle, hearing.distance, Config.game)),
				" | through a CLOSED door" if hearing.closed_doors > 0 else ""]
	var lines: PackedStringArray = ["Players (speaking shows ((( talking ))) ):"]
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
			_set_fly.rpc(Net.local_player_id(), not _fly_on.get(Net.local_player_id(), false))
		KEY_L:
			_echo_on = false
			Voice.set_loopback(not Voice.is_loopback())
		KEY_K:
			_echo_on = not _echo_on
			Voice.set_loopback(_echo_on, _dummy_head if _echo_on else null)
		KEY_J:
			var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
			if body != null:
				_dummy.global_position = body.global_position + Vector3(0, 1.0, 0)
		KEY_E:
			var me: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
			if me != null and me.global_position.distance_to(_door.global_position) <= DOOR_REACH:
				_set_door.rpc(not _door.is_open)
		KEY_P:
			Voice.set_push_to_talk(not Voice.is_push_to_talk())
		KEY_BRACKETLEFT:
			Voice.set_mic_sensitivity(Voice.get_mic_sensitivity() - SENSITIVITY_STEP)
		KEY_BRACKETRIGHT:
			Voice.set_mic_sensitivity(Voice.get_mic_sensitivity() + SENSITIVITY_STEP)


## STUB for upgrades: in the game, upgrades calls Voice.set_voice_effect on every PC.
@rpc("any_peer", "call_local", "reliable")
func _set_fly(player_id: int, enabled: bool) -> void:
	if not is_inside_tree():
		return
	_fly_on[player_id] = enabled
	if enabled:
		var fly := VoiceEffectData.new()
		fly.pitch_scale = FLY_PITCH
		fly.effect_preset = FLY_PRESET
		fly.effect_strength = FLY_STRENGTH
		Voice.set_voice_effect(player_id, FLY_SOURCE, fly)
	else:
		Voice.clear_voice_effect(player_id, FLY_SOURCE)


## STUB for the doors system: anyone may open or close the test door, on every PC.
@rpc("any_peer", "call_local", "reliable")
func _set_door(open: bool) -> void:
	if not is_inside_tree():
		return
	_door.is_open = open
	_door_body.collision_layer = 0 if open else PhysicsLayers.bit(PhysicsLayers.WORLD)
	_door_body.visible = not open


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

	_door = VoiceTestRooms.build(self, true, true)
	# The door you can see and bump into. Open (no collision) to start with.
	_door_body = StaticBody3D.new()
	_door_body.position = _door.position
	_door_body.collision_layer = 0
	_door_body.visible = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, VoiceTestRooms.WALL_HEIGHT, 0.2)
	shape.shape = box
	_door_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.35, 0.2)
	box_mesh.material = material
	mesh.mesh = box_mesh
	_door_body.add_child(mesh)
	add_child(_door_body)
	_add_label(_door.position + Vector3(0, 2.0, 0.5), "Door (E)")

	# Distance markers on the field south of Room B.
	for metres: int in [10, 20, 30, 40, 46]:
		_add_label(Vector3(6, 1.5, -4.0 - float(metres)), "%d m from Room B" % metres)

	# The echo dummy, in Room A.
	_dummy = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	var dummy_material := StandardMaterial3D.new()
	dummy_material.albedo_color = Color(0.95, 0.75, 0.2)
	capsule.material = dummy_material
	(_dummy as MeshInstance3D).mesh = capsule
	_dummy.position = VoiceTestRooms.ROOM_A_CENTER + Vector3(0, 1.0, 0)
	add_child(_dummy)
	_dummy_head = Node3D.new()
	_dummy_head.position = Vector3(0, 0.6, 0)
	_dummy.add_child(_dummy_head)
	var dummy_label := Label3D.new()
	dummy_label.text = "Echo dummy (K on/off, J moves it to you)"
	dummy_label.font_size = 40
	dummy_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dummy_label.position = Vector3(0, 1.4, 0)
	_dummy.add_child(dummy_label)
	_add_label(VoiceTestRooms.ROOM_A_CENTER + Vector3(0, 2.6, 0), "Room A")
	_add_label(VoiceTestRooms.ROOM_B_CENTER + Vector3(0, 2.6, 0), "Room B")


func _add_label(where: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = where
	add_child(label)


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
	_hearing_label = Label.new()
	_hearing_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	column.add_child(_hearing_label)
	column.add_child(MicSensitivityPanel.new())
	var help := Label.new()
	help.text = "F Fly voice | L hear yourself | K echo dummy | J move dummy here | E door | P open mic / push-to-talk (hold V)\n[ and ] change mic sensitivity (or drag the slider before clicking into the game)"
	column.add_child(help)
	_speakers = Label.new()
	column.add_child(_speakers)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
