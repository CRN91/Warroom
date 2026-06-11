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

# Reference prices (shop cards carry their own costs; the enemy AI budgets
# against these).
const COST := {
	"infantry":  600,
	"artillery": 900,
	"logistics": 500,
	"rail":      100,
	"train":     600,
	"bridge":    400,
	"tunnel":    800,
}

var units: Array = []
var cities: Array = []
var trains: Array = []

var state: Dictionary = {}             # story flags set by cards ("prepared_for_winter", ...)
var recent_death_hexes: Array = []     # no respawning on a hex something just died on
var purchase_city: Node2D = null       # context for "near": "purchased_city" spawns

# Generated company names — small, flavourful, renameable by the player.
const NAME_ORDINALS := ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th",
	"9th", "11th", "13th", "17th", "21st", "42nd"]
const NAME_REGIONS := ["Lowland", "Greymoor", "Ashvale", "Northern", "Veldt",
	"Brennish", "Kalten", "Eastmark", "Hollow Vale"]
const NAME_CORPS := {
	"infantry":  ["Rifles", "Fusiliers", "Grenadiers", "Foot", "Pickets"],
	"artillery": ["Battery", "Guns", "Howitzers", "Field Guns"],
	"logistics": ["Sappers", "Pioneers", "Supply Corps", "Field Engineers"],
}

var s: GameServices

# city -> Array of { "unit": Node2D, "weeks": int } resting inside it
var garrisons: Dictionary = {}
const REST_WEEKS := 6
const ENGINEER_RESERVE := 20
const HARASSMENT := 20          # weekly partisan toll on haulers in hostile paint
const SURRENDER_WEEKS := 3      # cut off + empty for this long -> the city yields

func setup(services: GameServices) -> void:
	s = services
	s.rail_network.train_created.connect(_on_train_created)
	Events.city_captured.connect(_on_city_changed_hands)

# ── Registration / dependency injection ───────────────────────────────────────

func register_unit(unit: Node2D) -> void:
	unit.inject(s.grid, s.modifiers, s.terrain)
	units.append(unit)

func register_city(city: Node2D) -> void:
	city.inject(s.grid, s.modifiers, s.terrain)
	cities.append(city)

func _on_train_created(train: Node2D) -> void:
	train.inject(s.grid, s.modifiers, s.terrain)
	train._apply_team_shade()   # trains bypass add_unit, so shade them here
	trains.append(train)
	units.append(train)

# ── Scenario helpers (used by Game.gd to lay out the start) ───────────────────

func add_unit(type: String, hex: Vector2i, team: int = 1) -> Node2D:
	var unit: Node2D = UNIT_SCENES[type].instantiate()
	add_child(unit, true)
	unit.setup(s.grid)
	register_unit(unit)
	unit.unit_type = type
	unit.name = generate_unit_name(type)
	match team:
		2: unit.set_enemy()
		3: unit.set_coalition()
		0: unit.set_neutral()
		_: unit.set_player()   # every unit gets shaded from the same constants
	unit.move_to(hex)
	if unit.get_hex() == null:
		# Placement failed (hex occupied/invalid) — don't leave a ghost piece.
		units.erase(unit)
		unit.queue_free()
		return null
	unit.update_ui()   # bar gets sized/styled now that the unit knows the board scale
	return unit

func add_city(city_name: String, hex: Vector2i, team: int, capital: bool = false) -> Node2D:
	var city: Node2D = CITY.instantiate()
	add_child(city, true)
	city.setup(s.grid)
	register_city(city)
	city.name = city_name
	city.is_capital = capital

	# Hub-and-spoke economy: the CAPITAL is the engine. Towns trickle — they're
	# forward tanks that only matter when stock is HAULED to them (engineers
	# delivering, trains automating the run).
	if capital:
		city.resource_comp.replenish_rate = 80
	else:
		city.resource_comp.set_max_resources(400)
		city.resource_comp.replenish_rate = 5
		city.resource_comp.resources = 120
	_fit_city_scale(city, capital)

	match team:
		2: city.set_enemy()
		0: city.set_neutral()
		_: city.set_player()
	city.set_hex(hex)
	city.update_ui()
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
		if effect.has("grant_attack"):  _grant_attack(p, effect["grant_attack"])
		for m in effect.get("modifiers", []):
			var mm: Dictionary = m.duplicate(true)
			mm["scope"] = "unit:%d" % p.get_instance_id()
			s.modifiers.add_modifier(mm)
		p.update_ui()
		done += 1

