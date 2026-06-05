extends Node
class_name CardResolver

# ──────────────────────────────────────────────────────────────────────────────
# CardResolver
# ──────────────────────────────────────────────────────────────────────────────
# Turns a card's `effects` array into actual changes in the game.
# Called when an intel/event card is drawn, and when a decision choice is made.
#
# Everything is routed through `game` and its sub-systems:
#   game.modifiers        (ModifierManager)   — buffs/debuffs/weather
#   game.card_manager     (CardManager)       — deck edits + scheduling
#   game.card_library     -> via card_manager — card lookups
#   game.spawn_unit / transform_units         — board changes
#
# To add a new declarative effect, add a `match` case. To add a one-off bespoke
# effect, use { "type": "script", "fn": "..." } and write it in card_scripts.gd.
# ──────────────────────────────────────────────────────────────────────────────

func resolve(effects: Array, game: Node) -> void:
	for effect in effects:
		_resolve_one(effect, game)

func _resolve_one(effect: Dictionary, game: Node) -> void:
	var cm = game.card_manager
	match effect.get("type", ""):

		# ── Simple flags / values on game_state ──────────────────────────────
		"set_state", "game_state":
			game.game_state[effect["key"]] = effect["value"]

		# ── Modifiers (the main event) ───────────────────────────────────────
		"add_modifier":
			game.modifiers.add_modifier(effect)
		"remove_modifier":
			game.modifiers.remove_modifier(effect["id"])
		"remove_modifiers_by_tag":
			game.modifiers.remove_by_tag(effect["tag"])

		# ── Weather convenience (clears previous weather, applies a bundle) ──
		"set_weather":
			game.game_state["weather"] = effect.get("name", "clear")
			game.modifiers.remove_by_tag("weather")
			for m in effect.get("modifiers", []):
				var mm: Dictionary = m.duplicate(true)
				var tags: Array = mm.get("tags", [])
				if not ("weather" in tags): tags.append("weather")
				mm["tags"] = tags
				game.modifiers.add_modifier(mm)

		# ── Deck editing ─────────────────────────────────────────────────────
		"inject_cards":
			var position: String = effect.get("position", "random")
			for id in effect["ids"]:
				var card: Dictionary = cm.card_library.get_card(id)
				if not card.is_empty():
					cm.deck.inject(card, position)
		"remove_cards":
			for id in effect["ids"]:
				cm.deck.remove_by_id(id)
		"add_set":
			var pos: String = effect.get("position", "random")
			for id in cm.card_library.get_set_card_ids(effect["set"]):
				var card: Dictionary = cm.card_library.get_card(id)
				if not card.is_empty():
					cm.deck.inject(card, pos)
		"remove_set":
			for id in cm.card_library.get_set_card_ids(effect["set"]):
				cm.deck.remove_by_id(id)

		# ── Scheduling (things that happen N days later) ─────────────────────
		"delayed_card":
			cm.schedule_card(effect["id"], effect["after_days"], effect.get("position", "soon"))
		"delayed_effect":
			cm.schedule_effect(effect["effect"], effect["after_days"])
		"restore_state":
			cm.schedule_effect(
				{ "type": "set_state", "key": effect["key"], "value": effect["value"] },
				effect["after_days"]
			)

		# ── Board changes ────────────────────────────────────────────────────
		"spawn_unit":
			game.spawn_unit(effect)
		"transform_unit":
			game.transform_units(effect)
		"grant_resources":
			for p in _select(game, effect):
				p.replenish(int(effect.get("amount", 0)))
		"drain_resources":
			for p in _select(game, effect):
				p.deplete(int(effect.get("amount", 0)))

		# ── Arbitrary scripted effect ────────────────────────────────────────
		"script":
			cm.card_scripts.run(effect.get("fn", ""), game, effect)

		_:
			push_warning("CardResolver: unknown effect type '%s'" % str(effect.get("type", "")))

func _select(game: Node, effect: Dictionary) -> Array:
	var scope: String = effect.get("scope", effect.get("selector", "all"))
	return game.modifiers.select_pieces(game, scope)
