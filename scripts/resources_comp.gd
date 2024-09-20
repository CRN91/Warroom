extends Node2D
class_name ResourceComponent

@export var MAX_RESC := 100
var resources : int

func _ready():
	resources = MAX_RESC
