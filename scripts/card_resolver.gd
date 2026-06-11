extends Node
class_name CardResolver

# ──────────────────────────────────────────────────────────────────────────────
# CardResolver
# ──────────────────────────────────────────────────────────────────────────────
# Turns a card's `effects` array into actual changes in the game.
# Called when an intel/event card is drawn, and when a decision choice is made.
#
# Everything is routed through the GameServices bundle:
#   s.modifiers     (ModifierManager)   — buffs/debuffs
#   s.weather       (WeatherManager)    — weather fronts
#   s.card_manager  (CardManager)       — deck edits + scheduling
#   s.board         (Board)             — spawns / transforms / resources
#   s.rail_network / s.terrain          — stock grants
#
# To add a new declarative effect, add a `match` case. To add a one-off bespoke
# effect, use { "type": "script", "fn": "..." } and write it in card_scripts.gd.
# ──────────────────────────────────────────────────────────────────────────────

var s: GameServices

func setup(services: GameServices) -> void:
	s = services

func resolve(effects: Array) -> void:
	for effect in effects:
		_resolve_one(effect)

func _resolve_one(effect: Dictionary) -> void:
	var cm := s.card_manager
	match effect.get("type", ""):

		# ── Story flags ──────────────────────────────────────────────────────
		"set_state", "game_state":
			s.board.state[effect["key"]] = effect["value"]

		# ── Modifiers (the main event) ───────────────────────────────────────
		"add_modifier":
			s.modifiers.add_modifier(effect)
		"remove_modifier":
			s.modifiers.remove_modifier(effect["id"])
		"remove_modifiers_by_tag":
			s.modifiers.remove_by_tag(effect["tag"])

		# ── Weather (clears the previous front, applies a bundle) ────────────
		"set_weather":
			s.weather.set_weather(effect.get("name", "clear"), effect.get("modifiers", []))

		# ── Deck editing ─────────────────────────────────────────────────────
		"inject_cards":
			var position: String = effect.get("position", "random")
			var delay: int = int(effect.get("after_days", 0))
			for id in effect.get("ids", []):
				if delay > 0:
					cm.schedule_card(id, delay, position)
				else:
					var card = cm.card_library.get_card(id)
					if card:
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

		# ── Reconnaissance ───────────────────────────────────────────────────
		"reveal_area":
			# Lifts fog around a point until next turn (photography flights).
			# { "type": "reveal_area", "near": "enemy_capital", "radius": 3 }
			var center = s.board.resolve_center(effect.get("near", "enemy_capital"))
			if center != null:
				var hexes: Array = s.board.HEX.axial_radius(center, int(effect.get("radius", 2)))
				hexes.append(center)
				s.fow.reveal_hexes(hexes)

		# ── Board changes ────────────────────────────────────────────────────
		"spawn_unit":
			s.board.spawn_unit(effect)
		"transform_unit":
			s.board.transform_units(effect)
		"grant_resources":
			for p in _select(effect):
				p.replenish(int(effect.get("amount", 0)))
		"drain_resources":
			for p in _select(effect):
				p.deplete(int(effect.get("amount", 0)))

		# ── Stock grants ─────────────────────────────────────────────────────
		"grant_rails":   s.rail_network.player_rail_stock  += int(effect.get("amount", 0))
		"grant_train":   s.rail_network.player_train_stock += int(effect.get("amount", 0))
		"grant_bridges": s.terrain.bridge_stock             += int(effect.get("amount", 0))
		"grant_tunnels": s.terrain.tunnel_stock             += int(effect.get("amount", 0))

		# ── Arbitrary scripted effect ────────────────────────────────────────
		"script":
			cm.card_scripts.run(effect.get("fn", ""), effect)

		_:
			push_warning("CardResolver: unknown effect type '%s'" % str(effect.get("type", "")))

func _select(effect: Dictionary) -> Array:
	var scope: String = effect.get("scope", effect.get("selector", "all"))
	return s.modifiers.select_pieces(s.board.units, s.board.cities, scope)
