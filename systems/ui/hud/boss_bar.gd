class_name BossBar
extends VBoxContainer
## The boss's name, phase and health across the top of the HUD, only while a boss is alive. NEW 2026-11-11
## (roadmap WP5). Reads Boss.current() (bosses). Spec: docs/systems/ui.md.

const BAR_SIZE: Vector2 = Vector2(420, 14)

var _title: Label
var _bar: ProgressBar
var _boss: Boss
var _use_test_boss: bool = false


## For tests only: show this boss instead of Boss.current().
func use_boss(boss: Boss) -> void:
	_boss = boss
	_use_test_boss = true


## "Giant Rat  phase 2 of 3", or "" when hidden.
func get_text() -> String:
	return _title.text if visible else ""


func get_fraction() -> float:
	return _bar.value


func _ready() -> void:
	name = "BossBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_title = HudStyle.label("Title")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_bar = HudStyle.bar("Bar", BAR_SIZE, HudStyle.BAD)
	add_child(_bar)


func _process(_delta: float) -> void:
	var boss: Boss = _boss if _use_test_boss else Boss.current()
	var health: HealthComponent = boss.get_health() if boss != null and is_instance_valid(boss) else null
	visible = health != null and not health.is_dead()
	if not visible:
		return
	var data: BossData = boss.boss_data
	var title: String = data.display_name if data != null and not data.display_name.is_empty() else "Boss"
	var phases: int = data.phases.size() if data != null else 0
	if phases > 1:
		title += "  phase %d of %d" % [clampi(boss.get_phase() + 1, 1, phases), phases]
	_title.text = title
	_bar.value = health.get_fraction()
