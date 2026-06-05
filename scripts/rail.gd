extends Node2D
class_name Rail

## Visual marker that sits on a hex to show rail is present.
## The actual data (which route, broken status) lives in rail_network.rail_hexes.

const BROKEN_TEXTURE = preload("res://assets/rail_broken.png")
const INTACT_TEXTURE = preload("res://assets/rail.png")

var hex_pos: Vector2i  # Axial coords of this rail hex
var broken: bool = false

func break_rail():
	broken = true
	if has_node("Sprite2D") and BROKEN_TEXTURE:
		$Sprite2D.texture = BROKEN_TEXTURE
	else:
		modulate = Color(0.6, 0.15, 0.15)

func repair_rail():
	broken = false
	if has_node("Sprite2D") and INTACT_TEXTURE:
		$Sprite2D.texture = INTACT_TEXTURE
	else:
		modulate = Color(1.0, 1.0, 1.0)
