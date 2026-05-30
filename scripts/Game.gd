extends Node2D

# Hexagonal tiled board
const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()
@onready var grid = %Grid

# Board pieces
const INFANTRY = preload("res://scenes/infantry.tscn")
const CITY = preload("res://scenes/city.tscn")
const LOGI = preload("res://scenes/logistics.tscn")

# UI
@onready var daycounter = $CanvasLayer/DayCount
@onready var nextdaybutton = $CanvasLayer/NextDay
@onready var panel      = $CanvasLayer/Panel
@onready var lbl_name   = $CanvasLayer/Panel/VBoxContainer/Name
@onready var lbl_res     = $CanvasLayer/Panel/VBoxContainer/Resources
@onready var lbl_act = $CanvasLayer/Panel/VBoxContainer/Action
@onready var card_ui = $CanvasLayer/CardUI
@onready var path_line = $PathLine

# Card logic
@onready var deck = $Deck
@onready var card_library = $CardLibrary
@onready var resolver = $CardResolver
var game_state: Dictionary = {
	"move_cost": 1,
	"attack_modifier": 1.0
}
var pending_cards: Array = []     # [{id, on_day}]
var pending_restores: Array = []  # [{key, value, on_day}]

# Game logic
var day: int = 0
var hex_to_move

var cities = []
var units = []

func _on_card_choice(card_data: Dictionary, choice: String):
	var effects = card_data[choice]["effects"]
	resolver.resolve(effects, self)

func _check_pending():
	# Inject delayed cards
	for i in range(pending_cards.size() - 1, -1, -1):
		if pending_cards[i]["on_day"] <= day:
			var card = card_library.get_card(pending_cards[i]["id"])
			deck.inject(card, "soon")
			pending_cards.remove_at(i)
	
	# Restore game state
	for i in range(pending_restores.size() - 1, -1, -1):
		if pending_restores[i]["on_day"] <= day:
			game_state[pending_restores[i]["key"]] = pending_restores[i]["value"]
			pending_restores.remove_at(i)

# Dummy test environment
func test_setup():
	var piece = INFANTRY.instantiate()
	add_child(piece,true)
	grid = piece.move_to(Vector2i(2,1), grid)
	units.append(piece)

	var piece2 = INFANTRY.instantiate()
	add_child(piece2,true)
	piece2.set_enemy()
	grid = piece2.move_to(Vector2i(1,-3), grid)
	units.append(piece2)
	
	var piece3 = INFANTRY.instantiate()
	add_child(piece3,true)
	grid = piece3.move_to(Vector2i(-1,2), grid)
	units.append(piece3)
	
	var city = CITY.instantiate()
	add_child(city, true)
	grid = city.set_hex(Vector2i(0,0), grid)
	cities.append(city)
	
	var city2 = CITY.instantiate()
	add_child(city2, true)
	city2.set_enemy()
	grid = city2.set_hex(Vector2i(0,-3), grid)
	cities.append(city2)
	
	var city3 = CITY.instantiate()
	add_child(city3, true)
	grid = city3.set_hex(Vector2i(0,3), grid)
	cities.append(city3)
	
	var logi = LOGI.instantiate()
	add_child(logi, true)
	grid = logi.move_to(Vector2i(-1,-1), grid)

	_unfreeze_all()

func _ready():
	card_library.load_library()
	
	var this_run_sets = ["western_front_intel", "weather_events", "command_decisions"]
	var starting_cards = card_library.build_starting_deck(this_run_sets)
	
	for card in starting_cards:
		deck.push(card)
		
	panel.hide()
	card_ui.hide() 
	deck.load()   
	test_setup()
	nextdaybutton.pressed.connect(self._next_day_button)

func _select_piece(piece: Node2D, hex: Vector2i):
	show_stats(piece)
	hex_to_move = hex
 
func _deselect_piece():
	path_line.clear_points()
	hex_to_move = null
	grid.deselect()
	panel.hide()
	
func _die(dead_piece):
	print("dead boy")
	var dead_hex = dead_piece.get_hex()
	# Deletes from grid dictionary, better implementation with signals
	grid.Grid[dead_hex]["Piece"].queue_free()
	grid.Grid[dead_hex]["Piece"] = null
	print(grid.Grid[dead_hex]["Piece"])
	
func _fight(piece1, piece2):
	var to_die = []
	if piece1.combatant():
		# Returns true if the piece 'selected' dies
		if piece1.attack(piece2):
			to_die.append(piece2)
	if piece2.combatant():
		if piece2.attack(piece1):
			to_die.append(piece1)
	
	# After all attacks remove dead pieces
	for i in to_die:
		_die(i)	

