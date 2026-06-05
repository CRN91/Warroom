extends Node2D
class_name TerrainManager

## Terrain layer for the existing grid. Does NOT change the grid shape — it
## sprinkles features onto whatever Grid.make_grid_axial() already produced.
##
## Two feature types:
##   • Mountains  — a HEX is impassable to ground units and blocks ranged
##                  line-of-fire. A tunnel (bought + built) lets RAIL/trains
##                  through; foot units still can't enter.
##   • Rivers     — an EDGE between two hexes is impassable. Units stand on any
##                  hex; they just can't step across a river edge. A bridge
##                  (bought + built by Logistics) opens one edge. Bridges break
##                  under fire and are repaired like rail.
##
## Pathfinding is handled by manipulating Grid's astar (disable mountain points,
## disconnect/reconnect river edges), so the enemy AI routes around terrain for
## free — it already pathfinds through astar.

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var grid: Node
var hex_size: float = 32.0

# hex(Vector2i) -> { "tunnel": bool }
var mountains: Dictionary = {}
const MOUNTAIN_TEX = preload("res://assets/mountain.png")
# edge_key(String) -> { "a": Vector2i, "b": Vector2i, "bridge": bool, "broken": bool }
var river: Dictionary = {}

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(_grid: Node) -> void:
	grid = _grid
	_compute_hex_size()

func _compute_hex_size() -> void:
	for hex in grid.Grid.keys():
		for nb in HEX.axial_neighbours(hex):
			if grid.Grid.has(nb):
				hex_size = grid.get_hex_pos(hex).distance_to(grid.get_hex_pos(nb)) / sqrt(3.0)
				return

# ── Generation ────────────────────────────────────────────────────────────────

func generate(opts: Dictionary) -> void:
	var hq_hexes: Array      = opts.get("hq_hexes", [])
	var city_hexes: Array    = opts.get("city_hexes", [])
	var occupied: Array      = opts.get("occupied", [])
	var mfraction: float     = opts.get("mountain_fraction", 0.10)
	var fords: int           = opts.get("fords", 1)
	if opts.has("seed"):
		seed(int(opts["seed"]))

	_generate_river(hq_hexes, city_hexes, fords)
	_generate_mountains(hq_hexes, city_hexes, occupied, mfraction)
	queue_redraw()

func _generate_river(hq_hexes: Array, city_hexes: Array, fords: int) -> void:
	var axis: int = 1               # 0 = q, 1 = r, 2 = s (= -q-r)
	var threshold: float = 0.0
	if hq_hexes.size() >= 2:
		var a: Vector2i = hq_hexes[0]
		var b: Vector2i = hq_hexes[1]
		var dq: int = abs(a.x - b.x)
		var dr: int = abs(a.y - b.y)
		var ds: int = abs((-a.x - a.y) - (-b.x - b.y))
		if dq >= dr and dq >= ds:
			axis = 0; threshold = (a.x + b.x) / 2.0
		elif ds >= dr:
			axis = 2; threshold = ((-a.x - a.y) + (-b.x - b.y)) / 2.0
		else:
			axis = 1; threshold = (a.y + b.y) / 2.0
	else:
		threshold = _median_axis_value(axis)

	var seen: Dictionary = {}
	for hex in grid.Grid.keys():
		for nb in HEX.axial_neighbours(hex):
			if not grid.Grid.has(nb): continue
			var k: String = _edge_key(hex, nb)
			if seen.has(k): continue
			seen[k] = true
			var side_a: bool = _axis_value(hex, axis) <= threshold
			var side_b: bool = _axis_value(nb, axis) <= threshold
			if side_a != side_b:
				river[k] = { "a": hex, "b": nb, "bridge": false, "broken": false }

	if fords > 0 and river.size() > 0:
		var valid_ford_edges = []
		
		# Only keep edges where NEITHER side is a city
		for k in river.keys():
			var e = river[k]
			if not e["a"] in city_hexes and not e["b"] in city_hexes:
				valid_ford_edges.append(k)
				
		# Sort the remaining valid edges by proximity to the city
		valid_ford_edges.sort_custom(func(x, y): return _edge_city_dist(river[x], city_hexes) < _edge_city_dist(river[y], city_hexes))
		
		for i in range(min(fords, valid_ford_edges.size())):
			var k = valid_ford_edges[i]
			
			# Spawn a pre-built bridge at the crossing
			river[k]["bridge"] = true 
			river[k]["broken"] = false

	# Apply the cut to astar so pathfinding (and the AI) respects it.
	for k in river.keys():
		var e: Dictionary = river[k]
		if not e["bridge"]: 
			grid.disconnect_hexes(e["a"], e["b"])

