class_name SecurityMonitor
extends WorldDevice
## NEW 2026-11-10 (floor generation step 4e, plan section 7.2): one monitor in the security room. It shows one
## of the floor's security cameras (FloorLayout.cameras) as low-resolution security footage, with the
## camera's label and the time on it; a broken camera shows static. Its Prev and Next buttons (WorldButtons
## the Security service wires to it) step through the cameras. Which camera it shows is host state, sent to
## every PC like a door's; each PC draws its own picture (pictures never cross the network). The picture only
## redraws when the Security service calls render_once() (a few times a second, while someone is near).
## Its screen faces +Z. Inputs: next, prev (and enable, disable). Outputs: changed.

## The cameras it can show: [marker key, label, broken], as in FloorLayout.cameras. Set before adding it.
var cameras: Array[Array] = []
## Which camera it starts on (each monitor starts on a different one).
var start_index: int = 0
## Screen size (metres).
var screen_size: Vector2 = Vector2(1.0, 0.56)

const SHADER: Shader = preload("res://systems/security/security_feed.gdshader")

var _index: int = 0
var _viewport: SubViewport
var _camera: Camera3D
var _screen: MeshInstance3D
var _material: ShaderMaterial
var _label: Label3D
var _clock: Label3D
var _feed_active: bool = false


func _build() -> void:
	_index = posmod(start_index, maxi(cameras.size(), 1))
	var tuning: FloorGenTuning = Config.floor_gen
	_viewport = SubViewport.new()
	_viewport.name = "Feed"
	_viewport.size = tuning.feed_resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 80.0
	_camera.far = 60.0
	_viewport.add_child(_camera)
	add_child(_viewport)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"feed", _viewport.get_texture())
	var quad := QuadMesh.new()
	quad.size = screen_size
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	_screen.mesh = quad
	_screen.material_override = _material
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_screen)
	_label = _text("Label", Vector3(-screen_size.x / 2.0 + 0.03, screen_size.y / 2.0 - 0.04, 0.005),
		HORIZONTAL_ALIGNMENT_LEFT)
	_clock = _text("Clock", Vector3(screen_size.x / 2.0 - 0.03, -screen_size.y / 2.0 + 0.04, 0.005),
		HORIZONTAL_ALIGNMENT_RIGHT)
	_show()


func get_inputs() -> PackedStringArray:
	return PackedStringArray(["next", "prev"])


## Which camera (an index into `cameras`) it shows.
func get_camera_index() -> int:
	return _index


## The label of the camera it shows ("" if there are none).
func get_camera_label() -> String:
	return str(cameras[_index][1]) if _index < cameras.size() else ""


## Is the camera it shows broken (static)?
func is_showing_static() -> bool:
	return cameras.is_empty() or (_index < cameras.size() and (cameras[_index][2] as bool))


## Is its picture being redrawn now (someone is near the security room)?
func is_feed_active() -> bool:
	return _feed_active


## Every PC (the Security service): someone is near, or nobody is. While nobody is, nothing redraws.
func set_feed_active(active: bool) -> void:
	_feed_active = active
	if not active:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Every PC (the Security service, feed_updates_per_second times a second while someone is near): point the
## camera at its spot (the floor may have moved) and draw one new picture.
func render_once() -> void:
	if not _feed_active or is_showing_static():
		return
	var spot: Transform3D = _camera_spot()
	if spot == Transform3D():
		return
	_camera.global_transform = spot
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_clock.text = Time.get_time_string_from_system()


func _on_input(action: StringName, activator_id: int) -> void:
	if cameras.is_empty():
		return
	match action:
		&"next":
			_index = posmod(_index + 1, cameras.size())
		&"prev":
			_index = posmod(_index - 1, cameras.size())
	_show()
	push_state()
	fire_output(&"changed", activator_id)


func get_state() -> Array:
	return [_index]


func _apply_state(state: Array) -> void:
	if state.is_empty():
		return
	_index = posmod(state[0] as int, maxi(cameras.size(), 1))
	_show()


func _show() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"broken", is_showing_static())
	_label.text = get_camera_label() if not cameras.is_empty() else "NO SIGNAL"


## Where the shown camera hangs, looking at the middle of its room (its marker only says where it is).
func _camera_spot() -> Transform3D:
	if _index >= cameras.size():
		return Transform3D()
	var key: String = cameras[_index][0]
	var marker: RoomMarker = Level.get_marker_by_key(key)
	if marker == null:
		return Transform3D()
	var rooms: Array[Node3D] = Level.get_room_nodes()
	var room_index: int = key.get_slice("/", 0).to_int()
	var target: Vector3 = marker.global_position + marker.global_basis.z
	if room_index < rooms.size():
		var tile := rooms[room_index] as BlockoutTile
		if tile != null:
			var middle := Vector3(tile.size_units.x, 0.0, tile.size_units.y) * Config.floor_gen.grid_unit / 2.0
			target = tile.global_transform * (middle + Vector3.UP * 1.0)
	var spot := Transform3D(Basis.IDENTITY, marker.global_position)
	if target.distance_to(spot.origin) > 0.1:
		spot = spot.looking_at(target, Vector3.UP)
	return spot


func _text(text_name: String, at: Vector3, align: HorizontalAlignment) -> Label3D:
	var label := Label3D.new()
	label.name = text_name
	label.position = at
	label.pixel_size = 0.0012
	label.font_size = 28
	label.modulate = Color(0.75, 1.0, 0.8)
	label.outline_size = 0
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.shaded = false
	label.double_sided = false
	add_child(label)
	return label
