extends Node2D
class_name City

@onready var movement_comp = $Movement
@onready var resource_comp = $Resource
@export var hex_tile: Vector2i # Use this later with signals

# Called when the node enters the scene tree for the first time.
func _ready():
	resource_comp.set_max_resources(1000)
	resource_comp.set_resupply_rate(1000)

func combatant():
	return false

func is_frozen():
	return movement_comp.frozen

func unfreeze():
	pass
	
func set_hex(hex, grid):
	return movement_comp.set_hex(hex, grid)	
	
func status():
	return "Hex: %s\nUnit: %s\nResources: %d" % [movement_comp.get_cell(), self.name, resource_comp.get_resources()]

func move_to(hex, grid):
	return grid

func get_resources():
	return resource_comp.get_resources()

func deplete(x):
	resource_comp.deplete(x)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
