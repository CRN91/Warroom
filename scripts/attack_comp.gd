extends Node2D
class_name Attack

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@export var damage: int = 99
@export var attack_cost: int = 0
@export var attack_range: int = 1

var unit: Node2D                 # the Unit this component belongs to
var target: Node2D = null        # sticky target (keeps firing while in range)
var pending_attack: Node2D = null # manual order this turn — fires even after moving

func _ready():
	unit = get_parent()

func attack(enemy, damage_override = null):
	var dmg = damage
	if damage_override != null:
		dmg = damage_override

	# Card/modifier effects on outgoing damage (buffs, debuffs, morale_collapse...)
	if unit.modifiers:
		dmg = int(round(unit.modifiers.get_value("attack", float(dmg), unit)))
		if dmg < 0:
			dmg = 0

	var destroyed := false
	if not (enemy.is_combatant() and unit.team == enemy.team):
		destroyed = enemy.deplete(dmg)

	if attack_cost > 0:
		unit.deplete(attack_cost)

	return destroyed

func get_damage(): return damage
func get_range(): return attack_range

# ── Targeting ─────────────────────────────────────────────────────────────────

func set_target(enemy: Node2D):
	if unit.is_frozen(): return
	unit.freeze()
	pending_attack = enemy
	target = enemy

func clear_target():
	target = null
	pending_attack = null

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
	if unit.is_frozen(): return null

	# 4. Check if our sticky target is still in range
	if target:
		if HEX.axial_distance(unit.get_hex(), target.get_hex()) <= unit.get_attack_range():
			return target

	# 5. Otherwise, scan for a new target
	if grid:
		return _find_enemy_in_range(grid)
	return target

func _find_enemy_in_range(grid) -> Node2D:
	var possible: Array = []
	for hex in HEX.axial_radius(unit.get_hex(), unit.get_attack_range()):
		if not grid.Grid.has(hex): continue
		if unit.terrain and unit.terrain.blocks_line_of_fire(unit.get_hex(), hex):
			continue
		var candidate = grid.get_piece(hex)
		if candidate and candidate.team != unit.team:
			possible.append(candidate)

	if possible.is_empty(): return null

	# Priority targeting: combatants > logistics > anything else (cities)
	for t in possible:
		if t.is_combatant(): return t
	for t in possible:
		if t is Logistics: return t
	return possible[0]
