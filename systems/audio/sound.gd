class_name SoundService
extends Node
## Autoload "Sound": music and sound effects. Spec: docs/systems/audio.md.
## - Buses (made at startup if missing): Music, SFX, Voice (voice chat sends here), UI, all into Master.
## - Music follows the game: calm music in the menu and Break Room, the department's music on floors, the
##   boss's music on boss floors, crossfading between them. Missing music uses event_sounds.tres (and, while
##   that's empty, generated placeholders).
## - A pool of 3D and 2D players, so 200 sounds at once never make 200 nodes (the oldest is reused).
## - Game events make their sounds on every PC locally (nothing is sent over the network): hits and deaths
##   (any HealthComponent), item use, reprints, upgrades, purchases, the lift and the boss, and (NEW 2026-10-30)
##   the "can't use" buzz (EventBus.use_denied). World devices (doors, buttons, valves) play their own.

const BUSES: Array[StringName] = [&"Music", &"SFX", &"Voice", &"UI"]
const POOL_3D: int = 32
const POOL_2D: int = 8
const MUSIC_DB: float = -10.0
const SILENT_DB: float = -60.0
const SOUND_TABLE: EventSounds = preload("res://systems/audio/event_sounds.tres")
## How far 3D sounds carry (metres).
const MAX_DISTANCE: float = 40.0

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_2d: int = 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _music_tween: Tween
var _lift_hum: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _health_seen: Dictionary[int, float] = {}
var _table: EventSounds = SOUND_TABLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	for index: int in POOL_3D:
		var player := AudioStreamPlayer3D.new()
		player.bus = &"SFX"
		player.max_distance = MAX_DISTANCE
		player.unit_size = 4.0
		add_child(player)
		_pool_3d.append(player)
	for index: int in POOL_2D:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool_2d.append(player)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_lift_hum = AudioStreamPlayer.new()
	_lift_hum.bus = &"SFX"
	_lift_hum.volume_db = -8.0
	add_child(_lift_hum)
	get_tree().node_added.connect(_on_node_added)
	_connect_events()


## For tests: use another event sound table.
func use_table(table: EventSounds) -> void:
	_table = table


## Make the buses if they don't exist (each sends to Master).
static func ensure_buses() -> void:
	for bus: StringName in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")


## A bus's volume, 0 to 1 (settings_input will call this; 1 until then).
func set_volume(bus: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


func get_volume(bus: StringName) -> float:
	var index: int = AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(index)) if index >= 0 else 0.0


# --- Music ---------------------------------------------------------------------------------------------

func play_music(stream: AudioStream, fade_seconds: float = 1.5) -> void:
	if stream == null:
		stop_music(fade_seconds)
		return
	if _music_current != null and _music_current.stream == stream and _music_current.playing:
		return
	var old: AudioStreamPlayer = _music_current
	var new_player: AudioStreamPlayer = _music_b if _music_current == _music_a else _music_a
	new_player.stream = stream
	new_player.volume_db = SILENT_DB
	new_player.play()
	_music_current = new_player
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(new_player, "volume_db", MUSIC_DB, maxf(fade_seconds, 0.01))
	if old != null:
		_music_tween.tween_property(old, "volume_db", SILENT_DB, maxf(fade_seconds, 0.01))
		_music_tween.chain().tween_callback(old.stop)


func stop_music(fade_seconds: float = 1.5) -> void:
	if _music_current == null:
		return
	var old: AudioStreamPlayer = _music_current
	_music_current = null
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(old, "volume_db", SILENT_DB, maxf(fade_seconds, 0.01))
	_music_tween.tween_callback(old.stop)


## What's playing as music now (null = nothing).
func get_music() -> AudioStream:
	return _music_current.stream if _music_current != null else null


# --- Sound effects ---------------------------------------------------------------------------------------

func play_ui(stream: AudioStream) -> void:
	play_2d(stream, 0.0, &"UI")


func play_2d(stream: AudioStream, volume_db: float = 0.0, bus: StringName = &"SFX") -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = bus
	player.play()


## A sound at a spot in the world. When all pooled players are busy, the quietest one is cut off, or the new
## sound is skipped if it is quieter still (CHANGED 2026-10-29: was the oldest, so footsteps could cut off
## a boss roar).
func play_3d(stream: AudioStream, at: Vector3, volume_db: float = 0.0, pitch_variation: float = 0.05) -> void:
	if stream == null or not is_inside_tree():
		return
	var player: AudioStreamPlayer3D = _pick_3d(volume_db)
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	# Not gameplay: a little pitch variety so repeated sounds don't sound copied.
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	player.global_position = at
	player.play()


## A free pooled player (looking from where the last one was taken), else the quietest busy one (the oldest
## of equals) if it is no louder than `volume_db`, else null.
func _pick_3d(volume_db: float) -> AudioStreamPlayer3D:
	var quietest: int = -1
	for offset: int in _pool_3d.size():
		var index: int = (_next_3d + offset) % _pool_3d.size()
		var candidate: AudioStreamPlayer3D = _pool_3d[index]
		if not candidate.playing:
			quietest = index
			break
		if quietest < 0 or candidate.volume_db < _pool_3d[quietest].volume_db:
			quietest = index
	if quietest < 0:
		return null
	var picked: AudioStreamPlayer3D = _pool_3d[quietest]
	if picked.playing and picked.volume_db > volume_db:
		return null
	_next_3d = (quietest + 1) % _pool_3d.size()
	return picked


