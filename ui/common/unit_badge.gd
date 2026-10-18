class_name UnitBadge
extends RefCounted


## Shared identity marks for statistics rows: Hero crests, job/enemy medallions
## and the skull used for fallen units.


## Returns {"texture": Texture2D or null, "glyph": String, "color": Color, "hero": bool}
## for a statistics entry (CombatStatistics.unit_stats / CombatResult.unit_statistics).
static func describe(data: Dictionary, registry: Node) -> Dictionary:
	var definition_id := StringName(data.get("definition_id", ""))
	var kind := int(data.get("unit_kind", -1))
	var name := String(data.get("display_name", "?"))
	var info := {"texture": null, "glyph": name.left(1).to_upper(), "color": Color(0.7, 0.6, 0.48), "hero": false}
	if registry == null:
		return info
	if kind == CombatUnitSnapshot.UnitKind.HERO:
		var hero := registry.get_definition(definition_id, false) as HeroDefinition
		if hero != null:
			info.texture = HeroSelectionCard.atlas_texture(HeroSelectionCard.BADGE_REGIONS[HeroSelectionCard.identity_index_of(hero)])
			info.color = hero.placeholder_color
			info.hero = true
		return info
	var job_id := StringName(data.get("job_id", ""))
	if not String(job_id).is_empty():
		var job := registry.get_definition(job_id, false) as JobDefinition
		if job != null:
			info.glyph = job.display_name.left(1).to_upper()
			info.color = job.placeholder_color
			return info
	var definition = registry.get_definition(definition_id, false)
	if definition is EnemyDefinition:
		info.color = (definition as EnemyDefinition).placeholder_color
		info.glyph = (definition as EnemyDefinition).display_name.left(1).to_upper()
	return info


## Draws a round medallion (or Hero crest) centered in rect. Fallen units get a skull.
static func draw_badge(canvas: CanvasItem, rect: Rect2, info: Dictionary, dead: bool, font: Font) -> void:
	var center := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.5
	if dead:
		draw_skull(canvas, center, radius * 0.9, Color(0.86, 0.8, 0.72, 0.9))
		return
	var color: Color = info.color
	var texture = info.get("texture")
	if texture is Texture2D:
		var crest := Vector2(radius * 1.6, radius * 1.95)
		canvas.draw_texture_rect(texture, Rect2(center - crest * 0.5, crest), false)
		return
	canvas.draw_circle(center, radius, Color(0.07, 0.05, 0.035, 0.95))
	canvas.draw_arc(center, radius - 1.0, 0.0, TAU, 32, color, 2.0, true)
	var size := int(radius * 1.1)
	canvas.draw_string(font, center + Vector2(-radius, size * 0.36), String(info.glyph), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, size, color.lightened(0.45))


## Minimal engraved skull: cranium, cheekbones, eye sockets, nose and teeth.
static func draw_skull(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var dark := Color(0.06, 0.04, 0.03, 1.0)
	var cranium := center + Vector2(0.0, -radius * 0.12)
	canvas.draw_circle(cranium, radius * 0.78, color)
	canvas.draw_rect(Rect2(center + Vector2(-radius * 0.42, radius * 0.2), Vector2(radius * 0.84, radius * 0.5)), color)
	canvas.draw_circle(cranium + Vector2(-radius * 0.3, radius * 0.08), radius * 0.2, dark)
	canvas.draw_circle(cranium + Vector2(radius * 0.3, radius * 0.08), radius * 0.2, dark)
	var nose := cranium + Vector2(0.0, radius * 0.38)
	canvas.draw_colored_polygon(PackedVector2Array([nose + Vector2(0, -radius * 0.1), nose + Vector2(radius * 0.08, radius * 0.06), nose + Vector2(-radius * 0.08, radius * 0.06)]), dark)
	for index in 3:
		var x := center.x + (index - 1) * radius * 0.26
		canvas.draw_line(Vector2(x, center.y + radius * 0.42), Vector2(x, center.y + radius * 0.7), dark, maxf(1.0, radius * 0.08), true)
