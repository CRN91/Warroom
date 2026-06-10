extends Unit
class_name Artillery

## Artillery is the defensive anchor: it must SET UP (D key — costs the turn's
## action) before it can fire, and any move tears the position down again.
## Infantry pushes the line; deployed guns break what walks into it.

var deployed: bool = false

func _ready():
	_apply_team_shade()
	update_ui()

func is_combatant(): return true

func can_fire() -> bool:
	return deployed

func on_moved():
	if deployed:
		deployed = false
		if attack_comp: attack_comp.clear_target()
		queue_redraw()

func try_deploy() -> bool:
	## Costs the unit's action for the turn; it can fire from next turn.
	if deployed: return true
	if is_frozen():
		if team == 1: Events.notify("%s has already acted this week." % name)
		return false
	deployed = true
	freeze()
	queue_redraw()
	if team == 1: Events.notify("%s is setting up — ready to fire next week." % name)
	return true

func pack_up() -> void:
	if not deployed: return
	deployed = false
	if attack_comp: attack_comp.clear_target()
	queue_redraw()

func _draw():
	super._draw()
	# Deployed: a firm emplacement ring; setting-up state reads from the panel
	if deployed:
		var inv := 1.0 / maxf(scale.x, 0.001)
		draw_arc(Vector2.ZERO, _selection_radius() * 0.8 * inv, 0, TAU, 6, Color(0.55, 0.42, 0.25, 0.95), _hex_metric() * 0.03 * inv)
