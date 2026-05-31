extends Node2D
class_name Unit

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var allied: bool = true
var frozen: bool = false
var supplier: int = 0
var path = []

@onready var movement_comp = $Movement
@onready var resource_comp = $Resources
@onready var resupply_comp = $Resupply

var DAILY_DEPLETE: int = 1
var attack_range: int = 1 

func is_allied(): return allied
func combatant(): return false
func is_frozen(): return frozen
func unfreeze(): frozen = false
func get_hex(): return movement_comp.get_cell()
func get_resources(): return resource_comp.get_resources()
func get_max_resources(): return resource_comp.get_max_resources()
func deplete(x): return resource_comp.deplete(x)
func next_day(): return resource_comp.clock_cycle()
func set_enemy(): allied = false
func set_path(x): path = x
func restore(x): resource_comp.resupply(x)
func resupply_from(ally): resupply_comp.resupply_from(ally)
func get_attack_range() -> int: return attack_range

func move_to(new_hex, old_hex, grid):
	if not frozen:
		frozen = true
		if not old_hex:
			grid.disable_hex(new_hex)
			return movement_comp.set_hex(new_hex, grid)
		
		grid.enable_hex(old_hex)
			
		if new_hex in HEX.axial_neighbours(old_hex):
			if grid.Grid[new_hex]["Piece"] == null:
				grid.enable_hex(old_hex)
				grid.disable_hex(new_hex)
				return movement_comp.set_hex(new_hex, grid)
			else:
				frozen = false
		else:
			var calculated_path = grid.get_map_path(old_hex, new_hex)
			if calculated_path.size() > 1:
				var next_hex = calculated_path[1]
				path = calculated_path.slice(2)
				grid.disable_hex(next_hex)
				return movement_comp.set_hex(next_hex, grid)
			else:
				frozen = false
	return grid

func status():
	return "Hex: %s | Unit: %s | HP: %d/%d" % [
		get_hex(), name, get_resources(), get_max_resources()
	]
