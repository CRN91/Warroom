extends Node2D
class_name Resources

@export var MAX_RESC := 100
var resources : int # Current resources

func _ready():
	resources = MAX_RESC
	print("check ready, "+str(resources))
	
func get_resources():
	return resources
	
func deplete(x):
	resources -= x
	if resources < 0:
		resources = 0

func resupply(x):
	resources += x
	if resources > MAX_RESC:
		resources = MAX_RESC


