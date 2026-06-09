extends Node
class_name CardManager

# Owns the deck lifecycle: builds the starting deck, draws one card per day on the
# intel -> event -> decision loop, holds the scheduler for "happens N days later"
# effects, AND bridges the board to the story via triggers/conditions.
#
# Two new mechanisms make the board and the card game one system:
#
#   trigger  — a card carries  "trigger": { "event": "...", <ctx matches>, ... }
#              When game code calls  card_manager.notify("event", {ctx})  any card
#              whose trigger matches (and whose `requires` hold) is injected.
#
#   requires — a card carries  "requires": { <world condition>, ... }
#              The card can only be drawn or triggered while the condition holds,
#              e.g. an "armoured train" decision that only appears when a train
#              actually exists on the board.
#
# Effects themselves are still applied by CardResolver.

@onready var deck         = $Deck
@onready var card_library = $CardLibrary
@onready var resolver     = $CardResolver
@onready var card_scripts: CardScripts = $CardScripts

var scheduled: Array = []              # [{ on_day:int, effect:Dictionary }]
var game: Node2D

# Board -> story triggers
var watchers: Array = []               # card ids in the library that carry a "trigger"
var fired: Dictionary = {}             # card_id -> true   (once-triggers already fired)
var tally: Dictionary = {}             # card_id -> int    (running count toward trigger.count)

# Paid shops: not in the starting deck — scheduled one at a time so they stay occasional.
const SHOP_SET := "supply_offers"
const SHOP_PITY := 8                    # guarantee a shop if none has appeared in N weeks
const SHOP_GAP_MIN := 3                 # otherwise the next random shop lands in 3..6 weeks
const SHOP_GAP_MAX := 6
var weeks_since_shop := 0
var _shop_ids: Array = []

func setup(_game: Node2D):
	game = _game
	card_library.load_library()

	var starting = card_library.build_starting_deck([
		"ambient",        # recurring texture (weather, filler intel, supply)
		"story_seeds",    # the per-run story openers
	])
	for card in starting:
		deck.push(card)

	_index_watchers()
	_shop_ids = card_library.get_set_card_ids(SHOP_SET)
	_schedule_next_shop()
	print("CardManager: starting deck has %d cards, %d trigger-watchers." % [deck.size(), watchers.size()])

func _index_watchers() -> void:
	watchers.clear()
	for id in card_library.all_cards:
		if card_library.all_cards[id].has("trigger"):
			watchers.append(id)

# ── Scheduling ────────────────────────────────────────────────────────────────

func schedule_effect(effect: Dictionary, after_days) -> void:
	scheduled.append({ "on_day": game.day + int(after_days), "effect": effect })

func schedule_card(id: String, after_days, position: String = "soon") -> void:
	schedule_effect({ "type": "inject_cards", "ids": [id], "position": position }, after_days)

func check_pending(day: int) -> void:
	# Expire old modifiers, fire day-based triggers, then fire scheduled effects.
	game.modifiers.tick(day)
	_check_day_triggers(day)
	for i in range(scheduled.size() - 1, -1, -1):
		if scheduled[i]["on_day"] <= day:
			resolver.resolve([scheduled[i]["effect"]], game)
			scheduled.remove_at(i)

# ── Board events (call card_manager.notify(...) from gameplay code) ───────────

func notify(event: String, ctx: Dictionary = {}) -> void:
	if game == null:
		return
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

	# Pity bookkeeping: reset when a shop surfaces, otherwise count the week.
	if _is_shop(drawn):
		weeks_since_shop = 0
	else:
		weeks_since_shop += 1
	return drawn

func _filler_card(required: String) -> Dictionary:
	match required:
		"intel":
			return { "id": "filler_intel", "type": "intel",
				"text": "The front is quiet. No new reports.", "effects": [] }
		"event":
			return { "id": "filler_event", "type": "event",
				"text": "An uneventful day passes on the line.", "effects": [] }
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
		resolver.resolve(card["effects"], game)

