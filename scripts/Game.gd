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

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const PLAYER_CAPITAL_HEX := Vector2i(0, 3)
const ENEMY_CAPITAL_HEX := Vector2i(0, -3)
const STARTING_UNIT_HEXES := {
	"player_infantry_a": Vector2i(2, 1),
	"player_infantry_b": Vector2i(-2, 3),
	"player_artillery": Vector2i(0, 2),
	"player_engineers": Vector2i(1, 2),
	"enemy_infantry_a": Vector2i(1, -3),
	"enemy_infantry_b": Vector2i(-1, -2),
	"enemy_artillery": Vector2i(0, -2),
}
const TOWN_NAMES := ["Brennfeld", "Kaltenmoor", "Severin", "Ostbruck", "Witmark", "Lindenhal"]

var town_hexes: Array = []

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
	town_hexes = _pick_town_hexes(1 + randi() % 3)   # 1–3 neutral towns per run
	terrain_manager.generate({
		"capital_hexes": [PLAYER_CAPITAL_HEX, ENEMY_CAPITAL_HEX],
		"city_hexes": town_hexes,
		"occupied": STARTING_UNIT_HEXES.values(),
		"bridges": 1,   # exactly one pre-built crossing per run
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

func _pick_town_hexes(count: int) -> Array:
	## Random town sites: away from both capitals, away from each other, and
	## not on a starting unit's hex.
	var capitals := [PLAYER_CAPITAL_HEX, ENEMY_CAPITAL_HEX]
	var blocked: Array = STARTING_UNIT_HEXES.values()

	var candidates: Array = []
	for hex in grid.Grid.keys():
		if hex in blocked: continue
		var ok := true
		for cap in capitals:
			if HEX.axial_distance(hex, cap) < 3:
				ok = false
				break
		if ok: candidates.append(hex)
	candidates.shuffle()

	var picked: Array = []
	for hex in candidates:
		if picked.size() >= count: break
		var clear := true
		for p in picked:
			if HEX.axial_distance(hex, p) < 3:
				clear = false
				break
		if clear: picked.append(hex)
	return picked

func _spawn_starting_forces():
	board.add_city("Aldermark", PLAYER_CAPITAL_HEX, 1, true)   # player capital
	board.add_city("Veslograd", ENEMY_CAPITAL_HEX, 2, true)    # enemy capital

	var names := TOWN_NAMES.duplicate()
	names.shuffle()
	for i in range(town_hexes.size()):
		board.add_city(names[i], town_hexes[i], 0)             # neutral towns

	board.add_unit("infantry", STARTING_UNIT_HEXES["player_infantry_a"], 1)
	board.add_unit("infantry", STARTING_UNIT_HEXES["player_infantry_b"], 1)
	board.add_unit("artillery", STARTING_UNIT_HEXES["player_artillery"], 1)
	board.add_unit("logistics", STARTING_UNIT_HEXES["player_engineers"], 1)

	board.add_unit("infantry", STARTING_UNIT_HEXES["enemy_infantry_a"], 2)
	board.add_unit("infantry", STARTING_UNIT_HEXES["enemy_infantry_b"], 2)
	board.add_unit("artillery", STARTING_UNIT_HEXES["enemy_artillery"], 2)

	# Militias spawn last so they never steal a starting unit's hex.
	for hex in town_hexes:
		_spawn_town_militia(hex)

func _spawn_town_militia(town_hex: Vector2i) -> void:
	## Towns don't fall for free: a small neutral militia stands beside each
	## one and shoots at whoever comes close. It never moves or resupplies.
	var hex = board._free_hex_near(town_hex)
	if hex == null: return
	var militia = board.add_unit("infantry", hex, 0)
	if militia:
		militia.name = "Town Militia"
		militia.resource_comp.set_max_resources(60)
		militia.resource_comp.resources = 60
		militia.resource_comp.deplete_rate = 0   # they live off the town
		militia.update_ui()
