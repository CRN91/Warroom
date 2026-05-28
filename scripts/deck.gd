extends Node

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

# Loading decks from JSON file
func load():
	var file = FileAccess.open("res://res/deck.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_string)
		
		if error == OK:
			var data = json.data
			for card in data:
				push(card)
			print("SUCCESS: Deck loaded with ", queue.size(), " cards!")
		else:
			print("JSON Parse Error: ", json.get_error_message())
		file.close()
	else:
		print("CRITICAL ERROR: Could not find deck.json at the specified path!")
