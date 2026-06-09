extends Node
class_name CardScripts

# ──────────────────────────────────────────────────────────────────────────────
# CardScripts
# ──────────────────────────────────────────────────────────────────────────────
# The data-driven effects in card_resolver.gd cover the common cases (modifiers,
# spawning, deck edits, scheduling). This file is the escape hatch: any card can
# run a named function here with full access to the game's systems via `s`.
#
# In a card's effects array:
#   { "type": "script", "fn": "harsh_winter", "days": 3 }
#
# The resolver calls run("harsh_winter", effect). Inside the function you have
# everything: s.modifiers, s.board (units/cities/spawn_unit), s.weather,
# s.rail_network, s.card_manager... `ctx` is the effect dictionary itself, so
# parameters can be passed straight from JSON.
# ──────────────────────────────────────────────────────────────────────────────

var s: GameServices

func setup(services: GameServices) -> void:
	s = services

func run(fn: String, ctx: Dictionary) -> void:
	if fn == "":
		push_error("CardScripts: empty fn")
		return
	if not has_method(fn):
		push_error("CardScripts: no script named '%s'" % fn)
		return
	call(fn, ctx)

# ── Weather ───────────────────────────────────────────────────────────────────

func harsh_winter(ctx: Dictionary) -> void:
	# Freezes ground movement and halves all city income for N days.
	# Trains keep running (rail is cleared first).
	var days: int = int(ctx.get("days", 3))
	s.weather.set_weather("winter", [
		{ "id": "winter_freeze", "stat": "move_block", "op": "set", "value": 1,
		  "scope": "ground", "duration_days": days },
		{ "id": "winter_income", "stat": "city_income", "op": "mul", "value": 0.5,
		  "scope": "all", "duration_days": days },
	], "harsh_winter")
	Events.notify("Harsh winter: ground frozen, city income halved for %d weeks." % days)

func clear_skies(_ctx: Dictionary) -> void:
	# Lifts any weather modifiers early.
	s.weather.clear_weather()

# ── Reinforcement / unit scripts ──────────────────────────────────────────────

func summon_reinforcements(ctx: Dictionary) -> void:
	# Spawns fresh infantry next to the player capital and tops up the capital city.
	var count: int = int(ctx.get("count", 1))
	for i in range(count):
		s.board.spawn_unit({ "unit": "infantry", "team": 1, "near": "player_capital" })
	var capital = s.board.player_capital()
	if capital:
		capital.replenish(int(ctx.get("supplies", 300)))

func elite_commando(_ctx: Dictionary) -> void:
	# Spawns a custom unit: an infantry chassis with a permanent attack buff and
	# a bigger supply tank, tagged so other cards can target it later.
	s.board.spawn_unit({
		"unit": "infantry", "team": 1, "near": "player_capital",
		"unit_type": "commando", "name": "Commando", "max_resources": 160, "fill": true,
		"tags": ["elite"],
		"modifiers": [
			{ "stat": "attack", "op": "mul", "value": 1.5 }   # permanent, auto-scoped to this unit
		]
	})

func relic_awakens(_ctx: Dictionary) -> void:
	# Story payoff: turns one of the player's combat units into an "anomaly" with
	# a huge attack bonus, then schedules a follow-up card a week later.
	var candidates: Array = s.modifiers.select_pieces(s.board.units, s.board.cities, "player")
	candidates = candidates.filter(func(p): return p.has_method("is_combatant") and p.is_combatant())
	if candidates.is_empty():
		return
	var target = candidates[randi() % candidates.size()]
	target.unit_type = "anomaly"
	target.name = "The Anomaly"
	target.tags = ["anomaly"]
	target.resource_comp.set_max_resources(250)
	target.replenish(250)
	s.modifiers.add_modifier({
		"id": "anomaly_power", "stat": "attack", "op": "mul", "value": 2.0,
		"scope": "unit:%d" % target.get_instance_id(), "source": "relic_awakens"
	})
	s.card_manager.schedule_card("intel_anomaly_grows", 7)

func enemy_offensive(ctx: Dictionary) -> void:
	# Asymmetric pressure: temporarily buffs every enemy combatant and drops a
	# fresh enemy artillery piece at their capital.
	var days: int = int(ctx.get("days", 4))
	s.modifiers.add_modifier({
		"id": "enemy_push", "stat": "attack", "op": "mul", "value": 1.5,
		"scope": "enemy", "duration_days": days, "source": "enemy_offensive"
	})
	s.board.spawn_unit({ "unit": "artillery", "team": 2, "near": "enemy_capital" })

func sabotage_rail(_ctx: Dictionary) -> void:
	# Supply disruption: breaks a random intact player rail hex.
	var candidates: Array = []
	for hex in s.rail_network.rail_hexes:
		if not s.rail_network.rail_hexes[hex]["broken"]:
			candidates.append(hex)
	if candidates.is_empty():
		return
	s.rail_network.break_rail_at(candidates[randi() % candidates.size()])

func morale_collapse(ctx: Dictionary) -> void:
	# Drains supplies from every player combat unit (a soft punishment that lands
	# on the board rather than a number on a menu).
	var amount: int = int(ctx.get("amount", 40))
	for p in s.modifiers.select_pieces(s.board.units, s.board.cities, "player"):
		if p.has_method("is_combatant") and p.is_combatant():
			p.deplete(amount)
	Events.notify("Morale collapse: front-line units lose %d supplies." % amount)
