extends Node2D
class_name Attack

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@export var damage: int = 99
@export var attack_cost: int = 0    
@export var attack_range: int = 1   

var piece
var target: Node2D = null
var pending_attack: Node2D = null
var ally: Node2D

func _ready():
	ally = get_parent()
	piece = get_parent()

func attack(enemy, damage_override = null):
	var dmg = damage
	if damage_override:
		dmg = damage_override

	var destroyed := false

	if enemy.is_combatant():
		if ally.team != enemy.team:
			destroyed = enemy.deplete(dmg)
	else:
		destroyed = enemy.deplete(dmg)

	if attack_cost > 0:
		ally.deplete(attack_cost)

	return destroyed

func get_damage():
	return damage

func get_range():
	return attack_range

func get_target(grid = null) -> Node2D:
	# 1. Clean up dead targets to avoid crashes
	if target and not is_instance_valid(target): target = null
	if pending_attack and not is_instance_valid(pending_attack): pending_attack = null

	# 2. Manual attacks ordered this turn take priority
	if pending_attack:
		var t = pending_attack
		pending_attack = null
		return t
		
	# 3. If we already moved (frozen), we cannot auto-attack this turn
	if piece.is_frozen(): return null
	
	# 4. Check if our sticky target is still in range
	if target:
		if HEX.axial_distance(piece.get_hex(), target.get_hex()) <= piece.get_attack_range():
			return target
			
	# 5. Otherwise, scan for a new target
	if grid:
		return _find_enemy_in_range(grid)
	return target

func _find_enemy_in_range(grid) -> Node2D:
	var possible: Array = []
	for hex in HEX.axial_radius(piece.get_hex(), piece.get_attack_range()):
		if not grid.Grid.has(hex): continue
		var temp_piece = grid.get_piece(hex)
		if temp_piece and temp_piece.team != piece.team:
			possible.append(temp_piece)
			
	if possible.is_empty(): return null
	
	# Priority targeting: Combatants > Logistics > Anything else (Cities)
	for t in possible:
		if t.is_combatant(): return t
	for t in possible:
		if t is Logistics: return t
	return possible[0]

func set_target(enemy: Node2D):
	if piece.frozen: return
	piece.frozen = true
	pending_attack = enemy
	target = enemy

func clear_target():
	target        = null
	pending_attack = null