func _supply(piece1, piece2):
	print("resupply")
	if piece1.supplier > piece2.supplier:
		piece2.resupply_from(piece1)
	elif piece2.supplier > piece1.supplier:
		piece1.resupply_from(piece2)

func _play_selected(hex, hex_to_move):
	# Checks the previously selected hex is adjacent
	if hex_to_move in HEX.axial_neighbours(hex):
		
		var selected = grid.Grid[hex]["Piece"]
		
		# If there was a previously selected hex
		if hex_to_move:
			var previous_selected = grid.Grid[hex_to_move]["Piece"]
			
			# If there is a piece we do an action
			if previous_selected:
				var same_team = previous_selected.is_allied() == selected.is_allied()
				# Both pieces have a chance to fight
				if not same_team:
					if previous_selected.combatant() or selected.combatant():
						_fight(previous_selected, selected)
				# Resupply if allied
				elif same_team:
					_supply(previous_selected, selected)
			else:
				grid = grid.Grid[hex_to_move]["Piece"].move_to(hex, grid)
				hex_to_move = null
				grid.deselect()
				# Old code about to_move being 0,0 not sure what thats about
				#elif to_move or to_move == Vector2i(0,0):
		# First selection
		else:
			# Caches the piece to be moved on the next click
			hex_to_move = hex

func _input(event):	
	if event.is_action_pressed("select"):
		# Gets the selected hex axial
		var oddr_hex = grid.local_to_map(get_global_mouse_position())
		var hex = HEX.oddr_to_axial(oddr_hex)
		
		# Checks the hex exists
		if hex in grid.Grid.keys():
			# Draws selection around cell for user
			grid.select_cell(oddr_hex)
			var selected = grid.Grid[hex]["Piece"]

			# If a piece exists in the selected hex
			if selected:
				if hex_to_move:
					_play_selected(hex, hex_to_move)
					_deselect_piece()
				else:
					_select_piece(selected, hex)
			elif hex_to_move:
				grid = grid.Grid[hex_to_move]["Piece"].move_to(hex, grid)
				_deselect_piece()
				
	elif event.is_action_pressed("deselect"):
		_deselect_piece()
		
	elif event is InputEventMouseMotion:
		if hex_to_move:
			var oddr_hex = grid.local_to_map(get_global_mouse_position())
			var target_hex = HEX.oddr_to_axial(oddr_hex)
			
			if target_hex in grid.Grid.keys():
				var pixel_path = grid.get_hex_path(hex_to_move, target_hex)
				path_line.points = pixel_path
			else:
				path_line.clear_points()

func _unfreeze_all():
	for hex in grid.Grid:
		var piece = grid.Grid[hex]["Piece"]
		if piece:
			piece.unfreeze()
			
"Functionality for a single game turn"
func clock_increment():
	day += 1
	daycounter.text = "DAY "+str(day)
	print(daycounter.position)
	
	# Auto-play
	_unfreeze_all()
	for hex in grid.Grid:
		var piece = grid.Grid[hex]["Piece"]
		if piece:
			piece.unfreeze()
			
			for adjacent in HEX.axial_neighbours(hex):
				if adjacent in grid.Grid.keys():
					var adj_piece = grid.Grid[adjacent]["Piece"]
					if adj_piece:
						# All pairs only play once per day
						if hex < adjacent:
							var same_team = piece.is_allied() == adj_piece.is_allied()
							
							# Combat
							if not same_team:
								_fight(piece, adj_piece)
							# Resupply
							elif same_team:
								_supply(piece, adj_piece)

	var cycle = day % 3
	var required_type = ""
	
	if cycle == 1:
		required_type = "intel"
	elif cycle == 2:
		required_type = "event"
	elif cycle == 0:
		required_type = "decision"
	
	# Search the deck for the first card that matches the required type
	var card_to_play = null
	for i in range(deck.size()):
		var checked_card = deck.queue[i]
		if deck.len() > 1:
			if checked_card["type"] == required_type:
				card_to_play = checked_card
				deck.queue.remove_at(i) # Remove it from the deck
				break
			
	# Send the card to the UI
	if card_to_play != null:
		print("Drawing card: ", card_to_play["text"])
		card_ui.display_card(card_to_play)
	else:
		card_ui.hide()
	
	for hex in grid.Grid:
		var piece = grid.Grid[hex]["Piece"]
		if piece and piece is City:
			piece.restore(100)
	
	_unfreeze_all()

func show_stats(piece):
	lbl_name.text = str(piece.name)
	lbl_res.text = "Resources: %d / %d" % [piece.get_resources(), piece.get_max_resources()]
	lbl_act.text = "Frozen: %s" % str(piece.is_frozen())
	panel.show()

func _next_day_button():
	clock_increment()
