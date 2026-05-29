extends Panel
class_name CardUI

signal choice_made(card_data: Dictionary, choice: String)

@onready var lbl_type = $VBoxContainer/type
@onready var lbl_text = $VBoxContainer/text
@onready var button_container = $VBoxContainer/ButtonContainer
@onready var btn_yes = $VBoxContainer/ButtonContainer/BtnYes
@onready var btn_no = $VBoxContainer/ButtonContainer/BtnNo

var current_card_data: Dictionary

func _ready():
	btn_yes.pressed.connect(_on_yes_pressed)
	btn_no.pressed.connect(_on_no_pressed)

# Updates the UI based on the dictionary passed from the Deck
func display_card(card_data: Dictionary):
	current_card_data = card_data
	
	lbl_type.text = str(card_data["type"]).capitalize()
	lbl_text.text = str(card_data["text"])
	
	# Decision card buttons
	if card_data["type"] == "decision":
		button_container.show()
		
		if card_data.has("choices"):
			btn_yes.text = str(card_data["choices"][0])
			btn_no.text = str(card_data["choices"][1])
		else:
			btn_yes.text = "Yes"
			btn_no.text = "No"
	else:
		# Hide the buttons for Intel and Event cards
		button_container.hide()
	
	# Show the panel
	show()

func _on_yes_pressed():
	choice_made.emit(current_card_data, "yes")
	button_container.hide() # Close the card after making a choice

func _on_no_pressed():
	choice_made.emit(current_card_data, "no")
	button_container.hide() # Close the card after making a choice
