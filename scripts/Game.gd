extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const PIECE = preload("res://scenes/piece.tscn") 
const CITY = preload("res://scenes/city.tscn")

@onready var grid = %Grid

func generate_map():
	var city = CITY.instantiate()
	grid.Grid = city.setup(Vector2i(0,2), grid)
	add_child(city)
	
	var ene_cap = CITY.instantiate()
	grid.Grid = ene_cap.setup(Vector2i(2,-4), grid)
	add_child(ene_cap)
	
	var own_cap = CITY.instantiate()
	grid.Grid = own_cap.setup(Vector2i(-2,4), grid)
	add_child(own_cap)

func _ready():
	generate_map()
	var piece = PIECE.instantiate()
	add_child(piece)
	
func _process(delta):
	if Input.is_action_just_pressed("next"):
		var troop = PIECE.instantiate()
		add_child(troop)
		troop.move_to(Vector2i(0,3))
	
