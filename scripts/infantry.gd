extends Node2D

class_name Infantry

var cell
@onready var movement_comp = $movement_comp

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

func move_to(new_cell, grid):
	movement_comp.set_cell(new_cell, grid)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
