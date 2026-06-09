extends Node2D
class_name Game

## Composition root. Builds the GameServices bundle, wires the systems
## together, and lays out the starting scenario. All gameplay logic lives in
## the subsystems:
##
##   Board           — pieces on the map: spawning, purchasing, death
##   TurnManager     — day counter + end-of-turn pipeline
##   InputController — selection, orders, rail keys, path preview
##   WeatherManager  — calendar, seasons, weather modifier lifecycle
##   CardManager     — deck, draws, triggers, scheduling
##   ModifierManager — every active buff/debuff, queried by stat
##   RailNetwork     — rail routes + trains
##   TerrainManager  — mountains, rivers, bridges, tunnels
##   FOWManager      — fog of war
##   EnemyAI         — opposing commander
##   UIManager       — panels, top bar, toasts, cards
##   Events (autoload) — global signal bus

@onready var grid = %Grid
@onready var ui: UIManager = $UI
@onready var path_line: Line2D = $PathLine
@onready var card_manager: CardManager = $CardManager
@onready var enemy_ai: EnemyAI = $EnemyAI
@onready var rail_network: RailNetwork = $RailNetwork
@onready var fow_manager: FOWManager = $FowManager
@onready var modifiers: ModifierManager = $ModifierManager
@onready var terrain_manager: TerrainManager = $TerrainManager
@onready var weather: WeatherManager = $WeatherManager
@onready var board: Board = $Board
@onready var turn_manager: TurnManager = $TurnManager
@onready var input_controller: InputController = $InputController

func _ready():
	var s := GameServices.new()
	s.grid = grid
	s.board = board
	s.turn = turn_manager
	s.modifiers = modifiers
	s.weather = weather
	s.terrain = terrain_manager
	s.rail_network = rail_network
	s.fow = fow_manager
	s.card_manager = card_manager
	s.enemy_ai = enemy_ai
	s.ui = ui

	# World generation
	terrain_manager.setup(grid)
	grid.terrain = terrain_manager
	terrain_manager.generate({
		"capital_hexes": [Vector2i(0, 3), Vector2i(0, -3)],
		"city_hexes": [Vector2i(0, 0)],
		"occupied": [Vector2i(2, 1), Vector2i(1, -3), Vector2i(2, -3), Vector2i(-1, 2), Vector2i(-1, -1)],
	})
	rail_network.setup(grid, terrain_manager)

	# Systems
	weather.setup(modifiers)
	board.setup(s)
	card_manager.setup(s)
	enemy_ai.setup(s)
	fow_manager.setup(grid, rail_network, board)
	ui.setup(s)
	turn_manager.setup(s)
	input_controller.setup(s, path_line)

	# UI -> gameplay wiring
	ui.next_day_requested.connect(turn_manager.advance_day)
	ui.card_choice_made.connect(card_manager.resolve_choice)

	_spawn_starting_forces()
	fow_manager.update_fow()

func _spawn_starting_forces():
	board.add_city("Aldermark", Vector2i(0, 3), 1, true)     # player capital
	board.add_city("Veslograd", Vector2i(0, -3), 2, true)    # enemy capital
	board.add_city("Brennfeld", Vector2i(0, 0), 0)           # contested neutral city

	board.add_unit("infantry", Vector2i(2, 1), 1)
	board.add_unit("logistics", Vector2i(-1, -1), 1)
	board.add_unit("infantry", Vector2i(1, -3), 2)
