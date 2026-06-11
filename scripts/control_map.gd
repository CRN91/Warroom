extends Node2D
class_name ControlMap

## The grease-pencil layer of the war table: who controls which hex.
##
## Rules (decided in design):
##   • Initial paint = the two territories the map generator grew from the capitals.
##   • Each week, every COMBAT unit projects control over its hex + 6 neighbours
##     (engineers and trains project nothing — supply doesn't hold ground).
##     Cities project the same for their owner.
##   • A hex projected by BOTH sides becomes grey no-man's-land.
##   • Unprojected hexes keep their last owner — the map remembers the campaign.
##   • Pockets: a region of one side's paint containing none of that side's
##     units or cities is absorbed by the other side.
##   • Isolation: paint disconnected from that side's CAPITAL flags every unit
##     and city standing in it as cut off (drives sieges and surrender).

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const NML := 0   # grey no-man's-land

var owner_map: Dictionary = {}   # hex -> 0 (NML) / 1 (player side) / 2 (enemy side)
var s: GameServices
var hex_size: float = 32.0

func setup(services: GameServices) -> void:
	s = services
	# MULTIPLY blending: territory paint darkens/casts the tile art instead of
	# covering it — ground texture stays fully visible underneath.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = mat
	_compute_hex_size()
	# Initial paint from the map generator's territory split
	for hex in s.grid.Grid.keys():
		var t: int = int(s.terrain.territory.get(hex, 0))
		owner_map[hex] = 1 if t == 0 else 2
	queue_redraw()

func _compute_hex_size() -> void:
	for hex in s.grid.Grid.keys():
		for nb in HEX.axial_neighbours(hex):
			if s.grid.Grid.has(nb):
				hex_size = s.grid.get_hex_pos(hex).distance_to(s.grid.get_hex_pos(nb)) / sqrt(3.0)
				return

# ── Queries ───────────────────────────────────────────────────────────────────

func side_at(hex) -> int:
	return owner_map.get(hex, NML)

func is_hostile_ground(hex, team: int) -> bool:
	var at := side_at(hex)
	return at != NML and at != Sides.side_of(team)

func territory_share(side: int) -> float:
	var held := 0
	var total := 0
	for hex in owner_map:
		total += 1
		if owner_map[hex] == side:
			held += 1
	return float(held) / float(max(1, total))

# ── Weekly update ─────────────────────────────────────────────────────────────

func weekly_update() -> void:
	var proj := { 1: {}, 2: {} }

	for u in s.board.units:
		if not is_instance_valid(u): continue
		if u is Train: continue                      # rail doesn't hold ground
		if not (u.has_method("is_combatant") and u.is_combatant()): continue
		var side := Sides.side_of(u.team)
		if side == 0: continue
		_project(proj[side], u.get_hex())

	for c in s.board.cities:
		if not is_instance_valid(c): continue
		var side := Sides.side_of(c.team)
		if side == 0: continue
		_project(proj[side], c.get_hex())

	for hex in s.grid.Grid.keys():
		var p1: bool = proj[1].has(hex)
		var p2: bool = proj[2].has(hex)
		if p1 and p2:
			owner_map[hex] = NML
		elif p1:
			owner_map[hex] = 1
		elif p2:
			owner_map[hex] = 2
		# neither: keep previous owner (or previous NML)

	_absorb_pockets()
	queue_redraw()

func _project(into: Dictionary, hex) -> void:
	if hex == null: return
	into[hex] = true
	for nb in HEX.axial_neighbours(hex):
		if s.grid.Grid.has(nb):
			into[nb] = true

# ── Pockets & isolation ───────────────────────────────────────────────────────

func _absorb_pockets() -> void:
	## A region of side X's paint with none of X's units or cities in it
	## belongs to whoever surrounded it.
	for side in [1, 2]:
		var other: int = 2 if side == 1 else 1
		for region in _regions_of(side):
			if not _region_has_assets(region, side):
				for hex in region:
					owner_map[hex] = other

