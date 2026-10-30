extends "res://systems/player/test/movement_test.gd"
## Playtest level for the HL2 feel work (NEW 2026-10-29). Claude opens it from the editor when a step needs
## a human to play it. The movement test level, plus a course for the feel steps (stairs, a block, a
## ledge) and an on-screen list of what to try, read from playtest_checklist.txt (rewritten for each step).
## F1 hides or shows the list. Everything else (keys, mutation keys 4 to 7, host and join) works as in
## the movement test.
## NEW 2026-10-30 (step 3): an enemy pen (a room with rats and a kangaroo) behind the ladder platform.
## F2 puts the pen's enemies back, F3 drops a kangaroo out in the open, F4 kills every enemy, F5 turns
## god mode on or off (enemies still attack, you just don't die).
## CHANGED 2026-10-30: you always come back at the start after dying (the real game runs out of free
## reprints), and the mouse wheel scrolls the list while it's shown (F1 hides it to get item switching back).

const CHECKLIST_PATH: String = "res://systems/player/test/playtest_checklist.txt"
const COURSE_COLOR: Color = Color(0.5, 0.42, 0.55)
## NEW 2026-10-29 (step 2): the prop yard, and the targets to throw things at.
const PROP_YARD: Vector3 = Vector3(7, 0, -14)
const TARGET_COLOR: Color = Color(0.75, 0.35, 0.3)
const TARGET_REVIVE_SECONDS: float = 2.0
## NEW 2026-10-30 (step 3): the enemy pen, a 10 x 8 m room with its doorway facing +Z.
const PEN_CENTER: Vector3 = Vector3(-14, 0, -15)
const PEN_SIZE: Vector2 = Vector2(10, 8)
const PEN_COLOR: Color = Color(0.42, 0.47, 0.42)
## Where a dead player comes back, and after how long.
const RESPAWN_SPOT: Vector3 = Vector3(0, 0.1, 3)
const RESPAWN_SECONDS: float = 2.0
const CHECKLIST_WIDTH: float = 440.0
## How far one mouse wheel notch scrolls the list.
const CHECKLIST_SCROLL_STEP: int = 48

var _checklist: PanelContainer
var _props: PropSpawner
var _enemies: EnemySpawner
var _health_label: Label
var _checklist_scroll: ScrollContainer


func _ready() -> void:
	# Props (NEW 2026-10-29, step 2): a spawner, so grabbing, throwing and breaking work here.
	_props = PropSpawner.new()
	_props.name = "Props"
	add_child(_props)
	# Enemies (NEW 2026-10-30, step 3): their own spawner, and a navigation mesh for the whole level.
	_enemies = EnemySpawner.new()
	_enemies.name = "TestEnemies"
	add_child(_enemies)
	super._ready()
	_fill_prop_yard.call_deferred()
	_start_enemies.call_deferred()
	EventBus.player_died.connect(_on_player_died)


## Host: bring a dead player back at the start after a moment, however often they die.
func _on_player_died(player_id: int, _where: Vector3) -> void:
	if not multiplayer.is_server():
		return
	Death.tell(player_id, "Back at the start in %d s." % roundi(RESPAWN_SECONDS))
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(func() -> void:
		if Death.is_dead(player_id):
			Death.reprint(player_id, Transform3D(Basis.IDENTITY, RESPAWN_SPOT)))


func _process(delta: float) -> void:
	super._process(delta)
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	var health: HealthComponent = HealthComponent.of(body) if body != null else null
	if health != null:
		_health_label.text = "Health %d / %d%s" % [roundi(health.get_current()), roundi(health.get_max()),
			"  (god mode)" if health.invulnerable else ""]


## Host: bake the navigation mesh in the background, then fill the pen.
func _start_enemies() -> void:
	if not multiplayer.is_server():
		return
	Enemies.bake_navigation(self)
	_fill_pen()


## Host: a pack of four rats at the back of the pen and a kangaroo by the pillar (old ones removed first).
func _fill_pen() -> void:
	if not multiplayer.is_server():
		return
	_enemies.despawn_all()
	for index: int in 4:
		var spot: Vector3 = PEN_CENTER + Vector3(float(index) * 0.9 - 1.35, 0.1, -2.6)
		_enemies.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, spot))
	_enemies.spawn(&"enemy_kangaroo", Transform3D(Basis.IDENTITY, PEN_CENTER + Vector3(3.2, 0.1, -1.5)))


