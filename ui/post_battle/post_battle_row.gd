class_name PostBattleRow
extends PanelContainer


## Scoreboard line: the contribution bar is painted behind the columns so values
## stay right-aligned and comparable at a glance.

var fraction := 0.0
var accent := Color(0.9, 0.72, 0.32)
var highlighted := false
## Optional split of the bar: [{"share": float, "color": Color}, ...] (shares sum to 1).
var segments: Array = []


func _draw() -> void:
	if fraction <= 0.0:
		return
	var inner := Rect2(Vector2(46.0, 3.0), Vector2((size.x - 52.0) * clampf(fraction, 0.0, 1.0), size.y - 6.0))
	if segments.is_empty():
		var fill := accent
		fill.a = 0.2 if highlighted else 0.13
		draw_rect(inner, fill)
	else:
		var x := inner.position.x
		for index in segments.size():
			var segment: Dictionary = segments[index]
			var width := inner.size.x * float(segment.share)
			if index == segments.size() - 1:
				width = inner.end.x - x
			if width <= 0.0:
				continue
			var color: Color = segment.color
			color.a = 0.34 if highlighted else 0.26
			draw_rect(Rect2(Vector2(x, inner.position.y), Vector2(width, inner.size.y)), color)
			var rim: Color = segment.color
			rim.a = 0.75
			draw_rect(Rect2(Vector2(x, inner.end.y - 2.0), Vector2(width, 2.0)), rim)
			x += width
	var edge := accent
	edge.a = 0.7
	draw_rect(Rect2(Vector2(inner.end.x - 2.0, inner.position.y), Vector2(2.0, inner.size.y)), edge)
