class_name UnitBadgeView
extends Control


## Small control that shows a unit's crest/medallion, or a skull when fallen.

var info := {}
var dead := false
var mvp := false


func setup(badge_info: Dictionary, is_dead: bool, is_mvp := false) -> void:
	info = badge_info
	dead = is_dead
	mvp = is_mvp
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	if info.is_empty() and not dead:
		return
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
	UnitBadge.draw_badge(self, rect, info, dead, get_theme_default_font())
	if mvp:
		var gem := OrnateFrame.gem_texture(&"gold")
		var gem_size := side * 0.48
		draw_texture_rect(gem, Rect2(rect.end - Vector2.ONE * gem_size * 0.85, Vector2.ONE * gem_size), false)
