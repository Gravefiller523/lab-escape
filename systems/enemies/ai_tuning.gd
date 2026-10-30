class_name AiTuning
extends Resource
## How every enemy thinks and moves, for all enemy types. NEW 2026-10-29 (feel tuning, step 0).
## The live copy is the "ai" section of res://config/feel_tuning.tres (open it in the Inspector).
## Read it with Config.feel.ai.<field>. Per-enemy numbers (health, speed, sight range, view cone, dodging)
## stay in content/enemies/*.tres.

@export_group("Senses")
## How often (seconds) an enemy looks for players. Lower = reacts faster but costs more.
@export var sight_check_seconds: float = 0.2
## An enemy's eyes are this high (m) above its origin.
@export var eye_height: float = 0.4
## Enemies aim their sight line at this height (m) on a player: the chest.
@export var player_chest_height: float = 1.0
## Seconds it remembers a player it can no longer see. CHANGED 2026-10-30 (HL2 feel step 3.2): 3 -> 5.5.
@export var target_memory_seconds: float = 5.5
## NEW 2026-10-30 (step 3.2): a player this close (m) is noticed from any side, even outside the view cone.
@export var close_sense_range: float = 3.0
## NEW 2026-10-30 (step 3.2): seconds a player must stay in view before an enemy reacts (it squeaks, then
## comes). Players inside close_sense_range, and players it already knows about, are noticed at once.
@export var notice_seconds: float = 0.45
## NEW 2026-10-30 (step 3.2): at most this many sight lines for all enemies together each physics tick;
## the rest look a tick later. Keeps big packs cheap.
@export var sight_rays_per_tick: int = 10
## NEW 2026-10-30 (step 3.2): seconds an enemy looks around where it last saw (or heard) someone before
## giving up.
@export var search_seconds: float = 2.5

@export_group("Hearing")
## NEW 2026-10-30 (step 3.3): how far (m) each noise carries. Calm enemies within it come to look.
@export var noise_crouch_step: float = 2.0
@export var noise_step: float = 5.0
@export var noise_sprint_step: float = 10.0
@export var noise_landing: float = 7.0
## A prop knock carries from the quietest distance (a soft bump) to the loudest (a hard hit).
@export var noise_prop_quietest: float = 3.0
@export var noise_prop_loudest: float = 15.0
## An enemy dying squeals this far.
@export var noise_death: float = 15.0
## NEW 2026-10-30 (step 3.3): an enemy that notices a player tells others of its kind this close (m).
@export var pack_alert_radius: float = 13.0

@export_group("Fighting")
## NEW 2026-10-30 (step 3.4): "attack tickets" per player. An enemy needs one (a kangaroo needs
## EnemyData.attack_tickets = 2) to start an attack; the others circle until one is free.
@export var attack_tickets_per_player: int = 2
## A ticket is handed back after this long (s) even if the attack never happened.
@export var ticket_max_hold: float = 2.0
## At least this long (s) between two tickets given out for the same player.
@export var ticket_grant_gap: float = 0.4
## Enemies waiting for a ticket circle the player this far away (m).
@export var circle_distance: float = 3.5
## Seconds an attack winds up (with a growl) before it strikes, so you can see it coming.
@export var attack_windup: float = 0.4
## After the wind-up, how long (s) the strike can still connect (a kangaroo's leap).
@export var attack_strike_seconds: float = 0.6
## Choosing whom to go after: the current target counts as this many times closer (it sticks to you).
@export var target_stickiness: float = 1.3
## ...and is kept at least this long (s) while it's still in view.
@export var target_min_hold: float = 2.0
## Each other enemy already after a player makes that player count as this much further away (x 1.5 for
## one, x 2 for two...), so enemies spread over the team.
@export var target_crowd_penalty: float = 0.5
## A player who hurt this enemy in the last few seconds counts as this many times closer.
@export var target_revenge: float = 1.6

@export_group("Dodging")
## NEW 2026-10-30 (step 3.6): props at least this heavy (kg) flying at an enemy at least this fast (m/s)
## make it try to jump aside (EnemyData.dodge_chance).
@export var dodge_min_mass: float = 10.0
@export var dodge_min_speed: float = 6.0
## How far ahead (m) it watches for an incoming prop, how close (m) a prop must pass to count, and how
## fast (m/s) it jumps aside.
@export var dodge_look_distance: float = 8.0
@export var dodge_miss_distance: float = 1.3
@export var dodge_speed: float = 6.0
@export var dodge_cooldown: float = 2.0

@export_group("Moving")
## How fast enemies turn to face where they're going (higher = snappier).
@export var turn_speed: float = 8.0
## How often (seconds) a path is worked out again (each enemy starts at a random point, so they don't all
## do it on the same tick).
@export var repath_seconds: float = 0.25
## On other PCs, how quickly an enemy's copy catches up with where the host says it is.
@export var client_smoothing: float = 15.0
## NEW 2026-10-30 (step 3.5): walking enemies keep at least this gap (m) between their bodies, sliding
## round each other instead of piling up. Worked out every spacing_check_seconds (cheap for big packs).
@export var spacing_gap: float = 0.3
@export var spacing_check_seconds: float = 0.2

@export_group("Death")
## Seconds a dead enemy lies there before it's removed.
@export var corpse_seconds: float = 2.0
## NEW 2026-10-30 (step 3.6): at most this many tumbling bodies at once on each PC (the oldest goes first).
@export var max_corpses: int = 8
