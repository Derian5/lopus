extends Control


## Decorative frame of a Hero Selection card.
## Both states use the gothic bronze frame. Selected cards add a pulsing
## identity-colored aura, lit gems in the corners and a bronze crown on the top
## edge whose gem count equals the Hero's roster position.

const CUT := 26.0
const CORNER_GEM_SIZE := 34.0
const CROWN_GEM_SIZE := 40.0
const CROWN_GEM_SPACING := 44.0

var accent_color := Color(0.72, 0.62, 0.48)
var active := false
var selected := false
var selected_order := -1
var lit_gem: Texture2D
var dim_gem: Texture2D
var flash := 0.0:
	set(value):
		flash = value
		queue_redraw()

var _time := 0.0
var _flash_tween: Tween
var _bronze_box: StyleBoxTexture


func _ready() -> void:
	set_process(false)


func configure(color: Color, is_active: bool, order: int, lit_gem_texture: Texture2D, dim_gem_texture: Texture2D, animate := false) -> void:
	var was_selected := selected
	accent_color = color
	active = is_active
	selected_order = order
	selected = order >= 0
	lit_gem = lit_gem_texture
	dim_gem = dim_gem_texture
	set_process(selected and is_visible_in_tree())
	if animate and selected and not was_selected:
		play_selection_flash()
	elif not selected:
		_stop_flash()
	queue_redraw()


func play_selection_flash() -> void:
	_stop_flash()
	flash = 1.0
	_flash_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(self, "flash", 0.0, 0.55)


func _stop_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	flash = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(selected and is_visible_in_tree())


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var outer_rect := Rect2(Vector2(5, 5), size - Vector2(10, 10))
	if selected:
		_draw_selected(outer_rect)
	else:
		_draw_idle(outer_rect)


func _bronze() -> StyleBoxTexture:
	if _bronze_box == null:
		_bronze_box = OrnateFrame.bronze_box(false)
	return _bronze_box


func _draw_idle(outer_rect: Rect2) -> void:
	var box := _bronze()
	box.modulate_color = Color(1.0, 0.96, 0.9) if active else Color(0.72, 0.68, 0.62)
	draw_style_box(box, outer_rect)
	var line := accent_color
	line.a = 0.35 if active else 0.18
	draw_polyline(_chamfer(outer_rect.grow(-12.0), CUT - 8.0), line, 1.5, true)
	if dim_gem != null:
		for corner in _corner_points(outer_rect):
			_draw_gem(dim_gem, corner, CORNER_GEM_SIZE * 0.66, Color(0.8, 0.78, 0.74, 0.75 if active else 0.5))


func _draw_selected(outer_rect: Rect2) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 2.4)
	var glow := accent_color.lightened(0.15)

	# Identity-colored aura outside the bronze frame.
	for step in 4:
		var halo := glow
		halo.a = (0.26 - step * 0.06) * (0.6 + 0.4 * pulse) + flash * 0.16
		draw_polyline(_chamfer(outer_rect.grow(step * 3.0), CUT + step * 2.0), halo, 5.0, true)
	# Inner tint creeping from the edges.
	for step in 5:
		var tint := glow
		tint.a = (0.1 - step * 0.018) * (0.75 + 0.25 * pulse) + flash * 0.05
		draw_polyline(_chamfer(outer_rect.grow(-14.0 - step * 7.0), maxf(CUT - 10.0 - step * 3.0, 4.0)), tint, 8.0, true)

	var box := _bronze()
	box.modulate_color = Color(1.0, 1.0, 1.0).lerp(Color(1.3, 1.15, 0.92), 0.4 + 0.3 * pulse + flash * 0.3)
	draw_style_box(box, outer_rect)
	var line := accent_color.lightened(0.3)
	line.a = 0.75
	draw_polyline(_chamfer(outer_rect.grow(-12.0), CUT - 8.0), line, 2.0, true)

	_draw_crown(Vector2(size.x * 0.5, outer_rect.position.y), pulse)

	if lit_gem != null:
		var gem_tint := Color(1, 1, 1, 1).lerp(Color(1.35, 1.35, 1.35), pulse * 0.4 + flash * 0.6)
		for corner in _corner_points(outer_rect):
			_draw_gem(lit_gem, corner, CORNER_GEM_SIZE, gem_tint)

	if flash > 0.0:
		var flash_color := accent_color.lightened(0.6)
		flash_color.a = flash * 0.2
		draw_colored_polygon(_chamfer(outer_rect, CUT, false), flash_color)


func _draw_crown(center: Vector2, pulse: float) -> void:
	var count := clampi(selected_order + 1, 1, 3)
	var width := (count - 1) * CROWN_GEM_SPACING
	var crest := OrnateFrame.CREST_TEXTURE
	var crest_size := Vector2(width + 170.0, (width + 170.0) * crest.get_height() / crest.get_width())
	draw_texture_rect(crest, Rect2(center - crest_size * 0.5, crest_size), false, Color(1.15, 1.05, 0.9))
	if lit_gem == null:
		return
	var tint := Color(1, 1, 1, 1).lerp(Color(1.4, 1.4, 1.4, 1), pulse * 0.35 + flash * 0.65)
	for index in count:
		var gem_center := center + Vector2(-width * 0.5 + index * CROWN_GEM_SPACING, 0)
		var gem_size := CROWN_GEM_SIZE * (1.0 + flash * 0.35)
		_draw_gem(lit_gem, gem_center, gem_size, tint)


func _draw_edge_crest(origin: Vector2, inward: Vector2, color: Color, soft_color: Color, gem_radius: float, wing: float) -> void:
	var across := Vector2(inward.y, -inward.x)
	draw_line(origin - across * wing, origin + across * wing, color, 2.0, true)
	draw_line(origin - across * (wing - 12.0) + inward * 6.0, origin + across * (wing - 12.0) + inward * 6.0, soft_color, 1.0, true)
	var diamond := PackedVector2Array([
		origin - inward * gem_radius, origin + across * gem_radius, origin + inward * gem_radius, origin - across * gem_radius,
	])
	draw_colored_polygon(diamond, Color(0.02, 0.015, 0.025, 0.95))
	diamond.append(diamond[0])
	draw_polyline(diamond, color, 2.0, true)


func _draw_side_notch(origin: Vector2, inward: Vector2, color: Color) -> void:
	var along := Vector2(inward.y, -inward.x)
	var notch := PackedVector2Array([
		origin + along * 26.0, origin + inward * 10.0 + along * 10.0, origin + inward * 14.0,
		origin + inward * 10.0 - along * 10.0, origin - along * 26.0,
	])
	draw_polyline(notch, color, 2.0, true)


func _draw_gem(texture: Texture2D, center: Vector2, gem_size: float, tint: Color) -> void:
	draw_texture_rect(texture, Rect2(center - Vector2.ONE * gem_size * 0.5, Vector2.ONE * gem_size), false, tint)


func _corner_points(rect: Rect2) -> Array[Vector2]:
	var offset := CUT * 0.5
	return [
		rect.position + Vector2(offset, offset),
		Vector2(rect.end.x - offset, rect.position.y + offset),
		rect.end - Vector2(offset, offset),
		Vector2(rect.position.x + offset, rect.end.y - offset),
	]


func _chamfer(rect: Rect2, cut: float, closed := true) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var points := PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut),
		Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y),
		Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut),
	])
	if closed:
		points.append(points[0])
	return points
