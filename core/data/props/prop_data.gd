class_name PropData
extends ContentData
## A loose physics object players carry by hand or in a cart:
## gems, meat, robot parts, lift parts, keycards, crates, trash.
## Example id: "prop_gem". Files live in res://content/props/.

## The RigidBody3D scene. Its root must use the physics_props system's NetProp script.
@export var scene: PackedScene
## Kilograms. Above GameConfig.grab_max_mass one player can only drag it slowly; each extra
## helper (or pusher) makes it faster.
@export var mass: float = 1.0
## Key objects (lift parts, keycards) respawn somewhere safe if they fall out of the world.
@export var is_key_object: bool = false
## Can it be put in a cart?
@export var cart_allowed: bool = true
## Seconds before it vanishes when nobody touches it. 0 = never.
@export var despawn_after_seconds: float = 0.0
## Money value for gems. 0 for everything else.
@export var gem_value: int = 0
## True for glowing gems and robot parts: holding it and pressing use
## gives the upgrade stored on the object.
@export var grants_upgrade: bool = false
## NEW 2026-10-19: lift parts. Which cargo lift slot this fits (e.g. "gear", "fuse"); empty = not a lift part.
## Every prop with a lift_slot adds that slot to the lift, so a new part type is just a new file.
@export var lift_slot: StringName = &""
## Fragile: it shatters when it hits something at this speed or faster (metres per second). 0 = sturdy.
@export var fragile_break_speed: float = 0.0
## Seconds it must sit on a charger before a lift slot accepts it (a battery). 0 = no charging.
@export var needs_charge_seconds: float = 0.0
## NEW 2026-10-29: what it is made of, for its knock and scrape sounds: a file name in
## res://systems/audio/surfaces/ (wood, metal, glass, flesh, concrete).
@export var surface: StringName = &"wood"
## NEW 2026-10-29: breakable props: how much knocking about it takes before it breaks (hard hits wear it
## down, see PropTuning.prop_self_damage_scale). 0 = never breaks this way.
@export var health: float = 0.0
## NEW 2026-10-29: how many pieces it breaks into (plain boxes in its colour), unless break_scene is set.
@export var break_pieces: int = 6
## NEW 2026-10-29: optional scene of pieces (RigidBody3D children) to show when it breaks.
@export var break_scene: PackedScene
## NEW 2026-10-30 (floor generation): lift parts only: "small", "medium", "large" or "huge". Decides which
## "lift_part" markers it fits (their max_size) and how likely it is on higher floors.
@export var part_size: StringName = &""
## NEW 2026-10-30 (floor generation): lift parts only: "mechanical", "electrical", "electronic", "power",
## "structural"... Matched against the rooms' part_categories, so parts turn up where they make sense.
@export var part_category: StringName = &""


func get_type_key() -> StringName:
	return &"prop"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("scene")
	return fields
