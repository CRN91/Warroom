extends Node2D

class_name Logistics

var cell
var allied
@onready var movement_comp = $Movement
@onready var resource_comp = $Resources
@onready var resupply_comp = $Resupply

# Called when the node enters the scene tree for the first time.
func _ready():
	allied = true # Sets team
	
func combatant():
	return false
	
func set_enemy():
	$Sprite2D.texture = load("res://assets/logir.png")
	allied = false

func move_to(new_cell, grid):
	return movement_comp.set_hex(new_cell, grid)
	
func deplete(x):
	resource_comp.deplete(x)
	
func restore(x):
	resource_comp.resupply(x)
	
func resupply(ally):
	resupply_comp.resupply(ally)
	
func get_resources():
	return resource_comp.get_resources()
	
func get_max_resources():
	return resource_comp.get_max_resources()
	
func is_allied():
	return allied
	
func status():
	return "Hex: %s\nUnit: %s\nResources: %d" % [movement_comp.get_cell(), self.name, resource_comp.get_resources()]
