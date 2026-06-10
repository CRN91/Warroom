extends Node
class_name CardManager

# Owns the deck lifecycle: builds the starting deck, draws one card per day on
# the intel -> event -> decision loop, holds the scheduler for "happens N days
# later" effects, and bridges the board to the story via triggers/conditions.
#
# Two mechanisms make the board and the card game one system:
#
#   trigger  — a card carries  "trigger": { "event": "...", <ctx matches>, ... }
#              Board facts arrive via the Events bus (city_captured,
#              rail_established, unit_died); any card whose trigger matches
#              (and whose `requires` hold) is injected into the deck.
#
#   requires — a card carries  "requires": { <world condition>, ... }
#              The card can only be drawn or triggered while the condition
#              holds, e.g. an "armoured train" decision that only appears when
#              a train actually exists on the board.
#
# Effects themselves are applied by CardResolver.

@onready var deck: Deck = $Deck
@onready var card_library: CardLibrary = $CardLibrary
@onready var resolver: CardResolver = $CardResolver
@onready var card_scripts: CardScripts = $CardScripts

var scheduled: Array = []              # [{ on_day:int, effect:Dictionary }]
var s: GameServices

# Board -> story triggers
var watchers: Array = []               # card ids in the library that carry a "trigger"
var fired: Dictionary = {}             # card_id -> true   (once-triggers already fired)
var tally: Dictionary = {}             # card_id -> int    (running count toward trigger.count)

# Paid shops: not in the starting deck — scheduled one at a time so they stay
# occasional, and ALWAYS paid (there is no free acquisition in this game).
const SHOP_SET := "supply_offers"
const SHOP_PITY := 10                   # guarantee a shop if none has appeared in N weeks
const SHOP_GAP_MIN := 4                 # otherwise the next random shop lands in 4..7 weeks
const SHOP_GAP_MAX := 7
var weeks_since_shop := 0
var _shop_ids: Array = []
var _last_shop_id := ""

# Combat events queue up here (via Events.battle_event) and surface as a
# field-report intel card instead of noisy toasts.
var battle_log: Array = []

func setup(services: GameServices):
	s = services
	card_library.load_library()
	resolver.setup(s)
	card_scripts.setup(s)

	var starting = card_library.build_starting_deck([
		"ambient",        # recurring texture (weather, filler intel, supply)
		"story_seeds",    # the per-run story openers
	])
	for card in starting:
		deck.push(card)

	_index_watchers()
	_shop_ids = card_library.get_set_card_ids(SHOP_SET)
	_schedule_next_shop()

	# Board facts -> story triggers
	Events.city_captured.connect(_on_city_captured)
	Events.rail_established.connect(func(_route_id): notify("rail_established"))
	Events.unit_died.connect(func(unit): notify("unit_died", { "team": unit.team }))
	Events.battle_event.connect(func(m: String):
		battle_log.append(m)
		if battle_log.size() > 8: battle_log.pop_front()
	)

	print("CardManager: starting deck has %d cards, %d trigger-watchers." % [deck.size(), watchers.size()])

func _on_city_captured(_city: Node2D, by_team: int, prev_team: int) -> void:
	if by_team == 1:
		var ev := "enemy_city_captured" if prev_team == 2 else "neutral_city_captured"
		notify(ev, { "by": 1 })
	else:
		notify("city_lost", { "by": by_team })

func _index_watchers() -> void:
	watchers.clear()
	for id in card_library.all_cards:
		if card_library.all_cards[id].has("trigger"):
			watchers.append(id)

# ── Scheduling ────────────────────────────────────────────────────────────────

func schedule_effect(effect: Dictionary, after_days) -> void:
	scheduled.append({ "on_day": s.turn.day + int(after_days), "effect": effect })

func schedule_card(id: String, after_days, position: String = "soon") -> void:
	schedule_effect({ "type": "inject_cards", "ids": [id], "position": position }, after_days)

func check_pending(day: int) -> void:
	_check_day_triggers(day)
	for i in range(scheduled.size() - 1, -1, -1):
		if scheduled[i]["on_day"] <= day:
			resolver.resolve([scheduled[i]["effect"]])
			scheduled.remove_at(i)

# ── Board events ──────────────────────────────────────────────────────────────

