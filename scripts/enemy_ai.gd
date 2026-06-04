extends Node
class_name EnemyAI

var game: Node2D # Reference to Game.gd to access the world state

func setup(_game: Node2D):
	game = _game

func run_turn():
	# 1. Buy units if affordable
	for city in game.cities:
		if city.team != 2: continue
		var res = city.get_resources()
		
		if res >= game.COST["infantry"]:
			var choices = []
			if res >= game.COST["artillery"]: choices.append("artillery")
			if res >= game.COST["logistics"]: choices.append("logistics")
			choices.append("infantry")
			
			var choice = choices[randi() % choices.size()]
			var scene = {"infantry": game.INFANTRY, "artillery": game.ARTILLERY, "logistics": game.LOGI}[choice]
			
			if game._spawn_unit_near_city(scene, city):
				city.deplete(game.COST[choice])

	# 2. Move units toward targets
	for unit in game.units:
		if unit.team != 2 or unit is City or unit is Train: continue

		# FIX: Retreat only if supplies drop below 30% of their specific max capacity!
		var is_starving = unit.get_resources() <= (unit.get_max_resources() * 0.3)

		if is_starving:
			# Flee to nearest friendly city
			var best_city = null
			var best_dist = 9999
			for city in game.cities:
				if city.team == 2:
					var d = game.HEX.axial_distance(unit.get_hex(), city.get_hex())
					if d < best_dist:
						best_dist = d
						best_city = city
			if best_city:
				unit.movement_comp.set_goal(best_city.get_hex())
			continue # Skip the attack logic so they focus on running home

		# If they aren't starving, and already have a goal, let them keep marching
		if unit.movement_comp.goal != null: continue

		# OFFENSE: Find the nearest player unit or city to attack
		var best_target = null
		var best_dist   = 9999
		
		for p_unit in game.units:
			if p_unit.team == 1:
				var d = game.HEX.axial_distance(unit.get_hex(), p_unit.get_hex())
				if d < best_dist:
					best_dist = d
					best_target = p_unit
					
		for city in game.cities:
			if city.team == 1:
				var d = game.HEX.axial_distance(unit.get_hex(), city.get_hex())
				if d < best_dist:
					best_dist = d
					best_target = city
					
		# Charge the target!
		if best_target:
			unit.movement_comp.set_goal(best_target.get_hex())
