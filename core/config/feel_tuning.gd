class_name FeelTuning
extends Resource
## Every "how it feels" number in one place: movement, props and enemies. NEW 2026-10-29.
## The live copy is res://config/feel_tuning.tres, loaded by the Config autoload: read it with
## Config.feel.player / Config.feel.props / Config.feel.ai. Open the file in the Inspector and fold out a
## section to tweak it. While the game runs, the debug console's `tune` command changes values live.
## Game rules (players, floors, loot, network rates) stay in GameConfig (res://config/game_config.tres).

## Walking, sprinting, jumping, crouching, ladders, mutation movement, mouse look limits.
## This is systems/player/player_tuning.tres (the player scene uses the same file).
@export var player: PlayerTuning
## Picking up, holding, throwing and pushing props.
@export var props: PropTuning
## How enemies see, remember, turn and move.
@export var ai: AiTuning
