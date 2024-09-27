extends Node2D

@export var piece: Node2D

func resupply(ally):
	var piece_max_resources = piece.get_max_resources()
	var resource_gap = piece_max_resources - piece.get_resources()
	var ally_resources = ally.get_resources()
	var take: int
	
	# Scenario where piece is fully resupplied
	if ally_resources > resource_gap:
		take = resource_gap
	# Scenario where piece is not fully resupplied
	else:
		take = ally_resources
	
	ally.deplete(take)
	piece.restore(take)
		
