extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const INFANTRY = preload("res://scenes/infantry.tscn")

@onready var grid = %Grid

func _ready():
	var piece = INFANTRY.instantiate()
	add_child(piece,true)
	grid = piece.move_to(Vector2i(2,1), grid)

	var piece2 = INFANTRY.instantiate()
	add_child(piece2,true)
	
	grid = piece2.move_to(Vector2i(1,1), grid)
	
	var piece3 = INFANTRY.instantiate()
	add_child(piece3,true)
	grid = piece3.move_to(Vector2i(1,2), grid)

	
func _process(delta):
	pass

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hex = HEX.oddr_to_axial(grid.local_to_map(get_global_mouse_position()))
			print(grid.Grid[hex])
			print(hex)
			print()
			
