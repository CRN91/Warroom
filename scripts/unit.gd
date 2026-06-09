extends Node2D
class_name Unit

## Base class for everything that sits on a hex: infantry, artillery,
## logistics, trains and (via subclass) cities.
##
## Dependencies are injected by Board.register_unit — units never hold a
## reference to Game. They receive exactly what they use:
##   grid       — position / pathing
##   modifiers  — stat queries (attack buffs etc.)
##   terrain    — line-of-fire checks (used by the attack component)

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

var grid: Node
var modifiers: ModifierManager = null
var terrain: TerrainManager = null

func setup(p_grid: Node):
	grid = p_grid

func inject(p_grid: Node, p_modifiers: ModifierManager, p_terrain: TerrainManager) -> void:
	grid = p_grid
	modifiers = p_modifiers
	terrain = p_terrain

# Used by modifier scopes like "type:infantry" and "tag:elite". Set per unit
# scene (e.g. "infantry", "artillery", "logistics") or via a spawn/transform card.
@export var unit_type: String = ""
var tags: Array = []

# ── Action (1 per day) ────────────────────────────────────────────────────────

var frozen: bool = false

func is_frozen(): return frozen

func freeze():
	frozen = true
	_update_frozen_visual()

func unfreeze():
	frozen = false
	_update_frozen_visual()

func _update_frozen_visual():
	# Spent units dim so it's obvious who can still act this turn.
	modulate = Color(0.55, 0.55, 0.55) if frozen else Color(1, 1, 1)

# ── Movement ──────────────────────────────────────────────────────────────────

@onready var movement_comp: Movement = $Movement

func get_hex(): return movement_comp.get_hex()
func move_to(hex): movement_comp.move_to(hex, grid)

func clear_movement():
	if movement_comp: movement_comp.clear_movement()
	refresh_intent()

func process_movement():
	if not get_hex() or is_frozen(): return
	movement_comp.process_movement(grid)

func set_destination(hex):
	movement_comp.set_goal(hex)
	refresh_intent()

func add_waypoint(hex):
	movement_comp.add_waypoint(hex)
	refresh_intent()

# ── Resources ─────────────────────────────────────────────────────────────────

@onready var resource_comp: Resources = $Resources

func get_resources() -> int: return resource_comp.get_resources()
func get_max_resources() -> int: return resource_comp.get_max_resources()

func deplete(x) -> bool:
	var starved = resource_comp.deplete(x)
	update_ui()
	return starved

func replenish(x) -> void:
	resource_comp.replenish(x)
	update_ui()

# ── Supply chain ──────────────────────────────────────────────────────────────

@onready var resupply_comp = get_node_or_null("Resupply")

func process_resupply() -> void:
	if resupply_comp:
		resupply_comp.process_resupply(grid)

func receive_from(donor: Node2D) -> void:
	if resupply_comp:
		resupply_comp.receive_from(donor)

func supply_to(target: Node2D) -> void:
	if resupply_comp:
		resupply_comp.supply_to(target)

# ── Attack ────────────────────────────────────────────────────────────────────

func is_combatant(): return false

@onready var attack_comp = get_node_or_null("Attack")

func get_attack_target():
	return attack_comp.get_target(grid) if attack_comp else null

func get_attack_range():
	return attack_comp.get_range() if attack_comp else 1

func get_damage():
	var base = attack_comp.get_damage() if attack_comp else 0
	if modifiers:
		return int(round(modifiers.get_value("attack", float(base), self)))
	return base

func attack(enemy):
	return attack_comp.attack(enemy) if attack_comp else false

func set_attack_target(piece):
	if attack_comp: attack_comp.set_target(piece)
	refresh_intent()

func clear_attack_target():
	if attack_comp: attack_comp.clear_target()
	refresh_intent()

# ── Team ──────────────────────────────────────────────────────────────────────

var team: int = 1 # 1 = Player, 2 = Enemy, 0 = Neutral
func set_enemy():   team = 2
func set_neutral(): team = 0
func set_player():  team = 1

# ── Daily tick ────────────────────────────────────────────────────────────────

func next_day() -> bool:
	var starved = resource_comp.clock_cycle()
	update_ui()
	return starved

# ── UI ────────────────────────────────────────────────────────────────────────

@onready var resource_bar = get_node_or_null("ResourceBar")
var _bar_setup_done: bool = false

func update_ui():
	if resource_bar:
		if not _bar_setup_done:
			resource_bar.custom_minimum_size = Vector2(60, 8)
			resource_bar.position = Vector2(-150, -300)
			resource_bar.show_percentage = false

			var bg_style = StyleBoxFlat.new()
			bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
			resource_bar.add_theme_stylebox_override("background", bg_style)

			var fill_style = StyleBoxFlat.new()
			fill_style.bg_color = Color(0.2, 0.7, 0.3, 1.0)
			resource_bar.add_theme_stylebox_override("fill", fill_style)

			_bar_setup_done = true

		resource_bar.max_value = get_max_resources()
		resource_bar.value = get_resources()

