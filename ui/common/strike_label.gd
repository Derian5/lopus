class_name StrikeLabel
extends Label


## Label that can be struck through, used for fallen units in statistics.

var struck := false:
	set(value):
		struck = value
		queue_redraw()
var strike_color := Color(0.82, 0.3, 0.26, 0.9)


func _draw() -> void:
	if not struck or text.is_empty():
		return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var width := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, size.x)
	var x := 0.0
	if horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = size.x - width
	elif horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (size.x - width) * 0.5
	var y := size.y * 0.5 + 1.0
	draw_line(Vector2(x - 1.0, y), Vector2(x + width + 1.0, y), strike_color, 1.6, true)
