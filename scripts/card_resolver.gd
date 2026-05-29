extends Node
class_name CardResolver

# Called by Game.gd when a card is drawn (intel/event) or a choice is made (decision)
func resolve(effects: Array, game: Node):
	for effect in effects:
		match effect["type"]:
			"game_state":
				game.game_state[effect["key"]] = effect["value"]

			"restore_state":
				game.pending_restores.append({
					"key": effect["key"],
					"value": effect["value"],
					"on_day": game.day + effect["after_days"]
				})

			"inject_cards":
				var position = effect.get("position", "random")
				for id in effect["ids"]:
					var card = game.card_library.get_card(id)
					if card:
						game.deck.inject(card, position)

			"remove_cards":
				for id in effect["ids"]:
					game.deck.remove_by_id(id)

			"delayed_card":
				game.pending_cards.append({
					"id": effect["id"],
					"on_day": game.day + effect["after_days"]
				})
