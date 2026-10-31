extends Node
## Autoload "Config". Holds the live GameConfig (tuning numbers).
## Use: Config.game.max_players
## NEW 2026-10-30: and the live FloorGenTuning (floor generation numbers): Config.floor_gen.grid_unit
## NEW 2026-10-29: also holds the live FeelTuning ("how it feels" numbers): Config.feel.props.throw_force
## Also registers the default input actions so every system can use them.

const CONFIG_PATH: String = "res://config/game_config.tres"
const FEEL_PATH: String = "res://config/feel_tuning.tres"
const FLOOR_GEN_PATH: String = "res://config/floor_gen_tuning.tres"

var game: GameConfig
var feel: FeelTuning
## NEW 2026-10-30: floor generation numbers (FloorGenTuning). Not used by gameplay yet.
var floor_gen: FloorGenTuning


func _enter_tree() -> void:
	# _enter_tree runs before other autoloads' _ready, so Config.game is
	# always set by the time anything else asks for it.
	if ResourceLoader.exists(CONFIG_PATH):
		game = load(CONFIG_PATH) as GameConfig
	if game == null:
		push_error("Config: could not load %s, using defaults." % CONFIG_PATH)
		game = GameConfig.new()
	_load_feel()
	_load_floor_gen()
	InputActions.ensure_registered()


func _load_feel() -> void:
	if ResourceLoader.exists(FEEL_PATH):
		feel = load(FEEL_PATH) as FeelTuning
	if feel == null:
		push_error("Config: could not load %s, using defaults." % FEEL_PATH)
		feel = FeelTuning.new()
	# A section left empty in the file falls back to the defaults written in its script.
	if feel.player == null:
		feel.player = PlayerTuning.new()
	if feel.props == null:
		feel.props = PropTuning.new()
	if feel.ai == null:
		feel.ai = AiTuning.new()


func _load_floor_gen() -> void:
	if ResourceLoader.exists(FLOOR_GEN_PATH):
		floor_gen = load(FLOOR_GEN_PATH) as FloorGenTuning
	if floor_gen == null:
		push_error("Config: could not load %s, using defaults." % FLOOR_GEN_PATH)
		floor_gen = FloorGenTuning.new()
