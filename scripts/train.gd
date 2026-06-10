extends Unit
class_name Train

## Runs back and forth along a committed rail route, hauling supplies between
## the cities at (or adjacent to) its termini. Player can manually drive it up
## to `speed` hexes along the route; otherwise it shuttles automatically,
## waiting at a terminus until its cargo condition is met.

var rail_network: Node

var route: Array = []
var route_id: int = -1
var direction: int = 1
var speed: int = 2
var manual_override: bool = false

func setup_route(new_route: Array, id: int, p_grid: Node, p_rail_network: Node, start_hex = null):
	setup(p_grid)
	route = new_route
	route_id = id
	direction = 1
	manual_override = false
	rail_network = p_rail_network

	var start = start_hex if start_hex != null else route[0]
	grid.set_piece(start, self)
	grid.disable_hex(start)
	movement_comp.force_hex(start, grid)
	update_ui()

	if has_node("Sprite2D"):
		$Sprite2D.flip_h = false

func move_to(new_hex) -> void:
	## Manual drive: the player clicks a hex on this train's route.
	if frozen: return

	var old_hex = get_hex()
	if old_hex == null:
		freeze()
		grid.disable_hex(new_hex)
		movement_comp.force_hex(new_hex, grid)
		return

	var old_idx = route.find(old_hex)
	var new_idx = route.find(new_hex)
	if new_idx == -1 or old_idx == -1 or new_idx == old_idx:
		return

	var distance = abs(new_idx - old_idx)
	if distance > speed:
		return

	# Every hex along the way must be clear
	var step_dir = 1 if new_idx > old_idx else -1
	for i in range(1, distance + 1):
		var check_hex = route[old_idx + (i * step_dir)]
		if grid.get_piece(check_hex) != null:
			return

	freeze()
	direction = step_dir
	manual_override = true
	_face_direction()

	grid.enable_hex(old_hex)
	grid.disable_hex(new_hex)
	movement_comp.force_hex(new_hex, grid)

	_exchange_supplies()

func process_movement():
	if route.is_empty():
		return

	if not _route_intact():
		if not _halt_notified:
			Events.notify("%s halted — line broken at %s." % [name, _first_broken()])
			_halt_notified = true
		return
	_halt_notified = false

	var current_idx = route.find(get_hex())
	if current_idx == -1: return

	var facing_terminus_a = (direction == -1 and current_idx == 0)
	var facing_terminus_b = (direction == 1 and current_idx == route.size() - 1)

	if facing_terminus_a or facing_terminus_b:
		_exchange_supplies()

		if not manual_override:
			# At a capital: wait until loaded. At a town: wait until delivered
			# (or the town is full). Anywhere else: keep rolling.
			var stop_city := _adjacent_city()
			var ready_to_leave := true
			if stop_city != null:
				if stop_city.is_capital:
					ready_to_leave = get_resources() >= get_max_resources()
				else:
					ready_to_leave = get_resources() <= 1 \
						or stop_city.get_resources() >= stop_city.get_max_resources()

			if ready_to_leave:
				direction = -direction
				_face_direction()
			else:
				return
		manual_override = false

	for _step in range(speed):
		current_idx = route.find(get_hex())
		var next_idx = current_idx + direction

		if next_idx < 0 or next_idx >= route.size():
			direction = -direction
			_face_direction()
			break

		var next_hex = route[next_idx]
		if grid.get_piece(next_hex) != null:
			break

		grid.set_piece(get_hex())
		grid.enable_hex(get_hex())
		grid.set_piece(next_hex, self)
		grid.disable_hex(next_hex)
		movement_comp.force_hex(next_hex, grid)

		_exchange_supplies()

func _face_direction():
	if has_node("Sprite2D"):
		$Sprite2D.flip_h = (direction == -1)

func _adjacent_city() -> City:
	var current_hex = get_hex()
	if current_hex == null: return null
	for hex in [current_hex] + HEX.axial_neighbours(current_hex):
		if not grid.Grid.has(hex): continue
		var p = grid.get_piece(hex)
		if p is City and p.team == team:
			return p
	return null

func _exchange_supplies():
	## The automation that makes rail worth building: LOAD at any capital stop,
	## DELIVER at any town stop. A capital→town line keeps the forward depot
	## topped up with no orders at all.
	var current_hex = get_hex()
	if current_hex == null: return

	for hex in [current_hex] + HEX.axial_neighbours(current_hex):
		if not grid.Grid.has(hex): continue
		var city = grid.get_piece(hex)
		if city == null or not (city is City): continue
		if city.team != team: continue

		if city.is_capital:
			receive_from(city)   # load up
		else:
			# Keep 1 aboard — a hauler at exactly 0 reads as destroyed.
			var drop_off = min(get_resources() - 1, city.get_max_resources() - city.get_resources())
			if drop_off > 0:
				city.replenish(drop_off)
				deplete(drop_off)

# ── Rail integrity ────────────────────────────────────────────────────────────

var _halt_notified: bool = false

func _route_intact() -> bool:
	for hex in route:
		if not rail_network.rail_hexes.has(hex): return false
		if rail_network.rail_hexes[hex].get("broken", false): return false
	# A blown bridge along the line stops the train too
	for i in range(route.size() - 1):
		if terrain and not terrain.is_crossable(route[i], route[i + 1]):
			return false
	return true

func _first_broken() -> Vector2i:
	for hex in route:
		if not rail_network.rail_hexes.has(hex) or rail_network.rail_hexes[hex].get("broken", false):
			return hex
	for i in range(route.size() - 1):
		if terrain and not terrain.is_crossable(route[i], route[i + 1]):
			return route[i]
	return Vector2i(-99, -99)
