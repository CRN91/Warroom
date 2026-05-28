extends Unit
 
class_name Logistics
 
@onready var resupply_comp = $Resupply
 
func _ready():
	allied = true
	supplier = 1
 
func set_enemy():
	$Sprite2D.texture = load("res://assets/logir.png")
	allied = false
 
func resupply_from(ally):
	if not frozen:
		frozen = true
		resupply_comp.resupply_from(ally)
