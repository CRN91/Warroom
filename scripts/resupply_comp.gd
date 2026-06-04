## ResupplyComp — attached to units that participate in the logistics chain.
## A unit with this component can either give supplies, receive them, or both,
## depending on supplier_rank and can_receive.
##
## Rank hierarchy (configure per unit type in the editor):
##   3 = City          — top-level source, gives only
##   2 = Train/Logi    — mid-tier, takes from rank 3, gives to rank 1
##   1 = Infantry/etc  — leaf consumers, takes from rank 2+
##
## Units without this component (e.g. Rail) are invisible to the supply chain.

extends Node2D
class_name Resupply

## How authoritative this unit is as a supply source.
## Higher rank can donate to lower rank. Equal ranks do not supply each other.
@export var supplier_rank: int = 1

## Minimum reserves this unit keeps before donating to others.
@export var supplier_reserve: int = 0

## Whether this unit can receive supplies from higher-ranked neighbours.
## Set false for Cities — they are pure sources, not consumers of the chain.
@export var can_receive: bool = true

var _piece: Node2D

func _ready():
	_piece = get_parent()

## Each turn: scan neighbours and pull supplies from the best available donor.
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
		var donor_supply = candidate.get_node_or_null("Resupply")
		if donor_supply == null:
			continue
		if donor_supply.supplier_rank > supplier_rank and donor_supply.supplier_rank > best_rank:
			best_donor = candidate
			best_rank = donor_supply.supplier_rank

	if best_donor:
		receive_from(best_donor)

## Pull supplies from a specific donor unit. Called either by process_resupply
## or directly (e.g. Train loading at a terminus).
func receive_from(donor: Node2D) -> void:
	var gap = _piece.get_max_resources() - _piece.get_resources()
	var donor_res = donor.get_node_or_null("Resupply")
	var reserve = donor_res.supplier_reserve if donor_res else 0
	var available = donor.get_resources() - reserve

	if gap <= 0 or available <= 0:
		return

	var take = min(gap, available)
	donor.deplete(take)
	_piece.replenish(take)

## Donate supplies to a specific target unit. Convenience wrapper used by
## Train._exchange_supplies so the call reads clearly at the call site.
func supply_to(target: Node2D) -> void:
	var target_supply = target.get_node_or_null("Resupply")
	if target_supply:
		target_supply.receive_from(_piece)

## Returns true if this unit outranks another and has surplus to give.
func can_supply_to(other: Node2D) -> bool:
	var other_supply = other.get_node_or_null("Resupply")
	if other_supply == null:
		return false
	return supplier_rank > other_supply.supplier_rank and \
		   _piece.get_resources() > supplier_reserve
