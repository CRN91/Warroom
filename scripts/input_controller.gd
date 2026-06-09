extends Node2D
class_name InputController

## All mouse/keyboard handling for the board: selecting pieces, issuing move /
## attack / build orders, rail planning keys, and the path preview line.
##
## Keys: R = plan rail on hovered hex, T = commit rail route, M = clear movement,
##       F = clear attack target, Esc = cancel rail plan / deselect, F3 = debug overlay.

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var s: GameServices
var path_line: Line2D
var selected_unit: Node2D = null

func setup(services: GameServices, p_path_line: Line2D) -> void:
	s = services
	path_line = p_path_line

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event):
	if (event is InputEventMouse) and s.ui.is_mouse_over_ui():
		return

	if event.is_action_pressed("select"):
		_on_select(_hex_under_mouse())
	elif event.is_action_pressed("deselect"):
		deselect()
	elif event is InputEventMouseMotion:
		_on_mouse_moved(_hex_under_mouse())
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode, _hex_under_mouse())

func _hex_under_mouse() -> Vector2i:
	var oddr = s.grid.base_layer.local_to_map(s.grid.get_global_mouse_position())
	return HEX.oddr_to_axial(oddr)

func _on_select(hex: Vector2i) -> void:
	if not s.grid.Grid.has(hex):
		return
	s.grid.select_hex(HEX.axial_to_oddr(hex))
	var clicked_piece = s.board.get_piece(hex)

	if selected_unit != null and not is_instance_valid(selected_unit):
		selected_unit = null

	if selected_unit == null:
		if clicked_piece == null:
			# Empty rail hex? Deploy a stocked train.
			if s.rail_network.can_deploy_train(hex) and s.rail_network.player_train_stock > 0:
				s.rail_network.deploy_train_from_stock(hex)
		else:
			_select_piece(clicked_piece)
	else:
		if clicked_piece == selected_unit:
			deselect()
		elif clicked_piece != null and clicked_piece.team == selected_unit.team and clicked_piece.visible:
			_select_piece(clicked_piece)
		else:
			_play_selected(hex)
			s.ui.show_stats(selected_unit)
			_update_path_preview(selected_unit, hex)

func _on_mouse_moved(hex: Vector2i) -> void:
	if selected_unit != null and is_instance_valid(selected_unit):
		_update_path_preview(selected_unit, hex)
	else:
		path_line.clear_points()

func _on_key(keycode: int, hex: Vector2i) -> void:
	match keycode:
		KEY_M:
			if selected_unit and is_instance_valid(selected_unit):
				selected_unit.clear_movement()
				s.ui.show_stats(selected_unit)
				_update_path_preview(selected_unit, hex)
		KEY_F:
			if selected_unit and is_instance_valid(selected_unit) and selected_unit.is_combatant():
				selected_unit.clear_attack_target()
				s.ui.show_stats(selected_unit)
		KEY_R:
			if s.grid.Grid.has(hex):
				s.rail_network.toggle_rail(hex)
		KEY_T:
			s.rail_network.commit_rail_route()
		KEY_F3:
			s.ui.toggle_debug()
		KEY_ESCAPE:
			if not s.rail_network.building_route.is_empty():
				s.rail_network.cancel_rail_build()
			else:
				deselect()

# ── Selection ─────────────────────────────────────────────────────────────────

func _select_piece(piece: Node2D) -> void:
	if piece is City:
		if piece.team == 1:
			_set_selected(null)
			s.ui.show_stats(piece)
	elif piece.team == 1:
		_set_selected(piece)
		s.ui.show_stats(piece)

func deselect() -> void:
	path_line.clear_points()
	_set_selected(null)
	s.grid.deselect()
	s.ui.hide_panels()

func _set_selected(piece: Node2D) -> void:
	if selected_unit and is_instance_valid(selected_unit) and selected_unit.has_method("set_selected"):
		selected_unit.set_selected(false)
	selected_unit = piece
	if piece and piece.has_method("set_selected"):
		piece.set_selected(true)

# ── Orders ────────────────────────────────────────────────────────────────────

func _play_selected(hex: Vector2i) -> void:
	var active_unit = selected_unit
	if not active_unit or not is_instance_valid(active_unit): return
	var active_hex = active_unit.get_hex()
	var clicked = s.board.get_piece(hex)

	# Trains drive along their own route: click a rail hex on the line
	if active_unit is Train:
		if s.rail_network.rail_hexes.has(hex):
			active_unit.move_to(hex)
			s.ui.show_stats(active_unit)
		return

	# Logistics build/repair actions on adjacent hexes
	if active_unit is Logistics and HEX.axial_distance(active_hex, hex) == 1:
		if _try_logistics_action(active_unit, active_hex, hex):
			return

	# Already on a manual path: clicks extend the path
	if active_unit.movement_comp.path.size() > 0:
		if not (clicked is City):
			_handle_movement_command(active_unit, hex)
		return

	# Treat fogged enemies as empty ground
	var click_as_empty: bool = clicked == null or (not clicked.visible and clicked.team != active_unit.team)
	if click_as_empty:
		_handle_movement_command(active_unit, hex)
		return

	var dist: int = HEX.axial_distance(active_hex, hex)

	if active_unit.team != clicked.team:
		if active_unit.is_combatant() and dist <= active_unit.get_attack_range():
			if dist > 1 and s.terrain.blocks_line_of_fire(active_hex, hex):
				Events.notify("Line of fire blocked by a mountain.")
			else:
				active_unit.set_attack_target(clicked)
				s.ui.show_stats(active_unit)
	elif dist == 1:
		_handle_supply_transfer(active_unit, clicked)

	s.board.cull_dead()

