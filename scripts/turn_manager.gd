extends Node
class_name TurnManager

## Owns the day counter and runs the end-of-turn pipeline:
## upkeep -> enemy orders -> movement -> combat -> resupply -> card draw -> cleanup.

var day: int = 0
var game_paused: bool = false

var s: GameServices

func setup(services: GameServices) -> void:
	s = services
	Events.game_over.connect(_on_game_over)

func _on_game_over(player_lost: bool) -> void:
	game_paused = true
	s.ui.show_game_over(player_lost, day)
	get_tree().paused = true

# ── The day cycle ─────────────────────────────────────────────────────────────

func advance_day() -> void:
	if game_paused: return
	if s.ui.decision_pending: return   # belt-and-braces; the button is disabled too

	day += 1
	Events.day_advanced.emit(day)

	_unfreeze_all()
	s.modifiers.tick(day)
	s.weather.on_day_tick()
	s.card_manager.check_pending(day)
	s.enemy_ai.run_turn()

	var starved := _resolve_all_movement()

	s.board.recent_death_hexes.clear()
	_resolve_all_combat()

	for unit in s.board.units:
		if is_instance_valid(unit):
			unit.process_resupply()

	_draw_and_show_card()

	for city in s.board.cities:
		if is_instance_valid(city):
			city.next_day()

	for dead in starved:
		if is_instance_valid(dead):
			Events.notify("%s ran out of supplies and disbanded." % dead.name)
			s.board.kill(dead)

	s.board.cull_dead()

	_unfreeze_all()
	s.fow.update_fow()

	for unit in s.board.units:
		if is_instance_valid(unit) and unit.has_method("refresh_intent"):
			unit.refresh_intent()

	s.ui.on_day_finished()

func _draw_and_show_card() -> void:
	var card = s.card_manager.draw_daily_card(day)
	if card == null:
		s.ui.card_ui.hide()
		return
	s.card_manager.resolve_drawn(card)
	s.ui.card_ui.display_card(card, _max_city_funds())
	# Decision cards block the next End Turn until answered.
	Events.decision_pending.emit(card.get("type", "") == "decision")

func _max_city_funds() -> int:
	var funds := 0
	for c in s.board.cities:
		if c.team == 1:
			funds = max(funds, c.get_resources())
	return funds

func _unfreeze_all() -> void:
	for unit in s.board.units:
		if is_instance_valid(unit):
			unit.unfreeze()

# ── Movement ──────────────────────────────────────────────────────────────────

func _resolve_all_movement() -> Array:
	## Player units with manual paths go first, then player auto-goal units,
	## then the enemy. Runs multiple passes so a unit blocked by a friend that
	## moves this turn can step into the vacated hex (no swaps — the hex must
	## actually be free when the follower moves).
	## Returns the units that starved during their daily tick.
	var movers: Array = _movement_order()
	var done: Dictionary = {}

	for _pass in range(3):
		var any_moved := false
		for unit in movers:
			if not is_instance_valid(unit) or done.has(unit): continue
			if not unit.has_method("process_movement"): continue
			if s.modifiers.is_movement_blocked(unit):
				done[unit] = true
				continue

			var before = unit.get_hex()
			unit.process_movement()

			if unit is Train:
				done[unit] = true   # trains run their whole route in one go
			elif unit.get_hex() != before:
				done[unit] = true   # moved (and froze) — spent for today
				any_moved = true
		if not any_moved:
			break

	var starved: Array = []
	for unit in movers:
		if is_instance_valid(unit) and unit.next_day():
			starved.append(unit)
	return starved

func _movement_order() -> Array:
	var player_manual: Array = []
	var player_auto: Array = []
	var others: Array = []

	for unit in s.board.units:
		if unit is City: continue
		if unit.team == 1:
			if unit.movement_comp.path.size() > 0:
				player_manual.append(unit)
			else:
				player_auto.append(unit)
		else:
			others.append(unit)

	return player_manual + player_auto + others

# ── Combat ────────────────────────────────────────────────────────────────────

func _resolve_all_combat() -> void:
	## All attacks are gathered first, then applied — simultaneous resolution,
	## so two units that target each other both get their shot in.
	var attacks: Array = []
	var to_die: Array = []

	for unit in s.board.units:
		if not unit.is_combatant(): continue
		var target = unit.get_attack_target()
		if target:
			attacks.append({ "attacker": unit, "target": target })

	for pair in attacks:
		var attacker = pair["attacker"]
		var target = pair["target"]
		if not is_instance_valid(attacker) or not is_instance_valid(target): continue

		if attacker.attack(target):
			if target is City:
				# Shellfire can empty a city, but only adjacent troops take it.
				if s.board.HEX.axial_distance(attacker.get_hex(), target.get_hex()) == 1:
					target.capture(attacker.team)
			elif target not in to_die:
				to_die.append(target)

		# Shellfire wrecks any rail on the defender's hex.
		var target_hex = target.get_hex()
		if target_hex != null and s.rail_network.rail_hexes.has(target_hex):
			s.rail_network.break_rail_at(target_hex)

		if attacker.get_resources() <= 0 and attacker not in to_die:
			to_die.append(attacker)

	for dead in to_die:
		if is_instance_valid(dead):
			s.board.kill(dead)
