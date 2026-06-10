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

	# Never damage your own SIDE — allies and captured cities included.
	var destroyed := false
	if Sides.hostile(unit.team, enemy.team):
		destroyed = enemy.deplete(dmg)

	if attack_cost > 0:
		unit.deplete(attack_cost)

	# Cities are captured, not killed — only unit kills count toward veterancy.
	if destroyed and not (enemy is City) and unit.has_method("record_kill"):
		unit.record_kill()

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

func get_target(_grid = null) -> Node2D:
	## HONEST TELEGRAPH RULE: a unit may only fire at a target it locked on a
	## previous turn (acquire_target) or was manually ordered to attack. There
	## is no opportunistic move-in-and-shoot — if you saw no red arrow, you
	## take no hit.

	# 1. Clean up dead targets — and targets that changed sides (captured cities)
	if target and (not is_instance_valid(target) or not Sides.hostile(unit.team, target.team)): target = null
	if pending_attack and (not is_instance_valid(pending_attack) or not Sides.hostile(unit.team, pending_attack.team)): pending_attack = null

	# 2. Guns that aren't set up don't fire at all
	if not unit.can_fire(): return null

	# 3. Manual attacks ordered this turn take priority
	if pending_attack:
		var t = pending_attack
		pending_attack = null
		return t

	# 4. If we already moved (frozen), we cannot auto-attack this turn
	if unit.is_frozen(): return null

	# 5. The locked (telegraphed) target — must still be in range and in sight
	if target:
		var dist = HEX.axial_distance(unit.get_hex(), target.get_hex())
		if dist <= unit.get_attack_range():
			if dist <= 1 or unit.terrain == null or not unit.terrain.blocks_line_of_fire(unit.get_hex(), target.get_hex()):
				return target
	return null

func acquire_target(grid) -> Node2D:
	## End-of-turn telegraph: lock the target this unit will fire at next turn.
	## The intent arrows render it, so every attack is visible a turn ahead.
	if not unit.can_fire():
		target = null
		return null
	target = _find_enemy_in_range(grid)
	return target

func _find_enemy_in_range(grid) -> Node2D:
	var possible: Array = []
	for hex in HEX.axial_radius(unit.get_hex(), unit.get_attack_range()):
		if not grid.Grid.has(hex): continue
		if unit.terrain and unit.terrain.blocks_line_of_fire(unit.get_hex(), hex):
			continue
		var candidate = grid.get_piece(hex)
		if candidate and Sides.hostile(unit.team, candidate.team):
			possible.append(candidate)

	if possible.is_empty(): return null

	# Priority targeting: combatants > engineers > anything else (cities)
	for t in possible:
		if t.is_combatant(): return t
	for t in possible:
		if t is Engineers: return t
	return possible[0]
