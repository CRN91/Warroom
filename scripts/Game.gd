extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const INFANTRY = preload("res://scenes/infantry.tscn")
const CITY = preload("res://scenes/city.tscn")
const LOGI = preload("res://scenes/logistics.tscn")

@onready var grid = %Grid
@onready var daycounter = $DayCount
@onready var nextdaybutton = $NextDay

@onready var panel      = $CanvasLayer/Panel
@onready var lbl_name   = $CanvasLayer/Panel/VBoxContainer/Name
@onready var lbl_res     = $CanvasLayer/Panel/VBoxContainer/Resources
@onready var lbl_act = $CanvasLayer/Panel/VBoxContainer/Action

var day: int = 0
var hex_to_move

# Dummy test environment
func test_setup():
	var piece = INFANTRY.instantiate()
	add_child(piece,true)
	grid = piece.move_to(Vector2i(2,1), grid)

	var piece2 = INFANTRY.instantiate()
	add_child(piece2,true)
	piece2.set_enemy()
	
	grid = piece2.move_to(Vector2i(1,1), grid)
	
	var piece3 = INFANTRY.instantiate()
	add_child(piece3,true)
	grid = piece3.move_to(Vector2i(-1,2), grid)
	
	var city = CITY.instantiate()
	add_child(city, true)
	grid = city.set_hex(Vector2i(0,0), grid)
	
	var logi = LOGI.instantiate()
	add_child(logi, true)
	grid = logi.move_to(Vector2i(-1,-1), grid)

func _ready():
	panel.hide()
	test_setup()
	nextdaybutton.pressed.connect(self._next_day_button)

func _select_piece(piece: Node2D, hex: Vector2i):
	show_stats(piece)
	hex_to_move = hex
 
func _deselect_piece():
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

func play_selected(hex, hex_to_move):
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
					play_selected(hex, hex_to_move)
					_deselect_piece()
				else:
					_select_piece(selected, hex)
			elif hex_to_move:
				grid = grid.Grid[hex_to_move]["Piece"].move_to(hex, grid)
				_deselect_piece()
				
	elif event.is_action_pressed("deselect"):
		_deselect_piece()

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
							if not same_team and piece.combatant() and adj_piece.combatant():
								_fight(piece, adj_piece)
							# Resupply
							elif same_team:
								_supply(piece, adj_piece)

	# TODO: Get a card
	
	for hex in grid.Grid:
		var piece = grid.Grid[hex]["Piece"]
		if piece and piece is City:
			piece.restore(100)

func show_stats(piece):
	lbl_name.text = str(piece.name)
	lbl_res.text = "Resources: %d / %d" % [piece.get_resources(), piece.get_max_resources()]
	lbl_act.text = "Frozen: %s" % str(piece.is_frozen())
	panel.show()

func _next_day_button():
	clock_increment()
