extends Node2D

const VFX := preload("res://combat/vfx/combat_vfx.gd")
const SHAPES := preload("res://combat/vfx/spell_shape_vfx.gd")
var projectile: Node2D
var effect_id: StringName
var tint := Color.WHITE
var points: Array[Vector2] = []
var visual_time := 0.0
var retired_time := 0.0

func _ready() -> void:
	material = VFX.material_for(&"magic_burst")
	points.append(projectile.global_position)

func _process(delta: float) -> void:
	visual_time += delta
	if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
		var point := projectile.global_position
		if points.is_empty() or points[-1].distance_squared_to(point) > 4.0:
			points.append(point)
		var maximum := 36.0 if effect_id == &"arrow" else (150.0 if effect_id == &"fire_arrow" else 90.0)
		while points.size() > 2 and (points.size() > 20 or points[0].distance_to(point) > maximum):
			points.pop_front()
	else:
		retired_time += delta
		if retired_time >= 0.18:
			queue_free()
			return
	queue_redraw()

func _draw() -> void:
	if points.is_empty():
		return
	var fade := 1.0 - retired_time / 0.18
	var fire := effect_id in [&"fire_arrow", &"ember_bolt"]
	var physical := effect_id == &"arrow"
	var magical := not physical and not fire
	for index in range(1, points.size()):
		var progress := float(index) / float(points.size() - 1)
		var a := to_local(points[index - 1])
		var b := to_local(points[index])
		var strength := progress * progress * fade
		if fire:
			# A glowing ribbon of heat behind the shot: wide red haze, orange body, hot core.
			draw_line(a, b, Color(1, 0.22, 0.03, strength * 0.3), 26.0 * progress, true)
			draw_line(a, b, Color(1, 0.5, 0.1, strength * 0.55), 10.0 * progress, true)
			draw_line(a, b, Color(1, 0.85, 0.5, strength * 0.7), 3.0 * progress, true)
		else:
			if magical:
				draw_line(a, b, Color(tint, strength * 0.09), 8.0 * progress, true)
			var width := 1.0 if physical else 2.0
			draw_line(a, b, Color(tint, strength * (0.25 if physical else 0.55)), width, true)
			if magical and index % 3 == 0:
				draw_circle(b + Vector2(sin(visual_time * 8 + index), cos(visual_time * 7 + index)) * 3.0, 1.1, Color(tint, strength * 0.6))
	if retired_time > 0.0:
		return
	var head := to_local(points[-1])
	if fire and effect_id != &"fire_arrow":
		var direction := Vector2.RIGHT
		if points.size() >= 2:
			direction = (points[-1] - points[-2]).normalized()
		for index in 3:
			var at := head - direction * (index * 8.0 + 3.0)
			draw_set_transform(at, direction.angle() - PI * 0.5)
			SHAPES.flame(self, Vector2.ZERO, 3.0, 13.0 + index * 3.0, visual_time * 12 + index, 0.55 - index * 0.1)
		draw_set_transform(Vector2.ZERO)
	if not physical:
		var radius := 34.0 if effect_id == &"fire_arrow" else (15.0 if fire else 11.0)
		draw_texture_rect(VFX.get_light_texture(), Rect2(head - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, Color(tint, 0.25))
