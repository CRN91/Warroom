extends Node
class_name Deck

# The live draw pile. Cards are plain Dictionaries (see deck.json / CardLibrary).
# CardManager fills this on setup; cards then get drawn, injected and removed
# during play by the resolver.

var queue: Array = []

func len():        return queue.size()
func size():       return queue.size()
func is_empty():   return queue.is_empty()
func push(x):      queue.push_back(x)
func pop():        return queue.pop_front()
func _to_string(): return str(queue)

# ── Editing the deck from cards ───────────────────────────────────────────────

func inject(card: Dictionary, position: String = "random") -> void:
	# position controls WHERE a newly added card lands in the pile:
	#   "front"  -> next thing drawn (of its type)
	#   "soon"   -> a couple of cards in
	#   "random" -> anywhere
	#   "back"   -> bottom of the pile
	if card.is_empty():
		return
	match position:
		"front":
			queue.push_front(card)
		"soon":
			var idx: int = min(2, queue.size())
			queue.insert(idx, card)
		"back":
			queue.push_back(card)
		_:  # "random"
			queue.insert(randi() % (queue.size() + 1), card)

func remove_by_id(id: String) -> void:
	for i in range(queue.size() - 1, -1, -1):
		if queue[i].get("id", "") == id:
			queue.remove_at(i)

func has_id(id: String) -> bool:
	for c in queue:
		if c.get("id", "") == id:
			return true
	return false

func shuffle() -> void:
	queue.shuffle()
