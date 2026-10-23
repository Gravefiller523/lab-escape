extends Node3D
## Test scene for bosses (run alone with F6): a hand-built 24 x 24 m arena with one doorway, two minion
## spawn spots and the Giant Rat. Walk in through the doorway: the fight starts, and once everyone is
## inside the doorway is barred until the rat is beaten.
## Keys: F1 damage the boss 10%, F2 a new boss, F7 players invisible, F10 give yourself a crowbar.
## Use 2 windows (Esc > Host local / Join local). Launch options after "--": "host", "join", "port=7790".

const BOSS_ID: StringName = &"boss_giant_rat"
const ARENA_SIZE: float = 24.0

var _overview: Camera3D
var _prompt: Label
var _info: Label
var _arena: BossArena


func _ready() -> void:
	_build_world()
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var start := Marker3D.new()
	start.name = "Start"
	start.position = Vector3(12, 0.1, 8)
	add_child(start)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_points = [start]
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(12, 22, 30)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	_build_ui()
	_start.call_deferred()
	_run_launch_options.call_deferred()


func _start() -> void:
	Enemies.bake_navigation(self)
	if multiplayer.is_server():
		_spawn_boss()


func _spawn_boss() -> void:
	if multiplayer.is_server() and (Boss.current() == null or Boss.current().is_queued_for_deletion()):
		Bosses.spawn(BOSS_ID, Transform3D(Basis.IDENTITY, Vector3(12, 0.2, -18)))


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
	var actions: Dictionary[Key, StringName] = {KEY_F1: &"damage", KEY_F2: &"new_boss", KEY_F7: &"invisible",
		KEY_F10: &"crowbar"}
	if actions.has(key.keycode):
		_request_rpc.rpc_id(1, actions[key.keycode])
		get_viewport().set_input_as_handled()


## Anyone -> host: a test action.
@rpc("any_peer", "call_local", "reliable")
func _request_rpc(action: StringName) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var player_id: int = Net.get_player_id_for_peer(sender) if sender > 1 else Net.local_player_id()
	var boss: Boss = Boss.current()
	match action:
		&"damage":
			if boss != null:
				var info := DamageInfo.make(boss.get_health().get_max() * 0.1, &"blunt")
				info.source_player_id = player_id
				boss.get_health().apply_damage(info)
		&"new_boss":
			_spawn_boss()
		&"invisible":
			_set_invisible.rpc(not Perception.players_invisible)
		&"crowbar":
			var inventory: InventoryComponent = InventoryComponent.of(PlayerCharacter.find(player_id))
			if inventory != null:
				inventory.pick_up(&"item_crowbar")


@rpc("authority", "call_local", "reliable")
func _set_invisible(invisible: bool) -> void:
	if is_inside_tree():
		Perception.players_invisible = invisible


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	var me: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	var health: HealthComponent = HealthComponent.of(me) if me != null else null
	var boss: Boss = Boss.current()
	_info.text = "Your health %d   Boss phase %s   Doors %s   Minions %d   Invisible: %s" % [
		roundi(health.get_current()) if health != null else 0,
		str(boss.get_phase() + 1) if boss != null and boss.get_phase() >= 0 else "-",
		"LOCKED" if _arena != null and _arena.is_locked() else "open",
		maxi(Enemies.get_alive().size() - (1 if boss != null else 0), 0),
		"yes" if Perception.players_invisible else "no"]


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.25, 0.22, 0.24)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.5, 0.5)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var grey := Color(0.5, 0.48, 0.5)
	# A corridor in front of the doorway (south, +z), then the arena (x 0..24, z -24..0).
	_add_box(Vector3(12, -0.5, -6), Vector3(30, 1, 40), Color(0.42, 0.4, 0.42))
	var room := Node3D.new()
	room.name = "Arena"
	room.position = Vector3(0, 0, -ARENA_SIZE)
	add_child(room)
	for wall: Array in [[Vector3(12, 2, -ARENA_SIZE - 0.2), Vector3(ARENA_SIZE, 4, 0.4)],
			[Vector3(-0.2, 2, -12), Vector3(0.4, 4, ARENA_SIZE)], [Vector3(ARENA_SIZE + 0.2, 2, -12), Vector3(0.4, 4, ARENA_SIZE)],
			[Vector3(5.5, 2, 0.2), Vector3(11, 4, 0.4)], [Vector3(18.5, 2, 0.2), Vector3(11, 4, 0.4)]]:
		var center: Vector3 = wall[0]
		var size: Vector3 = wall[1]
		_add_box(center, size, grey)
	var doorway := RoomDoorway.new()
	doorway.name = "DoorSouth"
	doorway.width = 2.0
	doorway.position = Vector3(12, 0, ARENA_SIZE)
	room.add_child(doorway)
	for index: int in 2:
		var marker := RoomMarker.new()
		marker.name = "MinionSpawn%d" % index
		marker.kind = &"minion_spawn"
		marker.position = Vector3(4.0 + 16.0 * float(index), 0, 4)
		room.add_child(marker)
	_arena = BossArena.new()
	_arena.setup(room, Vector2(ARENA_SIZE, ARENA_SIZE))
	room.add_child(_arena)


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
	help.text = "Walk north through the doorway into the arena.\n" \
		+ "F1 damage the boss 10%   F2 new boss   F7 players invisible   F10 crowbar   Left click: attack"
	column.add_child(help)
	_info = Label.new()
	column.add_child(_info)
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
