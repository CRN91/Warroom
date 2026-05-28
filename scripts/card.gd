extends Node2D

class_name Card

var type

func set_type(card_type):
	match card_type:
		"intel":
			type = 0
		"event":
			type = 1
		"decision":
			type = 2
