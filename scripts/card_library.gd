extends Node
class_name CardLibrary

var all_cards: Dictionary = {}   # id -> card data
var sets: Dictionary = {}        # set_name -> set data

func load_library():
	var file = FileAccess.open("res://res/deck.json", FileAccess.READ)
	if not file:
		push_error("CardLibrary: could not open cards.json")
		return
	var json = JSON.new()
	json.parse(file.get_as_text())
	file.close()
	
	sets = json.data["sets"]
	
	# Flatten all cards into the lookup table regardless of set
	for set_name in sets:
		for card in sets[set_name]["cards"]:
			all_cards[card["id"]] = card

func get_card(id: String) -> Dictionary:
	if all_cards.has(id):
		return all_cards[id].duplicate(true)
	push_error("CardLibrary: unknown id '%s'" % id)
	return {}

# Returns a shuffled array of cards from the chosen set names
func build_starting_deck(chosen_sets: Array) -> Array:
	var result = []
	for set_name in chosen_sets:
		if not sets.has(set_name):
			push_error("CardLibrary: unknown set '%s'" % set_name)
			continue
		if not sets[set_name]["startable"]:
			push_error("CardLibrary: set '%s' is not startable" % set_name)
			continue
		for card in sets[set_name]["cards"]:
			result.append(card.duplicate(true))
	result.shuffle()
	return result

# Returns all set names marked as startable - useful for a run setup screen later
func get_startable_sets() -> Array:
	return sets.keys().filter(func(s): return sets[s]["startable"])