func generate_unit_name(type: String) -> String:
	var corps: Array = NAME_CORPS.get(type, ["Company"])
	var n: String = "%s %s" % [
		NAME_ORDINALS[randi() % NAME_ORDINALS.size()],
		corps[randi() % corps.size()],
	]
	if randf() < 0.6:
		var bits := n.split(" ")
		n = "%s %s %s" % [bits[0], NAME_REGIONS[randi() % NAME_REGIONS.size()], bits[1]]
	return n

# City art can be any resolution (32px pixel art, old 370px renders, anything):
# the sprite is scaled so the city spans a consistent share of the hex.
const CAPITAL_HEX_SHARE := 0.88   # capitals dominate their hex
const TOWN_HEX_SHARE := 0.64      # towns sit smaller
const HEX_WIDTH := 500.0          # world width of one hex cell

func _fit_city_scale(city: Node2D, capital: bool) -> void:
	var spr = city.get_node_or_null("Sprite2D")
	if spr == null or spr.texture == null:
		return
	var art_w: float = maxf(1.0, spr.texture.get_width())
	var target: float = HEX_WIDTH * (CAPITAL_HEX_SHARE if capital else TOWN_HEX_SHARE)
	city.scale = Vector2.ONE * (target / art_w)

func _grant_attack(piece: Node2D, spec: Dictionary) -> void:
	## Gives a non-combat piece a real Attack component (e.g. the armoured
	## train). Pair with add_tags: ["combatant"] so is_combatant() flips too.
	if piece.attack_comp != null:
		piece.attack_comp.damage = int(spec.get("damage", piece.attack_comp.damage))
		piece.attack_comp.attack_range = int(spec.get("range", piece.attack_comp.attack_range))
		return
	var a := Attack.new()
	a.name = "Attack"
	a.damage = int(spec.get("damage", 40))
	a.attack_range = int(spec.get("range", 1))
	piece.add_child(a)
	piece.attack_comp = a

# ── Spawn-location helpers ────────────────────────────────────────────────────

func resolve_center(near):
	## Turns a card's "near" value into a hex: [q, r], "player_capital",
	## "enemy_capital", "purchased_city", or a city name.
	if near is Array and near.size() == 2:
		var hex := Vector2i(int(near[0]), int(near[1]))
		return hex if s.grid.Grid.has(hex) else null
	if near == "player_capital":
		var capital := player_capital()
		return capital.get_hex() if capital else null
	if near == "enemy_capital":
		var capital := enemy_capital()
		return capital.get_hex() if capital else null
	if near == "purchased_city":
		if purchase_city:
			return purchase_city.get_hex()
		var capital := player_capital()
		return capital.get_hex() if capital else null
	var c := find_city_by_name(str(near))
	return c.get_hex() if c else null

func _resolve_spawn_hex(near):
	# Exact coordinates spawn on the spot when free
	if near is Array and near.size() == 2:
		var hex := Vector2i(int(near[0]), int(near[1]))
		if s.grid.Grid.has(hex) and get_piece(hex) == null:
			return hex
	var center = resolve_center(near)
	if center == null:
		return null
	return _free_hex_near(center)

func _free_hex_near(center: Vector2i):
	# axial_radius is ordered nearest-first, so adjacent hexes are preferred
	for adj in HEX.axial_radius(center, 2):
		if not s.grid.Grid.has(adj): continue
		if get_piece(adj) != null: continue
		if s.rail_network.rail_hexes.has(adj): continue
		if adj in recent_death_hexes: continue
		if s.terrain.is_mountain(adj): continue
		return adj
	return null

