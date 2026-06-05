extends Panel
class_name CardUI

signal card_chosen(card_data: Dictionary, choice: String)

@onready var lbl_type = $VBoxContainer/type
@onready var lbl_text = $VBoxContainer/text
@onready var button_container = $VBoxContainer/ButtonContainer
@onready var btn_yes = $VBoxContainer/ButtonContainer/BtnYes
@onready var btn_no  = $VBoxContainer/ButtonContainer/BtnNo

var current_card_data: Dictionary

func _ready():
	btn_yes.pressed.connect(_on_yes_pressed)
	btn_no.pressed.connect(_on_no_pressed)

func display_card(card_data: Dictionary):
	current_card_data = card_data

	lbl_type.text = str(card_data["type"]).capitalize()
	lbl_text.text = str(card_data["text"])

	if card_data["type"] == "decision":
		# Two real choices, labelled from the JSON (choice_a / choice_b).
		button_container.show()
		btn_no.show()
		btn_yes.text = str(card_data.get("choice_a", {}).get("label", "Yes"))
		btn_no.text  = str(card_data.get("choice_b", {}).get("label", "No"))
	else:
		# intel / event: effects already applied on draw, so just offer a dismiss.
		button_container.show()
		btn_no.hide()
		btn_yes.text = "Continue"

	show()

func _on_yes_pressed():
	# Decision -> choice_a ; intel/event Continue -> "ack" (no choice effects)
	var choice := "choice_a" if current_card_data.get("type", "") == "decision" else "ack"
	card_chosen.emit(current_card_data, choice)
	hide()

func _on_no_pressed():
	card_chosen.emit(current_card_data, "choice_b")
	hide()
