class_name UseTuning
extends Resource
## How using things feels. NEW 2026-10-30 (HL2 feel step 4.1).
## The live copy is the "interaction" section of res://config/feel_tuning.tres (open it in the Inspector).
## Read it with Config.feel.interaction.<field>. Per-object numbers (reach, hold time) stay on each Interactable.

@export_group("Aiming")
## If the thin look ray misses everything usable, a ball this wide (radius, metres) is swept along the
## same line to find a small button or handle just beside the crosshair (never through a wall). 0 = off.
@export var aim_assist_radius: float = 0.12

@export_group("Feedback")
## The "can't use that" buzz plays at most once per this many seconds.
@export var deny_cooldown: float = 0.3
