extends Node2D
class_name Unit

var allied: bool = true
var frozen: bool = false
var supplier: int = 0

@onready var movement_comp = $Movement
@onready var resource_comp = $Resources

func is_allied(): return allied
func combatant(): return false
func is_frozen(): return frozen
func unfreeze(): frozen = false
func get_hex(): return movement_comp.get_cell()
func get_resources(): return resource_comp.get_resources()
func get_max_resources(): return resource_comp.get_max_resources()
func deplete(x): return resource_comp.deplete(x)
func restore(x): resource_comp.resupply(x)
func set_enemy(): allied = false

func move_to(new_cell, grid):
	if not frozen:
		frozen = true
		return movement_comp.set_hex(new_cell, grid)
	return grid

func status():
	return "Hex: %s | Unit: %s | HP: %d/%d" % [
		get_hex(), name, get_resources(), get_max_resources()
	]
