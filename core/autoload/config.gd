extends Node
## Autoload "Config". Holds the live GameConfig (tuning numbers).
## Use: Config.game.max_players
## Also registers the default input actions so every system can use them.

const CONFIG_PATH: String = "res://config/game_config.tres"

var game: GameConfig


func _enter_tree() -> void:
	# _enter_tree runs before other autoloads' _ready, so Config.game is
	# always set by the time anything else asks for it.
	if ResourceLoader.exists(CONFIG_PATH):
		game = load(CONFIG_PATH) as GameConfig
	if game == null:
		push_error("Config: could not load %s, using defaults." % CONFIG_PATH)
		game = GameConfig.new()
	InputActions.ensure_registered()
