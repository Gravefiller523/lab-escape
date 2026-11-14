class_name CreditsData
extends Resource
## The words the credits roll shows (NEW 2026-11-13, roadmap WP19). Lives in res://config/credits.tres and is written
## from docs/CREDITS.md (keep the two the same). The engine's own licence notices are added after it by the credits
## screen, straight from Godot, so they are always complete.

## Each line is one line on screen. A line starting with "# " is a heading; an empty line is a gap.
@export_multiline var text: String = ""
