extends Node2D

var piece: Node2D

func _ready():
	piece = get_parent()

func resupply_from(ally):
	var gap       = piece.get_max_resources() - piece.get_resources()
	# Ally keeps back their reserve — they won't give away their last N resources
	var available = ally.get_resources() - ally.supplier_reserve
	if gap <= 0 or available <= 0:
		return
	var take = min(gap, available)
	ally.deplete(take)
	piece.restore(take)