func resolve_choice(card_data: Dictionary, choice: String):
	# Accepts any choice_* key (yes/no and multi-choice). "ack"/anything else =
	# a plain dismiss of an intel/event card.
	if not (choice.begins_with("choice_") and card_data.has(choice)):
		return
		
	var ch = card_data[choice]
	var cost := int(ch.get("cost", 0))
	var effects = ch.get("effects", [])
	
	if cost > 0 and ch.get("pay_from", "pick_city") == "pick_city":
		# Gather all cities that can actually afford this
		var eligible_cities = []
		for c in game.cities:
			if c.team == 1 and c.get_resources() >= cost:
				eligible_cities.append(c)
				
		# 1. Auto-purchase if only 1 city is eligible!
		if eligible_cities.size() == 1:
			game.execute_purchase(eligible_cities[0], cost, effects)
			
		# 2. Show UI overlay if multiple cities are eligible!
		elif eligible_cities.size() > 1:
			game.prompt_city_selection(eligible_cities, cost, effects)
	else:
		resolver.resolve(effects, game)
		
	# Recycle a paid shop: queue the next random shop a few weeks out so they recur.
	if _is_shop(card_data):
		_schedule_next_shop()

# ── Conditions / world snapshot ───────────────────────────────────────────────

func _world() -> Dictionary:
	var by_type: Dictionary = {}
	for u in game.units:
		var t = u.get("unit_type")
		if t != null and str(t) != "":
			by_type[str(t)] = int(by_type.get(str(t), 0)) + 1

	var rn = game.get("rail_network")
	var tm = game.get("terrain_manager")
	return {
		"day": game.day,
		"week": game.day,
		"season": game.current_season() if game.has_method("current_season") else "spring",
		"unit_count": game.units.size(),
		"city_count": game.cities.size(),
		"train_count": game.trains.size(),
		"train_exists": game.trains.size() > 0,
		"rail_count": rn.rail_hexes.size() if rn else 0,
		"bridge_count": _bridge_count(tm),
		"weather": game.game_state.get("weather", "clear"),
		"by_type": by_type,
	}

func _bridge_count(tm) -> int:
	var n := 0
	if tm:
		for k in tm.river.keys():
			if tm.river[k].get("bridge", false):
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

func _is_shop(card) -> bool:
	return card != null and card.get("id", "") in _shop_ids

func _schedule_next_shop() -> void:
	# Queue one random paid shop a few weeks out (the "recycle").
	if _shop_ids.is_empty():
		return
	var id: String = _shop_ids[randi() % _shop_ids.size()]
	schedule_card(id, randi_range(SHOP_GAP_MIN, SHOP_GAP_MAX), "soon")

func _force_shop() -> void:
	# Pity backstop: drop a random shop in now if we've gone too long without one.
	if _shop_ids.is_empty():
		return
	var id: String = _shop_ids[randi() % _shop_ids.size()]
	if not deck.has_id(id):
		deck.inject(card_library.get_card(id), "front")
	weeks_since_shop = 0

# ── Guaranteed weekly acquisition (Mini Metro style) ──────────────────────────
# Built fresh each week so it's reliable and predictable, separate from the random
# draw. Free, small picks — the steady drip that replaces the old always-open shop.
# (Keep the paid `supply_offers` shops for bigger/rarer buys and their FTL tension.)
func weekly_offer() -> Dictionary:
	var pool := [
		{ "label": "A new locomotive", "effects": [{ "type": "grant_train", "amount": 1 }] },
		{ "label": "A new rail line (5 rails)", "effects": [{ "type": "grant_rails", "amount": 5 }] },
		{ "label": "A prefab bridge", "effects": [{ "type": "grant_bridges", "amount": 1 }] },
		{ "label": "Fresh infantry at the capital",
		  "effects": [{ "type": "spawn_unit", "unit": "infantry", "team": 1, "near": "player_capital" }] },
	]
	pool.shuffle()
	return {
		"id": "weekly_requisition",
		"type": "decision",
		"text": "High command's weekly allocation has arrived. Choose one.",
		"choice_a": pool[0],
		"choice_b": pool[1],
		"choice_c": { "label": "Hold it back this week", "effects": [] },
	}