func status() -> String:
	var extras = ""
	if attack_comp and attack_comp.target and is_instance_valid(attack_comp.target):
		extras += " | Target: %s" % attack_comp.target.name

	if movement_comp.path.size() > 0:
		extras += " | Manual Path (%d waypoints)" % movement_comp.path.size()
	elif movement_comp.goal != null:
		extras += " | Auto → %s" % str(movement_comp.goal)

	return "Hex: %s | %s | Resources: %d/%d%s" % [
		get_hex(), name, get_resources(), get_max_resources(), extras
	]

# ── Selection highlight ───────────────────────────────────────────────────────

var is_selected: bool = false
var _ring_radius: float = 0.0

func set_selected(v: bool) -> void:
	is_selected = v
	queue_redraw()

func _selection_radius() -> float:
	if _ring_radius <= 0.0 and is_instance_valid(grid):
		var hex = get_hex()
		if hex != null:
			for nb in HEX.axial_neighbours(hex):
				if grid.Grid.has(nb):
					_ring_radius = grid.get_hex_pos(hex).distance_to(grid.get_hex_pos(nb)) * 0.45
					break
	return _ring_radius if _ring_radius > 0.0 else 250.0

# ── Visual Intent (Telegraphing) ──────────────────────────────────────────────

var _next_move_hex = null
var _target_piece = null
var _resupply_piece = null

func refresh_intent():
	_next_move_hex = null
	_target_piece = null
	_resupply_piece = null

	# 1. Movement intent
	if movement_comp and movement_comp.path.size() > 0:
		_next_move_hex = movement_comp.path[0]
	elif movement_comp and movement_comp.goal != null:
		var passable = [get_hex(), movement_comp.goal]
		for h in grid.Grid:
			var p = grid.get_piece(h)
			if p and p.has_method("is_combatant") and not (p is City):
				passable.append(h)
		grid.sync_pathing(passable)
		var apath = grid.get_map_path(get_hex(), movement_comp.goal)
		grid.sync_pathing()
		if apath.size() > 1:
			_next_move_hex = apath[1]

	# 2. If not moving: attack intent
	if _next_move_hex == null and attack_comp:
		_target_piece = attack_comp.target if is_instance_valid(attack_comp.target) else null

	# 3. If not moving or attacking: resupply tether
	if _next_move_hex == null and _target_piece == null and resupply_comp and resupply_comp.can_receive:
		_resupply_piece = _best_adjacent_donor()

	queue_redraw()

func _best_adjacent_donor() -> Node2D:
	var best_donor: Node2D = null
	var best_rank := -1
	for adj in HEX.axial_neighbours(get_hex()):
		if not grid.Grid.has(adj): continue
		var candidate = grid.get_piece(adj)
		if candidate == null or candidate.team != team: continue
		var donor_supply = candidate.get_node_or_null("Resupply")
		# Needs a higher-rank supplier with spare supplies to give
		if donor_supply and donor_supply.supplier_rank > resupply_comp.supplier_rank and donor_supply.supplier_rank > best_rank:
			if (candidate.get_resources() - donor_supply.supplier_reserve) > 0:
				best_donor = candidate
				best_rank = donor_supply.supplier_rank
	return best_donor

func _draw():
	if not is_instance_valid(grid): return

	var thickness = 30.0

	if is_selected:
		draw_arc(Vector2.ZERO, _selection_radius(), 0, TAU, 48, Color(1.0, 0.95, 0.4, 0.9), 14.0)

	# 1. Movement arrow (green)
	if _next_move_hex != null and grid.Grid.has(_next_move_hex):
		var target_pos = grid.get_hex_pos(_next_move_hex) - position
		draw_arrow(Vector2.ZERO, target_pos * 0.75, Color(0.2, 0.9, 0.2, 0.9), thickness)

	# 2. Attack crosshair & arrow (red)
	elif _target_piece != null and is_instance_valid(_target_piece):
		if _target_piece.visible: # strictly respects fog of war
			var target_pos = _target_piece.position - position
			var color = Color(0.9, 0.1, 0.1, 0.9)
			draw_arrow(Vector2.ZERO, target_pos * 0.75, color, thickness)
			draw_arc(target_pos, 22.0, 0, TAU, 16, color, thickness / 1.5)
			draw_line(target_pos - Vector2(30, 0), target_pos + Vector2(30, 0), color, thickness / 1.5)
			draw_line(target_pos - Vector2(0, 30), target_pos + Vector2(0, 30), color, thickness / 1.5)

	# 3. Resupply arrow (blue, flowing from supplier to this unit)
	elif _resupply_piece != null and is_instance_valid(_resupply_piece):
		var target_pos = _resupply_piece.position - position
		draw_arrow(target_pos * 0.75, target_pos * 0.25, Color(0.1, 0.6, 1.0, 0.9), thickness)

func draw_arrow(start: Vector2, end: Vector2, color: Color, thickness: float):
	if start.distance_to(end) < 1.0: return

	draw_line(start, end * 0.9, color, thickness)

	var dir = (end - start).normalized()
	var arrow_size = thickness * 4.0
	var p1 = end - dir * arrow_size + dir.orthogonal() * arrow_size * 0.6
	var p2 = end - dir * arrow_size - dir.orthogonal() * arrow_size * 0.6
	draw_colored_polygon(PackedVector2Array([end, p1, p2]), color)
