extends Node3D
## Test scene for damage (run alone with F6). A room with a red dummy (100 health, fire does double)
## and buttons (look at one and press E; the host checks it and applies the damage):
##   back row: hit the dummy (blunt 10, sharp 20 on its weak head spot = x2), set it on fire, revive it
##   front row: hurt yourself (25), set yourself on fire, speed boost (x1.5 move_speed stat), heal yourself
## The dummy's health floats above it; yours is in the top-left corner. Use 2 windows (Esc > Host local /
## Join local) to check every PC sees the same numbers. Console (`): hurt, heal, god, status, revive.
## Launch options after "--": "host", "join", "port=7790".

const DUMMY_FIRE_MULTIPLIER: float = 2.0

var _overview: Camera3D
var _prompt: Label
var _mine: Label
var _log: Label
var _dummy: StaticBody3D
var _dummy_label: Label3D


func _ready() -> void:
	_build_world()
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 12, 10)
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
	# STUB (ui HUD shows prompts only in the game world): the prompt.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	# STUB (ui HUD health bar): your own health and statuses.
	var me: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	var health: HealthComponent = HealthComponent.of(me) if me != null else null
	if health == null:
		_mine.text = ""
	else:
		var statuses: StatusEffectComponent = StatusEffectComponent.of(me)
		_mine.text = "Your health: %d / %d %s\nSpeed x%.1f" % [roundi(health.get_current()), roundi(health.get_max()),
			str(statuses.get_active()) if statuses != null and not statuses.get_active().is_empty() else "",
			StatsComponent.of(me).get_value(&"move_speed", 1.0)]
	var dummy: HealthComponent = HealthComponent.of(_dummy)
	var dummy_statuses: StatusEffectComponent = StatusEffectComponent.of(_dummy)
	_dummy_label.text = "DUMMY %d / %d%s" % [roundi(dummy.get_current()), roundi(dummy.get_max()),
		" (DEAD)" if dummy.is_dead() else (" (burning)" if dummy_statuses.has_status(&"status_burning") else "")]


## Host only (Interactable.used fires on the host).
func _on_used(player_id: int, action: StringName) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var dummy: HealthComponent = HealthComponent.of(_dummy)
	match action:
		&"blunt":
			var info := DamageInfo.make(10.0, &"blunt")
			info.source_player_id = player_id
			Damage.hit(_dummy.get_node("Hurtbox"), info)
		&"sharp_head":
			var info := DamageInfo.make(20.0, &"sharp")
			info.source_player_id = player_id
			Damage.hit(_dummy.get_node("HeadHurtbox"), info)
		&"burn_dummy":
			StatusEffectComponent.of(_dummy).apply(&"status_burning", player_id)
		&"revive_dummy":
			dummy.revive()
		&"hurt_me":
			if body != null:
				var info := DamageInfo.make(25.0, &"blunt")
				info.knockback = Vector3(0, 3, 4)
				Damage.hit(body, info)
		&"burn_me":
			if body != null:
				StatusEffectComponent.of(body).apply(&"status_burning", player_id)
		&"speed_me":
			if body != null:
				StatusEffectComponent.of(body).apply(&"status_speed_boost", player_id)
		&"heal_me":
			if body != null:
				HealthComponent.of(body).heal(100.0)
	_announce.rpc(Net.get_display_name(player_id), String(action))


@rpc("authority", "call_local", "reliable")
func _announce(player_name: String, action: String) -> void:
	if not is_inside_tree():
		return
	_log.text = "%s pressed %s (the host checked it)\n%s" % [player_name, action, _log.text.left(400)]


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.32, 0.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.5, -2)
	lamp.omni_range = 14.0
	lamp.light_energy = 2.0
	add_child(lamp)
	_add_box(Vector3(0, -0.5, -2), Vector3(16, 1, 16), Color(0.45, 0.46, 0.5), PhysicsLayers.WORLD)
	_add_box(Vector3(0, 2, -10.2), Vector3(16, 4, 0.4), Color(0.55, 0.55, 0.6), PhysicsLayers.WORLD)
	_add_box(Vector3(-8.2, 2, -2), Vector3(0.4, 4, 16), Color(0.55, 0.55, 0.6), PhysicsLayers.WORLD)
	_add_box(Vector3(8.2, 2, -2), Vector3(0.4, 4, 16), Color(0.55, 0.55, 0.6), PhysicsLayers.WORLD)
	_add_box(Vector3(0, 2, 6.2), Vector3(16, 4, 0.4), Color(0.55, 0.55, 0.6), PhysicsLayers.WORLD)

	# The dummy: health with fire x2, a body hurtbox and a head hurtbox (x2, a weak spot).
	_dummy = _add_box(Vector3(0, 0.9, -8), Vector3(0.7, 1.8, 0.7), Color(0.8, 0.25, 0.2), PhysicsLayers.WORLD)
	_dummy.name = "Dummy"
	DamageService.give_components(_dummy, 100.0, 0.5, 1.8)
	(_dummy.get_node("Hurtbox") as Node3D).position.y = -0.9
	HealthComponent.of(_dummy).damage_multipliers = {"fire": DUMMY_FIRE_MULTIPLIER}
	var head := Hurtbox.new()
	head.name = "HeadHurtbox"
	head.multiplier = 2.0
	var head_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	head_shape.shape = sphere
	head_shape.position.y = 1.2
	head.add_child(head_shape)
	_dummy.add_child(head)
	_dummy_label = Label3D.new()
	_dummy_label.font_size = 48
	_dummy_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_dummy_label.position = Vector3(0, 1.6, 0)
	_dummy.add_child(_dummy_label)

	var buttons: Array[Array] = [
		[&"blunt", Vector3(-3, 1.3, -5.5), Color(0.7, 0.7, 0.7), "Hit the dummy (blunt 10)"],
		[&"sharp_head", Vector3(-1, 1.3, -5.5), Color(0.9, 0.9, 0.3), "Hit its head (sharp 20, weak spot x2)"],
		[&"burn_dummy", Vector3(1, 1.3, -5.5), Color(1, 0.5, 0.1), "Set the dummy on fire (fire x2)"],
		[&"revive_dummy", Vector3(3, 1.3, -5.5), Color(0.3, 0.9, 0.4), "Revive the dummy"],
		[&"hurt_me", Vector3(-3, 1.3, -3), Color(0.8, 0.2, 0.2), "Hurt me (25, with a push)"],
		[&"burn_me", Vector3(-1, 1.3, -3), Color(1, 0.5, 0.1), "Set me on fire"],
		[&"speed_me", Vector3(1, 1.3, -3), Color(0.3, 0.6, 1), "Speed boost (6 s)"],
		[&"heal_me", Vector3(3, 1.3, -3), Color(0.3, 0.9, 0.4), "Heal me"],
	]
	for entry: Array in buttons:
		var action: StringName = entry[0]
		var where: Vector3 = entry[1]
		var color: Color = entry[2]
		var prompt: String = entry[3]
		var usable := _add_usable(String(action), where, color, prompt)
		usable.used.connect(_on_used.bind(action))


func _add_usable(node_name: String, where: Vector3, color: Color, prompt: String) -> Interactable:
	var body := _add_box(where, Vector3(0.6, 0.6, 0.3), color, PhysicsLayers.INTERACTABLES)
	body.name = node_name
	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_text = prompt
	body.add_child(interactable)
	return interactable


func _add_box(center: Vector3, size: Vector3, color: Color, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.bit(layer)
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
	_mine = Label.new()
	_mine.add_theme_font_size_override("font_size", 22)
	column.add_child(_mine)
	_log = Label.new()
	column.add_child(_log)
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
