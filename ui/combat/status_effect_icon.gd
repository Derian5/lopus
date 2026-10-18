class_name StatusEffectIcon
extends ContentButton


const ICON_SIZE := Vector2(42, 42)

var accent_color := Color(0.72, 0.64, 0.38)
var glyph := "?"
var status_icon: Texture2D
var remaining_duration := -1.0
var stacks := 1


func configure_status(title: String, details: String, polarity: int, duration: float, stack_count: int, icon_texture: Texture2D = null) -> void:
	custom_minimum_size = ICON_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	flat = true
	focus_mode = Control.FOCUS_NONE
	tooltip_override = "%s\n%s" % [title.to_upper(), details]
	accent_color = _polarity_color(polarity)
	glyph = _initials(title)
	status_icon = icon_texture
	remaining_duration = duration
	stacks = maxi(stack_count, 1)
	var empty_style := StyleBoxEmpty.new()
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(state, empty_style)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.45
	draw_circle(center, radius, Color(0.015, 0.02, 0.03, 0.94))
	draw_arc(center, radius, 0.0, TAU, 40, accent_color, 3.0, true)
	if status_icon != null:
		draw_texture_rect(status_icon, Rect2(center - Vector2.ONE * 13.0, Vector2.ONE * 26.0), false, Color(0.9, 0.9, 0.9, 1.0))
	else:
		_draw_centered_text(glyph, center + Vector2(0, 2), 14, Color.WHITE)
	if remaining_duration >= 0.0:
		var duration_text := "%d" % ceili(remaining_duration)
		_draw_centered_text(duration_text, Vector2(center.x, size.y - 2.0), 10, Color(0.94, 0.94, 0.96))
	if stacks > 1:
		draw_circle(Vector2(size.x - 6.0, 6.0), 7.0, accent_color)
		_draw_centered_text(str(stacks), Vector2(size.x - 6.0, 9.0), 9, Color(0.04, 0.04, 0.05))


func _draw_centered_text(value: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.get_project_theme().default_font
	var text_size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.28), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _polarity_color(polarity: int) -> Color:
	if polarity == StatusDefinition.Polarity.POSITIVE:
		return Color(0.25, 0.82, 0.52)
	if polarity == StatusDefinition.Polarity.NEGATIVE:
		return Color(0.9, 0.3, 0.32)
	return Color(0.82, 0.66, 0.3)


func _initials(title: String) -> String:
	var result := ""
	for word in title.split(" ", false):
		result += word.left(1).to_upper()
		if result.length() == 2:
			break
	return result if not result.is_empty() else "?"
