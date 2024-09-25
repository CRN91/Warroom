extends Node2D

class_name Infantry

var cell
var allied
@onready var movement_comp = $Movement
@onready var resource_comp = $Resources
@onready var attack_comp = $Attack

# Called when the node enters the scene tree for the first time.
func _ready():
	allied = true # Sets team
	
func set_enemy():
	$Sprite2D.texture = load("res://assets/troopsr.png")
	allied = false

func move_to(new_cell, grid):
	return movement_comp.set_cell(new_cell, grid, self)
	
func deplete(x):
	# Deletes the object
	if resource_comp.deplete(x):
		queue_free()
		return true
	else:
		return false
	
func get_resources():
	return resource_comp.get_resources()
	
func attack(enemy):
	return attack_comp.attack(self, enemy)
	
func is_allied():
	return allied
	
func status():
	return "Hex: %s\nUnit: %s\nResources: %d\nDamage %d" % [movement_comp.get_cell(), self.name, resource_comp.get_resources(), attack_comp.get_damage()]

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
