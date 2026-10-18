class_name ContentIconButton
extends ContentButton


const SLOT_SIZE := Vector2(64.0, 64.0)
const ABILITY_COLOR := Color(0.24, 0.48, 0.78)
const ITEM_COLOR := Color(0.72, 0.52, 0.2)
const EMPTY_COLOR := Color(0.23, 0.27, 0.34)

var _glyph := ""
var badge_text := ""
## Empty slots draw a quiet engraved "+" instead of placeholder letters.
var _empty_slot := false
## Locked slots (e.g. professionalism not reached yet) dim the icon and show a padlock.
var locked := false:
	set(value):
		locked = value
		queue_redraw()


func configure(
	definition: ContentDefinition,
	slot_kind: StringName,
	badge := "",
	selected := false,
	custom_tooltip := ""
) -> void:
	custom_minimum_size = SLOT_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_NONE
	content_id = definition.id if definition != null else &""
	tooltip_override = custom_tooltip
	icon = _definition_icon(definition)
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph = _fallback_glyph(definition, slot_kind)
	set_badge(badge)
	var accent := _accent_color(definition, slot_kind)
	add_theme_color_override("font_color", Color(0.94, 0.95, 0.98))
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_font_size_override("font_size", 13)
	add_theme_stylebox_override("normal", _slot_style(accent, selected, 0.24))
	add_theme_stylebox_override("hover", _slot_style(accent.lightened(0.14), true, 0.34))
	add_theme_stylebox_override("pressed", _slot_style(accent.lightened(0.22), true, 0.42))
	add_theme_stylebox_override("disabled", _slot_style(EMPTY_COLOR, false, 0.16))


func set_badge(badge: String) -> void:
	badge_text = badge
	_empty_slot = content_id.is_empty() and icon == null
	if _empty_slot:
		text = ""
	else:
		text = (_glyph if badge.is_empty() else "%s\n%s" % [_glyph, badge]) if icon == null else ""
	queue_redraw()


func _draw() -> void:
	if _empty_slot:
		var center := size * 0.5
		var arm := minf(size.x, size.y) * 0.12
		var mark := Color(0.78, 0.62, 0.4, 0.45)
		draw_line(center - Vector2(arm, 0), center + Vector2(arm, 0), mark, 2.0, true)
		draw_line(center - Vector2(0, arm), center + Vector2(0, arm), mark, 2.0, true)
		return
	if locked:
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(0.03, 0.02, 0.015, 0.62))
		_draw_padlock(size * 0.5 + Vector2(0, -2), minf(size.x, size.y) * 0.2)
	if icon == null or badge_text.is_empty():
		return
	var font := get_theme_default_font()
	var font_size := 12
	var text_size := font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var badge_size := Vector2(text_size.x + 8.0, font.get_height(font_size) + 4.0)
	var badge_rect := Rect2(size - badge_size - Vector2(5.0, 5.0), badge_size)
	draw_rect(badge_rect, Color(0.035, 0.025, 0.02, 0.9))
	draw_rect(badge_rect, Color(0.88, 0.68, 0.34, 0.9), false, 1.0)
	var baseline := badge_rect.position + Vector2(4.0, 2.0 + font.get_ascent(font_size))
	draw_string(font, baseline, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.98, 0.92, 0.8))


func _definition_icon(definition: ContentDefinition) -> Texture2D:
	if definition is AbilityDefinition and definition.presentation_icon != null:
		return definition.presentation_icon
	return definition.icon if definition != null else null


func _fallback_glyph(definition: ContentDefinition, slot_kind: StringName) -> String:
	if definition == null:
		return "A" if slot_kind == &"ability" else "I"
	if definition is AbilityDefinition and not definition.presentation_text.is_empty() and definition.presentation_text.length() <= 3:
		return definition.presentation_text.to_upper()
	var words := definition.display_name.split(" ", false)
	var initials := ""
	for word in words:
		if not word.is_empty():
			initials += word.left(1).to_upper()
		if initials.length() == 2:
			break
	return initials if not initials.is_empty() else ("A" if slot_kind == &"ability" else "I")


func _accent_color(definition: ContentDefinition, slot_kind: StringName) -> Color:
	if definition is AbilityDefinition and definition.presentation_color != Color.WHITE:
		return definition.presentation_color
	if definition == null:
		return EMPTY_COLOR
	return ABILITY_COLOR if slot_kind == &"ability" else ITEM_COLOR


func _slot_style(accent: Color, emphasized: bool, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.96)
	style.border_width_left = 3 if emphasized else 2
	style.border_width_top = 3 if emphasized else 2
	style.border_width_right = 3 if emphasized else 2
	style.border_width_bottom = 3 if emphasized else 2
	style.border_color = Color(accent.r, accent.g, accent.b, alpha + (0.38 if emphasized else 0.2))
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.corner_detail = 1
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.25 if emphasized else 0.0)
	style.shadow_size = 8 if emphasized else 0
	return style


func _draw_padlock(center: Vector2, unit: float) -> void:
	var body := Rect2(center + Vector2(-unit, -unit * 0.1), Vector2(unit * 2.0, unit * 1.5))
	var metal := Color(0.86, 0.7, 0.44, 0.95)
	draw_arc(center + Vector2(0, -unit * 0.1), unit * 0.62, PI, TAU, 16, Color(0, 0, 0, 0.8), unit * 0.5, true)
	draw_arc(center + Vector2(0, -unit * 0.1), unit * 0.62, PI, TAU, 16, metal, unit * 0.28, true)
	draw_rect(body.grow(1.5), Color(0, 0, 0, 0.8))
	draw_rect(body, metal)
	draw_circle(body.get_center() + Vector2(0, -unit * 0.1), unit * 0.22, Color(0.2, 0.13, 0.07))
