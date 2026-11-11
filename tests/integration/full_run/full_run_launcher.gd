extends Node
## The scene tests/integration/test_full_run.gd starts in each game process (NEW 2026-11-11, roadmap WP1). It puts
## a full_run_driver.gd node under the tree's root (so it outlives GameFlow's scene changes) and steps aside.

const DRIVER: Script = preload("res://tests/integration/full_run/full_run_driver.gd")


func _ready() -> void:
	var driver := Node.new()
	driver.name = "FullRunDriver"
	driver.set_script(DRIVER)
	get_tree().root.add_child.call_deferred(driver)
