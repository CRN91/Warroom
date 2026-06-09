extends Panel
class_name CardUI

## Displays the daily card.
##   intel / event — passive: no buttons, effects already applied. The card can
##                   be clicked away, and is replaced on the next draw anyway.
##   decision      — blocking: shows one button per choice_*; End Turn stays
##                   disabled (see UIManager) until a choice is clicked.

signal card_chosen(card_data: Dictionary, choice: String)

const TYPE_COLORS := {
	"intel":    Color(0.45, 0.75, 1.0),
	"event":    Color(1.0, 0.65, 0.3),
	"decision": Color(1.0, 0.45, 0.45),
}

@onready var lbl_type: Label = $Margin/VBoxContainer/type
@onready var lbl_text: Label = $Margin/VBoxContainer/text
@onready var button_container: VBoxContainer = $Margin/VBoxContainer/ButtonContainer

var current_card_data: Dictionary
var _dismissible: bool = false
var _style: StyleBoxFlat

func _ready():
	gui_input.connect(_on_gui_input)

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.10, 0.10, 0.13, 0.96)
	_style.border_width_left = 3
	_style.border_color = Color(0.5, 0.5, 0.5)
	_style.corner_radius_top_left = 6
	_style.corner_radius_top_right = 6
	_style.corner_radius_bottom_left = 6
	_style.corner_radius_bottom_right = 6
	_style.shadow_size = 8
	_style.shadow_color = Color(0, 0, 0, 0.4)
	add_theme_stylebox_override("panel", _style)

	lbl_type.add_theme_font_size_override("font_size", 15)
	lbl_text.add_theme_font_size_override("font_size", 16)

func display_card(card_data: Dictionary, max_funds: int = -1):
	current_card_data = card_data
	var type := str(card_data.get("type", "intel"))
	var accent: Color = TYPE_COLORS.get(type, Color.WHITE)

	lbl_type.text = type.to_upper()
	lbl_type.add_theme_color_override("font_color", accent)
	_style.border_color = accent
	lbl_text.text = str(card_data.get("text", ""))

	for c in button_container.get_children():
		c.queue_free()

	_dismissible = type != "decision"
	if type == "decision":
		var keys := []
		for k in card_data.keys():
			if k.begins_with("choice_"): keys.append(k)
		keys.sort()
		for ck in keys:
			_add_button(str(card_data[ck].get("label", ck)), ck, max_funds)
	else:
		var hint := Label.new()
		hint.text = "click to dismiss"
		hint.add_theme_font_size_override("font_size", 11)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.modulate = Color(1, 1, 1, 0.45)
		button_container.add_child(hint)

	show()

func _on_gui_input(event: InputEvent):
	if _dismissible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide()

func _add_button(text: String, choice: String, max_funds: int) -> void:
	var b := Button.new()

	# Choices can carry a cost; show it and grey the button out if unaffordable.
	var cost: int = 0
	if current_card_data.has(choice) and current_card_data[choice].has("cost"):
		cost = current_card_data[choice]["cost"]
		b.text = "%s   (−%d)" % [text, cost]
	else:
		b.text = text

	b.disabled = max_funds >= 0 and cost > max_funds
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		card_chosen.emit(current_card_data, choice)
		hide()
	)
	button_container.add_child(b)
