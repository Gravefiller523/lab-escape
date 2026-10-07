class_name ContentValidator
extends RefCounted
## Checks content files for mistakes. Used by the content validation test
## (tests/content/test_content_validation.gd) and the debug console.
##
## It works on every content type without per-type code, using naming rules:
## - Each file's id starts with its type key ("mutation_") and matches its file name.
## - Fields listed by get_required_fields() must be filled in.
## - Any field ending in "_id" or "_ids" is a reference to other content and must
##   point to an id that exists. If the word just before "_id" is a type key
##   (boss_id, minion_enemy_ids, loot_id), the id must also be that type.
## - Effect pieces, loot entries and other sub-resources inside a file are checked too.


## Checks everything. Returns a list of problems; empty means all good.
## known_type_keys: the registry's type keys (ContentRegistry.get_type_keys()).
static func validate_all(all_content: Array[ContentData], known_type_keys: Array[StringName]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var by_id: Dictionary = {}
	for data: ContentData in all_content:
		if data == null:
			problems.append("A null content entry was found.")
			continue
		if by_id.has(data.id):
			problems.append("Duplicate id '%s'." % data.id)
		by_id[data.id] = data
	for data: ContentData in all_content:
		if data != null:
			problems.append_array(validate_one(data, by_id, known_type_keys))
	return problems


## Checks one content file against a lookup of every id (id -> ContentData).
static func validate_one(data: ContentData, by_id: Dictionary, known_type_keys: Array[StringName]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var label: String = _label(data)
	var type_key: String = String(data.get_type_key())
	var id_text: String = String(data.id)

	if type_key.is_empty():
		problems.append("%s: its data class doesn't override get_type_key()." % label)
	elif not id_text.begins_with(type_key + "_"):
		problems.append("%s: id must start with '%s_'." % [label, type_key])
	if id_text != id_text.to_lower() or id_text.contains(" "):
		problems.append("%s: ids are lower_snake_case with no spaces." % label)
	if not data.resource_path.is_empty():
		var file_base: String = data.resource_path.get_file().get_basename()
		if file_base != id_text:
			problems.append("%s: file name '%s' must match the id." % [label, data.resource_path.get_file()])

	for field: String in data.get_required_fields():
		if _is_empty_value(data.get(field)):
			problems.append("%s: required field '%s' is empty." % [label, field])

	_check_references(data, label, by_id, known_type_keys, problems, 0)
	return problems


static func _check_references(object: Resource, label: String, by_id: Dictionary, known_type_keys: Array[StringName], problems: PackedStringArray, depth: int) -> void:
	if depth > 8:
		return
	for property: Dictionary in object.get_property_list():
		var usage: int = property["usage"] as int
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var field: String = property["name"] as String
		var value: Variant = object.get(field)
		if field.ends_with("_id"):
			_check_one_reference(value, field, field.trim_suffix("_id"), label, by_id, known_type_keys, problems)
		elif field.ends_with("_ids"):
			if value is Array or value is PackedStringArray:
				for entry: Variant in value:
					_check_one_reference(entry, field, field.trim_suffix("_ids"), label, by_id, known_type_keys, problems)
		elif value is Array:
			for i: int in (value as Array).size():
				var entry: Variant = (value as Array)[i]
				if entry == null:
					problems.append("%s: '%s' has an empty slot at position %d." % [label, field, i])
				elif _is_sub_data(entry):
					_check_references(entry as Resource, "%s.%s[%d]" % [label, field, i], by_id, known_type_keys, problems, depth + 1)
		elif _is_sub_data(value):
			_check_references(value as Resource, "%s.%s" % [label, field], by_id, known_type_keys, problems, depth + 1)


static func _check_one_reference(value: Variant, field: String, field_stem: String, label: String, by_id: Dictionary, known_type_keys: Array[StringName], problems: PackedStringArray) -> void:
	if not (value is String or value is StringName):
		return
	var ref: String = String(value)
	if ref.is_empty():
		return
	if not by_id.has(StringName(ref)):
		problems.append("%s: '%s' points to '%s', which doesn't exist." % [label, field, ref])
		return
	var expected_type: String = field_stem.get_slice("_", field_stem.get_slice_count("_") - 1)
	if known_type_keys.has(StringName(expected_type)) and not ref.begins_with(expected_type + "_"):
		problems.append("%s: '%s' should point to a '%s', but '%s' isn't one." % [label, field, expected_type, ref])


## Sub-data = a scripted Resource saved inside a content file (effect pieces, loot entries).
## Content files referenced directly, scenes, textures and audio are not walked.
static func _is_sub_data(value: Variant) -> bool:
	if not (value is Resource):
		return false
	if value is ContentData:
		return false
	return (value as Resource).get_script() != null


static func _is_empty_value(value: Variant) -> bool:
	if value == null:
		return true
	if value is String or value is StringName:
		return String(value).is_empty()
	if value is Array:
		return (value as Array).is_empty()
	if value is PackedStringArray:
		return (value as PackedStringArray).is_empty()
	return false


static func _label(data: ContentData) -> String:
	if not data.resource_path.is_empty():
		return "%s (%s)" % [data.id, data.resource_path]
	return String(data.id) if not String(data.id).is_empty() else "<content with no id>"