func update_isolation() -> void:
	## Cut off = standing in friendly paint with no painted path back to your
	## capital. Sets `cut_off` on units and cities.
	for side in [1, 2]:
		var connected: Dictionary = {}
		var cap = s.board.player_capital() if side == 1 else s.board.enemy_capital()
		if cap != null and is_instance_valid(cap):
			connected = _flood_owned(cap.get_hex(), side)

		for u in s.board.units:
			if not is_instance_valid(u) or Sides.side_of(u.team) != side: continue
			var hex = u.get_hex()
			# Cut off when your ground (or the grey around you) doesn't reach home
			u.cut_off = hex != null and not connected.has(hex)
		for c in s.board.cities:
			if not is_instance_valid(c) or Sides.side_of(c.team) != side: continue
			c.cut_off = not connected.has(c.get_hex())

func _regions_of(side: int) -> Array:
	var seen: Dictionary = {}
	var regions: Array = []
	for hex in owner_map:
		if owner_map[hex] != side or seen.has(hex): continue
		var region: Array = []
		var stack: Array = [hex]
		seen[hex] = true
		while stack.size() > 0:
			var cur = stack.pop_back()
			region.append(cur)
			for nb in HEX.axial_neighbours(cur):
				if seen.has(nb): continue
				if owner_map.get(nb, -1) != side: continue
				seen[nb] = true
				stack.append(nb)
		regions.append(region)
	return regions

func _region_has_assets(region: Array, side: int) -> bool:
	for hex in region:
		var p = s.grid.get_piece(hex)
		if p != null and Sides.side_of(p.team) == side:
			return true
	return false

func _flood_owned(start, side: int) -> Dictionary:
	## Hexes reachable from `start` through this side's paint (NML passable —
	## the line itself doesn't sever you; enemy paint does).
	var seen: Dictionary = {}
	if start == null or not s.grid.Grid.has(start):
		return seen
	var stack: Array = [start]
	seen[start] = true
	while stack.size() > 0:
		var cur = stack.pop_back()
		for nb in HEX.axial_neighbours(cur):
			if seen.has(nb): continue
			if not s.grid.Grid.has(nb): continue
			var o: int = owner_map.get(nb, NML)
			if o != side and o != NML: continue
			seen[nb] = true
			stack.append(nb)
	return seen

# ── Rendering ─────────────────────────────────────────────────────────────────

# MULTIPLY-blend tints: 1.0 on a channel passes art through; lower darkens.
const COLOR_PLAYER := Color(0.88, 1.00, 0.88)   # faint green cast on your ground
const COLOR_ENEMY := Color(1.00, 0.74, 0.72)    # clear red cast on theirs
const COLOR_NML := Color(0.88, 0.88, 0.88)      # slightly dimmed no-man's-land
const LOC_LINE := Color(0.45, 0.45, 0.45)       # multiplies to a firm dark line

# Display modes (C key): 0 = tints + line, 1 = front line only, 2 = hidden
var display_mode: int = 0

func cycle_display() -> void:
	display_mode = (display_mode + 1) % 3
	queue_redraw()
	Events.notify(["Territory: tints + front line", "Territory: front line only",
		"Territory: hidden"][display_mode])

func _draw() -> void:
	if s == null: return
	if display_mode == 2: return

	if display_mode == 0:
		for hex in owner_map:
			var color: Color
			match owner_map[hex]:
				1: color = COLOR_PLAYER
				2: color = COLOR_ENEMY
				_: color = COLOR_NML
			draw_colored_polygon(_hex_corners(hex), color)

	# The front line: heavier stroke wherever differing paint meets
	var drawn: Dictionary = {}
	for hex in owner_map:
		for nb in HEX.axial_neighbours(hex):
			if not owner_map.has(nb): continue
			if owner_map[nb] == owner_map[hex]: continue
			var key := "%s|%s" % [hex, nb] if str(hex) < str(nb) else "%s|%s" % [nb, hex]
			if drawn.has(key): continue
			drawn[key] = true
			# Only stroke the actual front (a side touching NML or the other side)
			var ca: Vector2 = s.grid.get_hex_pos(hex)
			var cb: Vector2 = s.grid.get_hex_pos(nb)
			var mid: Vector2 = (ca + cb) * 0.5
			var dir: Vector2 = (cb - ca).normalized()
			var perp: Vector2 = Vector2(-dir.y, dir.x) * (hex_size * 0.5)
			draw_line(mid + perp, mid - perp, LOC_LINE, hex_size * 0.09)

func _hex_corners(hex) -> PackedVector2Array:
	var center: Vector2 = s.grid.get_hex_pos(hex)
	var corners := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)   # pointy-top
		corners.append(center + Vector2(cos(angle), sin(angle)) * hex_size)
	return corners
