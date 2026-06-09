extends Panel
class_name CardUI

signal card_chosen(card_data: Dictionary, choice: String)

@onready var lbl_type = $VBoxContainer/type
@onready var lbl_text = $VBoxContainer/text
@onready var button_container = $VBoxContainer/ButtonContainer

var current_card_data: Dictionary

func display_card(card_data: Dictionary, max_funds: int = -1):
	current_card_data = card_data
	lbl_type.text = str(card_data["type"]).capitalize()
	lbl_text.text = str(card_data["text"])
	for c in button_container.get_children():
		c.queue_free()
	if card_data["type"] == "decision":
		var keys := []
		for k in card_data.keys():
			if k.begins_with("choice_"): keys.append(k)
		keys.sort()
		for ck in keys:
			_add_button(str(card_data[ck].get("label", ck)), ck, max_funds)
	else:
		_add_button("Continue", "ack", max_funds)
	show()

func _add_button(text: String, choice: String, max_funds: int) -> void:
	var b := Button.new()
	
	# 1. Look inside the card data to see if this specific choice has a cost.
	# If it doesn't (like an "ack" continue button), default the cost to 0.
	var cost: int = 0
	if current_card_data.has(choice) and current_card_data[choice].has("cost"):
		cost = current_card_data[choice]["cost"]
		
		# Optional Bonus: Add the cost to the button text so the player can see it!
		b.text = text + " (-" + str(cost) + ")"
	else:
		b.text = text

	b.pressed.connect(func(): card_chosen.emit(current_card_data, choice); hide())
	button_container.add_child(b)
	
	# 2. Now the script knows what 'cost' is and can properly grey out the button
	var afford := (max_funds < 0) or (cost <= max_funds)
	b.disabled = not afford
