class_name SecurityMapTable
extends Node3D
## NEW 2026-11-10 (floor generation step 4e, plan section 7.1): the map table in the security room. Its screen
## shows the floor from above, drawn from the floor plan (rooms, hallways, the elevator, room names, locked and
## blocked doors), with every player as a coloured dot and the wings that hold a broken lift part blinking (not
## the exact room). Press E at it to lean over the map (the view eases down onto it); E again, or a movement key,
## stands back up. Every PC draws its own copy; nothing new crosses the network except "this player leans in".
## Sits on the security_map marker (the middle of the table, on the floor); the Security service makes it.

## How high the table top is (metres) and how big its screen is.
const TOP_HEIGHT: float = 0.9
const SCREEN_SIZE: Vector2 = Vector2(2.2, 1.25)

var _viewport: SubViewport
var _map: FloorMapView
var _overlay: SecurityMapOverlay
var _screen: MeshInstance3D
var _interactable: Interactable
var _lean_camera: Camera3D
var _leaning: bool = false
var _blink_time: float = 0.0
var _scan_time: float = 0.0


func _ready() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	_viewport = SubViewport.new()
	_viewport.name = "MapScreen"
	_viewport.size = tuning.map_resolution
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_map = FloorMapView.new()
	_map.name = "Map"
	_map.style = FloorMapView.STYLE_SECURITY
	_map.size = Vector2(tuning.map_resolution)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_map)
	_overlay = SecurityMapOverlay.new()
	_overlay.name = "Overlay"
	_overlay.map = _map
	_overlay.size = Vector2(tuning.map_resolution)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_overlay)
	add_child(_viewport)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	_screen.mesh = quad
	_screen.material_override = material
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lying flat on the table, its top edge towards -Z (the map's north is the floor's -Z).
	_screen.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, TOP_HEIGHT + 0.015, 0))
	add_child(_screen)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SCREEN_SIZE.x, 0.1, SCREEN_SIZE.y)
	shape.shape = box
	shape.position = Vector3(0, TOP_HEIGHT + 0.05, 0)
	body.add_child(shape)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt_text = "Look at the map"
	_interactable.used.connect(_on_used)
	body.add_child(_interactable)
	add_child(body)


## Every PC: the floor plan to draw (drawn once) and the department's accent colour for its lines.
func show_layout(layout: FloorLayout, accent: Color) -> void:
	_map.accent_color = accent
	_map.layout = layout
	refresh([] as Array[int], [] as Array[Dictionary], 0.0)


## Every PC, a few times a second (the Security service): the blinking part wings and the players' dots, then
## one new picture. `delta` is the time since the last refresh.
func refresh(highlighted: Array[int], dots: Array[Dictionary], delta: float) -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	_blink_time += delta
	_scan_time += delta
	_overlay.highlighted = highlighted
	_overlay.dots = dots
	_overlay.blink_on = fmod(_blink_time, tuning.map_blink_seconds * 2.0) < tuning.map_blink_seconds
	_overlay.scan = fmod(_scan_time / maxf(tuning.map_scan_seconds, 0.1), 1.0)
	_overlay.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## For tests: what the overlay shows now.
func get_overlay() -> SecurityMapOverlay:
	return _overlay


func get_interactable() -> Interactable:
	return _interactable


## Is the local player leaning over the map?
func is_leaning() -> bool:
	return _leaning


## Local: lean over the map (the view eases down onto it, movement stops).
func lean_in() -> void:
	var body: PlayerCharacter = _local_body()
	if body == null or _leaning:
		return
	_leaning = true
	var tuning: FloorGenTuning = Config.floor_gen
	_lean_camera = Camera3D.new()
	_lean_camera.name = "LeanCamera"
	add_child(_lean_camera)
	var screen_middle: Vector3 = to_global(Vector3(0, TOP_HEIGHT, 0))
	var eye: Vector3 = to_global(Vector3(0, TOP_HEIGHT + tuning.map_lean_height, SCREEN_SIZE.y * 0.3))
	var start: Transform3D = body.get_camera().global_transform if body.get_camera() != null else Transform3D(Basis.IDENTITY, eye)
	_lean_camera.global_transform = start
	_lean_camera.make_current()
	body.set_input_enabled(false)
	var tween: Tween = create_tween()
	# Looking down at the map with its north (the table's -Z) at the top of the view.
	var target: Transform3D = Transform3D(Basis.IDENTITY, eye).looking_at(screen_middle, -global_basis.z.normalized())
	tween.tween_property(_lean_camera, "global_transform", target, tuning.map_lean_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Local: stand back up.
func lean_out() -> void:
	if not _leaning:
		return
	_leaning = false
	var body: PlayerCharacter = _local_body()
	if body != null:
		if body.get_camera() != null:
			body.get_camera().make_current()
		body.set_input_enabled(true)
	if _lean_camera != null and is_instance_valid(_lean_camera):
		_lean_camera.queue_free()
	_lean_camera = null


func _input(event: InputEvent) -> void:
	if not _leaning:
		return
	for action: StringName in [InputActions.USE, InputActions.MOVE_FORWARD, InputActions.MOVE_BACK,
			InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT]:
		if event.is_action_pressed(action):
			lean_out()
			get_viewport().set_input_as_handled()
			return


func _exit_tree() -> void:
	lean_out()


## Host: a player pressed E on the table: tell their PC to lean in.
func _on_used(player_id: int) -> void:
	var peer: int = Net.get_peer_id(player_id)
	if peer == 0 or peer == multiplayer.get_unique_id():
		lean_in()
	else:
		_lean_rpc.rpc_id(peer)


@rpc("authority", "call_remote", "reliable")
func _lean_rpc() -> void:
	lean_in()


func _local_body() -> PlayerCharacter:
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body != null and body.is_local():
			return body
	return null
