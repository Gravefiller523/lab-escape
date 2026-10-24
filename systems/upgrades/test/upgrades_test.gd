extends Node3D
## Test scene for upgrades (run alone with F6): a glowing gem for each mutation and a robot part (the
## test arm), lined up in front of you. Pick one up (E) and press E again while holding it to eat /
## install it. The prompt names the mutation only once someone has eaten it this run ("???" before).
## Keys: F1 lay out the gems again, F2 lose all your upgrades. Console: upgrade <id>, unupgrade <id>.
## Use 2 windows (Esc > Host local / Join local) to check everyone sees the wings, tentacles and necks.

var _overview: Camera3D
var _prompt: Label
var _info: Label


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.32, 0.36)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(environment)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	floor_body.add_child(mesh)
	floor_body.position.y = -0.5
	add_child(floor_body)
	# A wall to try Octo against, and a low doorway for the Giraffe.
	_add_wall(Vector3(-6, 2, -6), Vector3(0.4, 4, 6))
	_add_wall(Vector3(5, 2.5, -8), Vector3(6, 1, 0.6))
	var props := PropSpawner.new()
	props.name = "Props"
	add_child(props)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 10, 8)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var help := Label.new()
	help.text = "Pick a gem up (E), then press E again while holding it to eat it.   F1 lay the gems out again   F2 lose all upgrades"
	column.add_child(help)
	_info = Label.new()
	column.add_child(_info)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var middle := VBoxContainer.new()
	center.add_child(middle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	middle.add_child(_prompt)
	_lay_out.call_deferred()


## Host: one glowing gem per mutation, plus the robot part.
func _lay_out() -> void:
	if not multiplayer.is_server():
		return
	var ids: Array[StringName] = ContentRegistry.get_all_ids(&"mutation")
	for index: int in ids.size():
		Props.spawn_prop(&"prop_gem_glowing", Transform3D(Basis.IDENTITY, Vector3(-3.0 + 1.2 * float(index), 0.3, -2.5)),
			{"upgrade_id": String(ids[index])})
	for id: StringName in ContentRegistry.get_all_ids(&"cybernetic"):
		Props.spawn_prop(&"prop_robot_part", Transform3D(Basis.IDENTITY, Vector3(3.5, 0.3, -1.5)), {"upgrade_id": String(id)})


func _add_wall(center: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	wall.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	wall.add_child(mesh)
	add_child(wall)


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	_info.text = "Your upgrades: %s" % str(Upgrades.get_upgrades(Net.local_player_id()))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F1 or key.keycode == KEY_F2:
		_request_rpc.rpc_id(1, key.keycode == KEY_F2)
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func _request_rpc(clear: bool) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	if not clear:
		_lay_out()
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var player_id: int = Net.get_player_id_for_peer(sender) if sender > 1 else Net.local_player_id()
	for upgrade_id: StringName in Upgrades.get_upgrades(player_id):
		Upgrades.remove(player_id, upgrade_id)
