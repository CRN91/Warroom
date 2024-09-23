extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const INFANTRY = preload("res://scenes/infantry.tscn")

@onready var grid = %Grid

func _ready():
	var piece = INFANTRY.instantiate()
	add_child(piece)
	grid = piece.move_to(Vector2i(2,1), grid)
	#print(grid.Grid)
	var piece2 = INFANTRY.instantiate()
	add_child(piece2)
	grid = piece2.move_to(Vector2i(1,1), grid)
	
	print("Piece 1 resources: " + str(piece.get_resources())+
	"\nPiece 2 resources: " + str(piece2.get_resources()))
	
	piece.attack(piece2)
	
	print("Piece 1 resources: " + str(piece.get_resources())+
	"\nPiece 2 resources: " + str(piece2.get_resources()))
	
func _process(delta):
	if Input.is_action_just_pressed("next"):
		var troop = INFANTRY.instantiate()
		add_child(troop)
		