func notify(event: String, ctx: Dictionary = {}) -> void:
	var world := _world()
	for id in watchers:
		var card: Dictionary = card_library.all_cards[id]
		var trig: Dictionary = card.get("trigger", {})
		if str(trig.get("event", "")) != event:
			continue
		if fired.has(id):
			continue
		if not _trigger_ctx_matches(trig, ctx):
			continue
		if not _requires_met(card, world):
			continue
		# A trigger with "count": N fires only on the Nth matching event.
		var need: int = int(trig.get("count", 1))
		tally[id] = int(tally.get(id, 0)) + 1
		if tally[id] < need:
			continue
		deck.inject(card_library.get_card(id), str(trig.get("position", "soon")))
		if bool(trig.get("once", true)):
			fired[id] = true

func _trigger_ctx_matches(trig: Dictionary, ctx: Dictionary) -> bool:
	# Every key on the trigger besides the reserved ones must equal the ctx value.
	# e.g. { "event": "city_captured", "by": 1 }  requires ctx["by"] == 1.
	var reserved := ["event", "position", "once", "count", "requires"]
	for k in trig.keys():
		if k in reserved:
			continue
		if str(ctx.get(k, "")) != str(trig[k]):
			return false
	return true

func _check_day_triggers(day: int) -> void:
	var world := _world()
	for id in watchers:
		var card: Dictionary = card_library.all_cards[id]
		var trig: Dictionary = card.get("trigger", {})
		if str(trig.get("event", "")) != "day":
			continue
		if fired.has(id):
			continue
		if int(trig.get("day", 0)) > day:
			continue
		if not _requires_met(card, world):
			continue
		deck.inject(card_library.get_card(id), str(trig.get("position", "soon")))
		fired[id] = true

# ── Drawing ───────────────────────────────────────────────────────────────────

func draw_daily_card(day: int):
	# Pity: if it's been too long since a shop, make sure one is queued up front.
	if weeks_since_shop >= SHOP_PITY:
		_force_shop()

	var order = ["intel", "event", "decision"]
	var required: String = order[(day - 1) % 3] if day > 0 else "intel"

	var world := _world()
	var drawn = null
	for i in range(deck.size()):
		var card = deck.queue[i]
		if card.get("type", "") != required:
			continue
		# Gated cards (requires not currently met) stay in the deck for later.
		if not _requires_met(card, world):
			continue
		deck.queue.remove_at(i)
		drawn = card
		break
	if drawn == null:
		drawn = _filler_card(required)

	# Intel cards can carry live reconnaissance instead of canned text.
	if drawn.has("dynamic_text"):
		drawn = drawn.duplicate(true)
		if str(drawn["dynamic_text"]) == "war_report":
			drawn["text"] = IntelGenerator.war_report(battle_log)
			battle_log.clear()
		else:
			drawn["text"] = IntelGenerator.generate(str(drawn["dynamic_text"]), s.board)

	# Pity bookkeeping: reset when a shop surfaces, otherwise count the week.
	if _is_shop(drawn):
		weeks_since_shop = 0
	else:
		weeks_since_shop += 1
	return drawn

func _filler_card(required: String) -> Dictionary:
	match required:
		"intel":
			# Fighting last week? File the field report. Otherwise recon reports.
			if not battle_log.is_empty():
				var text := IntelGenerator.war_report(battle_log)
				battle_log.clear()
				return { "id": "filler_war_report", "type": "intel", "text": text, "effects": [] }
			return { "id": "filler_intel", "type": "intel",
				"text": IntelGenerator.generate("recon_report", s.board), "effects": [] }
		"event":
			return { "id": "filler_event", "type": "event",
				"text": "An uneventful week passes on the line.", "effects": [] }
		_:
			return { "id": "filler_decision", "type": "decision",
				"text": "Routine paperwork crosses your desk. Sign it?",
				"choice_a": { "label": "Sign", "effects": [] },
				"choice_b": { "label": "Set aside", "effects": [] } }

# ── Resolving ─────────────────────────────────────────────────────────────────

func resolve_drawn(card: Dictionary) -> void:
	if card.get("type", "") == "decision":
		return
	if card.has("effects"):
		resolver.resolve(card["effects"])

