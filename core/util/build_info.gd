class_name BuildInfo
## Which build of the game this is (NEW 2026-11-12, roadmap WP13b). Two parts:
## - the version: the number people say out loud, from Project Settings > Application > Config > Version;
## - the stamp: a short fingerprint that is different for every build, worked out by itself. In an exported game it
##   is taken from the game's own data file (the .pck next to the .exe), so two people who unzipped the same test
##   build always match and any two different builds never do. When running from the editor it is the git commit.
## net_core compares get_build_id() when a player joins, so mixed builds are turned away with a clear message
## instead of misbehaving on one PC. Spec: docs/systems/foundation.md.

const STAMP_LENGTH: int = 7
const DEV_PREFIX: String = "dev-"
const UNKNOWN_STAMP: String = "unknown"

static var _stamp: String = ""


## The version number, e.g. "0.1.0".
static func get_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## The fingerprint of this build, e.g. "3fa9c1d" (exported) or "dev-a3d2b76" (editor). Worked out once.
static func get_stamp() -> String:
	if _stamp.is_empty():
		_stamp = _editor_stamp() if OS.has_feature("editor") else _exported_stamp()
	return _stamp


## What net_core compares: version and stamp together.
static func get_build_id() -> String:
	return "%s+%s" % [get_version(), get_stamp()]


## For people: "v0.1.0 build 3fa9c1d".
static func get_label() -> String:
	return label_for(get_build_id())


## A build id (get_build_id) written for people. An empty id is a build from before the check existed.
static func label_for(build_id: String) -> String:
	if build_id.is_empty():
		return "an older build"
	var parts: PackedStringArray = build_id.split("+", true, 1)
	return "v%s build %s" % [parts[0], parts[1]] if parts.size() == 2 else build_id


## An exported game: the first letters of the MD5 of its data file (the .pck), or of the .exe when the data is
## packed inside it.
static func _exported_stamp() -> String:
	var exe: String = OS.get_executable_path()
	for path: String in [exe.get_basename() + ".pck", exe]:
		if FileAccess.file_exists(path):
			var md5: String = FileAccess.get_md5(path)
			if not md5.is_empty():
				return md5.substr(0, STAMP_LENGTH)
	return UNKNOWN_STAMP


## From the editor: the git commit the project folder is on ("dev-" plus its first letters).
static func _editor_stamp() -> String:
	return DEV_PREFIX + commit_from_git_folder(ProjectSettings.globalize_path("res://.git"))


## Reads the current commit out of a .git folder without needing git installed. "unknown" if it can't.
static func commit_from_git_folder(git_folder: String) -> String:
	var head: String = _read_text(git_folder.path_join("HEAD")).strip_edges()
	if head.is_empty():
		return UNKNOWN_STAMP
	if not head.begins_with("ref:"):
		return head.substr(0, STAMP_LENGTH)
	var ref: String = head.trim_prefix("ref:").strip_edges()
	var commit: String = _read_text(git_folder.path_join(ref)).strip_edges()
	if commit.is_empty():
		# Git sometimes keeps branch tips together in one "packed-refs" file: "<commit> <ref>" per line.
		for line: String in _read_text(git_folder.path_join("packed-refs")).split("\n"):
			if line.strip_edges().ends_with(" " + ref):
				commit = line.strip_edges().get_slice(" ", 0)
				break
	return commit.substr(0, STAMP_LENGTH) if not commit.is_empty() else UNKNOWN_STAMP


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
