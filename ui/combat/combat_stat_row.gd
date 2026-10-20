class_name CombatStatRow
extends Button


## One line of the live damage meter: identity badge, name, contribution bar,
## kill count and the value pinned to the right edge. Fallen units are dimmed,
## struck through and marked with a skull.

const ROW_HEIGHT := 22.0

var unit_name := ""
var value := 0.0
var fraction := 0.0
var kills := 0
var dead := false
var accent := Color(0.48, 0.76, 1.0)
var badge := {}
var rank := 0


func _init() -> void:
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = ""
	set_meta("disable_auto_motion", true)
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(style, empty)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func configure(data: Dictionary, metric_value: float, max_value: float, team_accent: Color, badge_info: Dictionary, row_rank: int) -> void:
	unit_name = String(data.get("display_name", "?"))
	value = metric_value
	fraction = clampf(metric_value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	kills = int(data.get("kills", 0))
	dead = not bool(data.get("alive", true))
	accent = team_accent
	badge = badge_info
	rank = row_rank
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var rect := Rect2(Vector2.ZERO, size)
	var hovered := is_hovered()
	var alpha := 0.5 if dead else 1.0
	draw_rect(rect, Color(0.04, 0.028, 0.02, 0.3 if not hovered else 0.55))
	if fraction > 0.0:
		var bar := accent
		bar.a = (0.32 if rank == 0 else 0.22) * alpha
		draw_rect(Rect2(rect.position + Vector2(ROW_HEIGHT, 2.0), Vector2((rect.size.x - ROW_HEIGHT) * fraction, rect.size.y - 4.0)), bar)
		var edge := accent
		edge.a = 0.8 * alpha
		draw_rect(Rect2(Vector2(ROW_HEIGHT + (rect.size.x - ROW_HEIGHT) * fraction - 2.0, 2.0), Vector2(2.0, rect.size.y - 4.0)), edge)
	if hovered:
		draw_rect(rect.grow(-0.5), Color(0.96, 0.77, 0.4, 0.7), false, 1.0)

	UnitBadge.draw_badge(self, Rect2(Vector2(3.0, 3.0), Vector2(ROW_HEIGHT - 6.0, ROW_HEIGHT - 6.0)), badge, dead, font)

	var font_size := 13
	var value_text := _format(value)
	var value_width := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var right := rect.size.x - 7.0
	var baseline := rect.size.y * 0.5 + font.get_ascent(font_size) * 0.38
	draw_string(font, Vector2(right - value_width, baseline), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.92, 0.74, alpha))
	right -= value_width + 8.0
	if kills > 0:
		var kill_text := "%d" % kills
		var kill_width := font.get_string_size(kill_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var kill_x := right - kill_width
		draw_string(font, Vector2(kill_x, baseline), kill_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.55, 0.45, alpha))
		_draw_crossed_swords(Vector2(kill_x - 8.0, rect.size.y * 0.5), Color(0.95, 0.55, 0.45, alpha))
		right = kill_x - 18.0

	var name_x := ROW_HEIGHT + 4.0
	var name_width := maxf(right - name_x - 4.0, 10.0)
	var name_color := Color(0.62, 0.58, 0.52) if dead else Color(0.92, 0.88, 0.8)
	var shown := elide(font, unit_name, name_width, font_size)
	draw_string(font, Vector2(name_x, baseline), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, name_color)
	if dead:
		var drawn := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var strike_y := rect.size.y * 0.5 + 1.0
		draw_line(Vector2(name_x - 1.0, strike_y), Vector2(name_x + drawn + 1.0, strike_y), Color(0.82, 0.3, 0.26, 0.9), 1.5, true)


func _draw_crossed_swords(center: Vector2, color: Color) -> void:
	var r := 5.0
	draw_line(center + Vector2(-r, -r), center + Vector2(r, r), color, 1.4, true)
	draw_line(center + Vector2(r, -r), center + Vector2(-r, r), color, 1.4, true)
	draw_line(center + Vector2(-r - 1, r - 3), center + Vector2(-r + 3, r + 1), color, 1.4, true)
	draw_line(center + Vector2(r + 1, r - 3), center + Vector2(r - 3, r + 1), color, 1.4, true)


## Shortens text with an ellipsis so it fits max_width.
static func elide(font: Font, source: String, max_width: float, font_size: int) -> String:
	if font.get_string_size(source, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return source
	var result := source
	while result.length() > 1 and font.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		result = result.left(result.length() - 1)
	return result.strip_edges() + "…"


static func _format(amount: float) -> String:
	if amount >= 10000.0:
		return "%.1fk" % (amount / 1000.0)
	return "%d" % int(roundf(amount))
