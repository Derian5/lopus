extends Node2D

## Small, texture-free accents layered with the authored atlases. Presentation only.
var style: StringName = &"arcane"
var tint := Color(0.75, 0.65, 1.0)
var radius := 36.0
var duration := 0.55
var elapsed := 0.0
var puff_texture: Texture2D

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
	else:
		queue_redraw()

static func ellipse(canvas: CanvasItem, center: Vector2, r: float, color: Color, width := 1.5, start := 0.0, end := TAU) -> void:
	var points := PackedVector2Array()
	for index in 41:
		var angle := lerpf(start, end, index / 40.0)
		points.append(center + Vector2(cos(angle), sin(angle) * 0.35) * r)
	canvas.draw_polyline(points, color, width, true)

static func flame(canvas: CanvasItem, at: Vector2, width: float, height: float, phase: float, alpha: float) -> void:
	var sway := sin(phase) * width * 0.5
	var outer := PackedVector2Array([
		at + Vector2(-width, 0), at + Vector2(-width * 0.7, -height * 0.45),
		at + Vector2(-width * 0.35, -height * 0.3), at + Vector2(sway, -height),
		at + Vector2(width * 0.55, -height * 0.42), at + Vector2(width, -height * 0.12),
		at + Vector2(width * 0.6, height * 0.08)])
	canvas.draw_colored_polygon(outer, Color(1.0, 0.25, 0.025, alpha * 0.6))
	var inner := PackedVector2Array()
	for point in outer:
		inner.append(at + (point - at) * Vector2(0.48, 0.7))
	canvas.draw_colored_polygon(inner, Color(1.0, 0.72, 0.12, alpha * 0.85))

static func heart(canvas: CanvasItem, at: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 32:
		var a := TAU * index / 32.0
		var x := 16.0 * pow(sin(a), 3)
		var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
		points.append(at + Vector2(x, y) * size / 16.0)
	canvas.draw_colored_polygon(points, color)

func _draw() -> void:
	var p := clampf(elapsed / maxf(duration, 0.01), 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - p, 3)
	var alpha := minf(p * 12.0, 1.0) * pow(1.0 - p, 1.4)
	var r := radius * (0.28 + ease * 0.72)
	var color := Color(tint, alpha * 0.8)
	match style:
		&"smoke":
			if puff_texture != null:
				for index in 7:
					var a := index * TAU / 7.0 + p * 0.5
					var at := Vector2(cos(a) * r * 0.45, sin(a) * r * 0.18 - p * 12.0)
					var extent := Vector2(r * 0.65, r * 0.38)
					draw_texture_rect(puff_texture, Rect2(at - extent, extent * 2.0), false, Color(0.17, 0.18, 0.2, alpha * 0.65))
		&"nature":
			for index in 7:
				var a := TAU * index / 7.0
				var end := Vector2(cos(a), sin(a) * 0.4) * r
				var branch := PackedVector2Array([Vector2.ZERO, end * 0.35 + Vector2(0, -8), end * 0.7 + Vector2(5, 0), end])
				draw_polyline(branch, color, 2.0, true)
				draw_line(end * 0.55, end * 0.55 + Vector2(-7, -10), color, 1.5, true)
			ellipse(self, Vector2.ZERO, r * 0.8, Color(tint, alpha * 0.25))
		&"sleep", &"shadow", &"drain":
			for index in 3:
				var center := Vector2(0, -index * 12.0 - p * 22.0)
				ellipse(self, center, r * (1 - index * 0.18), Color(tint, alpha * 0.5), 1.8, p * TAU + index, p * TAU + index + PI * 1.4)
			for index in 6:
				var a := index * TAU / 6 + p * 2
				draw_circle(Vector2(cos(a) * r * 0.65, sin(a) * r * 0.2 - p * 36), 1.7, color)
		&"charm":
			ellipse(self, Vector2.ZERO, r, Color(tint, alpha * 0.35))
			for index in 4:
				var a := index * TAU / 4 + p
				heart(self, Vector2(cos(a) * r * 0.6, sin(a) * r * 0.2 - p * 40), 5.0 + radius * 0.035, color)
		&"chain":
			for index in 12:
				var a := index * TAU / 12 + p
				var at := Vector2(cos(a) * r, sin(a) * r * 0.35)
				draw_arc(at, 3.8, a, a + TAU * 0.85, 12, color, 1.2, true)
		&"blink":
			ellipse(self, Vector2.ZERO, r, Color(tint, alpha * 0.5), 1.6)
			for index in 7:
				var x := (index - 3.0) * r * 0.22
				var height := (0.5 + sin(index * 2.0) * 0.25) * radius
				draw_line(Vector2(x, -p * 18), Vector2(x, -height - p * 30), color, 1.3, true)
		&"poison":
			ellipse(self, Vector2.ZERO, r, Color(tint, alpha * 0.4), 2.0)
			for index in 8:
				var a := index * TAU / 8
				var at := Vector2(cos(a) * r * 0.75, sin(a) * r * 0.25 - sin(p * PI) * 25)
				draw_circle(at, 2.0 + (index % 3), Color(tint, alpha * 0.5))
		&"ward", &"holy", &"boon", &"summon":
			ellipse(self, Vector2.ZERO, r, color, 1.6)
			ellipse(self, Vector2(0, -5), r * 0.78, Color(tint, alpha * 0.35), 1.0)
			for index in 8:
				var a := index * TAU / 8
				var at := Vector2(cos(a), sin(a) * 0.35) * r
				draw_line(at, at + Vector2(0, -(10.0 + radius * 0.18) * (1 - p)), color, 2.0, true)
		&"physical", &"impact", &"fury":
			ellipse(self, Vector2.ZERO, r, Color(tint, alpha * 0.4), 2.0)
			for index in 8:
				var a := index * TAU / 8 + 0.2
				var direction := Vector2(cos(a), sin(a) * 0.5)
				draw_line(direction * r * 0.5, direction * r, color, 2.5, true)
		_:
			ellipse(self, Vector2.ZERO, r, color, 1.8, p * 2, p * 2 + PI * 1.55)
			for index in 6:
				var a := index * TAU / 6 - p * 2
				var at := Vector2(cos(a) * r * 0.7, sin(a) * r * 0.23)
				var diamond := PackedVector2Array([at + Vector2(0, -5), at + Vector2(3, 0), at + Vector2(0, 5), at + Vector2(-3, 0)])
				draw_colored_polygon(diamond, color)
