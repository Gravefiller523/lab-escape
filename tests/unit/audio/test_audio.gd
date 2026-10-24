extends GutTest
## Tests for audio (docs/systems/audio.md). The real Sound autoload; headless runs use a dummy audio
## driver, so these check what is set up and asked to play, not what you'd hear.


func after_each() -> void:
	Sound.use_table(preload("res://systems/audio/event_sounds.tres"))
	Sound.stop_music(0.01)
	await wait_process_frames(2)


func test_buses_exist() -> void:
	for bus: StringName in SoundService.BUSES:
		assert_gte(AudioServer.get_bus_index(bus), 0, "%s bus" % bus)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Voice")), &"Master")


func test_placeholders_fill_empty_event_sounds() -> void:
	var stream := Sound.event_sound(&"hit") as AudioStreamWAV
	assert_not_null(stream, "an empty field gets a generated placeholder")
	assert_gt(stream.data.size(), 0)
	assert_eq(Sound.event_sound(&"hit"), stream, "made once, then reused")


func test_a_real_sound_replaces_the_placeholder() -> void:
	var table := EventSounds.new()
	var mine := AudioStreamWAV.new()
	table.hit = mine
	Sound.use_table(table)
	assert_eq(Sound.event_sound(&"hit"), mine, "a file dropped on the field is used instead")


func test_music_switches_on_floor_ready() -> void:
	EventBus.floor_ready.emit(1, &"")
	assert_eq(Sound.get_music(), Sound.event_sound(&"floor_music"), "floor music (no department music yet)")
	EventBus.boss_floor_started.emit(&"boss_giant_rat")
	assert_eq(Sound.get_music(), Sound.event_sound(&"boss_music"), "boss music")
	EventBus.boss_defeated.emit(&"boss_giant_rat")
	assert_eq(Sound.get_music(), Sound.event_sound(&"floor_music"), "back to the floor music")


func test_department_music_from_data() -> void:
	var department := DepartmentData.new()
	department.id = &"department_test_music"
	var tune := AudioStreamWAV.new()
	department.music = tune
	if not ContentRegistry.has_content(department.id):
		ContentRegistry.register_content(department)
	EventBus.floor_ready.emit(1, &"department_test_music")
	assert_eq(Sound.get_music(), tune)


func test_pool_limit_respected() -> void:
	var children_before: int = Sound.get_child_count()
	for index: int in 200:
		Sound.play_3d(Sound.event_sound(&"hit"), Vector3(float(index), 0, 0))
	assert_eq(Sound.get_child_count(), children_before, "200 sounds, no new nodes")
	assert_lte(Sound.get_playing_3d(), Sound.get_pool_size_3d())


func test_volume_setting_applies() -> void:
	Sound.set_volume(&"Music", 0.5)
	assert_almost_eq(Sound.get_volume(&"Music"), 0.5, 0.01)
	Sound.set_volume(&"Music", 1.0)


func test_hits_make_a_sound_at_the_target() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	DamageService.give_components(target, 100.0)
	Sound.stop_effects()
	var before: int = Sound.get_playing_3d()
	HealthComponent.of(target).apply_damage(DamageInfo.make(10.0, &"blunt"))
	await wait_process_frames(1)
	assert_gt(Sound.get_playing_3d(), before, "a thunk where it was hit")
