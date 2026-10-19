class_name Nameplates
extends Node3D
## Other players' names floating above their heads, with a speaker icon next to the name while they
## talk. A name only shows when you are within Config.game.nameplate_range metres (5) of them. Walls
## hide names (they are drawn in the world, not on top of it). Your own name never shows.
## Local only: it reads Net (names), EventBus.player_speaking_changed (talking) and the player bodies.
## Spec: docs/systems/ui.md.

## How far above the eyes the name floats (metres).
const HEIGHT_ABOVE_EYES: float = 0.45
const FONT_SIZE: int = 48
const PIXEL_SIZE: float = 0.004
const OUTLINE_SIZE: int = 12
## Gap between the speaker icon and the start of the name (metres).
const ICON_GAP: float = 0.06
const ICON_PIXEL_SIZE: float = 0.0035
const SPEAKER_ICON: Texture2D = preload("res://systems/ui/hud/speaker_icon.svg")

var _net: NetService
var _config: GameConfig
## player_id -> its plate (a Node3D holding the "Name" Label3D and the "Speaker" Sprite3D).
var _plates: Dictionary[int, Node3D] = {}
var _speaking: Dictionary[int, bool] = {}


## For tests only: use this Net and config instead of the autoloads.
func use_net(net: NetService, config: GameConfig) -> void:
	_net = net
	_config = config


func _ready() -> void:
	name = "Nameplates"
	top_level = true
	EventBus.player_speaking_changed.connect(_on_speaking_changed)
	EventBus.player_left.connect(func(player_id: int) -> void: _speaking.erase(player_id))


## The plate above a player's head, or null (none yet, or it's you).
func get_plate(player_id: int) -> Node3D:
	return _plates.get(player_id)


## True if that player's name is on screen now (close enough).
func is_name_visible(player_id: int) -> bool:
	var plate: Node3D = get_plate(player_id)
	return plate != null and plate.visible


## True if the speaker icon next to that player's name is showing.
func is_speaker_visible(player_id: int) -> bool:
	var plate: Node3D = get_plate(player_id)
	return plate != null and plate.visible and (plate.get_node(^"Speaker") as Sprite3D).visible


func _process(_delta: float) -> void:
	var net: NetService = _net if _net != null else Net
	var config: GameConfig = _config if _config != null else Config.game
	var me: int = net.local_player_id()
	var viewer: Vector3 = _viewer_position(me)
	var seen: Dictionary[int, bool] = {}
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body == null or body.is_queued_for_deletion() or body.player_id == me \
				or body.get_viewport() != get_viewport():
			continue
		seen[body.player_id] = true
		var plate: Node3D = _plates.get(body.player_id)
		if plate == null:
			plate = _make_plate(body.player_id)
		_update_plate(plate, body, net, viewer, config.nameplate_range)
	for player_id: int in _plates.keys():
		if not seen.has(player_id):
			_plates[player_id].queue_free()
			_plates.erase(player_id)


## Where you are looking from: the camera of this viewport, or your body if there is no camera.
func _viewer_position(me: int) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	var body: PlayerCharacter = PlayerCharacter.find(me)
	return body.global_position if body != null else Vector3.INF


func _make_plate(player_id: int) -> Node3D:
	var plate := Node3D.new()
	plate.name = "Plate_%d" % player_id
	var label := Label3D.new()
	label.name = "Name"
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.outline_size = OUTLINE_SIZE
	label.outline_modulate = Color.BLACK
	plate.add_child(label)
	var speaker := Sprite3D.new()
	speaker.name = "Speaker"
	speaker.texture = SPEAKER_ICON
	speaker.pixel_size = ICON_PIXEL_SIZE
	speaker.visible = false
	plate.add_child(speaker)
	add_child(plate)
	_plates[player_id] = plate
	return plate


func _update_plate(plate: Node3D, body: PlayerCharacter, net: NetService, viewer: Vector3, plate_range: float) -> void:
	var camera: Camera3D = body.get_camera()
	var eyes: Vector3 = camera.global_position if camera != null else body.global_position + Vector3.UP * 1.6
	plate.global_position = eyes + Vector3.UP * HEIGHT_ABOVE_EYES
	plate.visible = viewer.distance_to(plate.global_position) <= plate_range
	if not plate.visible:
		return
	# Turn the whole plate (name and icon together) to face you.
	var to_viewer: Vector3 = viewer - plate.global_position
	to_viewer.y = 0.0
	if to_viewer.length() > 0.01:
		plate.look_at(plate.global_position + to_viewer, Vector3.UP, true)
	var label := plate.get_node(^"Name") as Label3D
	var display_name: String = net.get_display_name(body.player_id)
	label.text = display_name if not display_name.is_empty() else "Player %d" % body.player_id
	var speaker := plate.get_node(^"Speaker") as Sprite3D
	speaker.visible = _speaking.get(body.player_id, false)
	if speaker.visible:
		var font: Font = label.font if label.font != null else ThemeDB.fallback_font
		var half_width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x \
			* PIXEL_SIZE / 2.0
		var icon_half: float = float(SPEAKER_ICON.get_width()) * ICON_PIXEL_SIZE / 2.0
		speaker.position = Vector3(-(half_width + ICON_GAP + icon_half), 0.0, 0.0)


func _on_speaking_changed(player_id: int, speaking: bool) -> void:
	_speaking[player_id] = speaking
