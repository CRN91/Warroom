extends Node
class_name CardScripts

# ──────────────────────────────────────────────────────────────────────────────
# CardScripts
# ──────────────────────────────────────────────────────────────────────────────
# The data-driven effects in card_resolver.gd cover the common cases (modifiers,
# spawning, deck edits, scheduling). But you said a lot of your game's complexity
# will live in the cards, so this file is the escape hatch: any card can run a
# named function here with full access to `game`.
#
# In a card's effects array:
#   { "type": "script", "fn": "harsh_winter", "days": 3 }
#
# The resolver calls run("harsh_winter", game, effect). Inside the function you
# have the whole game: game.modifiers, game.units, game.cities, game.spawn_unit(),
# game.rail_network, game.deck, etc. Write whatever bespoke behaviour you want.
#
# `ctx` is the effect dictionary itself, so you can pass parameters from JSON.
# ──────────────────────────────────────────────────────────────────────────────

func run(fn: String, game: Node, ctx: Dictionary) -> void:
	if fn == "":
		push_error("CardScripts: empty fn")
		return
	if not has_method(fn):
		push_error("CardScripts: no script named '%s'" % fn)
		return
	call(fn, game, ctx)

# ── Dummy scripts to test the pipeline ────────────────────────────────────────

func harsh_winter(game: Node, ctx: Dictionary) -> void:
	# Weather demo: freezes ground movement and halves all city income for N days.
	# Trains keep running (rail is cleared first). Tagged so a thaw card can lift it.
	var days: int = int(ctx.get("days", 3))
	game.game_state["weather"] = "winter"
	game.modifiers.remove_by_tag("weather")
	game.modifiers.add_modifier({
		"id": "winter_freeze", "stat": "move_block", "op": "set", "value": 1,
		"scope": "ground", "duration_days": days, "tags": ["weather"], "source": "harsh_winter"
	})
	game.modifiers.add_modifier({
		"id": "winter_income", "stat": "city_income", "op": "mul", "value": 0.5,
		"scope": "all", "duration_days": days, "tags": ["weather"], "source": "harsh_winter"
	})
	print("[script] Harsh winter for %d days: ground frozen, city income halved." % days)

func clear_skies(game: Node, _ctx: Dictionary) -> void:
	# Lifts any weather modifiers early.
	game.game_state["weather"] = "clear"
	game.modifiers.remove_by_tag("weather")
	print("[script] Skies clear, weather modifiers lifted.")

func summon_reinforcements(game: Node, ctx: Dictionary) -> void:
	# Spawns fresh infantry next to the player HQ and tops up the HQ city.
	var count: int = int(ctx.get("count", 1))
	for i in range(count):
		game.spawn_unit({ "unit": "infantry", "team": 1, "near": "player_hq" })
	var hq = game.player_hq()
	if hq:
		hq.replenish(int(ctx.get("supplies", 300)))
	print("[script] Reinforcements: %d infantry spawned at player HQ." % count)

func elite_commando(game: Node, _ctx: Dictionary) -> void:
	# Spawns a custom unit: an infantry chassis with a permanent attack buff and
	# a bigger supply tank, tagged so other cards can target it later.
	var u = game.spawn_unit({
		"unit": "infantry", "team": 1, "near": "player_hq",
		"unit_type": "commando", "name": "Commando", "max_resources": 160, "fill": true,
		"tags": ["elite"],
		"modifiers": [
			{ "stat": "attack", "op": "mul", "value": 1.5 }   # permanent, auto-scoped to this unit
		]
	})
	if u:
		print("[script] Elite commando deployed: %s" % u.name)

func relic_awakens(game: Node, _ctx: Dictionary) -> void:
	# Story payoff: turns one of the player's combat units into an "anomaly" with
	# a huge attack bonus, then schedules a follow-up card a week later.
	var candidates: Array = game.modifiers.select_pieces(game, "player")
	candidates = candidates.filter(func(p): return p.has_method("is_combatant") and p.is_combatant())
	if candidates.is_empty():
		print("[script] Relic awakens, but no combat unit to transform.")
		return
	var target = candidates[randi() % candidates.size()]
	target.unit_type = "anomaly"
	target.name = "The Anomaly"
	target.tags = ["anomaly"]
	target.resource_comp.set_max_resources(250)
	target.replenish(250)
	game.modifiers.add_modifier({
		"id": "anomaly_power", "stat": "attack", "op": "mul", "value": 2.0,
		"scope": "unit:%d" % target.get_instance_id(), "source": "relic_awakens"
	})
	game.card_manager.schedule_card("intel_anomaly_grows", 7)
	print("[script] The relic awakens. %s transformed." % target.name)

func enemy_offensive(game: Node, ctx: Dictionary) -> void:
	# Asymmetric pressure: temporarily buffs every enemy combatant and drops a
	# fresh enemy artillery piece at their HQ.
	var days: int = int(ctx.get("days", 4))
	game.modifiers.add_modifier({
		"id": "enemy_push", "stat": "attack", "op": "mul", "value": 1.5,
		"scope": "enemy", "duration_days": days, "source": "enemy_offensive"
	})
	game.spawn_unit({ "unit": "artillery", "team": 2, "near": "enemy_hq" })
	print("[script] Enemy offensive for %d days + reinforcement spawned." % days)

func sabotage_rail(game: Node, _ctx: Dictionary) -> void:
	# Supply disruption: breaks a random intact player rail hex.
	var candidates: Array = []
	for hex in game.rail_network.rail_hexes:
		if not game.rail_network.rail_hexes[hex]["broken"]:
			candidates.append(hex)
	if candidates.is_empty():
		print("[script] Sabotage ordered, but there is no rail to break.")
		return
	game.rail_network.break_rail_at(candidates[randi() % candidates.size()])
	print("[script] A rail line was sabotaged.")

func morale_collapse(game: Node, ctx: Dictionary) -> void:
	# Drains supplies from every player combat unit (a soft punishment that lands
	# on the board rather than a number on a menu).
	var amount: int = int(ctx.get("amount", 40))
	for p in game.modifiers.select_pieces(game, "player"):
		if p.has_method("is_combatant") and p.is_combatant():
			p.deplete(amount)
	print("[script] Morale collapse: -%d supplies to all player combat units." % amount)
