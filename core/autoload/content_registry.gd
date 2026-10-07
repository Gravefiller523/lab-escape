extends Node
## Autoload "ContentRegistry". Finds every content file at startup.
##
## It scans each type folder under res://content/ (and its subfolders) for .tres
## files, and indexes them by id. No system keeps a hand-written list of content:
## ask the registry instead.
##
## Lists come back sorted by id, so every PC sees the same order. Level generation
## and loot rolls rely on that to stay identical for all players.
##
## Files and folders whose names start with "_" or "." are skipped (scratch space).

const CONTENT_ROOT: String = "res://content"

## Content type key -> folder. The type key is also the id prefix ("mutation_fly").
## Adding a new content TYPE (rare) means adding a line here and a data class.
const TYPE_FOLDERS: Dictionary = {
	&"mutation": "mutations",
	&"cybernetic": "cybernetics",
	&"item": "items",
	&"status": "status_effects",
	&"prop": "props",
	&"enemy": "enemies",
	&"boss": "bosses",
	&"room": "rooms",
	&"department": "departments",
	&"task": "floor_tasks",
	&"cosmetic": "cosmetics",
	&"achievement": "achievements",
	&"loot": "loot_tables",
	&"stock": "vendor_stock",
}

## Problems found while loading (duplicate ids, wrong folder, unreadable file).
## The content validation test fails if this isn't empty.
var load_errors: PackedStringArray = PackedStringArray()

var _by_id: Dictionary = {}  # StringName -> ContentData
var _by_type: Dictionary = {}  # StringName -> Array[ContentData], sorted by id


func _ready() -> void:
	reload()


## Clears everything and scans the content folders again.
func reload() -> void:
	_by_id.clear()
	_by_type.clear()
	load_errors.clear()
	for type_key: StringName in TYPE_FOLDERS:
		_by_type[type_key] = [] as Array[ContentData]
		var folder: String = CONTENT_ROOT.path_join(TYPE_FOLDERS[type_key] as String)
		for path: String in _find_resource_files(folder):
			_load_file(type_key, path)
	for type_key: StringName in _by_type:
		(_by_type[type_key] as Array[ContentData]).sort_custom(_sort_by_id)


## Returns the content with this id, or null if there is none.
func get_content(id: StringName) -> ContentData:
	return _by_id.get(id, null) as ContentData


func has_content(id: StringName) -> bool:
	return _by_id.has(id)


## All content of one type, sorted by id. Disabled content is left out
## unless include_disabled is true.
func get_all(type_key: StringName, include_disabled: bool = false) -> Array[ContentData]:
	var result: Array[ContentData] = []
	if not _by_type.has(type_key):
		push_error("ContentRegistry: unknown content type '%s'." % type_key)
		return result
	for data: ContentData in _by_type[type_key] as Array[ContentData]:
		if include_disabled or data.enabled:
			result.append(data)
	return result


## Ids of all content of one type, sorted.
func get_all_ids(type_key: StringName, include_disabled: bool = false) -> Array[StringName]:
	var ids: Array[StringName] = []
	for data: ContentData in get_all(type_key, include_disabled):
		ids.append(data.id)
	return ids


## Every loaded content file of every type (including disabled), for validation.
func get_everything() -> Array[ContentData]:
	var result: Array[ContentData] = []
	for type_key: StringName in TYPE_FOLDERS:
		result.append_array(_by_type[type_key] as Array[ContentData])
	return result


func get_type_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for type_key: StringName in TYPE_FOLDERS:
		keys.append(type_key)
	return keys


## Adds content that isn't in a file (used by tests and the debug console).
## Returns false if the id is already taken.
func register_content(data: ContentData) -> bool:
	var type_key: StringName = data.get_type_key()
	if not _by_type.has(type_key):
		load_errors.append("Unknown content type '%s' for '%s'." % [type_key, data.id])
		return false
	if _by_id.has(data.id):
		load_errors.append("Duplicate id '%s'." % data.id)
		return false
	_by_id[data.id] = data
	var list: Array[ContentData] = _by_type[type_key] as Array[ContentData]
	list.append(data)
	list.sort_custom(_sort_by_id)
	return true


## The type key an id belongs to, from its prefix ("mutation_fly" -> &"mutation").
## Returns &"" if the prefix isn't a known type.
static func type_key_for_id(id: StringName) -> StringName:
	var text: String = String(id)
	for type_key: StringName in TYPE_FOLDERS:
		if text.begins_with(String(type_key) + "_"):
			return type_key
	return &""


func _load_file(type_key: StringName, path: String) -> void:
	var data: ContentData = ResourceLoader.load(path) as ContentData
	if data == null:
		load_errors.append("%s is not a content file (wrong Resource type or broken)." % path)
		return
	if data.get_type_key() != type_key:
		load_errors.append("%s is a '%s' but sits in the '%s' folder." % [path, data.get_type_key(), type_key])
		return
	if String(data.id).is_empty():
		load_errors.append("%s has no id." % path)
		return
	if _by_id.has(data.id):
		var other: ContentData = _by_id[data.id] as ContentData
		load_errors.append("Duplicate id '%s' in %s and %s." % [data.id, path, other.resource_path])
		return
	_by_id[data.id] = data
	(_by_type[type_key] as Array[ContentData]).append(data)


func _find_resource_files(folder: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for file_name: String in DirAccess.get_files_at(folder):
		if file_name.begins_with("_") or file_name.begins_with("."):
			continue
		# Exported games rename resources to "<name>.tres.remap"; load the original path.
		var clean_name: String = file_name.trim_suffix(".remap")
		if clean_name.ends_with(".tres") or clean_name.ends_with(".res"):
			var path: String = folder.path_join(clean_name)
			if not found.has(path):
				found.append(path)
	for sub_folder: String in DirAccess.get_directories_at(folder):
		if sub_folder.begins_with("_") or sub_folder.begins_with("."):
			continue
		found.append_array(_find_resource_files(folder.path_join(sub_folder)))
	return found


static func _sort_by_id(a: ContentData, b: ContentData) -> bool:
	return String(a.id) < String(b.id)
