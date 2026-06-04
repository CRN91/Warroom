extends Node2D
class_name Resources

@export var MAX_RESC := 100
@export var replenish_rate := 0
@export var deplete_rate := 0
var resources: int

func _ready():
	resources = MAX_RESC

func get_resources(): return resources
func get_max_resources(): return MAX_RESC
func set_max_resources(x): MAX_RESC = x
func set_replenish_rate(x): replenish_rate = x
func get_space() -> int: return MAX_RESC - resources

func deplete(x) -> bool:
	resources -= x
	return resources <= 0

func replenish(x):
	resources = min(resources + x, MAX_RESC)

## Called once per game day. Returns true if the unit starved (resources <= 0).
func clock_cycle() -> bool:
	if replenish_rate > 0:
		replenish(replenish_rate)
		return false
	else:
		return deplete(deplete_rate)

## Drain without the daily replenish — used when siege suppresses city income.
func clock_cycle_depleting_only() -> bool:
	return deplete(deplete_rate)
