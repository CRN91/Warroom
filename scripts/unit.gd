extends Node2D
class_name Unit

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

# Team: 1 = Player, 2 = Enemy, 0 = Neutral
var team: int = 1
var allied: bool:
	get: return team == 1
	set(value): team = 1 if value else 2

var frozen: bool = false
var supplier: int = 0
var supplier_reserve: int = 0
var path: Array = []
var use_manual_path: bool = false

@onready var movement_comp = $Movement
@onready var resource_comp = $Resources
@onready var attack_comp   = get_node_or_null("Attack")
@onready var resupply_comp = get_node_or_null("Resupply")

# ── Targeting ─────────────────────────────────────────────────────────────────
var target: Node2D = null
var pending_attack: Node2D = null

# ── Navigation ────────────────────────────────────────────────────────────────
# Units store only a goal hex. A* is re-run each turn so obstacles are
# avoided dynamically. No stale pre-calculated path arrays.
var goal = null  # Vector2i destination, or null if idle

# ── Identity ──────────────────────────────────────────────────────────────────
func is_allied(): return team == 1
func combatant(): return false
func is_frozen(): return frozen
func unfreeze(): frozen = false
func get_hex(): return movement_comp.get_hex()
func get_resources(): return resource_comp.get_resources()
func get_max_resources(): return resource_comp.get_max_resources()
func deplete(x): return resource_comp.deplete(x)
func restore(x): resource_comp.resupply(x)
func set_enemy():   team = 2
func set_neutral(): team = 0
func set_player():  team = 1
func get_attack_range(): return attack_comp.get_range()  if attack_comp else 0
func get_damage():       return attack_comp.get_damage() if attack_comp else 0
func attack(enemy):      return attack_comp.attack(enemy) if attack_comp else false
func resupply_from(ally):
	if resupply_comp:
		resupply_comp.resupply_from(ally)

# ── Navigation API ────────────────────────────────────────────────────────────

## Set a multi-turn navigation destination.
## A* is recalculated every turn so the route adapts to moving obstacles.
func set_goal(hex):
	goal = hex

func clear_goal():
	goal = null

## Toggles between manual waypoint mode and auto A* mode.
## Clears the inactive mode's state when switching.
func toggle_path_mode():
	use_manual_path = not use_manual_path
	if use_manual_path:
		clear_goal()   # Switching to manual — drop the A* goal
	else:
		clear_path()   # Switching to auto — drop the waypoints

func add_waypoint(hex):
	path.append(hex)

func clear_path():
	path.clear()

# ── Combat API ────────────────────────────────────────────────────────────────

func get_attack_target(grid) -> Node2D:
	# 1. Clean up dead targets to avoid crashes
	if target and not is_instance_valid(target): target = null
	if pending_attack and not is_instance_valid(pending_attack): pending_attack = null

	# 2. Manual attacks ordered this turn take priority
	if pending_attack:
		var t = pending_attack
		pending_attack = null
		return t
		
	# 3. If we already moved (frozen), we cannot auto-attack this turn
	if is_frozen(): return null
	
	# 4. Check if our sticky target is still in range
	if target:
		if HEX.axial_distance(get_hex(), target.get_hex()) <= get_attack_range():
			return target
			
	# 5. Otherwise, scan for a new target
	return _find_enemy_in_range(grid)

func _find_enemy_in_range(grid) -> Node2D:
	var possible: Array = []
	for hex in HEX.axial_radius(get_hex(), get_attack_range()):
		if not grid.Grid.has(hex): continue
		var piece = grid.get_piece(hex)
		if piece and piece.team != team:
			possible.append(piece)
			
	if possible.is_empty(): return null
	
	# Priority targeting: Combatants > Logistics > Anything else (Cities)
	for t in possible:
		if t.combatant(): return t
	for t in possible:
		if t is Logistics: return t
	return possible[0]

func set_target(enemy: Node2D):
	if frozen: return
	frozen        = true
	pending_attack = enemy
	target         = enemy

func clear_target():
	target        = null
	pending_attack = null

# ── Daily tick ────────────────────────────────────────────────────────────────

func next_day() -> bool:
	return resource_comp.clock_cycle()

func resupply(supply_source: Node2D):
	if not frozen:
		frozen = true
		resupply_comp.resupply_from(supply_source)

# ── Movement ──────────────────────────────────────────────────────────────────

func process_movement(game):
	var grid = game.grid
	var current_hex = get_hex()
	if not current_hex or is_frozen(): return

	# Manual pathing check
	if path.size() > 0:
		var next_hex = path[0]
		if grid.get_piece(next_hex) == null:
			move_to(next_hex, current_hex, grid)
			path.pop_front()
	# Auto pathing check
	elif goal != null:
		if current_hex == goal:
			clear_goal()
		else:
			var goal_piece = grid.get_piece(goal)
			grid.enable_hex(current_hex)
			if goal_piece: grid.enable_hex(goal)

			var astar_path = grid.get_map_path(current_hex, goal)

			grid.disable_hex(current_hex)
			if goal_piece: grid.disable_hex(goal)

			if astar_path.size() > 1:
				move_to(astar_path[1], current_hex, grid)

## Move one step to new_hex from old_hex.
##
## Initial placement (old_hex = null):
##   Positions the unit without spending an action. Used when spawning.
##
## Normal move:
##   Consumes the unit's action (frozen = true). new_hex must be adjacent.
##   If new_hex is occupied the action is returned (frozen = false) and
##   old_hex is re-disabled so A* stays consistent.
func move_to(new_hex, old_hex, grid):
	# ── Initial placement — free action, no adjacency check ──────────────────
	if not old_hex:
		grid.disable_hex(new_hex)
		return movement_comp.set_hex(new_hex, grid)

	# ── Normal move — costs action ────────────────────────────────────────────
	if not frozen:
		frozen = true
		grid.enable_hex(old_hex)  # Unit is leaving — open for pathfinding

		if new_hex in HEX.axial_neighbours(old_hex):
			if grid.get_piece(new_hex) == null:
				grid.disable_hex(new_hex)
				return movement_comp.set_hex(new_hex, grid)
			else:
				# Destination occupied — give back action and re-close old hex
				frozen = false
				grid.disable_hex(old_hex)  # Fix: unit didn't leave, re-block it
		else:
			# Non-adjacent target passed directly — shouldn't happen in goal system
			frozen = false
			grid.disable_hex(old_hex)

	return grid

func status() -> String:
	var extras = ""
	if target and is_instance_valid(target):
		extras += " | Target: %s" % target.name
		
	# MISSING LOGIC ADDED HERE:
	if use_manual_path:
		extras += " | MANUAL PATH (%d waypoints)" % path.size()
	elif goal:
		extras += " | Auto → %s" % str(goal)
		
	return "Hex: %s | %s | HP: %d/%d%s" % [
		get_hex(), name, get_resources(), get_max_resources(), extras
	]
