class_name SecurityMapOverlay
extends Control
## NEW 2026-11-10 (floor generation step 4e, plan section 7.1): what moves on the security room's map table,
## drawn on top of the floor plan (a FloorMapView in the "security" style, drawn once): the wings (or rooms)
## that hold a broken lift part, shaded and blinking; every player as a coloured dot; a slow scan line.
## The SecurityMapTable fills it in a few times a second.

const HIGHLIGHT_COLOR: Color = Color(1.0, 0.55, 0.15, 0.45)
const SCAN_COLOR: Color = Color(0.6, 1.0, 0.85, 0.12)

## The floor plan underneath (for where things are on screen).
var map: FloorMapView
## Placements (FloorLayout.placements indexes) to shade while blinking on.
var highlighted: Array[int] = []
var blink_on: bool = true
## Players: {"cells": Vector2 (where on the floor, in grid cells), "color": Color}.
var dots: Array[Dictionary] = []
## How far down the scan line is (0 = top, 1 = bottom).
var scan: float = 0.0


func _draw() -> void:
	if map == null or map.layout == null:
		return
	if blink_on:
		for index: int in highlighted:
			var rect: Rect2 = map.room_screen_rect(index)
			draw_rect(rect.grow(-1.0), HIGHLIGHT_COLOR)
			draw_rect(rect.grow(-1.0), HIGHLIGHT_COLOR.lightened(0.4), false, 2.0)
	for dot: Dictionary in dots:
		var at: Vector2 = map.cells_to_screen(dot["cells"])
		draw_circle(at, 7.0, Color(0.0, 0.0, 0.0, 0.7))
		draw_circle(at, 5.0, dot["color"])
	var y: float = scan * size.y
	draw_rect(Rect2(0.0, y - 6.0, size.x, 12.0), SCAN_COLOR)
	draw_line(Vector2(0.0, y), Vector2(size.x, y), SCAN_COLOR * Color(1, 1, 1, 2.5), 1.0)
