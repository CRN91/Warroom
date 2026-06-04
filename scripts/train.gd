extends Unit
class_name Train

var rail_network: Node

var route: Array = []
var route_id: int = -1
var direction: int = 1
var speed: int = 2
var manual_override: bool = false

func setup_route(new_route: Array, id: int, p_grid: Node, p_rail_network: Node):
	setup(p_grid)
	route = new_route
	route_id = id
	direction = 1
	manual_override = false

	rail_network = p_rail_network

	var start = route[0]
	grid.set_piece(start, self)
	grid.disable_hex(start)
	movement_comp.force_hex(start, grid)

	if has_node("Sprite2D"):
		$Sprite2D.flip_h = false

func move_to(new_hex):
	var old_hex = get_hex()

	if frozen: return grid

	if old_hex == null:
		frozen = true
		grid.disable_hex(new_hex)
		movement_comp.force_hex(new_hex, grid)

	var old_idx = route.find(old_hex)
	var new_idx = route.find(new_hex)

	if new_idx == -1 or old_idx == -1 or new_idx == old_idx:
		return grid

	var distance = abs(new_idx - old_idx)
	if distance > speed:
		return grid

	var step_dir = 1 if new_idx > old_idx else -1
	for i in range(1, distance + 1):
		var check_idx = old_idx + (i * step_dir)
		var check_hex = route[check_idx]
		if grid.get_piece(check_hex) != null:
			return grid

	frozen = true
	direction = step_dir
	manual_override = true

	if has_node("Sprite2D"):
		$Sprite2D.flip_h = (direction == -1)

	grid.enable_hex(old_hex)
	grid.disable_hex(new_hex)
	movement_comp.force_hex(new_hex, grid)

	_exchange_supplies()

	return frozen

func process_movement():
	if route.is_empty():
		return

	if not _route_intact(rail_network.rail_hexes):
		print("%s halted — rail broken at %s" % [name, _first_broken(rail_network.rail_hexes)])
		return

	var current_hex = get_hex()
	var current_idx = route.find(current_hex)
	if current_idx == -1: return

	var facing_terminus_a = (direction == -1 and current_idx == 0)
	var facing_terminus_b = (direction == 1  and current_idx == route.size() - 1)

	if facing_terminus_a or facing_terminus_b:
		_exchange_supplies()

		if not manual_override:
			var ready_to_leave := false
			if facing_terminus_a:
				if get_resources() >= get_max_resources():
					ready_to_leave = true
			elif facing_terminus_b:
				if get_resources() < get_max_resources():
					ready_to_leave = true

			if ready_to_leave:
				direction = -direction
				if has_node("Sprite2D"):
					$Sprite2D.flip_h = (direction == -1)
			else:
				print("%s waiting at terminus for cargo conditions." % name)
				return
		manual_override = false

	for _step in range(speed):
		current_idx = route.find(get_hex())
		var next_idx = current_idx + direction

		if next_idx < 0 or next_idx >= route.size():
			direction = -direction
			if has_node("Sprite2D"):
				$Sprite2D.flip_h = (direction == -1)
			break

		var next_hex = route[next_idx]
		if grid.get_piece(next_hex) != null:
			break

		grid.set_piece(get_hex())
		grid.enable_hex(get_hex())
		grid.set_piece(next_hex, self)
		grid.disable_hex(next_hex)
		movement_comp.force_hex(next_hex,grid)

		_exchange_supplies()

func _exchange_supplies():
	var current_hex = get_hex()
	var current_idx = route.find(current_hex)
	if current_idx == -1: return

	var check_hexes = [current_hex] + HEX.axial_neighbours(current_hex)

	for hex in check_hexes:
		if not grid.Grid.has(hex): continue
		var city = grid.get_piece(hex)

		if city == null or not (city is City): continue
		if city.team != team: continue

		# Terminus A: load up from the city.
		if current_idx == 0:
			receive_from(city)
			print("%s loaded supplies from %s at Terminus A" % [name, city.name])

		# Any other position: drop off cargo to the city.
		else:
			var carry      = get_resources()
			var cargo_space = city.get_max_resources() - city.get_resources()
			var drop_off   = min(carry, cargo_space)

			if drop_off > 0:
				city.replenish(drop_off)
				deplete(drop_off)
				print("%s delivered %d supplies to %s" % [name, drop_off, city.name])

# ── Rail integrity ────────────────────────────────────────────────────────────

func _route_intact(rail_hexes: Dictionary) -> bool:
	for hex in route:
		if not rail_hexes.has(hex): return false
		if rail_hexes[hex].get("broken", false): return false
	return true

func _first_broken(rail_hexes: Dictionary) -> Vector2i:
	for hex in route:
		if not rail_hexes.has(hex) or rail_hexes[hex].get("broken", false):
			return hex
	return Vector2i(-99, -99)

func sabotage_at(hex: Vector2i, game: Node):
	if game.rail_network.rail_hexes.has(hex):
		game.rail_network.rail_hexes[hex]["broken"] = true
		print("Rail sabotaged at %s — %s halted!" % [str(hex), name])

func repair_at(hex: Vector2i, game: Node):
	if game.rail_network.rail_hexes.has(hex):
		game.rail_network.rail_hexes[hex]["broken"] = false
		print("Rail repaired at %s" % str(hex))
