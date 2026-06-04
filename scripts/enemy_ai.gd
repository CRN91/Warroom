extends Node
class_name EnemyAI

var game: Node2D 

func setup(_game: Node2D):
	game = _game

func run_turn():
	_purchase_units()
	_command_units()

# ── Economy ───────────────────────────────────────────────────────────────

func _purchase_units():
	for city in game.cities:
		if city.team != 2: continue
		var res = city.get_resources()
		
		if res >= game.COST["infantry"]:
			var choices = ["infantry"]
			if res >= game.COST["artillery"]: choices.append("artillery")
			if res >= game.COST["logistics"]: choices.append("logistics")
			
			var choice = choices[randi() % choices.size()]
			var scene = {"infantry": game.INFANTRY, "artillery": game.ARTILLERY, "logistics": game.LOGI}[choice]
			
			if game._spawn_unit_near_city(scene, city):
				city.deplete(game.COST[choice])

# ── Strategy ──────────────────────────────────────────────────────────────

func _command_units():
	for unit in game.units:
		if unit.team != 2 or unit is City or unit is Train: continue

		if unit.has_method("is_combatant") and unit.is_combatant():
			_command_combatant(unit)
		else:
			_command_logistics(unit)

func _command_combatant(unit):
	var is_starving = unit.get_resources() <= (unit.get_max_resources() * 0.3)

	if is_starving:
		var city = _get_nearest_friendly_city(unit.get_hex())
		if city: unit.movement_comp.set_goal(city.get_hex())
		return 

	if unit.movement_comp.goal != null: return

	var target = _get_nearest_enemy(unit.get_hex())
	if target:
		unit.movement_comp.set_goal(target.get_hex())

func _command_logistics(unit):
	var has_supplies = unit.get_resources() > (unit.get_max_resources() * 0.7)

	if has_supplies:
		var target = _get_nearest_friendly_combatant(unit.get_hex(), unit)
		if target:
			unit.movement_comp.set_goal(target.get_hex())
	else:
		var city = _get_nearest_friendly_city(unit.get_hex())
		if city:
			unit.movement_comp.set_goal(city.get_hex())

# ── Targeting Helpers ─────────────────────────────────────────────────────

func _get_nearest_friendly_city(start_hex) -> Node2D:
	var best_city = null
	var best_dist = 9999
	
	for city in game.cities:
		if city.team == 2:
			var d = game.HEX.axial_distance(start_hex, city.get_hex())
			if d < best_dist:
				best_dist = d
				best_city = city
				
	return best_city

func _get_nearest_enemy(start_hex) -> Node2D:
	var best_target = null
	var best_dist   = 9999
	
	for p_unit in game.units:
		if p_unit.team == 1:
			var d = game.HEX.axial_distance(start_hex, p_unit.get_hex())
			if d < best_dist:
				best_dist = d
				best_target = p_unit
				
	for city in game.cities:
		if city.team == 1:
			var d = game.HEX.axial_distance(start_hex, city.get_hex())
			if d < best_dist:
				best_dist = d
				best_target = city
				
	return best_target

func _get_nearest_friendly_combatant(start_hex, self_unit) -> Node2D:
	var best_target = null
	var best_dist   = 9999
	
	for f_unit in game.units:
		if f_unit.team == 2 and f_unit != self_unit and f_unit.has_method("is_combatant") and f_unit.is_combatant():
			var d = game.HEX.axial_distance(start_hex, f_unit.get_hex())
			if d < best_dist:
				best_dist = d
				best_target = f_unit
				
	return best_target