# ── Garrison rest (rotation) ──────────────────────────────────────────────────

func garrison_unit(unit: Node2D) -> bool:
	## Sends a worn division into an adjacent friendly city to rest for
	## REST_WEEKS. Off the board, safe — unless the city falls, then it's lost.
	var city := _adjacent_friendly_city(unit)
	if city == null:
		Events.notify("No adjacent friendly city to rest in.")
		return false

	# Clear orders FIRST — these refresh intent arrows, which need a valid
	# hex. Only then take the unit off the board.
	unit.clear_movement()
	unit.set_attack_target(null)
	var hex = unit.get_hex()
	if hex != null and s.grid.Grid.has(hex):
		s.grid.set_piece(hex, null)
		s.grid.enable_hex(hex)
	unit.movement_comp.hex = null
	unit.visible = false
	units.erase(unit)

	if not garrisons.has(city):
		garrisons[city] = []
	garrisons[city].append({ "unit": unit, "weeks": REST_WEEKS })
	if unit.team == 1:
		Events.notify("%s stands down in %s (%d weeks)." % [unit.name, city.name, REST_WEEKS])
	s.fow.update_fow()
	return true

func tick_garrisons() -> void:
	for city in garrisons.keys():
		if not is_instance_valid(city):
			garrisons.erase(city)
			continue
		var entries: Array = garrisons[city]
		for i in range(entries.size() - 1, -1, -1):
			entries[i]["weeks"] -= 1
			if entries[i]["weeks"] <= 0:
				if _redeploy(entries[i]["unit"], city):
					entries.remove_at(i)
				else:
					entries[i]["weeks"] = 1   # no room yet — try again next week
		if entries.is_empty():
			garrisons.erase(city)

func _redeploy(unit: Node2D, city: Node2D) -> bool:
	var hex = _free_hex_near(city.get_hex())
	if hex == null or not is_instance_valid(unit):
		return hex != null
	units.append(unit)
	unit.visible = true
	unit.move_to(hex)
	unit.reset_deployment()
	unit.unfreeze()
	# Refit from the city's actual stores — rest costs the economy
	var need: int = unit.get_max_resources() - unit.get_resources()
	var take: int = mini(need, city.get_resources())
	if take > 0:
		city.deplete(take)
		unit.replenish(take)
		unit.mark_resupplied()
	if unit.team == 1:
		Events.notify("%s returns to the field, rested." % unit.name)
	s.fow.update_fow()
	return true

func garrisoned_in(city: Node2D) -> Array:
	return garrisons.get(city, [])

func _on_city_changed_hands(city: Node2D, _by_team: int, _prev: int) -> void:
	_lose_garrison(city, "fall")
	# Nobody keeps shelling a city that just joined their side: clear every
	# stale lock on it the moment it flips (combat cleanup also does this,
	# but clearing at the source keeps intent arrows honest immediately).
	for unit in units:
		if not is_instance_valid(unit): continue
		var ac = unit.get("attack_comp")
		if ac == null: continue
		if (ac.target == city or ac.pending_attack == city) and not Sides.hostile(unit.team, city.team):
			ac.clear_target()
			if unit.has_method("refresh_intent"):
				unit.refresh_intent()

func scrub_grid() -> void:
	## Safety sweep: if a freed piece ever leaks a reference into a grid cell,
	## it blocks movement invisibly (freed != null) while drawing nothing.
	## Clear any such ghosts each turn.
	for hex in s.grid.Grid:
		var p = s.grid.Grid[hex]["Piece"]
		if p != null and not is_instance_valid(p):
			s.grid.Grid[hex]["Piece"] = null
			s.grid.enable_hex(hex)
			push_warning("Board: cleared ghost piece at %s" % str(hex))

