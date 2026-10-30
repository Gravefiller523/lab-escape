class_name PropTuning
extends Resource
## How picking up, holding, throwing and pushing props feels. NEW 2026-10-29 (feel tuning, step 0).
## The live copy is the "props" section of res://config/feel_tuning.tres (open it in the Inspector).
## Read it with Config.feel.props.<field>. Change numbers there, never in code.
## Network numbers (sync rates, interpolation delay) stay in GameConfig.

@export_group("Picking up")
## Heaviest object (kg) one player can lift. Heavier ones need helpers (see heavy_lift_per_holder).
@export var grab_max_mass: float = 40.0
## Heavy objects: each person holding one takes this many kg off its weight. 1 person moves it very
## slowly, more people faster; once they take off all of it, it is fully lifted.
@export var heavy_lift_per_holder: float = 30.0
## How far away (m) a player can grab something.
@export var grab_reach: float = 2.5
## NEW 2026-10-29: if the look ray misses, a prop this close to the middle of the view still counts
## (1 = dead centre only; 0.8 = within about 37 degrees). Only when nothing else is aimed at.
@export_range(0.0, 1.0, 0.01) var grab_cone_dot: float = 0.8
## NEW 2026-10-29: nobody can pick up a prop that any player is standing on (Zachary's rule, so nobody
## can launch a teammate by grabbing the crate under them). Also drops a held prop someone steps onto.
@export var no_grab_while_stood_on: bool = true
## NEW 2026-10-29 (after Zachary's playtest): nor a prop under any player's feet down to this depth (m), even
## mid-jump, so nobody can "prop fly" by jumping and grabbing the box under them again and again.
@export var no_grab_below_depth: float = 1.2

@export_group("Holding")
## @deprecated 2026-10-29: use hold_base_gap (held props now float closer, by their size along your view).
@export var hold_distance: float = 1.6
## NEW 2026-10-29: gap (m) between your body and a held object's near side. The object's centre floats
## hold_base_gap + your body's radius + its own depth along your view in front of the eyes, so big and
## small things both sit just in front of you (Half-Life 2: about 1.2 m plus the object's size).
@export var hold_base_gap: float = 0.6
## NEW 2026-10-29 (after Zachary's playtest): a held object is always kept at least this far (m) outside your
## own body, so looking down at your feet never shoves you backwards.
@export var hold_body_clearance: float = 0.1
## A held object never comes closer to a wall in front of you than this (m).
@export var min_hold_gap: float = 0.2
## Furthest up or down (degrees) a held object follows your look (Half-Life 2: 75).
@export_range(0.0, 90.0) var max_hold_pitch_degrees: float = 75.0
## How fast (m/s) a fully lifted prop may move to keep up with your hands (Half-Life 2: about 25).
## CHANGED 2026-10-29: 25 (was 20), as Half-Life 2.
@export var held_prop_track_speed: float = 25.0
## Fastest (m/s) a heavy prop can be dragged; it goes slower with fewer helpers.
@export var held_prop_max_speed: float = 8.0
## Fastest a held prop turns to keep its angle (radians a second; Half-Life 2: 62.8 = 3600 degrees).
## Jolt's own limit (Project Settings > Physics > Jolt Physics 3D > Limits) must be at least this.
@export var hold_max_spin: float = 62.8
## While held, a fully lifted prop weighs this much (kg), so it nudges things gently (Half-Life 2: 1).
@export var held_mass: float = 1.0
## How strongly a held prop's spinning is slowed down (Half-Life 2: 10).
@export var held_angular_damp: float = 10.0
## Heavy props that aren't fully lifted are pulled toward your hands by a spring: its strength
## (per metre, per kg) and how much it damps wobbling.
@export var hold_stiffness: float = 150.0
@export var hold_damping: float = 22.0
## NEW 2026-10-29: while a held object touches something, its turning slows down to this share of normal
## (so it doesn't jitter against walls)...
@export_range(0.0, 1.0, 0.01) var hold_contact_spin_min: float = 0.1
## ...changing by this much a second (it speeds up again the same way once free).
@export var hold_contact_spin_rate: float = 2.0
## NEW 2026-10-29: picking something up that is within this many degrees of a tidy angle (square to the
## world) straightens it. 0 = off.
@export_range(0.0, 45.0) var carry_snap_angle_degrees: float = 30.0

