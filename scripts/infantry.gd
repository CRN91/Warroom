extends Node2D

class_name Infantry

var cell
var allied
@onready var movement_comp = $Movement
@onready var resource_comp = $Resources
@onready var attack_comp = $Attack
@onready var resupply_comp = $Resupply

@onready var frozen = false

# Called when the node enters the scene tree for the first time.
func _ready():
	allied = true # Sets team
	
func combatant():
	return true
	
func set_enemy():
	$Sprite2D.texture = load("res://assets/troopsr.png")
	allied = false

func unfreeze():
	frozen = false
	
func is_frozen():
	return frozen

func move_to(new_cell, grid):
	if not frozen:
		frozen = true
		return movement_comp.set_hex(new_cell, grid)
	else:
		return grid
	
func deplete(x):
	# Deletes the object
	return resource_comp.deplete(x)
		#queue_free()
	
func restore(x):
	resource_comp.resupply(x)
	
func resupply(ally):
	if not frozen:
		resupply_comp.resupply(ally)
	
func get_resources():
	return resource_comp.get_resources()
	
func get_max_resources():
	return resource_comp.get_max_resources()
	
func attack(enemy, damage = -1):
	if not frozen:
		frozen = true
		return attack_comp.attack(enemy, damage)
	
func is_allied():
	return allied
	
func status():
	return "Hex: %s\nUnit: %s\nResources: %d\nDamage %d" % [movement_comp.get_cell(), self.name, resource_comp.get_resources(), attack_comp.get_damage()]

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