func _lose_garrison(city: Node2D, _why: String) -> void:
	if not garrisons.has(city):
		return
	for entry in garrisons[city]:
		var u = entry["unit"]
		if is_instance_valid(u):
			Events.report("%s was lost in the fall of %s." % [u.name, city.name])
			u.queue_free()
	garrisons.erase(city)

func _adjacent_friendly_city(unit: Node2D) -> Node2D:
	var hex = unit.get_hex()
	if hex == null: return null
	for adj in HEX.axial_neighbours(hex):
		if not s.grid.Grid.has(adj): continue
		var p = s.grid.get_piece(adj)
		if p is City and p.team == unit.team:
			return p
	return null

# ── Hauling & harassment ──────────────────────────────────────────────────────

func deliver_cargo(unit: Node2D) -> void:
	## Engineers unload everything above their reserve into an adjacent
	## friendly city. The explicit half of the supply line (trains automate it).
	var city := _adjacent_friendly_city(unit)
	if city == null:
		Events.notify("No adjacent friendly city to deliver to.")
		return
	var deposit: int = mini(unit.get_resources() - ENGINEER_RESERVE,
		city.get_max_resources() - city.get_resources())
	if deposit <= 0:
		Events.notify("Nothing to deliver (or %s is full)." % city.name)
		return
	unit.deplete(deposit)
	city.replenish(deposit)
	unit.recent_deposit = city   # don't auto-pull this delivery straight back out
	if unit.team == 1:
		Events.notify("%s delivered %d supplies to %s." % [unit.name, deposit, city.name])

func harass_haulers() -> void:
	## Partisans bleed supply convoys that end the week on hostile paint, or
	## near a holdout enemy city behind the line. Friendly paint is safe;
	## no-man's-land is clean — its danger is the guns pointing at it.
	for unit in units:
		if not is_instance_valid(unit): continue
		var sup = unit.get_node_or_null("Resupply")
		if sup == null or sup.supplier_rank < 2: continue   # only haulers
		var hex = unit.get_hex()
		if hex == null: continue

		var hostile_ground: bool = s.control.is_hostile_ground(hex, unit.team)
		if not hostile_ground and not _near_holdout_city(hex, unit.team):
			continue
		var loss: int = mini(HARASSMENT, unit.get_resources() - 1)
		if loss > 0:
			unit.deplete(loss)
			if unit.team == 1:
				Events.report("Partisans harassed %s — %d supplies lost." % [unit.name, loss])

func _near_holdout_city(hex, team: int) -> bool:
	for c in cities:
		if not is_instance_valid(c): continue
		if not Sides.hostile(team, c.team): continue
		if not c.cut_off: continue
		if HEX.axial_distance(hex, c.get_hex()) <= 2:
			return true
	return false

# ── Sieges ────────────────────────────────────────────────────────────────────

func check_sieges() -> void:
	## A city cut off from its capital and starved empty eventually yields to
	## whoever surrounds it — sieges end without a final assault.
	for city in cities.duplicate():
		if not is_instance_valid(city) or city.is_capital: continue
		if city.cut_off and city.get_resources() <= 0:
			city.surrender_weeks += 1
			if city.surrender_weeks == 1 and Sides.side_of(city.team) == 2:
				Events.notify("%s is starving under siege." % city.name)
			if city.surrender_weeks >= SURRENDER_WEEKS:
				var captor: int = 1 if Sides.side_of(city.team) == 2 else 2
				Events.report("%s surrendered after a %d-week siege." % [city.name, SURRENDER_WEEKS])
				city.capture(captor)
		else:
			city.surrender_weeks = 0

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
		_lose_garrison(dead_piece, "destruction")
		if dead_piece.is_capital:
			Events.game_over.emit(dead_piece.team == 1, "%s has fallen. The war is over." % dead_piece.name)
	else:
		units.erase(dead_piece)
		trains.erase(dead_piece)

	s.modifiers.remove_modifier("fatigue_%d" % dead_piece.get_instance_id())
	Events.unit_died.emit(dead_piece)
	dead_piece.queue_free()
