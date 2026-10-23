class_name GameWorld
extends Node3D
## The scene that stays loaded from the Break Room to the end of a run (game_world.tscn). It holds the
## cargo lift, the player and prop spawners, and a LevelRoot that game_flow fills with the current level
## (the Break Room, or a floor level_gen builds), lined up so the level's lift spot is where the lift is.
## Nothing inside the lift is ever unloaded, so players and props ride along between levels.
##
## STUBS until other systems exist:
## - physics_props: a crate (or the marker's "prop_id") at each prop_spawn marker on floor_ready (host);
## (CHANGED 2026-10-23: the "Defeat the boss" button stub is gone: the bosses system spawns the real boss.)
## (CHANGED 2026-10-19: the "E: ..." prompt and crosshair stub is gone: the ui HUD shows them.)

const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const DEFAULT_PROP_ID: StringName = &"prop_crate"

var _level_root: Node3D
var _lift: CargoLift
var _players: PlayerSpawner
var _props: PropSpawner


const GROUP: StringName = &"game_world"


## The game world in the game right now, or null (the main menu).
static func current() -> GameWorld:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var world := node as GameWorld
		if world != null and world.is_inside_tree() and not world.is_queued_for_deletion():
			return world
	return null


func _ready() -> void:
	add_to_group(GROUP)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.13, 0.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_level_root = Node3D.new()
	_level_root.name = "LevelRoot"
	add_child(_level_root)
	_lift = LIFT_SCENE.instantiate() as CargoLift
	_lift.name = "CargoLift"
	add_child(_lift)
	_players = PlayerSpawner.new()
	_players.name = "PlayerSpawner"
	# game_flow turns this on once the first level is in, so nobody appears before there is a floor.
	_players.auto_spawn = false
	add_child(_players)
	_props = PropSpawner.new()
	_props.name = "Props"
	add_child(_props)
	EventBus.floor_ready.connect(_on_floor_ready)


func get_lift() -> CargoLift:
	return _lift


func get_player_spawner() -> PlayerSpawner:
	return _players


func get_prop_spawner() -> PropSpawner:
	return _props


## Every PC: takes the current level away (the rooms or the Break Room).
func clear_level() -> void:
	Level.clear()
	for child: Node in _level_root.get_children():
		_level_root.remove_child(child)
		child.queue_free()
	_level_root.transform = Transform3D.IDENTITY


## Every PC: puts the Break Room in, lined up with the lift. Returns its spawn points.
func build_break_room(scene: PackedScene) -> Array[Node3D]:
	clear_level()
	var room := scene.instantiate() as BreakRoom
	_level_root.add_child(room)
	_line_up(room.get_lift_spot())
	return room.get_spawn_points()


## Every PC: builds a floor from its layout, lined up with the lift (at its lift room's lift marker).
func build_floor(layout: FloorLayout) -> void:
	clear_level()
	Level.build(layout, _level_root)
	var spots: Array[RoomMarker] = Level.get_markers(&"lift")
	if not spots.is_empty():
		_line_up(spots[0])


## Moves LevelRoot so that spot (inside it) ends up exactly where the lift is.
func _line_up(spot: Node3D) -> void:
	if spot == null:
		return
	var spot_in_root: Transform3D = _level_root.global_transform.affine_inverse() * spot.global_transform
	_level_root.global_transform = _lift.global_transform * spot_in_root.affine_inverse()


## Host, STUB for physics_props: the floor's crates.
func _on_floor_ready(_floor_number: int, _department_id: StringName) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	for marker: RoomMarker in Level.get_markers(&"prop_spawn"):
		var prop_id := StringName(str(marker.params.get("prop_id", DEFAULT_PROP_ID)))
		_props.spawn_prop(prop_id, marker.global_transform)

