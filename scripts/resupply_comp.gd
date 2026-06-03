extends Node2D

var piece: Node2D

func _ready():
	piece = get_parent()

# NEW: The unit scans its own neighbors and pulls supply
func process_resupply(grid):
	var hex = piece.get_hex()
	if not hex: return
	
	var HEX = piece.HEX
	for adj in HEX.axial_neighbours(hex):
		if grid.Grid.has(adj) and grid.get_piece(adj):
			var ally = grid.get_piece(adj)
			# If the neighbor is friendly and is a higher-tier supplier (like a City or Logi)
			if ally.team == piece.team and ally.supplier > piece.supplier:
				resupply_from(ally)

func resupply_from(ally):
	var gap       = piece.get_max_resources() - piece.get_resources()
	var available = ally.get_resources() - ally.supplier_reserve
	if gap <= 0 or available <= 0:
		return
	var take = min(gap, available)
	ally.deplete(take)
	piece.restore(take)