## Host: crates, a heavy crate, metal lift parts, a fragile glass tube, gems and meat in the yard.
func _fill_prop_yard() -> void:
	if not multiplayer.is_server():
		return
	var line: Array[StringName] = [&"prop_crate", &"prop_crate", &"prop_crate", &"prop_crate", &"prop_crate_heavy"]
	for index: int in line.size():
		_props.spawn_prop(line[index], Transform3D(Basis.IDENTITY, PROP_YARD + Vector3(index * 1.2 - 2.4, 0.4, 0)))
	var second: Array[StringName] = [&"prop_lift_part_zoology", &"prop_lift_gear", &"prop_lift_vacuum_tube", &"prop_gem",
		&"prop_gem", &"prop_meat"]
	for index: int in second.size():
		_props.spawn_prop(second[index], Transform3D(Basis.IDENTITY, PROP_YARD + Vector3(index * 1.0 - 2.5, 0.4, -1.8)))
	# Crates outside the enemy pen, to throw in (noise) or at a kangaroo (it dodges).
	for index: int in 3:
		var spot: Vector3 = PEN_CENTER + Vector3(float(index) * 1.2 - 1.2, 0.4, PEN_SIZE.y * 0.5 + 3.0)
		_props.spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, spot))

func _build_world() -> void:
	super._build_world()
	# Stairs going up along +X: 0.2 m steps (walk up) and 0.4 m steps (walk up, just).
	_add_stairs(Vector3(-6, 0, 13), 0.2, 6, "0.2 m stairs")
	_add_stairs(Vector3(-6, 0, 17), 0.4, 4, "0.4 m stairs")
	# A 0.5 m block: too high to walk up, you must jump.
	_add_box(Vector3(6, 0.25, 13), Vector3(2, 0.5, 2), COURSE_COLOR)
	_add_label(Vector3(6, 1.2, 13), "0.5 m block")
	# A 1.4 m ledge: only a crouch-jump gets you up.
	_add_box(Vector3(6, 0.7, 17), Vector3(2, 1.4, 2), COURSE_COLOR)
	_add_label(Vector3(6, 2.1, 17), "1.4 m ledge")
	_add_label(Vector3(-12, 3.6, -4), "3 m drop")
	_add_label(PROP_YARD + Vector3(0, 1.6, 0), "props (E pick up, left click throw)")
	# Targets: two light ones (like rats) and a heavy one (like a kangaroo).
	_add_target(PROP_YARD + Vector3(-3, 0, -5), 5.0, 15.0, "light target")
	_add_target(PROP_YARD + Vector3(0, 0, -5), 5.0, 15.0, "light target")
	_add_target(PROP_YARD + Vector3(3, 0, -5), 50.0, 60.0, "heavy target")
	# A metal floor plate, to hear the footsteps change.
	var plate: StaticBody3D = _add_box(Vector3(0, 0.025, 15), Vector3(4, 0.05, 6), Color(0.55, 0.6, 0.68))
	plate.set_meta(SurfaceType.META_KEY, "metal")
	_add_label(Vector3(0, 1.2, 15), "metal floor")
	_build_pen()


## The enemy pen: four walls 2.5 m high with a 2 m doorway in the +Z wall, and a pillar inside to hide behind.
func _build_pen() -> void:
	var half_x: float = PEN_SIZE.x * 0.5
	var half_z: float = PEN_SIZE.y * 0.5
	var height: float = 2.5
	_add_box(PEN_CENTER + Vector3(0, height * 0.5, -half_z), Vector3(PEN_SIZE.x, height, 0.3), PEN_COLOR)
	_add_box(PEN_CENTER + Vector3(-half_x, height * 0.5, 0), Vector3(0.3, height, PEN_SIZE.y), PEN_COLOR)
	_add_box(PEN_CENTER + Vector3(half_x, height * 0.5, 0), Vector3(0.3, height, PEN_SIZE.y), PEN_COLOR)
	var side: float = (PEN_SIZE.x - 2.0) * 0.5
	_add_box(PEN_CENTER + Vector3(-1.0 - side * 0.5, height * 0.5, half_z), Vector3(side, height, 0.3), PEN_COLOR)
	_add_box(PEN_CENTER + Vector3(1.0 + side * 0.5, height * 0.5, half_z), Vector3(side, height, 0.3), PEN_COLOR)
	_add_box(PEN_CENTER + Vector3(-1.5, 1.0, 0.5), Vector3(1, 2, 1), PEN_COLOR)
	_add_label(PEN_CENTER + Vector3(0, height + 0.8, half_z), "enemy pen (F2 resets it)")


