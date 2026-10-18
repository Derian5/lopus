@tool
class_name ScreenBackdrop
extends Control


## Full-screen background in the Hero Selection style: deep slate gradient,
## soft vignette, a faint arcane circle and constellation lines.

@export var top_color := Color(0.085, 0.058, 0.04):
	set(value):
		top_color = value
		queue_redraw()
@export var bottom_color := Color(0.016, 0.011, 0.008):
	set(value):
		bottom_color = value
		queue_redraw()
@export var accent_color := Color(0.72, 0.52, 0.3):
	set(value):
		accent_color = value
		queue_redraw()
@export_range(0.0, 1.0, 0.05) var ornament_strength := 1.0:
	set(value):
		ornament_strength = value
		queue_redraw()
## Vertical position of the horizon line as a fraction of the height. Negative hides it.
@export var horizon := 0.49:
	set(value):
		horizon = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var bands := 24
	for index in bands:
		var t := float(index) / float(bands - 1)
		var color := top_color.lerp(bottom_color, t)
		draw_rect(Rect2(0.0, size.y * index / bands, size.x, size.y / bands + 1.0), color)

	var center := Vector2(size.x * 0.5, size.y * 0.42)
	var glow := accent_color
	for step in 10:
		glow.a = 0.012 * ornament_strength
		draw_circle(center, size.y * (0.18 + step * 0.05), glow)

	var line := accent_color
	line.a = 0.14 * ornament_strength
	var faint := accent_color
	faint.a = 0.07 * ornament_strength
	var radius := size.y * 0.62
	draw_arc(center, radius, PI * 1.08, PI * 1.92, 96, line, 1.5, true)
	draw_arc(center, radius * 1.18, PI * 1.12, PI * 1.88, 96, faint, 1.0, true)
	draw_arc(center, radius * 0.78, PI * 1.02, PI * 1.98, 96, faint, 1.0, true)

	var nodes := [
		Vector2(0.27, 0.06), Vector2(0.3, 0.09), Vector2(0.39, 0.03),
		Vector2(0.73, 0.06), Vector2(0.7, 0.09), Vector2(0.61, 0.03),
	]
	for pair in [[0, 1], [1, 2], [3, 4], [4, 5]]:
		draw_line(nodes[pair[0]] * size, nodes[pair[1]] * size, faint, 1.0, true)
	for point in nodes:
		_draw_node(point * size, line)

	if horizon >= 0.0:
		var horizon_color := accent_color
		horizon_color.a = 0.2 * ornament_strength
		var y := size.y * horizon
		draw_line(Vector2(0.0, y), Vector2(size.x, y), horizon_color, 1.0, true)
		_draw_node(Vector2(size.x * 0.02, y), line)
		_draw_node(Vector2(size.x * 0.98, y), line)

	# Vignette.
	for step in 8:
		var shade := Color(0, 0, 0, 0.05 + step * 0.012)
		var inset := step * size.y * 0.018
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, inset)), shade)
		draw_rect(Rect2(Vector2(0.0, size.y - inset), Vector2(size.x, inset)), shade)
		draw_rect(Rect2(Vector2.ZERO, Vector2(inset * 1.4, size.y)), shade)
		draw_rect(Rect2(Vector2(size.x - inset * 1.4, 0.0), Vector2(inset * 1.4, size.y)), shade)


func _draw_node(point: Vector2, color: Color) -> void:
	var diamond := PackedVector2Array([
		point + Vector2(0, -4), point + Vector2(4, 0), point + Vector2(0, 4), point + Vector2(-4, 0), point + Vector2(0, -4),
	])
	draw_polyline(diamond, color, 1.0, true)
