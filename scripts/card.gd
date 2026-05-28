extends Panel
class_name CardUI

@onready var lbl_type = $VBoxContainer/type
@onready var lbl_text = $VBoxContainer/text

var current_card_data: Dictionary

# Updates the UI based on the dictionary passed from the Deck
func display_card(card_data: Dictionary):
	current_card_data = card_data
	
	lbl_type.text = str(card_data["type"]).capitalize()
	lbl_text.text = str(card_data["text"])
	
	# Show the panel
	show()
