extends Node2D
class_name Board

## The single owner of every piece on the map: units, cities and trains.
## All spawning, purchasing, transformation and death goes through here.
## Spawned pieces get their dependencies (grid, modifiers, terrain) injected
## at registration so they never need a reference back to Game.

const HEXGRID = preload("res://Hexgrid/hex.gd")
var HEX = HEXGRID.new()

const UNIT_SCENES := {
	"infantry":  preload("res://scenes/infantry.tscn"),
	"artillery": preload("res://scenes/artillery.tscn"),
	"logistics": preload("res://scenes/logistics.tscn"),
}
const CITY = preload("res://scenes/city.tscn")

const COST := {
	"infantry":  800,
	"artillery": 1000,
	"logistics": 800,
	"rail":      100,
	"train":     800,
	"bridge":    400,
	"tunnel":    800,
}

var units: Array = []
var cities: Array = []
var trains: Array = []

var state: Dictionary = {}             # story flags set by cards ("prepared_for_winter", ...)
var recent_death_hexes: Array = []     # no respawning on a hex something just died on
var purchase_city: Node2D = null       # context for "near": "purchased_city" spawns

var s: GameServices

func setup(services: GameServices) -> void:
	s = services
	s.rail_network.train_created.connect(_on_train_created)

# ── Registration / dependency injection ───────────────────────────────────────

func register_unit(unit: Node2D) -> void:
	unit.inject(s.grid, s.modifiers, s.terrain)
	units.append(unit)

func register_city(city: Node2D) -> void:
	city.inject(s.grid, s.modifiers, s.terrain)
	cities.append(city)

func _on_train_created(train: Node2D) -> void:
	train.inject(s.grid, s.modifiers, s.terrain)
	trains.append(train)
	units.append(train)

# ── Scenario helpers (used by Game.gd to lay out the start) ───────────────────

func add_unit(type: String, hex: Vector2i, team: int = 1) -> Node2D:
	var unit: Node2D = UNIT_SCENES[type].instantiate()
	add_child(unit, true)
	unit.setup(s.grid)
	register_unit(unit)
	unit.unit_type = type
	if team == 2: unit.set_enemy()
	unit.move_to(hex)
	return unit

func add_city(city_name: String, hex: Vector2i, team: int, capital: bool = false) -> Node2D:
	var city: Node2D = CITY.instantiate()
	add_child(city, true)
	city.setup(s.grid)
	register_city(city)
	city.name = city_name
	city.is_capital = capital
	match team:
		2: city.set_enemy()
		0: city.set_neutral()
		_: city.set_player()
	city.set_hex(hex)
	return city

# ── Purchasing ────────────────────────────────────────────────────────────────
# There is deliberately no open shop: the player acquires units and stock only
# through cards (paid supply offers, the periodic requisition, story rewards).
# The enemy AI buys through spawn_unit_near_city directly.

func spawn_unit_near_city(type: String, city: Node2D) -> Node2D:
	var hex = _free_hex_near(city.get_hex())
	if hex == null:
		Events.notify("No free hex adjacent to %s." % city.name)
		return null
	var unit := add_unit(type, hex, city.team)
	s.fow.update_fow()
	return unit

func execute_purchase(city: Node2D, cost: int, effects: Array) -> void:
	## A decision-card purchase: the chosen city pays, then the effects run with
	## that city available as the "purchased_city" spawn anchor.
	city.deplete(cost)
	purchase_city = city
	s.card_manager.resolver.resolve(effects)
	purchase_city = null

# ── Card-driven board changes ─────────────────────────────────────────────────

func spawn_unit(effect: Dictionary) -> Node2D:
	var type: String = effect.get("unit", "infantry")
	var team: int = int(effect.get("team", 1))

	var hex = _resolve_spawn_hex(effect.get("near", "player_capital"))
	if hex == null:
		Events.notify("No room to deploy %s." % type)
		return null

	var unit := add_unit(type, hex, team)
	unit.unit_type = effect.get("unit_type", type)

	if effect.has("name"):           unit.name = effect["name"]
	if effect.has("tags"):           unit.tags = effect["tags"].duplicate()
	if effect.has("max_resources"):  unit.resource_comp.set_max_resources(int(effect["max_resources"]))
	if effect.get("fill", false):    unit.replenish(unit.get_max_resources())

	for m in effect.get("modifiers", []):
		var mm: Dictionary = m.duplicate(true)
		mm["scope"] = "unit:%d" % unit.get_instance_id()
		s.modifiers.add_modifier(mm)

	s.fow.update_fow()
	return unit

