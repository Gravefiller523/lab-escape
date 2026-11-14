class_name HudStyle
## Shared looks for the HUD widgets (NEW 2026-11-11, roadmap WP5): outlined labels, dark see-through panels and flat
## bars. CHANGED 2026-11-14 (roadmap WP27, Zachary OK'd the mock-up): the lab theme's colours (dark ink panels,
## safety-yellow accents); the rest of the UI gets them from assets/ui/lab_theme.tres (the project's theme).

const FONT_SIZE: int = 20
const SMALL_FONT_SIZE: int = 16
const OUTLINE_SIZE: int = 6
const PANEL_COLOR: Color = Color(0.06, 0.07, 0.09, 0.8)
const PANEL_BORDER: Color = Color(1, 1, 1, 0.15)
const ACCENT: Color = Color(0.96, 0.76, 0.12)
const TRACK_COLOR: Color = Color(0, 0, 0, 0.55)
const GOOD: Color = Color(0.35, 0.8, 0.35)
const WARN: Color = Color(0.95, 0.7, 0.2)
const BAD: Color = Color(0.9, 0.25, 0.2)
const MUTED: Color = Color(1, 1, 1, 0.65)


static func label(node_name: String, font_size: int = FONT_SIZE) -> Label:
	var text := Label.new()
	text.name = node_name
	text.add_theme_font_size_override("font_size", font_size)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return text


static func panel_box(border: Color = PANEL_BORDER, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_COLOR
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	return box


## NEW 2026-11-14 (roadmap WP27): a panel with a thick coloured stripe down its left side (floor, lift, health).
static func accent_box(color: Color = ACCENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_COLOR
	box.border_color = color
	box.border_width_left = 6
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	return box


static func panel(node_name: String) -> PanelContainer:
	var container := PanelContainer.new()
	container.name = node_name
	container.add_theme_stylebox_override("panel", panel_box())
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return container


## A flat bar: a dark track and a coloured fill. Change the fill colour with set_bar_color.
static func bar(node_name: String, size: Vector2, fill: Color) -> ProgressBar:
	var progress := ProgressBar.new()
	progress.name = node_name
	progress.custom_minimum_size = size
	progress.max_value = 1.0
	progress.show_percentage = false
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_COLOR
	track.set_corner_radius_all(4)
	progress.add_theme_stylebox_override("background", track)
	set_bar_color(progress, fill)
	return progress


static func set_bar_color(progress: ProgressBar, fill: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(4)
	progress.add_theme_stylebox_override("fill", box)