func _generate_mountains(hq_hexes: Array, city_hexes: Array, occupied: Array, mfraction: float) -> void:
	var protected: Dictionary = {}
	for h in city_hexes:
		protected[h] = true
		for nb in HEX.axial_neighbours(h): protected[nb] = true
	for h in hq_hexes:
		protected[h] = true
	for h in occupied:
		protected[h] = true

	var candidates: Array = []
	for hex in grid.Grid.keys():
		if protected.has(hex): continue
		if grid.get_piece(hex) != null: continue
		candidates.append(hex)
	candidates.shuffle()

	var target: int = clampi(int(grid.Grid.size() * mfraction), 2, int(grid.Grid.size() / 4.0))
	var placed: int = 0
	for hex in candidates:
		if placed >= target: break
		_add_mountain(hex)
		placed += 1

	# Soft-lock guard: no city/HQ may be fully ringed, and each HQ must keep a
	# decent reachable area on its own side. Pull mountains back if so.
	_relieve_softlocks(city_hexes, hq_hexes)

func _add_mountain(hex: Vector2i) -> void:
	mountains[hex] = { "tunnel": false }
	grid.disable_hex(hex)

func _remove_mountain(hex: Vector2i) -> void:
	if not mountains.has(hex): return
	mountains.erase(hex)
	grid.enable_hex(hex)

func _relieve_softlocks(city_hexes: Array, hq_hexes: Array) -> void:
	# 1. Never fully ring a city/HQ.
	for h in city_hexes + hq_hexes:
		if not grid.Grid.has(h): continue
		var open: bool = false
		for nb in HEX.axial_neighbours(h):
			if grid.Grid.has(nb) and is_passable(nb) and is_crossable(h, nb):
				open = true; break
		if not open:
			for nb in HEX.axial_neighbours(h):
				if mountains.has(nb):
					_remove_mountain(nb); break

	# 2. Each HQ should reach a reasonable chunk of its own side.
	var min_reach: int = max(4, int(grid.Grid.size() / 6.0))
	for hq in hq_hexes:
		if not grid.Grid.has(hq): continue
		var tries: int = 0
		while _reachable_count(hq) < min_reach and mountains.size() > 0 and tries < 8:
			_remove_mountain(mountains.keys()[0])
			tries += 1

func _reachable_count(start: Vector2i) -> int:
	var seen: Dictionary = { start: true }
	var stack: Array = [start]
	while stack.size() > 0:
		var cur: Vector2i = stack.pop_back()
		for nb in HEX.axial_neighbours(cur):
			if not grid.Grid.has(nb): continue
			if seen.has(nb): continue
			if not is_passable(nb): continue
			if not is_crossable(cur, nb): continue
			seen[nb] = true
			stack.append(nb)
	return seen.size()

# ── Queries (used by movement, combat, rail) ──────────────────────────────────

func is_mountain(hex: Vector2i) -> bool:
	return mountains.has(hex)

func has_tunnel(hex: Vector2i) -> bool:
	return mountains.has(hex) and mountains[hex]["tunnel"]

func is_passable(hex: Vector2i) -> bool:
	# Ground units: blocked only by mountains. Tunnels are rail/train-only.
	return not mountains.has(hex)

func is_river_edge(a: Vector2i, b: Vector2i) -> bool:
	return river.has(_edge_key(a, b))

func is_crossable(a: Vector2i, b: Vector2i) -> bool:
	var k: String = _edge_key(a, b)
	if not river.has(k): return true
	var e: Dictionary = river[k]
	return e["bridge"] and not e["broken"]

func is_bridged(a: Vector2i, b: Vector2i) -> bool:
	var k: String = _edge_key(a, b)
	return river.has(k) and river[k]["bridge"]

func is_bridge_broken(a: Vector2i, b: Vector2i) -> bool:
	var k: String = _edge_key(a, b)
	return river.has(k) and river[k]["bridge"] and river[k]["broken"]

# ── Building / damage ─────────────────────────────────────────────────────────

func build_bridge(a: Vector2i, b: Vector2i) -> bool:
	var k: String = _edge_key(a, b)
	if not river.has(k): return false
	if river[k]["bridge"]: return false
	river[k]["bridge"] = true
	river[k]["broken"] = false
	grid.connect_hexes(a, b)
	queue_redraw()
	return true

func break_bridge(a: Vector2i, b: Vector2i) -> bool:
	var k: String = _edge_key(a, b)
	if not river.has(k): return false
	if not river[k]["bridge"] or river[k]["broken"]: return false
	river[k]["broken"] = true
	grid.disconnect_hexes(a, b)
	queue_redraw()
	return true

