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

func _on_game_over(player_lost: bool, headline: String) -> void:
	if game_paused: return
	game_paused = true
	s.ui.show_game_over(player_lost, day, headline)
	get_tree().paused = true

# ── The day cycle ─────────────────────────────────────────────────────────────

func advance_day() -> void:
	if game_paused: return
	if s.ui.decision_pending: return   # belt-and-braces; the button is disabled too

	day += 1
	Events.day_advanced.emit(day)

	s.fow.clear_flashes()
	s.board.scrub_grid()
	_unfreeze_all()
	s.modifiers.tick(day)
	s.weather.on_day_tick()
	s.card_manager.check_pending(day)
	s.enemy_ai.run_turn()

	# Standing supply runs set their goals before movement resolves
	for unit in s.board.units:
		if is_instance_valid(unit) and unit is Engineers and unit.has_shuttle():
			unit.process_shuttle(s.board)

	var starved := _resolve_all_movement()

	s.board.recent_death_hexes.clear()
	_resolve_all_combat()

	for unit in s.board.units:
		if is_instance_valid(unit):
			unit.process_resupply()

	# The map table updates: paint, pockets, who's cut off — then consequences
	s.control.weekly_update()
	s.control.update_isolation()
	s.board.harass_haulers()
	s.board.tick_garrisons()
	s.board.check_sieges()

	_draw_and_show_card()

	for city in s.board.cities:
		if is_instance_valid(city):
			city.next_day()

	for dead in starved:
		if is_instance_valid(dead):
			Events.notify("%s ran out of supplies and disbanded." % dead.name)
			s.board.kill(dead)

	s.board.cull_dead()
	_check_coalition_defeated()

	_unfreeze_all()
	s.fow.update_fow()

	_telegraph_attacks()

	for unit in s.board.units:
		if is_instance_valid(unit) and unit.has_method("refresh_intent"):
			unit.refresh_intent()

	s.ui.on_day_finished()

func _check_coalition_defeated() -> void:
	## Second victory path: the coalition expedition has landed and been wiped out.
	if game_paused: return
	if not s.board.state.get("coalition_landed", false): return
	if s.board.state.get("coalition_defeated", false): return
	for u in s.board.units:
		if is_instance_valid(u) and u.team == 3:
			return
	s.board.state["coalition_defeated"] = true
	Events.game_over.emit(false,
		"The coalition expedition is destroyed. Their colours come down; the enemy sues for peace.")

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

func prepare_first_turn() -> void:
	## Called once after setup: telegraphs + intents, then the run's first
	## decision — which army high command hands you (the doctrine pick).
	_telegraph_attacks()
	for unit in s.board.units:
		if is_instance_valid(unit) and unit.has_method("refresh_intent"):
			unit.refresh_intent()

	var doctrine = s.card_manager.doctrine_offer()
	s.ui.card_ui.display_card(doctrine, -1)
	Events.decision_pending.emit(true)

func _telegraph_attacks() -> void:
	## Every combatant locks in the target it would shoot next turn, so the
	## intent arrows (red) show incoming attacks before they happen — yours
	## and, crucially, the enemy's.
	for unit in s.board.units:
		if not is_instance_valid(unit): continue
		if not unit.is_combatant() or unit.attack_comp == null: continue
		if unit.attack_comp.target != null and is_instance_valid(unit.attack_comp.target):
			continue   # keep an existing (manual/sticky) target
		unit.attack_comp.acquire_target(s.grid)

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

		# Muzzle flash: firing gives away your position until next turn,
		# so fog can't hide an artillery piece that just shelled you.
		s.fow.flash(attacker)

		if attacker.attack(target):
			if target is City:
				# Shellfire can empty a city, but only adjacent troops take it.
				if s.board.HEX.axial_distance(attacker.get_hex(), target.get_hex()) == 1:
					target.capture(attacker.team)
			elif target not in to_die:
				to_die.append(target)
				if attacker.team == 1 or target.team == 1:
					Events.report("%s destroyed %s." % [attacker.name, target.name])

		# Shellfire wrecks any rail on the defender's hex.
		var target_hex = target.get_hex()
		if target_hex != null and s.rail_network.rail_hexes.has(target_hex):
			s.rail_network.break_rail_at(target_hex)

		if attacker.get_resources() <= 0 and attacker not in to_die:
			to_die.append(attacker)

	for dead in to_die:
		if is_instance_valid(dead):
			s.board.kill(dead)