func _try_logistics_action(unit: Node2D, from_hex: Vector2i, hex: Vector2i) -> bool:
	var acted := false

	if s.terrain.is_mountain(hex) and not s.terrain.has_tunnel(hex):
		if s.terrain.tunnel_stock > 0:
			s.terrain.build_tunnel(hex)
			s.terrain.tunnel_stock -= 1
			Events.notify("Tunnel built.")
			acted = true
		else:
			Events.notify("No tunnels in stock.")
	elif s.terrain.is_river_edge(from_hex, hex) and not s.terrain.is_bridged(from_hex, hex):
		if s.terrain.bridge_stock > 0:
			s.terrain.build_bridge(from_hex, hex)
			s.terrain.bridge_stock -= 1
			Events.notify("Bridge built.")
			acted = true
		else:
			Events.notify("No bridges in stock.")
	elif s.board.get_piece(hex) == null and s.rail_network.rail_hexes.has(hex) and s.rail_network.rail_hexes[hex]["broken"]:
		acted = s.rail_network.repair_rail_at(hex, unit)

	return acted

func _handle_supply_transfer(active_unit: Node2D, other: Node2D) -> void:
	var active_is_supplier: bool = not active_unit.is_combatant()
	var other_is_supplier: bool = not other.is_combatant()

	if active_is_supplier and not other_is_supplier:
		other.receive_from(active_unit)
	elif other_is_supplier and not active_is_supplier:
		active_unit.receive_from(other)
	elif active_is_supplier and other_is_supplier:
		active_unit.receive_from(other)

func _handle_movement_command(unit: Node2D, target_hex: Vector2i) -> void:
	var move_comp = unit.movement_comp

	if move_comp.goal == null and move_comp.path.is_empty():
		# First click: smart auto-goal (re-routes around traffic each day)
		unit.set_destination(target_hex)
		return

	# Second click (or more): lock in a strict manual path
	var start_hex = unit.get_hex()
	var passable := _passable_for_pathing()

	if move_comp.goal != null:
		# Convert the existing auto-goal into the first leg of the manual path
		var first_leg: Array = _routed_path(start_hex, move_comp.goal, passable)
		for i in range(1, first_leg.size()):
			move_comp.path.append(first_leg[i])
		move_comp.goal = null

	var route_start = move_comp.path.back() if move_comp.path.size() > 0 else start_hex
	var next_leg: Array = _routed_path(route_start, target_hex, passable)
	for i in range(1, next_leg.size()):
		move_comp.path.append(next_leg[i])
	unit.refresh_intent()

func _routed_path(from_hex: Vector2i, to_hex: Vector2i, passable: Array) -> Array:
	s.grid.sync_pathing(passable)
	var p = s.grid.get_map_path(from_hex, to_hex)
	s.grid.sync_pathing()
	return p

func _passable_for_pathing() -> Array:
	# Ignore all units (except cities) so paths can be drawn through traffic jams.
	var passable: Array = []
	for h in s.grid.Grid:
		var p = s.board.get_piece(h)
		if p and not (p is City):
			passable.append(h)
	return passable

# ── Path preview line ─────────────────────────────────────────────────────────

func _update_path_preview(piece: Node2D, target_hex: Vector2i) -> void:
	if not s.grid.Grid.has(target_hex) or not is_instance_valid(piece):
		path_line.clear_points()
		return

	var passable := _passable_for_pathing()
	var move_comp = piece.movement_comp

	if move_comp.path.size() > 0:
		# Committed manual path (yellow) + preview extension to the mouse
		path_line.default_color = Color(1.0, 0.8, 0.2)
		var points := PackedVector2Array()
		points.append(s.grid.get_hex_pos(piece.get_hex()))
		var prev = piece.get_hex()
		for p in move_comp.path:
			points.append(s.grid.get_hex_pos(p))
			prev = p
		points.append_array(_preview_leg(prev, target_hex, passable))
		path_line.points = points

	elif move_comp.goal != null:
		# Auto-goal (yellow) + preview extension from the goal to the mouse
		path_line.default_color = Color(1.0, 0.8, 0.2)
		var points := PackedVector2Array()
		s.grid.sync_pathing(passable)
		points.append_array(s.grid.get_hex_path(piece.get_hex(), move_comp.goal))
		s.grid.sync_pathing()
		points.append_array(_preview_leg(move_comp.goal, target_hex, passable))
		path_line.points = points

	else:
		# Pure hover preview (green)
		path_line.default_color = Color(0.5, 1.0, 0.2)
		s.grid.sync_pathing(passable)
		path_line.points = s.grid.get_hex_path(piece.get_hex(), target_hex)
		s.grid.sync_pathing()

func _preview_leg(from_hex: Vector2i, to_hex: Vector2i, passable: Array) -> PackedVector2Array:
	## The leg from from_hex to the mouse, minus its first point (already drawn).
	s.grid.sync_pathing(passable)
	var leg = s.grid.get_hex_path(from_hex, to_hex)
	s.grid.sync_pathing()
	return leg.slice(1) if leg.size() > 1 else PackedVector2Array()
