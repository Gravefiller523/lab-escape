class_name AchievementsService
extends Node
## Autoload "Achievements" (NEW 2026-11-13, roadmap WP18). Every AchievementData names an EventBus signal to count
## (`trigger_event`), maybe an id or word to match (`match_id` or `match_text`: the event's first StringName
## argument) and whether only this player's events count (`local_player_only`: the event's first int argument is
## this PC's player id). Each PC counts its own player's achievements. Progress is kept in the profile (SaveSystem stats
## "achievement:<id>") and, when the achievement has a `steam_stat_name`, in a Steam stat too; at
## `required_count` it unlocks on Steam (SteamSession), a toast shows, and EventBus.achievement_unlocked fires.
## Only counts in the game world (like lifetime stats), so tests and test scenes never touch the real profile.
## Console: `achievements` lists them; `achievements reset` (editor builds) starts them over.
## Spec: docs/systems/achievements.md.

const STAT_PREFIX: String = "achievement:"

var _by_event: Dictionary[StringName, Array] = {}
var _count_everywhere: bool = false
## Steam names unlocked this session, for tests (Steam itself may not be running).
var _unlock_log: Array[String] = []


func _ready() -> void:
	_connect_all()
	DebugConsole.register_command(&"achievements", _cmd_achievements,
		"achievements [reset]: your achievements and how far along you are", false)


## How many matching events have counted so far.
func get_progress(achievement_id: StringName) -> int:
	return SaveSystem.get_stat(StringName(STAT_PREFIX + String(achievement_id)))


func is_unlocked(achievement_id: StringName) -> bool:
	var data := ContentRegistry.get_content(achievement_id) as AchievementData
	return data != null and get_progress(achievement_id) >= maxi(data.required_count, 1)


## Event names an achievement file names that EventBus doesn't have (the content test reports these).
static func unknown_trigger_events() -> PackedStringArray:
	var unknown := PackedStringArray()
	for content: ContentData in ContentRegistry.get_all(&"achievement"):
		var data := content as AchievementData
		if data != null and not EventBus.has_signal(data.trigger_event):
			unknown.append("%s: %s" % [data.id, data.trigger_event])
	return unknown


## For tests: count even outside the game world (use SaveSystem.use_folder too, so the real profile is untouched).
func count_everywhere(on: bool) -> void:
	_count_everywhere = on


## For tests: the Steam API names unlocked since the game started.
func get_unlock_log() -> Array[String]:
	return _unlock_log.duplicate()


## Editor builds only: forget all progress (the profile's copy; Steam's own needs its reset tool).
func reset_all_for_testing() -> void:
	if not OS.has_feature("editor"):
		return
	for content: ContentData in ContentRegistry.get_all(&"achievement"):
		var profile: PlayerProfile = SaveSystem.get_profile()
		profile.stats.erase(STAT_PREFIX + String(content.id))
	SaveSystem.save_profile()


## Connects once to every signal some achievement counts. Called again if content changes (tests).
func _connect_all() -> void:
	for event_name: StringName in _by_event:
		if EventBus.is_connected(event_name, _on_event):
			EventBus.disconnect(event_name, _on_event)
	_by_event.clear()
	for content: ContentData in ContentRegistry.get_all(&"achievement"):
		var data := content as AchievementData
		if data == null or not EventBus.has_signal(data.trigger_event):
			continue
		if not _by_event.has(data.trigger_event):
			_by_event[data.trigger_event] = []
			EventBus.connect(data.trigger_event, _on_event.bind(data.trigger_event))
		_by_event[data.trigger_event].append(data)


## Any counted signal. The last argument is the signal's name (bound at connect); the rest are the signal's own.
func _on_event(...args: Array) -> void:
	if args.is_empty() or not _counting():
		return
	var event_name := StringName(str(args.pop_back()))
	var first_id: StringName = &""
	var first_int: int = 0
	var has_int: bool = false
	for value: Variant in args:
		if first_id == &"" and (value is StringName or value is String):
			first_id = StringName(str(value))
		elif not has_int and value is int:
			first_int = value as int
			has_int = true
	for entry: Variant in _by_event.get(event_name, []):
		var data := entry as AchievementData
		if data == null or is_unlocked(data.id):
			continue
		if data.match_id != &"" and data.match_id != first_id:
			continue
		if data.match_text != &"" and data.match_text != first_id:
			continue
		if data.local_player_only and (not has_int or first_int != Net.local_player_id()):
			continue
		_advance(data)


func _advance(data: AchievementData) -> void:
	var key := StringName(STAT_PREFIX + String(data.id))
	SaveSystem.increment_stat(key)
	var progress: int = SaveSystem.get_stat(key)
	SteamSession.set_stat(data.steam_stat_name, progress)
	if progress < maxi(data.required_count, 1):
		SteamSession.store_stats()
		return
	_unlock_log.append(data.steam_api_name)
	SteamSession.unlock_achievement(data.steam_api_name)
	EventBus.toast_requested.emit("Achievement: %s" % data.display_name)
	EventBus.achievement_unlocked.emit(data.id)


func _counting() -> bool:
	return _count_everywhere or GameWorld.current() != null


func _cmd_achievements(args: PackedStringArray, _player_id: int) -> String:
	if not args.is_empty() and args[0] == "reset":
		if not OS.has_feature("editor"):
			return "Only in editor builds."
		reset_all_for_testing()
		return "Achievement progress cleared on this PC."
	var lines := PackedStringArray()
	var ids: Array[StringName] = ContentRegistry.get_all_ids(&"achievement")
	ids.sort()
	for id: StringName in ids:
		var data := ContentRegistry.get_content(id) as AchievementData
		lines.append("%s %s (%d/%d)" % ["[x]" if is_unlocked(id) else "[ ]", data.display_name, mini(get_progress(id),
			data.required_count), data.required_count])
	return "\n".join(lines) if not lines.is_empty() else "No achievements."
