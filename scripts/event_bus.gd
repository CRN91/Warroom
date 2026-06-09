extends Node

## Global signal bus (autoloaded as `Events`).
##
## Systems emit facts about the world here; anything that cares subscribes.
## This is what lets e.g. City announce a capture without holding a reference
## to the CardManager, UI, or Game.

# ── Time ──────────────────────────────────────────────────────────────────────
signal day_advanced(day: int)

# ── Board facts ───────────────────────────────────────────────────────────────
signal unit_died(unit: Node2D)
signal city_captured(city: Node2D, by_team: int, prev_team: int)
signal rail_established(route_id: int)
signal rail_broken(hex: Vector2i)
signal rail_repaired(hex: Vector2i)

# ── Weather / story ───────────────────────────────────────────────────────────
signal weather_changed(weather_name: String)

# ── Flow control ──────────────────────────────────────────────────────────────
signal decision_pending(pending: bool)   # true while a decision card blocks End Turn
signal game_over(player_lost: bool)

# ── UI feedback ───────────────────────────────────────────────────────────────
signal toast(message: String)            # transient on-screen message

func notify(message: String) -> void:
	toast.emit(message)
