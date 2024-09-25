extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const INFANTRY = preload("res://scenes/infantry.tscn")

@onready var grid = %Grid
var to_move

func _ready():
	var check = Vector2i(-2,4)
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
	
	piece3.attack(piece2)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hex = HEX.oddr_to_axial(grid.local_to_map(get_global_mouse_position()))
			# Checks hex exists
			if hex in grid.Grid.keys():
				var selected = grid.Grid[hex]["Piece"]
				print(selected)
				# If a piece exists in the selected hex
				if selected:
					if to_move:
						var previous_selected = grid.Grid[to_move]["Piece"]
						if previous_selected.attack(selected):
							print("check")
							# Deletes from grid dictionary, better implementation with signals
							grid.Grid[hex]["Piece"] = null
						to_move = null
					else:
						# Debugging tool to see the status of selected piece
						#print(selected.status())
						# Caches the piece to be moved on the next click
						to_move = hex
				# If a piece was clicked on last, move it and clear to_move
				elif to_move or to_move == Vector2i(0,0):
					grid = grid.Grid[to_move]["Piece"].move_to(hex, grid)
					to_move = null
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Deselects piece
			to_move = null
