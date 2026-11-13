class_name LureBehaviourData
extends ItemBehaviourData
## Point the item at something to leave a lure there (NEW 2026-11-12, roadmap WP14): the laser pointer's dot.
## Enemies whose EnemyData.lure_kinds lists `lure_kind` and that can see the spot go to it instead of to you.

## The kind of lure it leaves (see Lure): "laser".
@export var lure_kind: StringName = &"laser"
## How far (m) the item reaches.
@export var reach: float = 30.0
## How long (s) the lure stays after a click. Clicking again moves it.
@export var seconds: float = 3.0
## How far (m) from the spot enemies are drawn.
@export var radius: float = 12.0
## The dot everyone sees.
@export var dot_color: Color = Color(1.0, 0.1, 0.1)
