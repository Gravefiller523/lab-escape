extends SceneTree
## Builds the sound sets (roadmap WP28): each game event or surface sound becomes an AudioStreamRandomizer that
## picks one of its variations (assets/audio/sfx/shared/sfx_<set>_<n>.ogg) with a little random pitch, saved as
## assets/audio/sfx/shared/sets/<set>.tres, and puts the sets into systems/audio/event_sounds.tres and the surface
## files. Run after adding or renaming sound files:
##   godot --headless --path . --editor --quit
##   godot --headless --path . -s assets/source/build_sound_sets.gd

const SOUNDS: String = "res://assets/audio/sfx/shared"
const SETS: String = "res://assets/audio/sfx/shared/sets"
## event_sounds.tres field -> set name. Fields not listed keep their generated placeholder.
const EVENTS: Dictionary = {
	"hit": "hit_punch", "enemy_death": "enemy_death", "player_death": "player_death", "item_use": "item_use_swing",
	"enemy_shoot": "enemy_shoot_laser", "reprint": "reprint_printer", "upgrade": "upgrade_confirm",
	"purchase": "purchase_coins", "gem_pickup": "gem_pickup_clink", "use_deny": "use_deny_buzz",
	"button_press": "button_press_click", "door_move": "door_open", "door_shut": "door_shut",
	"crank_turn": "crank_click", "punt": "punt_metal", "lift_arrive": "lift_arrive_bell",
	"lift_part": "lift_part_clank", "boss_phase": "boss_phase_boom",
}
## Looping sounds stay a single file (a randomizer can't loop).
const SINGLE: Dictionary = {"lift_ride": "lift_ride_hum"}
## surface file -> {field: set name}.
const SURFACES: Dictionary = {
	"concrete": {"step": "step_concrete", "land": "land_concrete", "impact": "impact_concrete"},
	"metal": {"step": "step_metal", "land": "land_metal", "impact": "impact_metal"},
	"wood": {"step": "step_wood", "land": "land_wood", "impact": "impact_wood"},
	"glass": {"step": "step_concrete", "land": "land_concrete", "impact": "impact_glass"},
	"flesh": {"step": "step_soft", "land": "land_concrete", "impact": "impact_flesh"},
}

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	DirAccess.make_dir_recursive_absolute(SETS)
	var table := load("res://systems/audio/event_sounds.tres") as Resource
	for field: String in EVENTS:
		table.set(field, _sound_set(str(EVENTS[field])))
	for field: String in SINGLE:
		table.set(field, load("%s/sfx_%s_1.ogg" % [SOUNDS, SINGLE[field]]))
	print("TABLE ", ResourceSaver.save(table, table.resource_path))
	for surface: String in SURFACES:
		var path: String = "res://systems/audio/surfaces/%s.tres" % surface
		var data := load(path) as Resource
		var fields: Dictionary = SURFACES[surface]
		for field: String in fields:
			data.set(field, _sound_set(str(fields[field])))
		print("SURFACE %s %s" % [surface, ResourceSaver.save(data, path)])
	quit()
	return false


func _sound_set(set_name: String) -> AudioStream:
	var path: String = "%s/%s.tres" % [SETS, set_name]
	var mix := AudioStreamRandomizer.new()
	mix.random_pitch = 1.08
	mix.random_volume_offset_db = 1.0
	var index: int = 1
	while ResourceLoader.exists("%s/sfx_%s_%d.ogg" % [SOUNDS, set_name, index]):
		mix.add_stream(-1, load("%s/sfx_%s_%d.ogg" % [SOUNDS, set_name, index]) as AudioStream)
		index += 1
	ResourceSaver.save(mix, path)
	return load(path) as AudioStream
