extends Node
class_name EnemyAI

## The opposing commander. Works only through Board's public API — buying
## units from its cities and giving its forces simple standing orders.

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var s: GameServices

func setup(services: GameServices):
	s = services

func run_turn():
	_purchase_units()
	_command_units()

# ── Economy ───────────────────────────────────────────────────────────────────

func _purchase_units():
	if s.turn.day % 4 != 0: return               # dial 1: only shop every 4th week
	var bought := 0
	for city in s.board.cities:
		if city.team != 2 or bought >= 1: continue   # dial 2: cap one buy per turn
		var res = city.get_resources()
		if res >= Board.COST["infantry"] + 600:      # dial 3: keep a surplus, don't self-drain
			var choices = ["infantry"]
			if res >= Board.COST["artillery"] + 600: choices.append("artillery")
			if res >= Board.COST["logistics"] + 600: choices.append("logistics")
			var choice = choices[randi() % choices.size()]
			if s.board.spawn_unit_near_city(choice, city) != null:
				city.deplete(Board.COST[choice])
				bought += 1

# ── Strategy ──────────────────────────────────────────────────────────────────

func _command_units():
	for unit in s.board.units:
		# Commands its own side: the enemy (2) and the coalition (3)
		if Sides.side_of(unit.team) != 2 or unit is City or unit is Train: continue

		if unit is Artillery:
			_command_artillery(unit)
		elif unit.is_combatant():
			_command_combatant(unit)
		else:
			_command_logistics(unit)

func _command_combatant(unit):
	unit.clear_movement()
	var is_starving = unit.get_resources() <= (unit.get_max_resources() * 0.3)

	# Worn-out divisions rotate home and rest, same rules as the player
	if unit.get("_fatigue_stage") != null and unit._fatigue_stage >= 2:
		var rest_city = _nearest_own_city(unit.get_hex())
		if rest_city:
			if HEX.axial_distance(unit.get_hex(), rest_city.get_hex()) == 1:
				s.board.garrison_unit(unit)
			else:
				unit.set_destination(rest_city.get_hex())
			return

	if is_starving:
		var city = _nearest_own_city(unit.get_hex())
		if city: unit.set_destination(city.get_hex())
		return

	if unit.movement_comp.goal != null: return

	var target = _nearest_player_piece(unit.get_hex())
	if target:
		unit.set_destination(target.get_hex())

func _command_artillery(unit):
	## Guns deploy when something is in reach, limber up to reposition, and
	## fall back rather than die in melee — artillery is too dear to trade.
	var target = _nearest_player_piece(unit.get_hex())
	if target == null: return
	var dist = HEX.axial_distance(unit.get_hex(), target.get_hex())

	if dist <= 1:
		# Enemy at the muzzle: pack up and pull back behind the line
		unit.pack_up()
		unit.clear_movement()
		var fallback = _nearest_own_city(unit.get_hex())
		if fallback:
			unit.set_destination(fallback.get_hex())
	elif dist <= unit.get_attack_range():
		unit.clear_movement()
		if not unit.deployed:
			unit.try_deploy()
	else:
		if unit.deployed:
			unit.pack_up()
		unit.clear_movement()
		unit.set_destination(target.get_hex())

func _command_logistics(unit):
	# Engineers run standing supply lines: capital -> the neediest town.
	# The shuttle automation does the driving; the AI just assigns routes.
	if unit is Engineers:
		if unit.has_shuttle():
			return   # the route runs itself
		var cap = _own_capital()
		var town = _neediest_own_town()
		if cap and town:
			unit.set_shuttle(cap, town)
			return

	var has_supplies = unit.get_resources() > (unit.get_max_resources() * 0.7)

	if has_supplies:
		var target = _nearest_own_combatant(unit.get_hex(), unit)
		if target:
			unit.set_destination(target.get_hex())
	else:
		var city = _nearest_own_city(unit.get_hex())
		if city:
			unit.set_destination(city.get_hex())

func _own_capital() -> Node2D:
	return s.board.enemy_capital()

func _neediest_own_town() -> Node2D:
	var best = null
	var best_stock := 300   # only towns actually short of stock qualify
	for city in s.board.cities:
		if not is_instance_valid(city) or city.is_capital: continue
		if Sides.side_of(city.team) != 2: continue
		if city.get_resources() < best_stock:
			best_stock = city.get_resources()
			best = city
	return best

# ── Targeting helpers ─────────────────────────────────────────────────────────

func _nearest_own_city(start_hex) -> Node2D:
	var best = null
	var best_dist = 9999
	for city in s.board.cities:
		if Sides.side_of(city.team) == 2:
			var d = HEX.axial_distance(start_hex, city.get_hex())
			if d < best_dist:
				best_dist = d
				best = city
	return best

func _nearest_player_piece(start_hex) -> Node2D:
	var best = null
	var best_dist = 9999
	for piece in s.board.units + s.board.cities:
		if piece.team == 1:
			var d = HEX.axial_distance(start_hex, piece.get_hex())
			if d < best_dist:
				best_dist = d
				best = piece
	return best

func _nearest_own_combatant(start_hex, self_unit) -> Node2D:
	var best = null
	var best_dist = 9999
	for unit in s.board.units:
		if Sides.side_of(unit.team) == 2 and unit != self_unit and unit.has_method("is_combatant") and unit.is_combatant():
			var d = HEX.axial_distance(start_hex, unit.get_hex())
			if d < best_dist:
				best_dist = d
				best = unit
	return best
