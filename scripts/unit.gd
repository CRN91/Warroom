extends Node2D
class_name Unit

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var allied: bool = true
var frozen: bool = false
var supplier: int = 0
var supplier_reserve: int = 0
var path = []

# Compulsorary modules
@onready var movement_comp = $Movement
@onready var resource_comp = $Resources

# Optional modules
@onready var attack_comp = get_node_or_null("Attack")
@onready var resupply_comp = get_node_or_null("Resupply")

# ── Targeting ─────────────────────────────────────────────────────────────────
var target: Node2D = null        # Persistent preferred target — survives between days
var pending_attack: Node2D = null  # Queued for this day's resolution only

func is_allied(): return allied
func combatant(): return false
func is_frozen(): return frozen
func unfreeze(): frozen = false
func get_hex(): return movement_comp.get_hex()
func get_resources(): return resource_comp.get_resources()
func get_max_resources(): return resource_comp.get_max_resources()
func deplete(x): return resource_comp.deplete(x)
func restore(x): resource_comp.resupply(x)
func set_enemy(): allied = false
func set_path(x): path = x
func get_attack_range(): return attack_comp.get_range() if attack_comp else 0
func get_damage(): return attack_comp.get_damage() if attack_comp else 0
func attack(enemy): return attack_comp.attack(enemy) if attack_comp else false
func resupply_from(ally):
	if resupply_comp:
		resupply_comp.resupply_from(ally)

## Player action — queues attack for this turn AND remembers as persistent target.
func set_target(enemy: Node2D):
	if frozen:
		return
	frozen        = true
	pending_attack = enemy
	target         = enemy  # Persist for future days

## Clears the persistent target (F key).
func clear_target():
	target         = null
	pending_attack = null

## Called each day. Returns true if unit starved.
func next_day() -> bool:
	return resource_comp.clock_cycle()

func resupply(supply_source: Node2D):
	if not frozen:
		frozen = true
		resupply_comp.resupply_from(supply_source)

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

func status() -> String:
	var t_str = ""
	if target and is_instance_valid(target):
		t_str = " | Target: %s" % target.name
	return "Hex: %s | %s | HP: %d/%d%s" % [
		get_hex(), name, get_resources(), get_max_resources(), t_str
	]
