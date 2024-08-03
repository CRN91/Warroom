extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

func set_pos(pos, grid):
	position = grid.map_to_local(HEX.axial_to_oddr(pos))
	
func setup(pos, grid):
	set_pos(pos, grid)
	var grid_dict = grid.Grid
	var oddr_pos = HEX.axial_to_oddr(pos)
	grid_dict[oddr_pos]['Structure'] = self
	return grid_dict
	
# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
