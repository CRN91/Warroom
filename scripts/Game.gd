extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const INFANTRY = preload("res://scenes/infantry.tscn")
const CITY = preload("res://scenes/city.tscn")
const LOGI = preload("res://scenes/logistics.tscn")

@onready var grid = %Grid
@onready var daycounter = $DayCount
@onready var nextdaybutton = $NextDay
var day: int = 0
var to_move

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
	grid = piece3.move_to(Vector2i(1,2), grid)
	
	var city = CITY.instantiate()
	add_child(city, true)
	grid = city.set_hex(Vector2i(0,0), grid)
	
	var logi = LOGI.instantiate()
	add_child(logi, true)
	grid = logi.move_to(Vector2i(-1,-1), grid)

func _ready():
	test_setup()
	nextdaybutton.pressed.connect(self._next_day_button)

func _input(event):	
	if event.is_action_pressed("select"):
		# Gets the selected hex
		var oddr_hex = grid.local_to_map(get_global_mouse_position())
		var hex = HEX.oddr_to_axial(oddr_hex)
		
		# Checks the hex exists
		if hex in grid.Grid.keys():
			var selected = grid.Grid[hex]["Piece"]
			# Draws selection around cell for user
			grid.select_cell(oddr_hex)

			# If a piece exists in the selected hex
			if selected:
				# If a piece was previously selected
				if to_move:
					var previous_selected = grid.Grid[to_move]["Piece"]
					# Attacks if both pieces are combatants
					if selected.combatant() and previous_selected.combatant():
						# Returns true if the piece 'selected' dies
						if previous_selected.attack(selected):
							print("dead boy")
							# Deletes from grid dictionary, better implementation with signals
							grid.Grid[hex]["Piece"] = null
							print(grid.Grid[hex]["Piece"])
						
						# Pieces are deselected
						to_move = null
						selected = null
						grid.deselect()
					# Resupply if the piece is a non combatant
					elif not selected.combatant():
						print("resupply")
						previous_selected.resupply(selected)
						to_move = null
						selected = null
				# Nothing else has been slected, just gives piece's stats
				else:
					# Debugging tool to see the status of selected piece
					print(selected.status())
					print()

					# Caches the piece to be moved on the next click
					to_move = hex

			# If a piece was clicked on last, move it and clear to_move
			elif to_move or to_move == Vector2i(0,0):
				grid = grid.Grid[to_move]["Piece"].move_to(hex, grid)
				to_move = null
				grid.deselect()

	elif event.is_action_pressed("deselect"):
		grid.deselect()
		# Deselects piece
		to_move = null

"Functionality for a single game turn"
func clock_increment():
	day += 1
	daycounter.text = "DAY "+str(day)
	print(daycounter.position)
	var killed = {}
	
	# Combat, checks adjacent cells of all pieces and attacks
	for hex in grid.Grid:
		var piece = grid.Grid[hex]["Piece"]
		if piece:
			# Allows the piece to move once
			piece.unfreeze()
			if piece.combatant():
				var team = piece.is_allied()
				for adjacent in HEX.axial_neighbours(hex):
					if adjacent in grid.Grid.keys():
						var adj_piece = grid.Grid[adjacent]["Piece"]
						if adj_piece:
							if adj_piece.combatant():
								if adj_piece.is_allied() != team:
									if piece.attack(adj_piece):
										# Piece is killed, using dictionary as a set
										if not killed.has(adjacent):
											killed[adjacent] = null
									# Auto attack does not freeze so manually unfreeze
									piece.unfreeze()


	# TODO: Get a card

	# Dealing with killed pieces
	for dead_hex in killed.keys():
		grid.Grid[dead_hex]["Piece"].queue_free()
		grid.Grid[dead_hex]["Piece"] = null	

func _next_day_button():
	clock_increment()
