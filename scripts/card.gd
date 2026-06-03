extends Panel
class_name CardUI

# Only need this one!
signal card_chosen(card_data: Dictionary, choice: String)

@onready var lbl_type = $VBoxContainer/type
@onready var lbl_text = $VBoxContainer/text
@onready var button_container = $VBoxContainer/ButtonContainer
@onready var btn_yes = $VBoxContainer/ButtonContainer/BtnYes
@onready var btn_no = $VBoxContainer/ButtonContainer/BtnNo

var current_card_data: Dictionary

func _ready():
	btn_yes.pressed.connect(_on_yes_pressed)
	btn_no.pressed.connect(_on_no_pressed)

func display_card(card_data: Dictionary):
	current_card_data = card_data
	
	lbl_type.text = str(card_data["type"]).capitalize()
	lbl_text.text = str(card_data["text"])
	
	if card_data["type"] == "decision":
		button_container.show()
		
		if card_data.has("choices"):
			btn_yes.text = str(card_data["choices"][0])
			btn_no.text = str(card_data["choices"][1])
		else:
			btn_yes.text = "Yes"
			btn_no.text = "No"
	else:
		button_container.hide()
	
	show()

func _on_yes_pressed():
	card_chosen.emit(current_card_data, "yes")
	hide() # Hides the whole CardUI panel!

func _on_no_pressed():
	card_chosen.emit(current_card_data, "no")
	hide() # Hides the whole CardUI panel!
