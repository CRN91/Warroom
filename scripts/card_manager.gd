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
	var order = ["intel", "event", "decision"]
	var required: String = order[(day - 1) % 3] if day > 0 else "intel"
	var world := _world()

	for i in range(deck.size()):
		var card = deck.queue[i]
		if card.get("type", "") != required:
			continue
		# Gated cards (requires not currently met) stay in the deck for later.
		if not _requires_met(card, world):
			continue
		deck.queue.remove_at(i)
		return card

	return _filler_card(required)

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
	if choice.begins_with("choice_") and card_data.has(choice):
		resolver.resolve(card_data[choice].get("effects", []), game)

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
