extends Unit
class_name Engineers

## Engineers: the builder/hauler unit. They ferry supplies, repair rail, build
## bridges and tunnels, and rail can only be laid near them.
##
## A standing SHUTTLE ROUTE ("Set Route" in the panel) automates the supply
## run: load at the source city, drive to the destination city, deliver,
## return. The commander orders the route; the truck does the driving.
## (Internal ids still use "logistics" so the card editor keeps working.)

var shuttle_src: Node2D = null
var shuttle_dst: Node2D = null
var _heading_out: bool = false   # false = going to load, true = going to deliver

func _ready():
	$Sprite2D.material.set_shader_parameter("new_color", Color(0.126, 0.207, 0.065, 1.0))
	update_ui()

func has_shuttle() -> bool:
	return shuttle_src != null and shuttle_dst != null

func set_shuttle(src: Node2D, dst: Node2D) -> void:
	shuttle_src = src
	shuttle_dst = dst
	if team != 1:
		_heading_out = get_resources() > get_max_resources() / 2
		return   # the enemy doesn't announce its supply runs
	_heading_out = get_resources() > get_max_resources() / 2
	Events.notify("%s: supply run %s → %s established." % [name, src.name, dst.name])

func clear_shuttle(quiet: bool = false) -> void:
	if has_shuttle() and not quiet and team == 1:
		Events.notify("%s: supply run cancelled." % name)
	shuttle_src = null
	shuttle_dst = null

func process_shuttle(board: Node2D) -> void:
	## Called by TurnManager before movement each week.
	if not has_shuttle(): return
	if not is_instance_valid(shuttle_src) or not is_instance_valid(shuttle_dst) \
			or shuttle_src.team != team or shuttle_dst.team != team:
		clear_shuttle()
		return

	var here = get_hex()
	if here == null: return

	# At the loading point: fill up, then turn around
	if HEX.axial_distance(here, shuttle_src.get_hex()) == 1 and not _heading_out:
		receive_from(shuttle_src)
		if get_resources() >= get_max_resources() - 5:
			_heading_out = true

	# At the delivery point: unload, then head home
	if HEX.axial_distance(here, shuttle_dst.get_hex()) == 1 and _heading_out:
		board.deliver_cargo(self)
		_heading_out = false

	# Keep rolling toward the current leg's city
	var target = shuttle_dst if _heading_out else shuttle_src
	if movement_comp.path.is_empty():
		var goal_hex = target.get_hex()
		if HEX.axial_distance(here, goal_hex) > 1 and movement_comp.goal != goal_hex:
			set_destination(goal_hex)
