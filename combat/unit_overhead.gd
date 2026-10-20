extends Node2D


## Drawn above every depth-sorted body, projectile and attack effect.
func _draw() -> void:
	var unit = get_parent()
	if unit.snapshot != null:
		unit.draw_overhead(self)
