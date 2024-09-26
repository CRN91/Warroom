extends Node2D
class_name Resources

@export var MAX_RESC := 100
var resupply_rate := 0
var resources : int # Current resources

func _ready():
	resources = MAX_RESC
	
func get_resources():
	return resources
	
func deplete(x):
	resources -= x
	if resources <= 0:
		print("true deplete")
		return true
	else:
		return false

func set_max_resources(x):
	MAX_RESC = x
	
func get_max_resources():
	return MAX_RESC

func set_resupply_rate(x):
	resupply_rate = x

func resupply(x):
	print(resources)
	resources += x
	if resources > MAX_RESC:
		resources = MAX_RESC
	print(resources)
# Called once per game day
func clock_cycle():
	resupply(resupply_rate)


