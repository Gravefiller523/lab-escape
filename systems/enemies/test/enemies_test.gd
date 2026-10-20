extends Node3D
## Test scene for enemies (run alone with F6). A grey-box arena with pillars and a back room behind a
## wall with a doorway (enemies path through it). Keys (they spawn in front of you; the host checks):
##   F1 rat   F2 kangaroo   F3 bat   F4 fly   F9 a whole floor's worth (the budget for this many players)
##   F7 players invisible on/off   F8 kill all   F10 give yourself a crowbar
##   [ and ] change the player count used by F9.
## Fight back with your fists or the crowbar (left click). Use 2 windows (Esc > Host local / Join local)
## to check enemies move smoothly on the client. Launch options after "--": "host", "join", "port=7790".

const SPAWN_KEYS: Dictionary[Key, StringName] = {
	KEY_F1: &"enemy_rat", KEY_F2: &"enemy_kangaroo", KEY_F3: &"enemy_bat", KEY_F4: &"enemy_fly",
}
const SPAWN_DISTANCE: float = 6.0

var _overview: Camera3D
var _prompt: Label
var _status: Label
var _info: Label
var _player_count: int = 1
var _floor_count: int = 0


func _ready() -> void:
	_build_world()
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 16, 14)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	_build_ui()
	_bake.call_deferred()
	_run_launch_options.call_deferred()


func _bake() -> void:
	Enemies.bake_navigation(self)


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


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var action: StringName = &""
	if SPAWN_KEYS.has(key.keycode):
		action = SPAWN_KEYS[key.keycode]
	else:
		match key.keycode:
			KEY_F7:
				action = &"invisible"
			KEY_F8:
				action = &"killall"
			KEY_F9:
				action = &"floor"
			KEY_F10:
				action = &"crowbar"
			KEY_BRACKETLEFT:
				_player_count = maxi(_player_count - 1, 1)
			KEY_BRACKETRIGHT:
				_player_count = mini(_player_count + 1, 8)
	if action != &"":
		_request_rpc.rpc_id(1, action, _player_count)
	get_viewport().set_input_as_handled()


## Anyone -> host: a test action.
@rpc("any_peer", "call_local", "reliable")
func _request_rpc(action: StringName, player_count: int) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var player_id: int = Net.get_player_id_for_peer(sender) if sender > 1 else Net.local_player_id()
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	match action:
		&"invisible":
			_set_invisible.rpc(not Perception.players_invisible)
		&"killall":
			DebugConsole.run("killall")
		&"crowbar":
			var inventory: InventoryComponent = InventoryComponent.of(body)
			if inventory != null:
				inventory.pick_up(&"item_crowbar")
		&"floor":
			_floor_count += 1
			var budget: int = RunDifficulty.enemy_budget(1, player_count)
			var plan: Array[StringName] = EnemiesService.plan_spawns(EnemiesService.pool_for(null), 2, budget,
				SeededRng.make(7, &"enemy_spawns", _floor_count))
			for index: int in plan.size():
				var angle: float = TAU * float(index) / float(maxi(plan.size(), 1))
				Enemies.spawn(plan[index], Transform3D(Basis.IDENTITY, Vector3(cos(angle) * 7.0, 0.3, sin(angle) * 7.0 - 2.0)))
			_announce.rpc("A floor for %d players: budget %d, %d enemies" % [player_count, budget, plan.size()])
		_:
			if body == null:
				return
			var forward: Vector3 = body.get_aim_direction()
			forward.y = 0.0
			var spot: Vector3 = body.global_position + forward.normalized() * SPAWN_DISTANCE + Vector3.UP * 0.3
			Enemies.spawn(action, Transform3D(Basis.IDENTITY, spot))


@rpc("authority", "call_local", "reliable")
func _set_invisible(invisible: bool) -> void:
	if is_inside_tree():
		Perception.players_invisible = invisible


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	if is_inside_tree():
		_status.text = text


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var me: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	var health: HealthComponent = HealthComponent.of(me) if me != null else null
	var counts: Dictionary[StringName, int] = {}
	for enemy: Enemy in Enemies.get_alive():
		var id: StringName = enemy.data.id if enemy.data != null else &"?"
		counts[id] = counts.get(id, 0) + 1
	_info.text = ("Your health %d   Players for F9: %d   Invisible: %s   Enemies: %s" % [
		roundi(health.get_current()) if health != null else 0, _player_count,
		"yes" if Perception.players_invisible else "no", str(counts)])


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.32, 0.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var grey := Color(0.55, 0.55, 0.6)
	_add_box(Vector3(0, -0.5, -4), Vector3(24, 1, 28), Color(0.45, 0.46, 0.5))
	_add_box(Vector3(0, 2, 10.2), Vector3(24, 4, 0.4), grey)
	_add_box(Vector3(-12.2, 2, -4), Vector3(0.4, 4, 28), grey)
	_add_box(Vector3(12.2, 2, -4), Vector3(0.4, 4, 28), grey)
	_add_box(Vector3(0, 2, -18.2), Vector3(24, 4, 0.4), grey)
	# The back room's wall with a 2 m doorway in the middle.
	_add_box(Vector3(-6.5, 2, -11), Vector3(11, 4, 0.4), grey)
	_add_box(Vector3(6.5, 2, -11), Vector3(11, 4, 0.4), grey)
	for pillar: Vector3 in [Vector3(-5, 1.5, -4), Vector3(5, 1.5, -4), Vector3(0, 1.5, 3)]:
		_add_box(pillar, Vector3(1.2, 3, 1.2), Color(0.5, 0.5, 0.56))


func _add_box(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
	return body


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var help := Label.new()
	help.text = "F1 rat  F2 kangaroo  F3 bat  F4 fly  F9 a floor's worth  [ ] players for F9\n" \
		+ "F7 players invisible  F8 kill all  F10 crowbar   Left click: attack"
	column.add_child(help)
	_info = Label.new()
	column.add_child(_info)
	_status = Label.new()
	column.add_child(_status)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(300, 80)
	center.add_child(middle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	middle.add_child(_prompt)