## A sound that moves with something (removed when it finishes).
func play_3d_attached(stream: AudioStream, parent: Node3D, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	if stream == null or parent == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = &"SFX"
	player.max_distance = MAX_DISTANCE
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


## Stop every pooled sound effect (tests; a scene change).
func stop_effects() -> void:
	for player: AudioStreamPlayer3D in _pool_3d:
		player.stop()
	for player: AudioStreamPlayer in _pool_2d:
		player.stop()


## How many pooled 3D players are playing (tests).
func get_playing_3d() -> int:
	var playing: int = 0
	for player: AudioStreamPlayer3D in _pool_3d:
		if player.playing:
			playing += 1
	return playing


func get_pool_size_3d() -> int:
	return _pool_3d.size()


## The sound an event makes (event_sounds.tres, or its placeholder).
func event_sound(field: StringName) -> AudioStream:
	return _table.sound_for(field)


# --- Game events ------------------------------------------------------------------------------------------

func _connect_events() -> void:
	EventBus.game_state_changed.connect(func(_old_state: int, _new_state: int) -> void: _music_for_state())
	EventBus.floor_ready.connect(func(_floor_number: int, department_id: StringName) -> void:
		_lift_hum.stop()
		play_2d(event_sound(&"lift_arrive"), -4.0)
		var run: RunState = GameFlow.get_run()
		if run == null or not run.is_boss_floor:
			_floor_music(department_id))
	EventBus.boss_floor_started.connect(func(boss_id: StringName) -> void:
		var boss := ContentRegistry.get_content(boss_id) as BossData
		play_music(boss.music if boss != null and boss.music != null else event_sound(&"boss_music")))
	EventBus.boss_defeated.connect(func(_boss_id: StringName) -> void:
		play_2d(event_sound(&"boss_defeated"))
		_floor_music(&""))
	EventBus.boss_phase_changed.connect(func(_boss_id: StringName, phase_index: int) -> void:
		if phase_index > 0:
			var boss: Boss = Boss.current()
			if boss != null:
				play_3d(event_sound(&"boss_phase"), boss.global_position, 4.0, 0.0))
	EventBus.run_ended.connect(func(_result: StringName) -> void: play_music(event_sound(&"menu_music")))
	EventBus.item_used.connect(func(player_id: int, _item_id: StringName) -> void:
		_at_player(player_id, &"item_use", -6.0))
	EventBus.player_reprinted.connect(func(player_id: int) -> void: _at_player(player_id, &"reprint", 0.0))
	EventBus.upgrade_gained.connect(func(player_id: int, _upgrade_id: StringName) -> void:
		_at_player(player_id, &"upgrade", 0.0))
	EventBus.vendor_purchase.connect(func(player_id: int, _item_id: StringName, _price: int) -> void:
		_at_player(player_id, &"purchase", 0.0))
	# NEW 2026-10-30 (step 4.1): the "can't use that" buzz, only on the PC of the player who tried.
	EventBus.use_denied.connect(func(_player_id: int) -> void: play_ui(event_sound(&"use_deny")))
	EventBus.lift_departed.connect(func(_floor_number: int) -> void:
		_lift_hum.stream = event_sound(&"lift_ride")
		_lift_hum.play())
	EventBus.lift_part_delivered.connect(func(_delivered: int, _needed: int) -> void:
		var lift: CargoLift = CargoLift.current()
		if lift != null:
			play_3d(event_sound(&"lift_part"), lift.global_position + Vector3.UP, 0.0))


func _music_for_state() -> void:
	var state: int = GameFlow.get_state()
	if state in [GameFlowService.State.MAIN_MENU, GameFlowService.State.BREAK_ROOM]:
		play_music(event_sound(&"menu_music"))


func _floor_music(department_id: StringName) -> void:
	var department := ContentRegistry.get_content(department_id) as DepartmentData
	if department == null:
		department = GameFlow.get_current_department()
	play_music(department.music if department != null and department.music != null else event_sound(&"floor_music"))


func _at_player(player_id: int, field: StringName, volume_db: float) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if body != null:
		play_3d(event_sound(field), body.global_position + Vector3.UP, volume_db)


## Every HealthComponent anywhere (players, enemies, bosses, dummies): hurt and death sounds on every PC.
func _on_node_added(node: Node) -> void:
	var health := node as HealthComponent
	if health == null:
		return
	health.health_changed.connect(_on_health_changed.bind(health))
	health.died.connect(_on_health_died.bind(health))


func _on_health_changed(current: float, maximum: float, health: HealthComponent) -> void:
	var key: int = health.get_instance_id()
	# Not seen before: it started at full health.
	var before: float = _health_seen.get(key, maximum)
	_health_seen[key] = current
	var owner_node := health.get_parent() as Node3D
	if current < before and current > 0.0 and owner_node != null and owner_node.is_inside_tree():
		play_3d(event_sound(&"hit"), owner_node.global_position + Vector3.UP * 0.8, -2.0)


func _on_health_died(_info: DamageInfo, health: HealthComponent) -> void:
	_health_seen.erase(health.get_instance_id())
	var owner_node := health.get_parent() as Node3D
	if owner_node == null or not owner_node.is_inside_tree():
		return
	var field: StringName = &"player_death" if owner_node is PlayerCharacter else &"enemy_death"
	play_3d(event_sound(field), owner_node.global_position + Vector3.UP * 0.5, 0.0)


func _make_music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"Music"
	player.volume_db = SILENT_DB
	add_child(player)
	return player
