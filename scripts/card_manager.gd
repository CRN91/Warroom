extends Node
class_name CardManager

@onready var deck         = $Deck
@onready var card_library = $CardLibrary
@onready var resolver     = $CardResolver

var pending_cards: Array    = []
var pending_restores: Array = []
var game: Node2D

func setup(_game: Node2D):
	game = _game
	card_library.load_library()
	
	for card in card_library.build_starting_deck(["western_front_intel", "weather_events", "command_decisions"]):
		deck.push(card)
		
	deck.load()

func check_pending(day: int):
	for i in range(pending_cards.size() - 1, -1, -1):
		if pending_cards[i]["on_day"] <= day:
			deck.inject(card_library.get_card(pending_cards[i]["id"]), "soon")
			pending_cards.remove_at(i)
			
	for i in range(pending_restores.size() - 1, -1, -1):
		if pending_restores[i]["on_day"] <= day:
			game.game_state[pending_restores[i]["key"]] = pending_restores[i]["value"]
			pending_restores.remove_at(i)

func draw_daily_card(day: int):
	var required_type = ["decision", "intel", "event"][day % 3]
	var card_to_play  = null
	
	for i in range(deck.size()):
		var checked = deck.queue[i]
		if deck.len() > 1 and checked["type"] == required_type:
			card_to_play = checked
			deck.queue.remove_at(i)
			break
			
	return card_to_play

func resolve_choice(card_data: Dictionary, choice: String):
	resolver.resolve(card_data[choice]["effects"], game)
