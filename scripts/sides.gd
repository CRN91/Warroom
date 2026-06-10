class_name Sides
extends RefCounted

## Alliance logic. Teams group into SIDES:
##   side 1 — the player (team 1)
##   side 2 — the enemy (team 2) and the coalition (team 3, orange)
## Hostility is between sides, so coalition troops never fight their ally.

static func side_of(team: int) -> int:
	match team:
		1: return 1
		2, 3: return 2
		_: return 0

static func hostile(team_a: int, team_b: int) -> bool:
	var a := side_of(team_a)
	var b := side_of(team_b)
	return a != b and a != 0 and b != 0

static func allied(team_a: int, team_b: int) -> bool:
	return side_of(team_a) == side_of(team_b)
