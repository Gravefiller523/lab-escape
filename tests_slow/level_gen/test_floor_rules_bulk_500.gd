extends "res://tests/unit/level_gen/test_floor_rules_bulk.gd"
## NEW 2026-11-10 (floor generation step 4f): the full bulk test from the plan: 500 floors per department (about
## a minute). Not in the normal run; run it with:
## godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests_slow -ginclude_subdirs -gexit


func before_all() -> void:
	seeds = 500
