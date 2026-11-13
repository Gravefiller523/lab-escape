extends GutTest
## BuildInfo: which build of the game this is (NEW 2026-11-12, roadmap WP13b).

const FOLDER: String = "user://test_build_info"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER.path_join("refs/heads/wp"))


func after_each() -> void:
	for path: String in ["refs/heads/wp/13b", "refs/heads/main", "HEAD", "packed-refs"]:
		if FileAccess.file_exists(FOLDER.path_join(path)):
			DirAccess.remove_absolute(FOLDER.path_join(path))


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(FOLDER.path_join(path), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_the_build_id_is_the_version_and_a_stamp() -> void:
	assert_eq(BuildInfo.get_version(), str(ProjectSettings.get_setting("application/config/version")))
	assert_ne(BuildInfo.get_version(), "0.0.0", "the project has a version number")
	assert_eq(BuildInfo.get_build_id(), "%s+%s" % [BuildInfo.get_version(), BuildInfo.get_stamp()])
	assert_true(BuildInfo.get_stamp().begins_with(BuildInfo.DEV_PREFIX), "from the editor it's a dev build")
	assert_eq(BuildInfo.get_stamp(), BuildInfo.get_stamp(), "and it doesn't change while the game runs")


func test_labels_are_written_for_people() -> void:
	assert_eq(BuildInfo.label_for("0.1.0+3fa9c1d"), "v0.1.0 build 3fa9c1d")
	assert_eq(BuildInfo.label_for(""), "an older build", "a build from before the check sends nothing")
	assert_eq(BuildInfo.get_label(), BuildInfo.label_for(BuildInfo.get_build_id()))


func test_the_commit_is_read_from_a_branch() -> void:
	_write("HEAD", "ref: refs/heads/wp/13b\n")
	_write("refs/heads/wp/13b", "0123456789abcdef0123456789abcdef01234567\n")
	assert_eq(BuildInfo.commit_from_git_folder(FOLDER), "0123456")


func test_the_commit_is_read_from_packed_refs() -> void:
	_write("HEAD", "ref: refs/heads/main\n")
	_write("packed-refs", "# pack-refs with: peeled fully-peeled sorted\nfeedfacefeedfacefeedfacefeedfacefeedface refs/heads/main\n")
	assert_eq(BuildInfo.commit_from_git_folder(FOLDER), "feedfac")


func test_a_checked_out_commit_and_a_missing_folder() -> void:
	_write("HEAD", "abcdef0123456789abcdef0123456789abcdef01\n")
	assert_eq(BuildInfo.commit_from_git_folder(FOLDER), "abcdef0", "HEAD can hold the commit itself")
	assert_eq(BuildInfo.commit_from_git_folder("user://no_such_folder"), BuildInfo.UNKNOWN_STAMP)
