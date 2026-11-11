class_name RangedAttackData
extends Resource
## How an enemy shoots (NEW 2026-11-11, roadmap WP9). Lives inside an EnemyData file (its `ranged_attack` field);
## an enemy with one and an "attack_ranged" state in its scene keeps its distance and fires projectiles. Botany's
## spore shooter, Robotics' turrets and drones, and Robobrain all use it. Every number here is tuning.

## Shots per attack (a burst), fired `shot_interval` seconds apart.
@export_range(1, 20) var shots: int = 1
@export var shot_interval: float = 0.2
## Metres per second.
@export var projectile_speed: float = 14.0
## How much gravity pulls it down (0 = flies straight, 1 = falls like a thrown thing).
@export_range(0.0, 1.0) var gravity_scale: float = 0.0
## Random aim error, in degrees either way.
@export var spread_degrees: float = 3.0
@export var damage: float = 8.0
@export var damage_type: StringName = &"blunt"
## A status effect the hit gives (e.g. "status_burning"); empty = none.
@export var status_id: StringName = &""
## It shoots between these distances: closer and it backs off, further and it walks closer.
@export var min_range: float = 4.0
@export var max_range: float = 16.0
## Size of the projectile's ball (metres) and its colour (grey-box look until the art pass).
@export var projectile_radius: float = 0.15
@export var projectile_color: Color = Color(0.6, 0.9, 0.3)
## Seconds before a projectile that hits nothing disappears.
@export var lifetime: float = 4.0
