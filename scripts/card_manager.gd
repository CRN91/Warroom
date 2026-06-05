extends Node
class_name CardManager

# Owns the deck lifecycle: builds the starting deck, draws one card per day on the
# intel -> event -> decision loop, and holds the scheduler for "happens N days
# later" effects. Effects themselves are applied by CardResolver.

@onready var deck         = $Deck
@onready var card_library = $CardLibrary
@onready var resolver     = $CardResolver
@onready var card_scripts: CardScripts = $CardScripts

var scheduled: Array = []              # [{ on_day:int, effect:Dictionary }]
var game: Node2D

func setup(_game: Node2D):
	game = _game
	card_library.load_library()

	var starting = card_library.build_starting_deck([
		"western_front_intel",
		"weather_events",
		"command_decisions",
		"field_operations",       # showcase set demonstrating the new effect types
	])
	for card in starting:
		deck.push(card)

	print("CardManager: starting deck has %d cards." % deck.size())

# ── Scheduling ────────────────────────────────────────────────────────────────

func schedule_effect(effect: Dictionary, after_days) -> void:
	scheduled.append({ "on_day": game.day + int(after_days), "effect": effect })

func schedule_card(id: String, after_days, position: String = "soon") -> void:
	schedule_effect({ "type": "inject_cards", "ids": [id], "position": position }, after_days)

func check_pending(day: int) -> void:
	# Expire old modifiers first, then fire any scheduled effects whose day arrived.
	game.modifiers.tick(day)
	for i in range(scheduled.size() - 1, -1, -1):
		if scheduled[i]["on_day"] <= day:
			resolver.resolve([scheduled[i]["effect"]], game)
			scheduled.remove_at(i)

# ── Drawing ───────────────────────────────────────────────────────────────────

func draw_daily_card(day: int):
	# 3-day loop. Day 1 = intel, 2 = event, 3 = decision, then repeats.
	var order = ["intel", "event", "decision"]
	var required: String = order[(day - 1) % 3] if day > 0 else "intel"

	for i in range(deck.size()):
		if deck.queue[i].get("type", "") == required:
			var card = deck.queue[i]
			deck.queue.remove_at(i)
			return card

	# Nothing of the required type left — hand back a filler so the loop never
	# stalls during testing. (In the real game you'd refill or recycle instead.)
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
	# intel/event cards apply their effects the moment they are drawn.
	# decision cards wait for the player's choice (resolve_choice below).
	if card.get("type", "") == "decision":
		return
	if card.has("effects"):
		resolver.resolve(card["effects"], game)

func resolve_choice(card_data: Dictionary, choice: String):
	# choice is "choice_a" or "choice_b" (sent by CardUI). "ack"/anything else =
	# a plain dismiss of an intel/event card, which has no choice effects.
	if choice in ["choice_a", "choice_b"] and card_data.has(choice):
		resolver.resolve(card_data[choice].get("effects", []), game)
