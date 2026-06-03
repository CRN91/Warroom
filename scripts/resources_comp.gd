extends Node2D
class_name Resources

@export var MAX_RESC := 100
@export var resupply_rate := 0
@export var daily_deplete := 0
var resources: int

func _ready():
	resources = MAX_RESC

func get_resources(): return resources
func get_max_resources(): return MAX_RESC
func set_max_resources(x): MAX_RESC = x
func set_resupply_rate(x): resupply_rate = x

func deplete(x) -> bool:
	resources -= x
	print("deplete")
	print(resources)
	return resources <= 0

func resupply(x):
	resources = min(resources + x, MAX_RESC)

## Called once per game day. Returns true if the unit starved (resources <= 0).
func clock_cycle():
	if resupply_rate > 0:
		resupply(resupply_rate)
		return false
	else:
		return deplete(daily_deplete)