func repair_bridge(a: Vector2i, b: Vector2i) -> bool:
	var k: String = _edge_key(a, b)
	if not river.has(k): return false
	if not river[k]["bridge"] or not river[k]["broken"]: return false
	river[k]["broken"] = false
	grid.connect_hexes(a, b)
	queue_redraw()
	return true

func build_tunnel(hex: Vector2i) -> bool:
	if not mountains.has(hex): return false
	if mountains[hex]["tunnel"]: return false
	mountains[hex]["tunnel"] = true
	queue_redraw()
	return true

# ── Line of fire ──────────────────────────────────────────────────────────────

func blocks_line_of_fire(from_hex: Vector2i, to_hex: Vector2i) -> bool:
	var n: int = _hex_dist(from_hex, to_hex)
	if n <= 1: return false
	var ax: float = from_hex.x; var az: float = from_hex.y; var ay: float = -ax - az
	var bx: float = to_hex.x;   var bz: float = to_hex.y;   var by: float = -bx - bz
	for i in range(1, n):
		var t: float = float(i) / float(n)
		var h: Vector2i = _cube_round(lerp(ax, bx, t), lerp(ay, by, t), lerp(az, bz, t))
		if is_mountain(h): return true
	return false

# ── Helpers ───────────────────────────────────────────────────────────────────

func _axis_value(hex: Vector2i, axis: int) -> float:
	if axis == 0: return float(hex.x)
	if axis == 2: return float(-hex.x - hex.y)
	return float(hex.y)

func _median_axis_value(axis: int) -> float:
	var vals: Array = []
	for hex in grid.Grid.keys():
		vals.append(_axis_value(hex, axis))
	vals.sort()
	return vals[int(vals.size() / 2.0)] if vals.size() > 0 else 0.0

func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]

func _edge_city_dist(e: Dictionary, city_hexes: Array) -> int:
	var best: int = 9999
	for c in city_hexes:
		best = min(best, _hex_dist(e["a"], c))
		best = min(best, _hex_dist(e["b"], c))
	return best

func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	var ds: int = (-a.x - a.y) - (-b.x - b.y)
	return int((abs(dx) + abs(dy) + abs(ds)) / 2.0)

func _cube_round(x: float, y: float, z: float) -> Vector2i:
	var rx: int = int(round(x)); var ry: int = int(round(y)); var rz: int = int(round(z))
	var dx: float = abs(rx - x); var dy: float = abs(ry - y); var dz: float = abs(rz - z)
	if dx > dy and dx > dz: rx = -ry - rz
	elif dy > dz:           ry = -rx - rz
	else:                   rz = -rx - ry
	return Vector2i(rx, rz)

# ── Rendering ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	if grid == null: return
	var r: float = hex_size * 0.6
	var tunnel_col: Color   = Color(0.80, 0.76, 0.68)

	# Decide how big the mountain image should be. 
	# hex_size * 2 roughly covers the whole hex. Adjust this if it looks too big/small!
	var draw_size = Vector2(hex_size * 2, hex_size * 2)

	for hex in mountains.keys():
		var c: Vector2 = grid.get_hex_pos(hex)
		
		# Shift the starting point up and left by half the size so it centers perfectly
		var top_left = c - (draw_size / 2.0)
		var rect = Rect2(top_left, draw_size)
		
		draw_texture_rect(MOUNTAIN_TEX, rect, false)
		
		# Draw the tunnel on top of the image if it has one
		if mountains[hex]["tunnel"]:
			draw_rect(Rect2(c.x - r * 0.32, c.y - r * 0.05, r * 0.64, r * 0.45), tunnel_col)

	for k in river.keys():
		var e: Dictionary = river[k]
		var ca: Vector2 = grid.get_hex_pos(e["a"])
		var cb: Vector2 = grid.get_hex_pos(e["b"])
		var mid: Vector2 = (ca + cb) * 0.5
		var dir: Vector2 = (cb - ca).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x) * (hex_size * 0.5)
		var p1: Vector2 = mid + perp
		var p2: Vector2 = mid - perp
		
		if e["bridge"] and not e["broken"]:
			draw_line(p1, p2, Color(0.55, 0.33, 0.18), hex_size * 0.24)
		elif e["bridge"] and e["broken"]:
			draw_line(p1, p2, Color(0.80, 0.21, 0.21), hex_size * 0.14)
		else:
			draw_line(p1, p2, Color(0.21, 0.54, 0.86), hex_size * 0.20)
