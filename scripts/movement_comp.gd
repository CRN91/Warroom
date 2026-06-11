extends Node2D
class_name Movement

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var piece: Node2D
var hex = null               # null until the piece is placed on the board

func get_hex(): return hex

func _ready():
	piece = get_parent()

# ── Moving Hex ────────────────────────────────────────────────────────────────

func set_hex(new_hex, grid):
	"""Places the piece on new_hex and updates the grid references."""
	grid.set_piece(new_hex, piece)
	if hex != null:
		grid.set_piece(hex)        # clear the old cell
	hex = new_hex
	piece.position = grid.get_hex_pos(new_hex)

func force_hex(new_hex, grid):
	"""Sets hex, bypassing adjacency checks (trains, teleports)."""
	if hex != null:
		grid.set_piece(hex)
	hex = new_hex
	grid.set_piece(new_hex, piece)
	piece.position = grid.get_hex_pos(new_hex)

func move_to(new_hex, grid) -> bool:
	"""One-step move. Initial placement is free; afterwards a move must be to an
	adjacent empty hex and spends the piece's daily action (freeze)."""
	if not grid.Grid.has(new_hex):
		return false

	# Initial placement does not freeze
	if hex == null:
		if grid.get_piece(new_hex) != null:
			return false
		set_hex(new_hex, grid)
		return true

	if piece.is_frozen():
		return false
	if not (new_hex in HEX.axial_neighbours(hex)):
		return false
	if grid.get_piece(new_hex) != null:
		return false

	var old_hex = hex
	grid.disable_hex(new_hex)
	set_hex(new_hex, grid)
	piece.freeze()
	if piece.has_method("on_moved"):
		piece.on_moved()   # artillery packs up, etc.
	_withdrawal_fire(old_hex, new_hex, grid)
	return true

func _withdrawal_fire(old_hex, new_hex, grid) -> void:
	## Disengaging from contact has a price: one adjacent enemy combatant gets
	## a parting shot (half damage) if the move breaks out of its reach.
	for adj in HEX.axial_neighbours(old_hex):
		if not grid.Grid.has(adj): continue
		var e = grid.get_piece(adj)
		if e == null or not Sides.hostile(piece.team, e.team): continue
		if not (e.has_method("is_combatant") and e.is_combatant()): continue
		if not e.can_fire(): continue                               # packed-up guns can't snipe
		if HEX.axial_distance(e.get_hex(), new_hex) <= 1: continue  # still in contact — no shot

		var dmg = int(round(e.get_damage() * 0.5))
		if dmg > 0:
			piece.deplete(dmg)
			if piece.team == 1:
				Events.report("%s took %d withdrawal fire from %s." % [piece.name, dmg, e.name])
			elif e.team == 1:
				Events.report("%s caught %s withdrawing — %d damage." % [e.name, piece.name, dmg])
		return

# ── Pathing ───────────────────────────────────────────────────────────────────

var goal = null              # auto-goal: re-routes around traffic each day
var path: Array = []         # manual path: strict list of hexes to walk
var _held_turns: int = 0     # consecutive weeks stuck behind friendly traffic

func set_goal(target_hex):
	path.clear()
	goal = target_hex
	_held_turns = 0

func add_waypoint(target_hex):
	goal = null
	path.append(target_hex)

func clear_movement():
	goal = null
	path.clear()
	_held_turns = 0

func process_movement(grid):
	"""Walks one step along the manual path, or one step toward the auto-goal."""
	if path.size() > 0:
		_manual_pathing(grid)
	elif goal != null:
		_auto_pathing(grid)

func _auto_pathing(grid):
	var current = get_hex()
	if current == goal:
		clear_movement()
		return

	# 1. Prefer a route around other units (true collisions, just allow the goal)
	grid.sync_pathing([current, goal])
	var astar_path = grid.get_map_path(current, goal)
	grid.sync_pathing()

	# 2. If fully boxed in, fall back to the through-traffic route and wait in line
	if astar_path.size() < 2:
		var passable = [current, goal]
		for h in grid.Grid:
			var p = grid.get_piece(h)
			if p and p.has_method("is_combatant") and not (p is City):
				passable.append(h)
		grid.sync_pathing(passable)
		astar_path = grid.get_map_path(current, goal)
		grid.sync_pathing()

	if astar_path.size() > 1:
		var next_hex = astar_path[1]
		var piece_in_way = grid.get_piece(next_hex)

		if piece_in_way == null:
			if move_to(next_hex, grid):
				_held_turns = 0
		elif piece_in_way is City:
			clear_movement()   # arrived next to the target city, or blocked by one
		elif Sides.hostile(piece.team, piece_in_way.team):
			clear_movement()   # enemy in the way: stop and let the player decide
		else:
			# Friendly/allied unit in the way: hold, but never silently forever
			_held_turns += 1
			if _held_turns == 3 and piece.team == 1:
				Events.notify("%s is held up — friendly units are blocking its route." % piece.name)
	else:
		# NO route exists, even through traffic — rivers without a bridge,
		# mountain walls. Silence here looked like the unit being "stuck";
		# say it plainly and clear the order so the player re-decides.
		if piece.team == 1:
			Events.notify("%s: no route to its destination (river or mountains in the way?). Orders cleared." % piece.name)
		clear_movement()

func _manual_pathing(grid):
	var next_hex = path[0]
	var piece_in_way = grid.get_piece(next_hex)

	if piece_in_way == null:
		if move_to(next_hex, grid):
			path.pop_front()
			_held_turns = 0
	elif piece_in_way is City:
		clear_movement()
	elif Sides.hostile(piece.team, piece_in_way.team):
		clear_movement()
	else:
		# Friendly unit parked on the path. Hold once, then try to REROUTE
		# around it to the path's destination — a manual path must never
		# strand a unit forever behind a friend who isn't moving.
		_held_turns += 1
		if _held_turns >= 2:
			var dest = path.back()
			grid.sync_pathing([get_hex(), dest])
			var detour = grid.get_map_path(get_hex(), dest)
			grid.sync_pathing()
			if detour.size() > 1:
				path = detour.slice(1)
				_held_turns = 0
				if piece.team == 1:
					Events.notify("%s is rerouting around friendly traffic." % piece.name)
			elif _held_turns == 2 and piece.team == 1:
				Events.notify("%s is held up — friendly units are blocking its route." % piece.name)
