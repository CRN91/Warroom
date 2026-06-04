extends Node2D
class_name Rail

## Visual marker that sits on a hex to show rail is present.
## The actual data (which route, broken status) lives in Game.rail_hexes.

var hex_pos: Vector2i  # Axial coords of this rail hex
var broken: bool = false

func break_rail():
	broken  = true
	modulate = Color(0.6, 0.15, 0.15)  # Red tint when sabotaged

func repair_rail():
	broken   = false
	modulate = Color(1.0, 1.0, 1.0)    # Normal when repaired
