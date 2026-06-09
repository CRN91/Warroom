extends Node
class_name CardLibrary

# Loads every card defined in deck.json once, then hands out copies on request.
# The deck.json root is { "sets": { set_name: { label, startable, cards: [...] } } }.

var all_cards: Dictionary = {}   # id -> card data
var sets: Dictionary = {}        # set_name -> set data

func load_library():
	var file = FileAccess.open("res://res/deck.json", FileAccess.READ)
	if not file:
		push_error("CardLibrary: could not open res://res/deck.json")
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("CardLibrary: JSON parse error: %s" % json.get_error_message())
		return

	sets = json.data["sets"]

	# Flatten all cards into the lookup table regardless of set
	all_cards.clear()
	for set_name in sets:
		for card in sets[set_name]["cards"]:
			all_cards[card["id"]] = card

	print("CardLibrary: loaded %d cards across %d sets." % [all_cards.size(), sets.size()])

func get_card(id: String) -> Dictionary:
	if all_cards.has(id):
		return all_cards[id].duplicate(true)
	push_error("CardLibrary: unknown card id '%s'" % id)
	return {}

# Returns a shuffled array of cards from the chosen STARTABLE set names.
func build_starting_deck(chosen_sets: Array) -> Array:
	var pool := []
	for set_name in chosen_sets:
		if not sets.has(set_name): continue
		if not sets[set_name].get("startable", false): continue
		for card in sets[set_name]["cards"]:
			pool.append(card.duplicate(true))
	# weighted ordering: higher weight tends to land earlier in the pile
	var keyed := []
	for c in pool:
		var w: float = float(c.get("weight", 1.0))
		var key: float = 0.0 if w <= 0.0 else pow(randf(), 1.0 / w)
		keyed.append({ "k": key, "card": c })
	keyed.sort_custom(func(a, b): return a["k"] > b["k"])
	var result := []
	for e in keyed:
		result.append(e["card"])
	return result

# All card ids in a set, startable or not (used by add_set/remove_set effects so
# cards can pull a whole hidden story branch into the deck mid-run).
func get_set_card_ids(set_name: String) -> Array:
	var ids: Array = []
	if not sets.has(set_name):
		push_error("CardLibrary: unknown set '%s'" % set_name)
		return ids
	for card in sets[set_name]["cards"]:
		ids.append(card["id"])
	return ids

func get_startable_sets() -> Array:
	return sets.keys().filter(func(s): return sets[s].get("startable", false))
