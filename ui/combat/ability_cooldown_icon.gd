class_name AbilityCooldownIcon
extends ContentIconButton


var cooldown_remaining := 0.0
var cooldown_total := 0.0
var cooldown_ratio := 0.0


func set_cooldown(remaining: float, total: float) -> void:
	cooldown_remaining = maxf(remaining, 0.0)
	cooldown_total = maxf(maxf(total, cooldown_remaining), 0.0)
	cooldown_ratio = clampf(cooldown_remaining / cooldown_total, 0.0, 1.0) if cooldown_total > 0.0 else 0.0
	for theme_color in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_focus_color"]:
		add_theme_color_override(theme_color, Color.WHITE)
	queue_redraw()


func _draw() -> void:
	super._draw()
	if cooldown_ratio <= 0.0:
		return
	var center := size * 0.5
	var inset := 3.0
	var usable_height := maxf(size.y - inset * 2.0, 0.0)
	var overlay_height := usable_height * cooldown_ratio
	var overlay_rect := Rect2(inset, size.y - inset - overlay_height, maxf(size.x - inset * 2.0, 0.0), overlay_height)
	draw_rect(overlay_rect, Color(0.015, 0.02, 0.035, 0.72))
	var cooldown_text := "%d" % ceili(cooldown_remaining) if cooldown_remaining >= 1.0 else "%.1f" % cooldown_remaining
	var font := ThemeDB.get_project_theme().default_font
	var font_size := 19
	var text_size := font.get_string_size(cooldown_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.34), cooldown_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)
