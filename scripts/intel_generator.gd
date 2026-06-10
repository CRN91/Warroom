extends RefCounted
class_name IntelGenerator

## Composes intel card text from the actual state of the board, so intel cards
## report real (if slightly fuzzed) information about the enemy.
##
## Cards opt in with  "dynamic_text": "<report name>"  — the text is generated
## at draw time. Also used for intel filler cards so a quiet deck still
## produces useful reconnaissance.

const TYPE_LABELS := {
	"infantry":  ["infantry company", "infantry companies"],
	"artillery": ["gun battery", "gun batteries"],
	"logistics": ["supply column", "supply columns"],
	"train":     ["train", "trains"],
}

static func generate(report: String, board: Board) -> String:
	match report:
		"recon_report":   return recon_report(board)
		"economy_report": return economy_report(board)
		_:
			push_warning("IntelGenerator: unknown report '%s'" % report)
			return "The report is illegible."

# ── Reports ───────────────────────────────────────────────────────────────────

static func war_report(log_lines: Array) -> String:
	## Last week's combat events, written up as a field report.
	if log_lines.is_empty():
		return "FIELD REPORT: The front is quiet. No engagements this week."
	var lines: Array = log_lines.slice(max(0, log_lines.size() - 4))
	return "FIELD REPORT:\n— " + "\n— ".join(lines)

static func recon_report(board: Board) -> String:
	var enemy_units: Array = board.units.filter(
		func(u): return is_instance_valid(u) and u.team == 2)
	if enemy_units.is_empty():
		return "Recon flights report no enemy formations in the field."

	var counts := board.unit_counts_by_type(2)
	var parts: Array = []
	for t in counts:
		parts.append(_count_phrase(t, counts[t]))

	var text := "Recon counts %s in the field." % _join_natural(parts)

	# Where is the weight of their force?
	var anchor := _force_anchor(board, enemy_units)
	if anchor != "":
		text += " The largest concentration is near %s." % anchor

	# How are they supplied?
	var supply := _avg_supply(enemy_units)
	if supply < 0.35:
		text += " Their supply situation looks desperate."
	elif supply < 0.6:
		text += " Prisoners complain of thin rations."

	return text

static func economy_report(board: Board) -> String:
	var enemy_cities: Array = board.cities.filter(
		func(c): return is_instance_valid(c) and c.team == 2)
	if enemy_cities.is_empty():
		return "Agents report the enemy holds no cities. Their war is already lost."

	var richest = enemy_cities[0]
	var total := 0
	for c in enemy_cities:
		total += c.get_resources()
		if c.get_resources() > richest.get_resources():
			richest = c

	# Round to the nearest 100 — agents estimate, they don't audit.
	var est := int(round(richest.get_resources() / 100.0) * 100.0)
	var text := "Agents behind the lines estimate stockpiles of roughly %d in %s." % [est, richest.name]
	if total >= 1500:
		text += " Their economy can sustain fresh formations."
	elif total <= 600:
		text += " Their depots are running dry."
	return text

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _count_phrase(type: String, n: int) -> String:
	var labels: Array = TYPE_LABELS.get(type, [type, type + "s"])
	return "%d %s" % [n, labels[0] if n == 1 else labels[1]]

static func _join_natural(parts: Array) -> String:
	match parts.size():
		0: return "nothing"
		1: return parts[0]
		2: return "%s and %s" % [parts[0], parts[1]]
		_: return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]

static func _force_anchor(board: Board, enemy_units: Array) -> String:
	## Names the city closest to the centre of enemy mass.
	if board.cities.is_empty(): return ""
	var cx := 0.0; var cy := 0.0
	for u in enemy_units:
		var h = u.get_hex()
		cx += h.x; cy += h.y
	cx /= enemy_units.size(); cy /= enemy_units.size()

	var best = null
	var best_d := INF
	for c in board.cities:
		if not is_instance_valid(c): continue
		var h = c.get_hex()
		var d: float = abs(h.x - cx) + abs(h.y - cy)
		if d < best_d:
			best_d = d
			best = c
	return best.name if best else ""

static func _avg_supply(units: Array) -> float:
	var total := 0.0
	for u in units:
		total += float(u.get_resources()) / max(1.0, float(u.get_max_resources()))
	return total / units.size()
