class_name VeterancyInsignia
extends Control


## Rank insignia for Soldier veterancy: stacked chevrons, readable at a glance.
## Ranks 0-2: 1-3 bronze chevrons. Ranks 3-5: 1-3 silver chevrons under a bar.
## Rank 6+: 1-3 gold chevrons under a star. A negative rank draws nothing.

const BRONZE := Color(0.82, 0.55, 0.3)
const SILVER := Color(0.84, 0.86, 0.9)
const GOLD := Color(1.0, 0.8, 0.32)
const OUTLINE := Color(0.06, 0.04, 0.03, 0.95)

var level := -1:
	set(value):
		level = value
		tooltip_text = "" if level < 0 else "Veterancy %d" % level
		queue_redraw()


static func color_for(rank: int) -> Color:
	if rank >= 6:
		return GOLD
	return SILVER if rank >= 3 else BRONZE


## Number of chevrons shown for a rank (1-3 per tier).
static func chevrons_for(rank: int) -> int:
	if rank < 0:
		return 0
	return mini(rank, 8) % 3 + 1


## Draws the insignia centred on center; width is the chevron width in pixels.
static func draw_insignia(canvas: CanvasItem, center: Vector2, rank: int, width := 12.0) -> void:
	var count := chevrons_for(rank)
	if count == 0:
		return
	var color := color_for(rank)
	var half := width * 0.5
	var depth := width * 0.38
	var gap := width * 0.34
	var thickness := maxf(1.6, width * 0.2)
	var total := (count - 1) * gap + depth
	var top := center.y - total * 0.5
	if rank >= 3:
		# Tier bar (silver) or crowning star (gold) above the chevrons.
		var mark_y := top - gap * 0.9
		if rank >= 6:
			_draw_star(canvas, Vector2(center.x, mark_y - width * 0.12), width * 0.42, color)
		else:
			var bar := Rect2(Vector2(center.x - half, mark_y - thickness * 0.5), Vector2(width, thickness))
			canvas.draw_rect(bar.grow(1.0), OUTLINE)
			canvas.draw_rect(bar, color)
	for index in count:
		var y := top + index * gap
		var points := PackedVector2Array([Vector2(center.x - half, y), Vector2(center.x, y + depth), Vector2(center.x + half, y)])
		canvas.draw_polyline(points, OUTLINE, thickness + 2.2, true)
		canvas.draw_polyline(points, color, thickness, true)


static func _draw_star(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var r := radius if index % 2 == 0 else radius * 0.45
		var angle := -PI * 0.5 + index * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	var outline := PackedVector2Array()
	for point in points:
		outline.append(center + (point - center) * 1.25)
	canvas.draw_colored_polygon(outline, OUTLINE)
	canvas.draw_colored_polygon(points, color)


func _init() -> void:
	custom_minimum_size = Vector2(22, 22)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	draw_insignia(self, size * 0.5 + Vector2(0, 2), level, minf(size.x, size.y) * 0.62)
