class_name EnemyToken
extends Control


## Small engraved medallion for an enemy type on an Encounter card: a role glyph
## (blade, spear, heavy shield, healer, caller, leaper, crown) on the creature's
## colour, with an optional count underneath.

const SIZE := 46.0

var enemy: EnemyDefinition
var count := 1
var concealed := false
var reinforcement := false
var show_count := true


func setup(definition: EnemyDefinition, enemy_count: int, is_concealed := false, is_reinforcement := false, with_count := true) -> void:
	enemy = definition
	count = enemy_count
	concealed = is_concealed
	reinforcement = is_reinforcement
	show_count = with_count
	custom_minimum_size = Vector2(SIZE + 6.0, SIZE + (22.0 if show_count else 4.0))
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = _tooltip()
	queue_redraw()


static func role_of(definition: EnemyDefinition) -> StringName:
	if definition == null:
		return &"unknown"
	var tags := definition.tags
	if definition is BossDefinition:
		return &"boss"
	if tags.has(&"support") or tags.has(&"priest"):
		return &"healer"
	if tags.has(&"summoner"):
		return &"caller"
	if tags.has(&"elite"):
		return &"leaper"
	if tags.has(&"heavy"):
		return &"heavy"
	if definition.attack_type == &"ranged":
		return &"ranged"
	return &"melee"


func _tooltip() -> String:
	if concealed or enemy == null:
		return "Unknown enemy"
	var lines: Array[String] = ["%s%s" % [enemy.display_name, "  x%d" % count if count > 1 else ""], enemy.description]
	var registry := get_node_or_null("/root/ContentRegistry")
	if registry != null:
		for ability_id in enemy.ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition
			if ability != null:
				lines.append("%s: %s" % [ability.display_name, AbilityText.plain(ability)])
	return "\n".join(lines)


func _draw() -> void:
	var font := get_theme_default_font()
	var radius := SIZE * 0.5 - 2.0
	var center := Vector2(size.x * 0.5, radius + 3.0)
	var base := Color(0.55, 0.5, 0.45) if concealed or enemy == null else enemy.placeholder_color
	var role := &"unknown" if concealed else role_of(enemy)
	# Plate, rim and inner bevel.
	draw_circle(center + Vector2(0, 2.5), radius, Color(0, 0, 0, 0.45))
	draw_circle(center, radius, Color(0.075, 0.055, 0.04, 0.98))
	var tint := base.darkened(0.55)
	tint.a = 0.95
	draw_circle(center, radius - 3.0, tint)
	var rim := UiStyle.GOLD if role == &"boss" else (UiStyle.BRONZE if not reinforcement else Color(0.62, 0.5, 0.82))
	draw_arc(center, radius - 0.5, 0.0, TAU, 40, rim, 2.0, true)
	draw_arc(center, radius - 4.0, 0.0, TAU, 40, Color(base.lightened(0.2), 0.55), 1.2, true)
	_draw_glyph(role, center, radius * 0.55, base.lightened(0.55))
	if not show_count:
		return
	# Count plaque under the medallion.
	var label := "?" if concealed and count <= 0 else ("x%d" % count)
	var font_size := 15
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var plaque := Rect2(Vector2(center.x - width * 0.5 - 6.0, SIZE + 1.0), Vector2(width + 12.0, 18.0))
	draw_rect(plaque, Color(0.05, 0.035, 0.025, 0.92))
	draw_rect(plaque, Color(rim, 0.65), false, 1.0)
	draw_string(font, Vector2(plaque.position.x + 6.0, plaque.end.y - 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiStyle.TEXT)


func _draw_glyph(role: StringName, c: Vector2, r: float, color: Color) -> void:
	var w := maxf(2.0, r * 0.2)
	match role:
		&"melee":
			# Cleaver: blade and grip.
			draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.55, -r * 0.55), color, w * 1.6, true)
			draw_line(c + Vector2(-r * 0.35, r * 0.05), c + Vector2(-r * 0.05, r * 0.35), color, w, true)
			draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(-r * 0.9, r * 0.9), color, w, true)
		&"ranged":
			# Barbed spear in flight.
			draw_line(c + Vector2(-r * 0.85, r * 0.85), c + Vector2(r * 0.6, -r * 0.6), color, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.9, -r * 0.9), c + Vector2(r * 0.25, -r * 0.55), c + Vector2(r * 0.55, -r * 0.25)]), color)
			draw_line(c + Vector2(-r * 0.85, r * 0.85), c + Vector2(-r * 0.5, r * 0.95), color, w * 0.8, true)
			draw_line(c + Vector2(-r * 0.85, r * 0.85), c + Vector2(-r * 0.95, r * 0.5), color, w * 0.8, true)
		&"heavy":
			# Tower shield.
			var shield := PackedVector2Array([c + Vector2(-r * 0.7, -r * 0.8), c + Vector2(r * 0.7, -r * 0.8), c + Vector2(r * 0.7, r * 0.15), c + Vector2(0, r * 0.95), c + Vector2(-r * 0.7, r * 0.15)])
			draw_colored_polygon(shield, Color(color, 0.85))
			draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.75), Color(0.1, 0.07, 0.05), w * 0.8, true)
		&"healer":
			draw_rect(Rect2(c - Vector2(w * 1.1, r * 0.8), Vector2(w * 2.2, r * 1.6)), color)
			draw_rect(Rect2(c - Vector2(r * 0.8, w * 1.1), Vector2(r * 1.6, w * 2.2)), color)
		&"caller":
			# Three eyes of the mire.
			for index in 3:
				var angle := -PI * 0.5 + TAU * index / 3.0
				draw_circle(c + Vector2.from_angle(angle) * r * 0.5, r * 0.26, color)
			draw_arc(c, r * 0.9, 0.0, TAU, 24, Color(color, 0.7), w * 0.6, true)
		&"leaper":
			# Downward chevrons: something that lands on you.
			for step in 2:
				var y := -r * 0.55 + step * r * 0.6
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.75, y), c + Vector2(0, y + r * 0.5), c + Vector2(r * 0.75, y)]), color, w * 1.2, true)
		&"boss":
			var crown := PackedVector2Array([c + Vector2(-r * 0.85, r * 0.55), c + Vector2(-r * 0.85, -r * 0.35), c + Vector2(-r * 0.4, r * 0.05), c + Vector2(0, -r * 0.75), c + Vector2(r * 0.4, r * 0.05), c + Vector2(r * 0.85, -r * 0.35), c + Vector2(r * 0.85, r * 0.55)])
			draw_colored_polygon(crown, UiStyle.GOLD)
		_:
			var font := get_theme_default_font()
			draw_string(font, c + Vector2(-r, r * 0.45), "?", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.5), color)
