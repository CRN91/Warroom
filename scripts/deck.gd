extends Node2D

class_name Deck

@onready var queue: Array = []

func pop():
	return queue.pop_front()

func size():
	return queue.size()

func is_empty():
	return queue.is_empty()

func push(x):
	queue.push_back(x)

func _to_string():
	return str(queue)

# Loading decks from save files
func load():
	var file = FileAccess.open("res/deck.txt", FileAccess.READ)
	var content = file.get_as_text()
	
