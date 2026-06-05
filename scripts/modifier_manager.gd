extends Node
class_name ModifierManager

# ──────────────────────────────────────────────────────────────────────────────
# ModifierManager
# ──────────────────────────────────────────────────────────────────────────────
# This is the single place that stores every active gameplay modifier and answers
# the question: "given this piece and this stat, what is the effective value?"
#
# A modifier is just a dictionary:
#   {
#     "id":            "winter_income",   # optional handle so it can be refreshed/removed
#     "stat":          "city_income",     # which stat it touches
#     "op":            "mul",             # "add" | "mul" | "set"
#     "value":         0.5,
#     "scope":         "player",          # WHO it applies to (see _matches below)
#     "duration_days": 3,                 # omit or -1 == permanent
#     "source":        "event_blizzard",  # flavour / debug only
#     "tags":          ["weather"]        # optional, lets you bulk-remove (e.g. clear weather)
#   }
#
# Game systems READ modifiers, they never store stat changes themselves. e.g.
#   var rate = modifiers.get_value("city_income", base_rate, self)
# This is what lets one card permanently buff the player while a different card
# temporarily debuffs a single enemy unit — they just stack as data.
# ──────────────────────────────────────────────────────────────────────────────

var mods: Array = []
var current_day: int = 0
var _next_auto: int = 0

# ── Adding / removing ─────────────────────────────────────────────────────────

func add_modifier(data: Dictionary) -> void:
	if not data.has("stat"):
		push_error("ModifierManager: modifier with no 'stat' ignored: %s" % str(data))
		return

	var m: Dictionary = data.duplicate(true)
	m.erase("type")   # effect dicts carry a "type" key we don't care about here

	if not m.has("op"):    m["op"] = "add"
	if not m.has("value"): m["value"] = 0.0
	if not m.has("scope"): m["scope"] = "all"
	if not m.has("tags"):  m["tags"] = []

	var dur: int = int(m.get("duration_days", -1))
	m["expires_on"] = -1 if dur < 0 else current_day + dur
	m.erase("duration_days")

	if not m.has("id") or str(m["id"]) == "":
		m["id"] = "%s_%s_%d" % [m["stat"], m["scope"], _next_auto]
		_next_auto += 1

	# Same id == refresh in place (lets you re-apply a weather card and reset its timer)
	for i in range(mods.size()):
		if mods[i]["id"] == m["id"]:
			mods[i] = m
			return
	mods.append(m)

func remove_modifier(id: String) -> void:
	for i in range(mods.size() - 1, -1, -1):
		if mods[i]["id"] == id:
			mods.remove_at(i)

func remove_by_tag(tag: String) -> void:
	for i in range(mods.size() - 1, -1, -1):
		if tag in mods[i].get("tags", []):
			mods.remove_at(i)

func clear_all() -> void:
	mods.clear()

# ── Daily tick ────────────────────────────────────────────────────────────────

func tick(day: int) -> void:
	# Called once at the start of each day. Drops anything that has expired.
	current_day = day
	for i in range(mods.size() - 1, -1, -1):
		var e: int = mods[i]["expires_on"]
		if e != -1 and day >= e:
			mods.remove_at(i)

# ── Queries ───────────────────────────────────────────────────────────────────

func get_value(stat: String, base: float, piece) -> float:
	# Returns base after every matching modifier is applied.
	# Order: sum all "add", then multiply all "mul", then "set" overrides everything.
	var add_sum: float = 0.0
	var mul: float = 1.0
	var set_val = null

	for m in mods:
		if m["stat"] != stat: continue
		if not _matches(m["scope"], piece): continue
		match m["op"]:
			"add": add_sum += float(m["value"])
			"mul": mul *= float(m["value"])
			"set": set_val = float(m["value"])

	var result: float = (base + add_sum) * mul
	if set_val != null:
		result = set_val
	return result

func get_attack_multiplier(piece) -> float:
	# Convenience for combat code: just the multiplicative part of "attack".
	var mul: float = 1.0
	for m in mods:
		if m["stat"] == "attack" and m["op"] == "mul" and _matches(m["scope"], piece):
			mul *= float(m["value"])
	return mul

func is_movement_blocked(piece) -> bool:
	# Any active "move_block" modifier that matches this piece freezes it (weather, mud, etc.)
	for m in mods:
		if m["stat"] == "move_block" and _matches(m["scope"], piece) and float(m["value"]) > 0.0:
			return true
	return false

func has_stat(stat: String, piece) -> bool:
	for m in mods:
		if m["stat"] == stat and _matches(m["scope"], piece):
			return true
	return false

# ── Selection (used by spawn / transform / grant effects) ─────────────────────

func select_pieces(units: Array, cities: Array, scope: String) -> Array:
	var out: Array = []
	for p in units:
		if is_instance_valid(p) and _matches(scope, p):
			out.append(p)
	for c in cities:
		if is_instance_valid(c) and _matches(scope, c) and c not in out:
			out.append(c)
	return out

# ── Scope matching ────────────────────────────────────────────────────────────
# A scope is a small string describing WHO a modifier / selector applies to.
# Supported:
#   "all"
#   "player" / "enemy" / "neutral"
#   "team:1"
#   "city" / "train" / "ground" (anything that isn't a city or train)
#   "combatant" / "supplier"
#   "type:infantry"   (matches Unit.unit_type, which you can set per scene/spawn)
#   "unit:<instance_id>"   (one specific piece)
#   "tag:elite"   (matches a piece that has that string in its `tags` array)

func _matches(scope: String, piece) -> bool:
	if scope == "" or scope == "all":
		return true
	if not is_instance_valid(piece):
		return false

	match scope:
		"player":    return piece.team == 1
		"enemy":     return piece.team == 2
		"neutral":   return piece.team == 0
		"city":      return piece is City
		"train":     return piece is Train
		"ground":    return not (piece is Train) and not (piece is City)
		"combatant": return piece.has_method("is_combatant") and piece.is_combatant()
		"supplier":  return piece.has_method("is_combatant") and not piece.is_combatant() and not (piece is City)

	if scope.begins_with("team:"):
		return str(piece.team) == scope.substr(5)
	if scope.begins_with("type:"):
		return _unit_type(piece) == scope.substr(5)
	if scope.begins_with("unit:"):
		return str(piece.get_instance_id()) == scope.substr(5)
	if scope.begins_with("tag:"):
		var t: String = scope.substr(4)
		return t in piece.get("tags") if piece.get("tags") != null else false

	return false

func _unit_type(piece) -> String:
	# Prefer an explicit unit_type export if you set one; otherwise derive from the class.
	var ut = piece.get("unit_type")
	if ut != null and str(ut) != "":
		return str(ut)
	if piece is City:       return "city"
	if piece is Train:      return "train"
	if piece is Infantry:   return "infantry"
	if piece is Artillery:  return "artillery"
	if piece is Logistics:  return "logistics"
	if piece.has_method("is_combatant"):
		return "combatant" if piece.is_combatant() else "supplier"
	return ""

# ── Debug ─────────────────────────────────────────────────────────────────────

func describe() -> Array:
	# Short human-readable lines for the on-screen debug overlay.
	var lines: Array = []
	for m in mods:
		var dur := "perm" if m["expires_on"] == -1 else ("until d%d" % m["expires_on"])
		var sym: String = {"add": "+", "mul": "x", "set": "="}.get(m["op"], "?")
		lines.append("%s %s%s [%s] (%s)" % [m["stat"], sym, str(m["value"]), m["scope"], dur])
	return lines