func transform_units(effect: Dictionary) -> void:
	var scope: String = effect.get("scope", "player")
	var pieces: Array = s.modifiers.select_pieces(units, cities, scope)
	if effect.get("combatants_only", false):
		pieces = pieces.filter(func(p): return p.has_method("is_combatant") and p.is_combatant())
	var count: int = int(effect.get("count", 1))

	var done := 0
	for p in pieces:
		if done >= count: break
		if effect.has("unit_type"):     p.unit_type = effect["unit_type"]
		if effect.has("rename"):        p.name = effect["rename"]
		if effect.has("add_tags"):      p.tags.append_array(effect["add_tags"])
		if effect.has("max_resources"): p.resource_comp.set_max_resources(int(effect["max_resources"]))
		if effect.has("set_resources"): p.resource_comp.resources = int(effect["set_resources"])
		if effect.has("replenish"):     p.replenish(int(effect["replenish"]))
		for m in effect.get("modifiers", []):
			var mm: Dictionary = m.duplicate(true)
			mm["scope"] = "unit:%d" % p.get_instance_id()
			s.modifiers.add_modifier(mm)
		p.update_ui()
		done += 1

# ── Spawn-location helpers ────────────────────────────────────────────────────

func _resolve_spawn_hex(near):
	var center = null
	if near is Array and near.size() == 2:
		center = Vector2i(int(near[0]), int(near[1]))
		if s.grid.Grid.has(center) and get_piece(center) == null:
			return center
	elif near == "player_capital":
		var capital := player_capital()
		center = capital.get_hex() if capital else null
	elif near == "enemy_capital":
		var capital := enemy_capital()
		center = capital.get_hex() if capital else null
	elif near == "purchased_city":
		if purchase_city:
			center = purchase_city.get_hex()
		else:
			var capital := player_capital()
			center = capital.get_hex() if capital else null
	else:
		var c := find_city_by_name(str(near))
		center = c.get_hex() if c else null
	if center == null:
		return null
	return _free_hex_near(center)

func _free_hex_near(center: Vector2i):
	for adj in HEX.axial_neighbours(center):
		if not s.grid.Grid.has(adj): continue
		if get_piece(adj) != null: continue
		if s.rail_network.rail_hexes.has(adj): continue
		if adj in recent_death_hexes: continue
		if s.terrain.is_mountain(adj): continue
		return adj
	return null

# ── Queries ───────────────────────────────────────────────────────────────────

func get_piece(hex):
	return s.grid.get_piece(hex)

func find_city_by_name(n: String) -> Node2D:
	for c in cities:
		if c.name == n: return c
	return null

func player_capital() -> Node2D:
	for c in cities:
		if c.is_capital and c.team == 1: return c
	return null

func enemy_capital() -> Node2D:
	for c in cities:
		if c.is_capital and c.team == 2: return c
	return null

func unit_counts_by_type(team: int = -1) -> Dictionary:
	var by_type: Dictionary = {}
	for u in units:
		if not is_instance_valid(u): continue
		if team != -1 and u.team != team: continue
		var t := str(u.get("unit_type"))
		if t != "":
			by_type[t] = int(by_type.get(t, 0)) + 1
	return by_type

# ── Death ─────────────────────────────────────────────────────────────────────

func cull_dead() -> void:
	var to_die: Array = []
	for unit in units:
		if is_instance_valid(unit) and not (unit is City):
			if unit.get_resources() <= 0:
				to_die.append(unit)
	for dead in to_die:
		if is_instance_valid(dead):
			kill(dead)

func kill(dead_piece: Node2D) -> void:
	# Anything targeting the dead piece loses its target.
	for unit in units:
		if is_instance_valid(unit) and unit.get("attack_comp") and unit.attack_comp and unit.attack_comp.target == dead_piece:
			unit.set_attack_target(null)

	var dead_hex = dead_piece.get_hex()
	if dead_hex != null and s.grid.Grid.has(dead_hex):
		s.grid.set_piece(dead_hex, null)
		s.grid.enable_hex(dead_hex)
		if not dead_hex in recent_death_hexes:
			recent_death_hexes.append(dead_hex)

	if dead_piece in cities:
		cities.erase(dead_piece)
		if dead_piece.is_capital:
			Events.game_over.emit(dead_piece.team == 1)
	else:
		units.erase(dead_piece)
		trains.erase(dead_piece)

	Events.unit_died.emit(dead_piece)
	dead_piece.queue_free()
