extends Node2D
class_name Resupply

@export var supplier_rank: int = 1
@export var supplier_reserve: int = 0
@export var can_receive: bool = true

var _piece: Node2D

func _ready():
	_piece = get_parent()

func process_resupply(grid) -> void:
	if not can_receive:
		return
	var hex = _piece.get_hex()
	if not hex:
		return

	var best_donor: Node2D = null
	var best_rank := -1

	for adj in _piece.HEX.axial_neighbours(hex):
		if not grid.Grid.has(adj):
			continue
		var candidate = grid.get_piece(adj)
		if candidate == null:
			continue
		if candidate.team != _piece.team:
			continue
		# Haulers (engineers/trains) auto-load only at the CAPITAL — otherwise
		# a truck parked by a town would siphon back its own deliveries.
		if supplier_rank >= 2 and candidate is City and not candidate.is_capital:
			continue
		var donor_supply = candidate.get_node_or_null("Resupply")
		if donor_supply == null:
			continue
		if donor_supply.supplier_rank > supplier_rank and donor_supply.supplier_rank > best_rank:
			best_donor = candidate
			best_rank = donor_supply.supplier_rank

	if best_donor:
		receive_from(best_donor)

func receive_from(donor: Node2D) -> void:
	var gap = _piece.get_max_resources() - _piece.get_resources()
	var donor_res = donor.get_node_or_null("Resupply")
	var reserve: int = donor_res.supplier_reserve if donor_res else 0

	# A unit donor must always keep at least 1 supply — a transfer can never
	# kill it. (Cities can be drained to zero; they don't die, they just starve.)
	if not (donor is City):
		reserve = max(reserve, 1)

	var available = donor.get_resources() - reserve
	if gap <= 0 or available <= 0:
		return

	var take = min(gap, available)
	donor.deplete(take)
	_piece.replenish(take)
	if take > 0 and _piece.has_method("mark_resupplied"):
		_piece.mark_resupplied()

func supply_to(target: Node2D) -> void:
	var target_supply = target.get_node_or_null("Resupply")
	if target_supply:
		target_supply.receive_from(_piece)

func can_supply_to(other: Node2D) -> bool:
	var other_supply = other.get_node_or_null("Resupply")
	if other_supply == null:
		return false
	return supplier_rank > other_supply.supplier_rank and \
		   _piece.get_resources() > supplier_reserve
