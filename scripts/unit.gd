extends Node2D
class_name Unit

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()
var grid: Node 
func setup(p_grid: Node): grid = p_grid

# Back-reference to the Game node, set right after spawn. Gives units (and cards
# that target them) access to game.modifiers etc. Null-safe everywhere it's used.
var game: Node = null

# Used by modifier scopes like "type:infantry" and "tag:elite". Set this per unit
# scene (e.g. "infantry", "artillery", "logistics") or via a spawn/transform card.
@export var unit_type: String = ""
var tags: Array = []

# ── Action ────────────────────────────────────────────────────────────────────

var frozen: bool = false
func is_frozen(): return frozen
func unfreeze(): frozen = false
func freeze(): frozen = true

# ── Movement ──────────────────────────────────────────────────────────────────

@onready var movement_comp = $Movement
func get_hex(): return movement_comp.get_hex()
func set_destination(hex): movement_comp.set_goal(hex)
func clear_destination(): movement_comp.clear_goal()
func add_waypoint(hex): movement_comp.add_waypoint(hex)
func move_to(hex): movement_comp.move_to(hex, grid)

var use_manual_path: bool = false
func toggle_path_mode():
	if movement_comp:
		use_manual_path = not use_manual_path
		if use_manual_path:
			movement_comp.clear_goal()
		else:
			movement_comp.clear_path()

func process_movement():
	if not get_hex() or is_frozen(): return
	movement_comp.process_movement(grid)

# ── Resources ─────────────────────────────────────────────────────────────────

@onready var resource_comp = $Resources

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
func set_attack_target(piece): return attack_comp.set_target(piece)
func get_attack_target(): return attack_comp.get_target(grid)
func clear_attack_target(): return attack_comp.clear_target()
func get_attack_range(): return attack_comp.get_range()  if attack_comp else 1
func get_damage():
	var base = attack_comp.get_damage() if attack_comp else 0
	# Apply any "attack" modifiers scoped to this unit (buffs, weather, debuffs).
	if game and game.modifiers:
		return int(round(game.modifiers.get_value("attack", float(base), self)))
	return base
func attack(enemy): return attack_comp.attack(enemy) if attack_comp else false

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

	if use_manual_path:
		extras += " | MANUAL PATH (%d waypoints)" % movement_comp.path.size()
	elif movement_comp.goal:
		extras += " | Auto → %s" % str(movement_comp.goal)

	return "Hex: %s | %s | HP: %d/%d%s" % [
		get_hex(), name, get_resources(), get_max_resources(), extras
	]
