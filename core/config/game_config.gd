class_name GameConfig
extends Resource
## Every tuning number in one place. The live copy is res://config/game_config.tres,
## loaded by the Config autoload: read it with Config.game.<field>.
## Change numbers in the Inspector during playtests; never copy them into code.
## Per-content numbers (an enemy's health, an item's price) live in content files instead.

@export_group("Players")
## Most players in one lobby. Never assume 4 anywhere in code: read this.
@export_range(1, 16) var max_players: int = 4

@export_group("Run")
## Floors per department, before its boss floor.
@export var floors_per_department: int = 5
## Departments in one run.
@export var departments_per_run: int = 3
## Non-zero forces every run to use this seed (for testing).
@export var debug_run_seed: int = 0
## Size of one room grid cell in metres.
@export var room_cell_size: float = 12.0

@export_group("Inventory")
## Inventory slots every player starts a run with (fists are always available on top).
@export var base_inventory_slots: int = 1
## The item used when the active slot is empty.
@export var unarmed_item_id: StringName = &"item_fists"

@export_group("Floors")
## Co-op floor tasks per floor before player scaling.
@export var floor_tasks_base: int = 1
## One extra floor task for every this many players beyond the first 2. 0 = never.
@export var extra_floor_task_every_players: int = 3

@export_group("Gems and loot")
## Chance (0 to 1) that a dropped gem glows and holds a mutation.
@export_range(0.0, 1.0) var gem_glow_chance: float = 0.15
## Pity rule: each gem that doesn't glow adds this much to the chance,
## until one glows. 0 turns the pity rule off.
@export_range(0.0, 1.0) var gem_glow_pity_step: float = 0.03
## The glow chance never goes above this, even with pity.
@export_range(0.0, 1.0) var gem_glow_chance_max: float = 0.6
## Chance (0 to 1) that a regular enemy outside Robotics drops a robot part.
@export_range(0.0, 1.0) var off_department_robot_part_chance: float = 0.0
## Loose gems allowed on one floor before nearby plain gems merge into bigger ones.
@export var max_loose_gems_per_floor: int = 150

@export_group("Death and reprinting")
## Meat needed in the 3D printer to reprint one player.
@export var meat_per_reprint: int = 1
## Extra meat needed for each reprint already done this floor.
@export var meat_cost_growth_per_reprint: int = 0
## Free reprints per floor when playing alone.
@export var solo_free_reprints_per_floor: int = 1
## Seconds a dead player waits before they can be reprinted.
@export var reprint_min_wait: float = 3.0

@export_group("Physics props")
## Heaviest object (kg) one player can lift.
@export var grab_max_mass: float = 40.0
## Heaviest object (kg) two players can lift together.
@export var two_player_lift_max_mass: float = 120.0
## How far away (m) a player can grab something.
@export var grab_reach: float = 2.5
## How far in front of the camera (m) a held object floats.
@export var hold_distance: float = 1.6
## If a held object gets stuck this far (m) from where it should be, it is dropped.
@export var hold_break_distance: float = 1.5
## Throw strength (impulse per kg, capped by mass).
@export var throw_impulse: float = 10.0
## How often (per second) moving props near players are sent to clients.
@export var prop_sync_rate_near: int = 20
## How often (per second) moving props far from every player are sent.
@export var prop_sync_rate_far: int = 4
## Distance (m) beyond which a prop counts as far.
@export var prop_far_distance: float = 30.0
## Anything below this height (m) has fallen out of the world.
@export var out_of_world_y: float = -50.0

@export_group("Carts")
## Most objects one cart can hold.
@export var cart_capacity: int = 12
## Widest cart (m). Every door in every room must be wider than this.
@export var cart_width: float = 1.2

@export_group("Voice")
## Within this distance (m) voices are at full volume.
@export var voice_full_volume_distance: float = 4.0
## Beyond this distance (m) voices are silent. 0 = hear everyone everywhere.
@export var voice_max_distance: float = 30.0
@export var voice_push_to_talk_default: bool = false

@export_group("Difficulty")
## Extra enemy spawn budget per player beyond the first (0.35 = +35% each).
@export var enemy_budget_per_extra_player: float = 0.35
## Extra enemy health per player beyond the first.
@export var enemy_health_per_extra_player: float = 0.2
## Extra boss health per player beyond the first.
@export var boss_health_per_extra_player: float = 0.5
## Extra enemy budget per floor reached in the run.
@export var enemy_budget_per_floor: float = 0.1
## Base enemy spawn budget on the first floor.
@export var base_enemy_budget: int = 6

@export_group("Break Room")
## Seconds before the host may start without everyone in the elevator. 0 = never.
@export var afk_force_start_after: float = 60.0

@export_group("Debug")
## Allow cheats in exported (release) builds. Always on in the editor.
@export var cheats_in_release: bool = false
