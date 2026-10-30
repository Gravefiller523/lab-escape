class_name TuneCommands
extends RefCounted
## NEW 2026-10-29: console commands to change feel numbers (Config.feel) while the game runs.
##   tune                      the sections (player, props, ai, interaction; NEW 2026-10-30: interaction)
##   tune props                every number in a section, with its value
##   tune props.throw_force    one value
##   tune props.throw_force 25 change it now
##   tune_save                 write the current numbers into res://config/feel_tuning.tres and
##                             systems/player/player_tuning.tres (editor only), so they stick
##   tune_reset                throw away unsaved changes: load the numbers from those files again
## Changes only this PC. Props and enemies run on the host, so tune those on the host.
## Registered by DebugConsole. Like other cheats, only works in editor and test builds.

const SECTIONS: Array[StringName] = [&"player", &"props", &"ai", &"interaction"]
const MSG_USAGE: String = "Usage: tune <section>.<name> [value]   e.g. tune props.throw_force 25"


static func tune(args: PackedStringArray, feel: FeelTuning) -> String:
	if args.is_empty():
		return "Sections: %s. Type tune <section> to list its numbers." % ", ".join(SECTIONS)
	var parts: PackedStringArray = args[0].split(".", false)
	var section: Resource = _section(feel, parts[0])
	if section == null:
		return "No section '%s'. Sections: %s" % [parts[0], ", ".join(SECTIONS)]
	if parts.size() == 1:
		return _list(parts[0], section)
	if parts.size() != 2:
		return MSG_USAGE
	var field: String = parts[1]
	if not _field_names(section).has(field):
		return "No number '%s' in %s. Type tune %s to see them." % [field, parts[0], parts[0]]
	if args.size() < 2:
		return "%s = %s" % [args[0], str(section.get(field))]
	var current: Variant = section.get(field)
	var parsed: Array = _parse(args[1], typeof(current))
	if parsed.is_empty():
		return "'%s' isn't a valid %s." % [args[1], type_string(typeof(current))]
	section.set(field, parsed[0])
	return "%s: %s -> %s (not saved: tune_save keeps it)" % [args[0], str(current), str(section.get(field))]


## Writes the live numbers back into the project's files. Only in the editor (exported games can't
## write into the game's own files).
static func save(feel: FeelTuning, is_editor: bool) -> String:
	if not is_editor:
		return "tune_save only works when running from the editor."
	var errors: PackedStringArray = []
	for resource: Resource in [feel.player, feel]:
		if resource.resource_path.is_empty():
			errors.append("a section has no file to save into")
			continue
		var result: Error = ResourceSaver.save(resource, resource.resource_path)
		if result != OK:
			errors.append("%s (error %d)" % [resource.resource_path, result])
	if not errors.is_empty():
		return "Could not save: " + ", ".join(errors)
	return "Saved to %s and %s." % [feel.resource_path, feel.player.resource_path]


## Loads the numbers from the files again and copies them into the live sections (the same objects
## stay in use, so everything that holds them sees the change).
static func reset(feel: FeelTuning) -> String:
	if feel.resource_path.is_empty():
		return "Nothing to reload from."
	var fresh := ResourceLoader.load(feel.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as FeelTuning
	if fresh == null:
		return "Could not load %s." % feel.resource_path
	for section_name: StringName in SECTIONS:
		var live: Resource = _section(feel, section_name)
		var saved: Resource = _section(fresh, section_name)
		if live == null or saved == null:
			continue
		for field: String in _field_names(live):
			live.set(field, saved.get(field))
	return "Feel numbers loaded from %s again." % feel.resource_path


static func _section(feel: FeelTuning, section_name: String) -> Resource:
	match section_name:
		"player":
			return feel.player
		"props":
			return feel.props
		"ai":
			return feel.ai
		"interaction":
			return feel.interaction
	return null


## The numbers you can change: the script's exported variables.
static func _field_names(section: Resource) -> PackedStringArray:
	var names: PackedStringArray = []
	for property: Dictionary in section.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_EDITOR:
			names.append(str(property["name"]))
	return names


static func _list(section_name: String, section: Resource) -> String:
	var lines: PackedStringArray = []
	for field: String in _field_names(section):
		lines.append("  %s.%s = %s" % [section_name, field, str(section.get(field))])
	return "\n".join(lines)


## [value] if `text` reads as that type, else []. Only numbers and true/false can be tuned.
static func _parse(text: String, type: int) -> Array:
	match type:
		TYPE_FLOAT:
			return [text.to_float()] if text.is_valid_float() else []
		TYPE_INT:
			return [text.to_int()] if text.is_valid_int() else []
		TYPE_BOOL:
			var lower: String = text.to_lower()
			if lower in ["true", "on", "1", "yes"]:
				return [true]
			if lower in ["false", "off", "0", "no"]:
				return [false]
	return []