@export_group("Dropping")
## @deprecated 2026-10-29: use hold_error_drop.
@export var hold_break_distance: float = 1.5
## @deprecated 2026-10-29: use hold_error_smoothing and hold_error_grace.
@export var hold_break_seconds: float = 0.4
## NEW 2026-10-29: a fully lifted object is dropped when it is, on average, this far (m) from where it
## should be (stuck behind something). Half-Life 2 uses 0.3; ours allows for network delay.
@export var hold_error_drop: float = 0.45
## How quickly that average follows the real distance (seconds; higher = slower to drop).
@export var hold_error_smoothing: float = 0.15
## No dropping for this long (seconds) after picking something up, while it flies to your hands.
@export var hold_error_grace: float = 1.0
## A dropped prop moves at most this fast (m/s), so you can't fling things by spinning around.
## CHANGED 2026-10-29: 7.2 (was 10.5), Half-Life 2's 1.5 x walking speed.
@export var held_prop_release_max_speed: float = 7.2
## A dropped prop spins at most this fast (radians a second; Half-Life 2: 12.6 = 720 degrees).
@export var release_max_spin: float = 12.6
## NEW 2026-10-29: a plain drop (not a throw) while the prop touches something stops it dead, so you
## can't fling things by dropping them against a wall (Half-Life 2 does this).
@export var drop_clears_velocity_on_contact: bool = true

@export_group("Throwing")
## Throw strength, Half-Life 2 style: the push is throw_force x a weight factor (0.5 at 0.5 kg up to 4
## at 15 kg and above), so a 10 kg crate flies about 10 m/s and heavier things go less far.
## CHANGED 2026-10-29: 25.4 (was 34), Half-Life 2's number (Zachary's choice).
@export var throw_force: float = 25.4
## A thrown prop gets up to this much random spin (radians a second on each axis).
@export var throw_spin: float = 3.0

## NEW 2026-10-29: no prop goes faster than this (m/s; Half-Life 2 caps about 51).
@export var prop_max_speed: float = 50.0
## NEW 2026-10-29: no sprinting while carrying something (Half-Life 2; Zachary's choice).
@export var disable_sprint_while_holding: bool = true

@export_group("Punt (punt arm cybernetic)")
## NEW 2026-10-30 (HL2 feel step 4.3): how far away (m) the punt reaches (Half-Life 2: about 6.35).
@export var punt_range: float = 6.35
## Seconds between punts (Half-Life 2: 0.5).
@export var punt_cooldown: float = 0.5
## A punted prop flies off at this speed (m/s; Half-Life 2: about 15)...
@export var punt_speed: float = 15.0
## ...plus up to this much more (m/s) the lighter it is below punt_light_mass (kg)...
@export var punt_light_bonus: float = 5.0
@export var punt_light_mass: float = 5.0
## ...but the push is never more than this (kg x m/s), so heavy things only shift: 600 sends a 40 kg prop
## at 15 m/s and an 80 kg one at 7.5.
@export var punt_max_impulse: float = 600.0
## A prop resting on something is never punted down into it: the launch points at least this far up (the
## upward part of the direction; 0.2 = about 12 degrees up; 0 = off), so things on the floor hop up and fly.
@export_range(0.0, 1.0, 0.01) var punt_floor_lift: float = 0.2
## NEW 2026-10-30 (Zachary): punting an enemy shoves it and never hurts it. It slides off at this push
## (kg x m/s) divided by its impact mass (a 5 kg rat: fast; a 50 kg kangaroo: 3 m/s)...
@export var punt_enemy_impulse: float = 150.0
## ...but no faster than this (m/s)...
@export var punt_enemy_max_speed: float = 10.0
## ...plus this much upwards (m/s) times the same share, so it hops instead of scraping the floor.
@export var punt_enemy_lift: float = 3.0
## If the look ray misses, a prop this close to the middle of the view still counts (0.97 = within about
## 14 degrees).
@export_range(0.0, 1.0, 0.01) var punt_cone_dot: float = 0.97

