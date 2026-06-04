extends Node2D
class_name Unit

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

@onready var movement_comp = $Movement
@onready var resource_comp = $Resources
@onready var resource_bar = get_node_or_null("ResourceBar")
@onready var attack_comp   = get_node_or_null("Attack")
@onready var resupply_comp = get_node_or_null("Resupply")

var team: int = 1 # Team: 1 = Player, 2 = Enemy, 0 = Neutral
var frozen: bool = false
var supplier: int = 0
var supplier_reserve: int = 0
var use_manual_path: bool = false
var _bar_setup_done: bool = false

# ── Targeting ─────────────────────────────────────────────────────────────────
var target: Node2D = null
var pending_attack: Node2D = null

# ── Identity ──────────────────────────────────────────────────────────────────
func combatant(): return false
func is_frozen(): return frozen
func unfreeze(): frozen = false
func get_hex(): return movement_comp.get_hex()
func get_resources(): return resource_comp.get_resources()
func get_max_resources(): return resource_comp.get_max_resources()
func set_enemy():   team = 2
func set_neutral(): team = 0
func set_player():  team = 1
func get_attack_range(): return attack_comp.get_range()  if attack_comp else 0
func get_damage():       return attack_comp.get_damage() if attack_comp else 0
func attack(enemy):      return attack_comp.attack(enemy) if attack_comp else false
func resupply_from(ally):
	if resupply_comp:
		resupply_comp.resupply_from(ally)

func update_ui():
	if resource_bar:
		# 1. Setup the bar styles dynamically (only runs once per unit)
		if not _bar_setup_done:
			# Force the exact size and position
			resource_bar.custom_minimum_size = Vector2(60, 8)
			resource_bar.position = Vector2(-150, -300)
			resource_bar.show_percentage = false
			
			# Create the dark background
			var bg_style = StyleBoxFlat.new()
			bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8) # Dark, semi-transparent grey
			resource_bar.add_theme_stylebox_override("background", bg_style)
			
			# Create the bright fill color
			var fill_style = StyleBoxFlat.new()
			fill_style.bg_color = Color(0.2, 0.7, 0.3, 1.0) # Nice, clean green
			resource_bar.add_theme_stylebox_override("fill", fill_style)
			
			_bar_setup_done = true
			
		# 2. Update the actual values
		resource_bar.max_value = get_max_resources()
		resource_bar.value = get_resources()

# UPDATE these three functions to call update_ui()
func deplete(x): 
	var starved = resource_comp.deplete(x)
	update_ui()
	return starved

func restore(x): 
	resource_comp.resupply(x)
	update_ui()

func toggle_path_mode():
	use_manual_path = not use_manual_path
	if use_manual_path:
		movement_comp.clear_goal()
	else:
		movement_comp.clear_path()
		
func move_to(hex, grid):
	movement_comp.move_to(hex, grid)

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
	var starved = resource_comp.clock_cycle()
	update_ui()
	return starved

func resupply(supply_source: Node2D):
	if not frozen:
		frozen = true
		resupply_comp.resupply_from(supply_source)

# ── Movement ──────────────────────────────────────────────────────────────────

func process_movement(game):
	var grid = game.grid
	if not get_hex() or is_frozen(): return
	movement_comp.process_movement(grid)

func status() -> String:
	var extras = ""
	if target and is_instance_valid(target):
		extras += " | Target: %s" % target.name
		
	# MISSING LOGIC ADDED HERE:
	if use_manual_path:
		extras += " | MANUAL PATH (%d waypoints)" % movement_comp.path.size()
	elif movement_comp.goal:
		extras += " | Auto → %s" % str(movement_comp.goal)
		
	return "Hex: %s | %s | HP: %d/%d%s" % [
		get_hex(), name, get_resources(), get_max_resources(), extras
	]
	
func interact_with_ally(ally: Node2D):
	if supplier > ally.supplier:
		ally.resupply_from(self)
	elif ally.supplier > supplier:
		resupply_from(ally)
