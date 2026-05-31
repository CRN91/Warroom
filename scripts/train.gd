extends Unit
class_name Train

# ── Route state ───────────────────────────────────────────────────────────────
var route: Array = []          # Ordered Array[Vector2i], terminus A → terminus B
var route_id: int = -1         # Matches Game.rail_routes key
var direction: int = 1         # 1 = moving toward route.back(), -1 = toward route.front()
var position_index: int = 0    # Current position as index into route
var speed: int = 2             # Hexes moved per day

func _ready():
	allied   = true
	supplier = 1    # Trains supply adjacent units at endpoints like a logistics truck

func combatant(): return false

# ── Setup ─────────────────────────────────────────────────────────────────────

## Called by Game.gd after the player commits a rail route.
## Places the train at route[0] and registers it in the grid.
func setup_route(new_route: Array, id: int, game: Node):
	route    = new_route
	route_id = id
	position_index = 0
	direction      = 1

	# Place on grid at the first hex of the route
	var start = route[0]
	game.grid.Grid[start]["Piece"] = self
	game.grid.disable_hex(start)
	game.grid = movement_comp.force_hex(start, game.grid)
	position = game.grid.map_to_local(HEX.axial_to_oddr(start))

# ── Daily tick ────────────────────────────────────────────────────────────────

## Called each day by Game.clock_increment().
func train_tick(game: Node):
	if route.is_empty():
		return

	# Halt if any hex in the owned route is broken
	if not _route_intact(game.rail_hexes):
		print("%s halted — rail broken at %s" % [name, _first_broken(game.rail_hexes)])
		return

	# At an endpoint: exchange supplies then reverse
	var at_terminus = (direction == 1  and position_index == route.size() - 1) \
				   or (direction == -1 and position_index == 0)

	if at_terminus:
		_exchange_supplies(game)
		direction = -direction
		return

	# Move up to `speed` steps along the route
	for _step in range(speed):
		var next_idx = position_index + direction
		if next_idx < 0 or next_idx >= route.size():
			direction = -direction
			break

		var next_hex = route[next_idx]
		if game.grid.Grid[next_hex]["Piece"] != null:
			break  # Occupied — wait one day

		# Vacate current hex
		var old_hex = route[position_index]
		game.grid.Grid[old_hex]["Piece"] = null
		game.grid.enable_hex(old_hex)

		# Occupy next hex
		position_index = next_idx
		game.grid.Grid[next_hex]["Piece"] = self
		game.grid.disable_hex(next_hex)
		game.grid = movement_comp.force_hex(next_hex, game.grid)
		position = game.grid.map_to_local(HEX.axial_to_oddr(next_hex))

# ── Supply exchange ───────────────────────────────────────────────────────────

## At terminus A (index 0): train loads up from any adjacent allied city.
## At terminus B (last index): train unloads into any adjacent allied city.
func _exchange_supplies(game: Node):
	var endpoint  = route[position_index]
	var check_hexes = [endpoint] + HEX.axial_neighbours(endpoint)

	for hex in check_hexes:
		if not game.grid.Grid.has(hex):
			continue
		var piece = game.grid.Grid[hex]["Piece"]
		if piece == null or not (piece is City):
			continue
		if piece.is_allied() != allied:
			continue

		# Terminus A — train fills up from city
		if position_index == 0:
			var space    = get_max_resources() - get_resources()
			var transfer = min(space, piece.get_resources())
			if transfer > 0:
				piece.deplete(transfer)
				restore(transfer)
				print("%s loaded %d supplies from %s" % [name, transfer, piece.name])

		# Terminus B — train delivers to city
		else:
			var carry = get_resources()
			if carry > 0:
				piece.restore(carry)
				deplete(carry)
				print("%s delivered %d supplies to %s" % [name, carry, piece.name])

# ── Route integrity ───────────────────────────────────────────────────────────

func _route_intact(rail_hexes: Dictionary) -> bool:
	for hex in route:
		if not rail_hexes.has(hex):
			return false
		if rail_hexes[hex].get("broken", false):
			return false
	return true

func _first_broken(rail_hexes: Dictionary) -> Vector2i:
	for hex in route:
		if not rail_hexes.has(hex) or rail_hexes[hex].get("broken", false):
			return hex
	return Vector2i(-99, -99)

# ── Sabotage API (called by Game.gd when an enemy attacks a rail hex) ─────────

## Marks the rail hex closest to this train as sabotaged.
## Called externally; the train doesn't move until repaired.
func sabotage_at(hex: Vector2i, game: Node):
	if game.rail_hexes.has(hex):
		game.rail_hexes[hex]["broken"] = true
		print("Rail sabotaged at %s — %s halted!" % [str(hex), name])

## Repairs a broken hex on this route (e.g. from a repair card/event).
func repair_at(hex: Vector2i, game: Node):
	if game.rail_hexes.has(hex):
		game.rail_hexes[hex]["broken"] = false
		print("Rail repaired at %s" % str(hex))