@export_group("Pull (punt arm cybernetic)")
## NEW 2026-10-30 (Zachary's idea): with the punt arm, holding E on a prop that is too far to pick up drags it
## towards you like a magnet (it keeps its weight and tumbles along), from up to this far (m).
## CHANGED 2026-10-30 (Zachary's playtest): 8 (was 15).
@export var pull_range: float = 8.0
## ...at up to this speed (m/s)...
@export var pull_speed: float = 10.0
## ...speeding up this fast (m/s per second).
@export var pull_acceleration: float = 40.0
## With the punt arm you can pick things up from this much further away (m) than grab_reach, and a pulled
## prop is picked up as soon as it is that close.
@export var pull_grab_bonus: float = 1.5
## How far above its middle the tug acts, as a share of its half height (0 = no tumbling, 1 = at its top).
@export_range(0.0, 1.0, 0.05) var pull_tumble: float = 0.5

@export_group("Sounds")
## NEW 2026-10-29 (Half-Life 2 numbers): a prop that loses less speed than this in a hit (m/s) is silent...
@export var impact_sound_min_speed: float = 1.8
## ...and one that loses this much or more is at full volume.
@export var impact_sound_full_speed: float = 8.0
## Loudness (dB) of the softest knock (at impact_sound_min_speed).
@export var impact_sound_quietest_db: float = -24.0
## At most one knock per prop this often (seconds).
@export var impact_sound_debounce: float = 0.05
## Loudness (dB) of the soft knock when a prop is picked up.
@export var pickup_sound_db: float = -18.0
## A prop sliding along something faster than this (m/s) scrapes...
@export var scrape_min_speed: float = 0.5
## ...louder up to this speed...
@export var scrape_full_speed: float = 4.0
## ...where it is this loud (dB).
@export var scrape_volume_db: float = -6.0

@export_group("Impact damage")
## NEW 2026-10-29: props lighter than this (kg) never hurt anything (gems, vials).
@export var impact_min_mass: float = 2.0
## A hit only counts if the prop loses at least this much speed (m/s).
@export var impact_damage_min_speed: float = 2.0
## Damage = impact_damage_scale x the prop's movement energy (half its mass x speed lost squared) / the
## victim's impact mass. A 10 kg crate losing 6 m/s: 36 to a rat (5 kg), 3.6 to a kangaroo (50 kg).
@export var impact_damage_scale: float = 1.0
## Props up to this mass (kg)...
@export var impact_small_mass: float = 5.0
## ...do at most this much damage per hit.
@export var impact_small_cap: float = 5.0
## Less damage than this is ignored (a gentle bump).
@export var impact_min_damage: float = 2.0
## Players count as this heavy (kg)...
@export var player_impact_mass: float = 85.0
## ...and take this share of the damage (teammates throwing things at each other).
@export_range(0.0, 1.0) var friendly_physics_damage_scale: float = 0.25
## Anything else that can be hurt (no enemy data) counts as this heavy (kg).
@export var default_impact_mass: float = 50.0
## The player who threw or dropped a prop gets the credit for hits within this many seconds.
@export var physics_attacker_window: float = 2.0
## The same prop can hurt the same victim at most once this often (seconds).
@export var impact_report_cooldown: float = 0.25

@export_group("Breaking")
## NEW 2026-10-29: hard hits wear down breakable props (PropData.health): wear = this x half the speed lost
## squared. A crate thrown into a wall (about 7 m/s) loses about 25 of its 60.
@export var prop_self_damage_scale: float = 1.0
## NEW 2026-10-29 (after Zachary's playtests): sideways hits that take away less speed than this (m/s) never
## wear a prop down. A throw into a wall (about 7 m/s) counts.
@export var prop_wear_min_speed: float = 5.0
## Landing from a fall only wears a prop if it lands faster than this (m/s): 9 is a fall of about 2.7 m, so
## dropping a crate from head height (or looking up) is harmless.
@export var prop_wear_min_fall_speed: float = 9.0
## Most broken pieces lying around at once (the oldest go first).
@export var max_gibs: int = 64
## Seconds broken pieces stay before they shrink away...
@export var gib_lifetime: float = 6.0
## ...over this many seconds.
@export var gib_fade_seconds: float = 1.0

@export_group("Pushing")
## Props you walk into move this fraction of your speed, so you stay pressed against them.
@export var push_speed_factor: float = 0.9
