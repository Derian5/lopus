extends Node2D

## Separate ground-plane marker: never paint the selection ring across a body.
func _draw() -> void:
	var unit := get_parent() as Combatant
	if unit == null or (not unit.selected and not unit.snapshot.is_boss) or not unit.is_alive():
		return
	var radius := maxf(unit.body_radius + 12.0, 30.0)
	var tint := Color(1.0, 0.82, 0.38) if unit.selected else Color(unit.snapshot.boss_telegraph_color, 0.7)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, radius, Color(tint, 0.09))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.03, 0.02, 0.01, 0.9), 5.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, tint, 2.0, true)
	if unit.snapshot.is_boss:
		for phase in range(1, unit.boss_phase):
			draw_arc(Vector2.ZERO, radius + phase * 3.0, 0.0, TAU, 64, Color(unit.snapshot.boss_telegraph_color.lightened(0.2), 0.6), 1.5, true)
	if unit.snapshot.is_boss and unit.state == Combatant.State.ATTACK_WINDUP:
		var progress := clampf(1.0 - unit.state_timer / maxf(unit.windup_duration, 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, unit.snapshot.boss_telegraph_color, 4.0, true)
	draw_set_transform(Vector2.ZERO)