func _build_ui() -> void:
	super._build_ui()
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_checklist = PanelContainer.new()
	_checklist.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_checklist)
	var column := VBoxContainer.new()
	_checklist.add_child(column)
	_health_label = Label.new()
	column.add_child(_health_label)
	# The list scrolls when it's taller than the window, with the mouse wheel (see _input).
	_checklist_scroll = ScrollContainer.new()
	_checklist_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_checklist_scroll)
	var text := Label.new()
	text.custom_minimum_size = Vector2(CHECKLIST_WIDTH, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = _read_checklist() + "\n\n(Mouse wheel scrolls this list. F1 hides it.)"
	_checklist_scroll.add_child(text)
	get_viewport().size_changed.connect(_fit_checklist)
	_fit_checklist()


## The list is as tall as the window allows (minus room for the health line), scrolling the rest.
func _fit_checklist() -> void:
	var height: float = get_viewport().get_visible_rect().size.y - 24.0 - 48.0
	_checklist_scroll.custom_minimum_size = Vector2(CHECKLIST_WIDTH + 16.0, maxf(height, 120.0))
	_checklist.reset_size()
	_checklist.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)


## While the list is shown, the mouse wheel scrolls it (even while you're looking around) instead of
## switching items.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or not _checklist.visible:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_checklist_scroll.scroll_vertical += CHECKLIST_SCROLL_STEP
	elif button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_checklist_scroll.scroll_vertical -= CHECKLIST_SCROLL_STEP
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		_checklist.visible = not _checklist.visible
		return
	if key != null and key.pressed and not key.echo and _enemy_key(key.keycode):
		return
	super._unhandled_key_input(event)


## F2 to F5 (enemy pen keys). True if the key was one of them.
func _enemy_key(keycode: Key) -> bool:
	match keycode:
		KEY_F2:
			_fill_pen()
		KEY_F3:
			var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
			if body != null and multiplayer.is_server():
				var ahead: Vector3 = body.get_aim_direction()
				ahead.y = 0.0
				var spot: Vector3 = body.global_position + ahead.normalized() * 8.0 + Vector3.UP * 0.1
				_enemies.spawn(&"enemy_kangaroo", Transform3D(Basis.IDENTITY, spot))
		KEY_F4:
			for enemy: Enemy in _enemies.get_alive():
				enemy.get_health().apply_damage(DamageInfo.make(9999.0, &"debug"))
		KEY_F5:
			var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
			var health: HealthComponent = HealthComponent.of(body) if body != null else null
			if health != null:
				health.invulnerable = not health.invulnerable
		_:
			return false
	return true


func _read_checklist() -> String:
	if not FileAccess.file_exists(CHECKLIST_PATH):
		return "No playtest checklist yet."
	return FileAccess.get_file_as_string(CHECKLIST_PATH).strip_edges()


## `count` steps of `rise` metres, each 0.5 m deep, going up along +X from `start`.
func _add_stairs(start: Vector3, rise: float, count: int, label: String) -> void:
	for index: int in count:
		var height: float = rise * float(index + 1)
		_add_box(start + Vector3(0.5 * index, height * 0.5, 0), Vector3(0.5, height, 2), COURSE_COLOR)
	_add_label(start + Vector3(0, rise + 0.8, 0), label)


## Something that can be hurt by thrown props, showing its health; it comes back after a moment.
func _add_target(where: Vector3, impact_mass: float, health: float, title: String) -> void:
	var target := CharacterBody3D.new()
	target.collision_layer = PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	target.set_meta(&"impact_mass", impact_mass)
	var size := Vector3(0.8, 1.2, 0.8) if impact_mass < 20.0 else Vector3(1.2, 2.0, 1.2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	target.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = TARGET_COLOR
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position.y = size.y / 2.0
	target.add_child(mesh)
	add_child(target)
	target.global_position = where
	DamageService.give_components(target, health, 0.0)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.position.y = size.y + 0.4
	target.add_child(label)
	var hp: HealthComponent = HealthComponent.of(target)
	var show := func(current: float, maximum: float) -> void:
		label.text = "%s\n%d / %d" % [title, roundi(current), roundi(maximum)]
	show.call(health, health)
	hp.health_changed.connect(show)
	hp.died.connect(func(_info: DamageInfo) -> void:
		label.text = "%s\nKO!" % title
		await get_tree().create_timer(TARGET_REVIVE_SECONDS).timeout
		if is_instance_valid(hp):
			hp.revive(1.0))


func _add_label(where: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = where
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	add_child(label)