func resolve_choice(card_data: Dictionary, choice: String):
	# Accepts any choice_* key (yes/no and multi-choice).
	if not (choice.begins_with("choice_") and card_data.has(choice)):
		return

	var ch = card_data[choice]
	var cost := int(ch.get("cost", 0))
	var effects = ch.get("effects", [])

	if cost > 0 and ch.get("pay_from", "pick_city") == "pick_city":
		var eligible_cities = []
		for c in s.board.cities:
			if c.team == 1 and c.get_resources() >= cost:
				eligible_cities.append(c)

		if eligible_cities.size() == 1:
			s.board.execute_purchase(eligible_cities[0], cost, effects)
		elif eligible_cities.size() > 1:
			s.ui.show_city_picker(eligible_cities, cost,
				func(city): s.board.execute_purchase(city, cost, effects))
		else:
			Events.notify("No city can afford that.")
	else:
		resolver.resolve(effects)

	# Recycle a paid shop: queue the next random shop a few weeks out so they recur.
	if _is_shop(card_data):
		_schedule_next_shop()

# ── Conditions / world snapshot ───────────────────────────────────────────────

func _world() -> Dictionary:
	return {
		"day": s.turn.day,
		"week": s.turn.day,
		"season": s.weather.current_season(),
		"unit_count": s.board.units.size(),
		"city_count": s.board.cities.size(),
		"train_count": s.board.trains.size(),
		"train_exists": s.board.trains.size() > 0,
		"rail_count": s.rail_network.rail_hexes.size(),
		"bridge_count": _bridge_count(),
		"weather": s.weather.weather_name,
		"by_type": s.board.unit_counts_by_type(),
	}

func _bridge_count() -> int:
	var n := 0
	for k in s.terrain.river.keys():
		if s.terrain.river[k].get("bridge", false):
			n += 1
	return n

func _requires_met(card: Dictionary, world: Dictionary) -> bool:
	var req: Dictionary = card.get("requires", {})
	for key in req.keys():
		if not _one_requirement(str(key), req[key], world):
			return false
	return true

func _one_requirement(key: String, want, world: Dictionary) -> bool:
	match key:
		"train_exists":
			return bool(world["train_exists"]) == bool(want)
		"has_unit_type":
			return int(world["by_type"].get(str(want), 0)) > 0
		"chain_active":
			return _chain_active(str(want))
		"min_day":
			return int(world["day"]) >= int(want)
		"max_day":
			return int(world["day"]) <= int(want)
		"weather":
			return str(world["weather"]) == str(want)
		"season":
			return str(world["season"]) == str(want)
		_:
			# Generic numeric fact (unit_count, rail_count, bridge_count, ...).
			# want can be a bare number (treated as >=) or { ">=": n }, { "<": n }, etc.
			if not world.has(key):
				return true
			var have = world[key]
			if typeof(want) == TYPE_DICTIONARY:
				for op in want.keys():
					if not _cmp(float(have), str(op), float(want[op])):
						return false
				return true
			return float(have) >= float(want)

func _cmp(a: float, op: String, b: float) -> bool:
	match op:
		">=": return a >= b
		"<=": return a <= b
		">":  return a > b
		"<":  return a < b
		"==": return a == b
		"!=": return a != b
	return false

func _chain_active(set_name: String) -> bool:
	# A storyline counts as "active" if any of its cards are currently in the deck.
	for id in card_library.get_set_card_ids(set_name):
		for c in deck.queue:
			if c.get("id", "") == id:
				return true
	return false

# ── Shops & offers ────────────────────────────────────────────────────────────

func _is_shop(card) -> bool:
	return card != null and card.get("id", "") in _shop_ids

func _pick_shop_id() -> String:
	# Avoid offering the same shop twice in a row (no more endless rail yards).
	var pool := _shop_ids.filter(func(id): return id != _last_shop_id)
	if pool.is_empty():
		pool = _shop_ids
	var id: String = pool[randi() % pool.size()]
	_last_shop_id = id
	return id

func _schedule_next_shop() -> void:
	# Queue one random paid shop a few weeks out (the "recycle").
	if _shop_ids.is_empty():
		return
	schedule_card(_pick_shop_id(), randi_range(SHOP_GAP_MIN, SHOP_GAP_MAX), "soon")

func _force_shop() -> void:
	# Pity backstop: drop a shop in now if we've gone too long without one.
	if _shop_ids.is_empty():
		return
	var id: String = _pick_shop_id()
	if not deck.has_id(id):
		deck.inject(card_library.get_card(id), "front")
	weeks_since_shop = 0
