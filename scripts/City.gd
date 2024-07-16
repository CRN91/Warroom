extends Node2D

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

func set_pos(pos, grid):
	position = grid.map_to_local(HEX.axial_to_oddr(pos))
	
# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
