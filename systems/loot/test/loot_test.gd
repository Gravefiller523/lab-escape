extends Node3D
## Test scene for loot (run alone with F6). Keys:
##   F1 "kill" a rat 100 times (rolls its table 100 times and shows the counts; spawns nothing)
##   F2 kill one rat in front of you for real (its drops pop out)   F3 the same for the Giant Rat
##   F4 drop 23 gem value   F8 merge loose gems now (normally only past max_loose_gems_per_floor)

var _overview: Camera3D
var _info: Label
var _counter: int = 0


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
	_info = Label.new()
	_info.position = Vector2(12, 12)
	layer.add_child(_info)
	_info.text = "F1 roll the rat table 100 times   F2 kill a rat here   F3 kill the Giant Rat here   F4 23 gems   F8 merge gems"


func _process(_delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not multiplayer.is_server():
		return
	var me: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	var spot: Vector3 = Vector3.ZERO
	if me != null:
		var forward: Vector3 = me.get_aim_direction()
		forward.y = 0.0
		spot = me.global_position + forward.normalized() * 2.0
	match key.keycode:
		KEY_F1:
			var counts: Dictionary[StringName, int] = {}
			for index: int in 100:
				_counter += 1
				for drop: LootDrop in Loot.roll(&"loot_zoology_small", SeededRng.make(1, &"loot_test", _counter)):
					counts[drop.prop_id] = counts.get(drop.prop_id, 0) + drop.count
			_info.text = "100 rats: %s" % str(counts)
		KEY_F2:
			EventBus.enemy_killed.emit(&"enemy_rat", spot, Net.local_player_id())
		KEY_F3:
			EventBus.enemy_killed.emit(&"boss_giant_rat", spot, Net.local_player_id())
		KEY_F4:
			DebugConsole.run("gems 23")
		KEY_F8:
			_info.text = "Merged away %d gems." % Loot.merge_gems(0)
		_:
			return
	get_viewport().set_input_as_handled()
