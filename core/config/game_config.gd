class_name GameConfig
extends Resource
## Every tuning number in one place. The live copy is res://config/game_config.tres,
## loaded by the Config autoload: read it with Config.game.<field>.
## Change numbers in the Inspector during playtests; never copy them into code.
## Per-content numbers (an enemy's health, an item's price) live in content files instead.

@export_group("Players")
## Most players in one lobby. Never assume 4 anywhere in code: read this.
@export_range(1, 16) var max_players: int = 4
## Seconds a joining PC has to load the host's current scene before its connection gives up.
@export var join_load_timeout: float = 30.0
## NEW 2026-10-19 (ui): other players' names float above their heads when you are this close (metres).
@export var nameplate_range: float = 5.0
## NEW 2026-10-19 (ui): how long a nameplate takes to fade in or out as you cross that distance (seconds).
@export var nameplate_fade_seconds: float = 0.4

@export_group("Run")
## Floors per department, before its boss floor.
@export var floors_per_department: int = 5
## Departments in one run.
@export var departments_per_run: int = 3
## Non-zero forces every run to use this seed (for testing).
@export var debug_run_seed: int = 0
## Seconds the elevator rides down from the Break Room before the first floor loads.
@export var elevator_ride_seconds: float = 2.0
## Seconds the run summary shows before everyone goes back to the Break Room.
@export var run_summary_seconds: float = 5.0
## Seconds the host waits for every PC to finish building a floor before starting it anyway.
@export var floor_load_timeout: float = 20.0
## Shortest cargo lift ride between floors (seconds); longer if a PC is still building the next floor.
@export var lift_ride_seconds: float = 8.0
## How fast the shaft slides past the lift while it rides (metres per second, looks only).
@export var lift_ride_speed: float = 4.0
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
## @deprecated Not used any more (2026-10-17): nothing is too heavy to move. Kept so existing
## files keep working.
@export var two_player_lift_max_mass: float = 120.0
## Heavy objects (above grab_max_mass): each person holding one takes this many kg off its weight.
## 1 person moves it very slowly, more people faster; once they take off all of it, it is fully lifted.
@export var heavy_lift_per_holder: float = 30.0
## Fastest (m/s) a held object can be carried; heavy ones go slower with fewer helpers.
@export var held_prop_max_speed: float = 8.0
## How fast (m/s) a fully lifted prop may move to keep up with your hands (Half-Life 2: about 19).
@export var held_prop_track_speed: float = 20.0
## A dropped prop moves at most this fast (m/s), so you can't fling things by spinning around.
@export var held_prop_release_max_speed: float = 10.5
## How far away (m) a player can grab something.
@export var grab_reach: float = 2.5
## How far in front of the camera (m) a held object floats.
@export var hold_distance: float = 1.6
## If a held object gets stuck this far (m) from where it should be, it is dropped.
@export var hold_break_distance: float = 1.5
## @deprecated Not used any more (2026-10-18): see throw_force.
@export var throw_impulse: float = 10.0
## Throw strength, Half-Life 2 style: the push is throw_force x a weight factor (0.5 at 0.5 kg up to 4
## at 15 kg and above), so a 10 kg crate flies about 10 m/s and heavier things go less far.
@export var throw_force: float = 34.0
## How often (per second) moving props near players are sent to clients.
@export var prop_sync_rate_near: int = 40
## How often (per second) moving props far from every player are sent.
@export var prop_sync_rate_far: int = 4
## Clients show props this many milliseconds behind the host, so they can glide evenly between
## snapshots instead of hopping. Higher = smoother but later.
@export var prop_interpolation_delay_msec: int = 50
## A prop that just changed which PC runs its physics waits this long (msec) before changing again,
## so two players grabbing it back and forth don't make it hop between PCs.
@export var prop_owner_cooldown_msec: int = 300
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
@export var voice_full_volume_distance: float = 10.0
## Beyond this distance (m) voices are silent. 0 = hear everyone everywhere.
@export var voice_max_distance: float = 46.0
## The shape of the fade between the two distances: left edge = full volume distance, right edge =
## max distance; height = volume (1 = full, 0 = silent). Drag the points in the Inspector to reshape it.
## Default: drops fairly quickly, then a long, quiet tail where you can barely hear someone.
@export var voice_distance_curve: Curve = default_voice_distance_curve()
## Far voices lose their high frequencies (like sound across a big space): the treble cut-off (Hz)
## at the max distance.
@export var voice_far_cutoff_hz: float = 2500.0
## Reverb (0 to 1) every voice has even up close, so the lab sounds like a big underground facility.
@export_range(0.0, 1.0) var voice_near_reverb: float = 0.2
## How much reverb (0 to 1) a voice has at the max distance, so far voices sound spread out.
@export_range(0.0, 1.0) var voice_far_reverb: float = 0.45
## How loud (0 to 1) the faint echo (a repeat ~0.3 s later) is at the max distance.
@export_range(0.0, 1.0) var voice_far_echo: float = 0.2
@export var voice_push_to_talk_default: bool = false
## Open mic: how easily your voice is picked up, 0 to 1. Higher = quieter talking is sent too.
## Lower it if background noise keeps your mic on. (settings_input will let players change it.)
@export_range(0.0, 1.0) var voice_mic_sensitivity: float = 0.7
## Over Steam: true = Steam records and compresses the mic (Steam's own voice settings decide when you talk);
## false = Godot records the mic the same way as local mode (our sensitivity slider applies) and sends it
## over Steam. False since the 2026-10-18 Steam test, where Steam's recording gave no audio.
@export var voice_use_steam_recording: bool = false
## Physics layer number (1 to 32) of things that block sound: level walls and floors (1 = world).
@export_range(1, 32) var voice_sound_blocker_layer: int = 1
## A fully muffled voice (behind a wall) is this loud, 0 to 1.
@export_range(0.0, 1.0) var voice_muffle_volume: float = 0.25
## A fully muffled voice keeps sounds below this pitch (Hz). Lower = more "through a wall".
@export var voice_muffle_cutoff_hz: float = 550.0
## Extra muffle (0 to 1) for each corner a voice goes round on its way through doors and halls.
@export_range(0.0, 1.0) var voice_corner_muffle: float = 0.1
## Extra muffle (0 to 1) for each closed door a voice passes through.
@export_range(0.0, 1.0) var voice_closed_door_muffle: float = 0.7
## A voice that has to go through a closed door can't be heard past this distance (metres).
@export var voice_closed_door_max_distance: float = 15.0
## Through a closed door, voices are only at full volume this close (metres); the fade starts after.
@export var voice_closed_door_full_volume_distance: float = 4.0
## How often each PC re-checks walls, doors and routes for every voice.
@export var voice_hearing_updates_per_second: float = 10.0

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


## The default voice fade (see voice_distance_curve): full, a fairly quick drop, then a long quiet tail.
static func default_voice_distance_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.15, 0.35))
	curve.add_point(Vector2(0.4, 0.12))
	curve.add_point(Vector2(0.75, 0.05))
	curve.add_point(Vector2(0.92, 0.025))
	curve.add_point(Vector2(1.0, 0.0))
	return curve
