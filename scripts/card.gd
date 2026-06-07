extends Panel
class_name CardUI

signal card_chosen(card_data: Dictionary, choice: String)

@onready var lbl_type = $VBoxContainer/type
@onready var lbl_text = $VBoxContainer/text
@onready var button_container = $VBoxContainer/ButtonContainer

var current_card_data: Dictionary

func display_card(card_data: Dictionary):
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
			_add_button(str(card_data[ck].get("label", ck)), ck)
	else:
		_add_button("Continue", "ack")
	show()

func _add_button(text: String, choice: String) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): card_chosen.emit(current_card_data, choice); hide())
	button_container.add_child(b)
