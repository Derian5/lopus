class_name BattlefieldPreview
extends Control


## Interactive miniature of the battlefield for the War Council.
## Shows the selected encounter's enemy line and lets the player drag their own
## units inside the deployment zone. Positions are stored through FormationService.

signal formation_changed
signal unit_selected(kind: String, index: int)

const BATTLEGROUND := preload("res://graphics/battleground.png")
const GOLD := Color(0.96, 0.77, 0.4)
const ENEMY_RED := Color(0.86, 0.24, 0.18)
const ZONE_FILL := Color(0.95, 0.72, 0.32, 0.07)
const PADDING := 22.0

var run_state: RunState
var tokens: Array[Dictionary] = []
var encounter: EncounterDefinition
var hovered_id := ""
var dragging_id := ""
var highlighted_id := ""
var _drag_offset := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _bronze: StyleBoxTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func setup(new_run_state: RunState) -> void:
	run_state = new_run_state
	refresh()


func refresh() -> void:
	tokens.clear()
	if run_state == null:
		queue_redraw()
		return
	var registry := _registry()
	FormationService.prune(run_state)
	var snapshots := CombatSnapshotBuilder.build_player_army(run_state, registry)
	var positions := FormationService.normalized_positions(snapshots, true)
	for snapshot in snapshots:
		tokens.append(_player_token(snapshot, Vector2(positions[snapshot.runtime_id])))
	encounter = null
	if not String(run_state.selected_encounter_id).is_empty():
		encounter = registry.get_definition(run_state.selected_encounter_id, false) as EncounterDefinition
	if encounter != null and not encounter.is_unknown:
		var enemies := CombatDemoFactory.create_enemy_army_from_encounter(encounter)
		var enemy_positions := FormationService.normalized_positions(enemies, false)
		for snapshot in enemies:
			tokens.append({
				"id": snapshot.runtime_id, "kind": "enemy", "index": -1, "team": "enemy",
				"name": snapshot.display_name, "color": snapshot.placeholder_color,
				"glyph": snapshot.display_name.left(1).to_upper(), "badge": null,
				"ranged": snapshot.attack_type == &"ranged", "range": snapshot.stats.attack_range,
				"pos": Vector2(enemy_positions[snapshot.runtime_id]), "boss": snapshot.is_boss,
			})
	queue_redraw()


func highlight_unit(unit_id: String) -> void:
	highlighted_id = unit_id
	queue_redraw()


func reset_formation() -> void:
	if run_state == null:
		return
	FormationService.reset(run_state)
	refresh()
	formation_changed.emit()


func player_positions() -> Dictionary:
	var result := {}
	for token in tokens:
		if token.team == "player":
			result[token.id] = token.pos
	return result


## Moves a player unit to a normalized position (used by drag & drop and tests).
func move_unit(unit_id: String, normalized: Vector2) -> bool:
	var token := _token(unit_id)
	if token.is_empty() or token.team != "player":
		return false
	var start: Vector2 = token.pos
	token.pos = FormationService.snap(normalized)
	var other := _overlapping_token(token)
	if not other.is_empty():
		other.pos = start
	FormationService.store_formation(run_state, player_positions())
	queue_redraw()
	formation_changed.emit()
	return true


# --- geometry -----------------------------------------------------------

func arena_rect() -> Rect2:
	var available := size - Vector2.ONE * PADDING * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var aspect := FormationService.REFERENCE_ARENA.x / FormationService.REFERENCE_ARENA.y
	var arena_size := Vector2(available.x, available.x / aspect)
	if arena_size.y > available.y:
		arena_size = Vector2(available.y * aspect, available.y)
	return Rect2((size - arena_size) * 0.5, arena_size)


func _to_screen(normalized: Vector2) -> Vector2:
	var rect := arena_rect()
	return rect.position + normalized * rect.size


func _to_normalized(point: Vector2) -> Vector2:
	var rect := arena_rect()
	return (point - rect.position) / rect.size


func _token_radius(token: Dictionary) -> float:
	var base := clampf(arena_rect().size.y * 0.036, 13.0, 28.0)
	return base * (1.28 if token.kind == "hero" or bool(token.get("boss", false)) else 1.0)


func _token_at(point: Vector2, player_only := true) -> Dictionary:
	for index in range(tokens.size() - 1, -1, -1):
		var token := tokens[index]
		if player_only and token.team != "player":
			continue
		if _to_screen(token.pos).distance_to(point) <= _token_radius(token) + 3.0:
			return token
	return {}


func _token(unit_id: String) -> Dictionary:
	for token in tokens:
		if token.id == unit_id:
			return token
	return {}


func _overlapping_token(moved: Dictionary) -> Dictionary:
	for token in tokens:
		if token == moved or token.team != "player":
			continue
		if _to_screen(token.pos).distance_to(_to_screen(moved.pos)) < (_token_radius(token) + _token_radius(moved)) * 0.8:
			return token
	return {}


# --- input ---------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var token := _token_at(event.position)
			if token.is_empty():
				return
			if event.double_click:
				unit_selected.emit(token.kind, int(token.index))
				return
			dragging_id = token.id
			_drag_start = token.pos
			_drag_offset = event.position - _to_screen(token.pos)
			accept_event()
			queue_redraw()
		elif not dragging_id.is_empty():
			var token := _token(dragging_id)
			var target: Vector2 = token.pos
			token.pos = _drag_start
			dragging_id = ""
			move_unit(token.id, target)
			hovered_id = String(_token_at(event.position, false).get("id", ""))
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		if not dragging_id.is_empty():
			var token := _token(dragging_id)
			token.pos = FormationService.clamp_to_zone(_to_normalized(event.position - _drag_offset))
			queue_redraw()
			accept_event()
		else:
			var hovered := _token_at(event.position, false)
			var new_id: String = hovered.get("id", "")
			if new_id != hovered_id:
				hovered_id = new_id
				mouse_default_cursor_shape = Control.CURSOR_DRAG if hovered.get("team", "") == "player" else Control.CURSOR_ARROW
				queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and dragging_id.is_empty():
		hovered_id = ""
		queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var token := _token_at(at_position, false)
	if token.is_empty():
		return ""
	var role := "Ranged" if bool(token.ranged) else "Melee"
	if token.team == "player":
		return "%s\n%s  -  range %d" % [token.name, role, int(token.range)]
	return "%s\n%s  -  range %d" % [token.name, role, int(token.range)]


# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	var rect := arena_rect()
	var font := get_theme_default_font()
	_draw_background(rect)
	_draw_zones(rect, font)
	_draw_reinforcements(rect, font)
	# The attack range is shown only for the unit being dragged or hovered; the unit
	# selected in the roster keeps just its gold ring.
	var focus_id := dragging_id if not dragging_id.is_empty() else hovered_id
	var focus := _token(focus_id)
	if not focus.is_empty():
		var radius := float(focus.range) * rect.size.x / FormationService.REFERENCE_ARENA.x + _token_radius(focus)
		var ring := GOLD if focus.team == "player" else ENEMY_RED
		ring.a = 0.10
		draw_circle(_to_screen(focus.pos), radius, ring)
		ring.a = 0.55
		draw_arc(_to_screen(focus.pos), radius, 0.0, TAU, 72, ring, 1.5, true)
	for token in tokens:
		if token.id != dragging_id:
			_draw_token(token, font, token.id == focus_id)
	if not dragging_id.is_empty():
		_draw_token(_token(dragging_id), font, true)
	for token in tokens:
		_draw_token_name(token, font, token.id == focus_id)


func _draw_background(rect: Rect2) -> void:
	var texture_size := BATTLEGROUND.get_size()
	var scale := maxf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var source_size := rect.size / scale
	var source := Rect2((texture_size - source_size) * 0.5, source_size)
	draw_texture_rect_region(BATTLEGROUND, rect, source, Color(0.72, 0.66, 0.6))
	draw_rect(rect, Color(0.02, 0.012, 0.008, 0.28))
	if _bronze == null:
		_bronze = OrnateFrame.bronze_box(false)
	draw_style_box(_bronze, rect.grow(12.0))


func _draw_zones(rect: Rect2, font: Font) -> void:
	var enemy_rect := Rect2(rect.position + Vector2(rect.size.x * 0.56, 0.0), Vector2(rect.size.x * 0.44, rect.size.y))
	draw_rect(enemy_rect, Color(0.45, 0.06, 0.03, 0.14))
	var mid_x := rect.position.x + rect.size.x * 0.5
	_draw_dashed(Vector2(mid_x, rect.position.y + 8.0), Vector2(mid_x, rect.end.y - 8.0), Color(0.86, 0.66, 0.38, 0.35), 2.0, 10.0)

	var zone := Rect2(rect.position + FormationService.DEPLOY_ZONE.position * rect.size, FormationService.DEPLOY_ZONE.size * rect.size)
	var active := not dragging_id.is_empty()
	var fill := ZONE_FILL
	fill.a = 0.13 if active else 0.07
	draw_rect(zone, fill)
	var border := GOLD
	border.a = 0.8 if active else 0.45
	var corners := [zone.position, Vector2(zone.end.x, zone.position.y), zone.end, Vector2(zone.position.x, zone.end.y)]
	for index in 4:
		_draw_dashed(corners[index], corners[(index + 1) % 4], border, 1.5, 8.0)
	if active:
		var dot := GOLD
		dot.a = 0.22
		var step := FormationService.GRID_STEP * rect.size
		var y := zone.position.y
		while y <= zone.end.y + 0.5:
			var x := zone.position.x
			while x <= zone.end.x + 0.5:
				draw_circle(Vector2(x, y), 1.4, dot)
				x += step.x * 2.0
			y += step.y * 2.0
	if encounter == null:
		pass
	elif encounter.is_unknown:
		draw_rect(enemy_rect, Color(0.02, 0.015, 0.012, 0.55))
		draw_string(font, enemy_rect.get_center() + Vector2(-enemy_rect.size.x * 0.5, 30.0), "?", HORIZONTAL_ALIGNMENT_CENTER, enemy_rect.size.x, 96, Color(1.0, 0.75, 0.6, 0.55))


func _draw_reinforcements(rect: Rect2, font: Font) -> void:
	if encounter == null or not encounter.has_reinforcements():
		return
	var count := encounter.reinforcement_enemy_ids.size()
	var color := Color(1.0, 0.45, 0.32, 0.8)
	var right_only := encounter.reinforcement_entry_direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE
	var points: Array[Vector2] = [Vector2(rect.end.x - 18.0, rect.get_center().y)]
	if not right_only:
		points.append(Vector2(rect.get_center().x, rect.position.y + 18.0))
		points.append(Vector2(rect.get_center().x, rect.end.y - 18.0))
	for point in points:
		var inward := (rect.get_center() - point).normalized()
		var across := Vector2(-inward.y, inward.x)
		for chevron in 2:
			var tip := point + inward * (chevron * 12.0 + 10.0)
			draw_polyline(PackedVector2Array([tip - inward * 9.0 + across * 9.0, tip, tip - inward * 9.0 - across * 9.0]), color, 3.0, true)
	var label := "+%d" % count if not encounter.is_unknown else "+?"
	_draw_right_text(font, Vector2(rect.end.x - 12.0, rect.end.y - 14.0), label, 14, color)


func _draw_token(token: Dictionary, font: Font, focused: bool) -> void:
	var center := _to_screen(token.pos)
	var radius := _token_radius(token)
	var color: Color = token.color
	var player: bool = token.team == "player"
	draw_circle(center + Vector2(0, radius * 0.55), radius * 0.9, Color(0, 0, 0, 0.35))
	if focused:
		for step in 3:
			var glow := color.lightened(0.2)
			glow.a = 0.22 - step * 0.06
			draw_circle(center, radius + 4.0 + step * 4.0, glow)
	if token.id == highlighted_id and not focused:
		draw_arc(center, radius + 6.0, 0.0, TAU, 48, GOLD, 2.0, true)
	draw_circle(center, radius, Color(0.07, 0.05, 0.035, 0.96))
	var ring := color if player else color.lerp(ENEMY_RED, 0.4)
	draw_arc(center, radius - 1.5, 0.0, TAU, 48, ring, 3.0, true)
	if bool(token.ranged):
		draw_arc(center, radius - 6.0, 0.0, TAU, 40, Color(ring.r, ring.g, ring.b, 0.6), 1.2, true)
	draw_arc(center, radius + 0.5, 0.0, TAU, 48, Color(0.66, 0.48, 0.27, 0.9), 1.0, true)
	var badge = token.get("badge")
	if badge is Texture2D:
		var badge_size := Vector2(radius * 1.15, radius * 1.38)
		draw_texture_rect(badge, Rect2(center - badge_size * 0.5, badge_size), false)
	else:
		var glyph_size := int(radius * 1.05)
		draw_string(font, center + Vector2(-radius, glyph_size * 0.36), String(token.glyph), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, glyph_size, ring.lightened(0.45))
	if int(token.get("veterancy", -1)) >= 0:
		VeterancyInsignia.draw_insignia(self, center + Vector2(radius * 0.78, -radius * 0.78), int(token.veterancy), maxf(9.0, radius * 0.55))


func _draw_token_name(token: Dictionary, font: Font, focused: bool) -> void:
	if not focused and token.kind != "hero":
		return
	var center := _to_screen(token.pos)
	var radius := _token_radius(token)
	var name_color := Color(0.98, 0.9, 0.75, 0.95 if focused else 0.8)
	draw_string_outline(font, center + Vector2(-80.0, radius + 16.0), String(token.name), HORIZONTAL_ALIGNMENT_CENTER, 160.0, 14, 5, Color(0, 0, 0, 0.9))
	draw_string(font, center + Vector2(-80.0, radius + 16.0), String(token.name), HORIZONTAL_ALIGNMENT_CENTER, 160.0, 14, name_color)


func _draw_right_text(font: Font, anchor: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, anchor - Vector2(width, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var direction := (to - from) / length
	var travelled := 0.0
	while travelled < length:
		var end := minf(travelled + dash, length)
		draw_line(from + direction * travelled, from + direction * end, color, width, true)
		travelled += dash * 2.0


func _player_token(snapshot: CombatUnitSnapshot, position: Vector2) -> Dictionary:
	var kind := "hero" if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else "soldier"
	var index := -1
	var badge: Texture2D = null
	if kind == "hero":
		for hero_index in run_state.heroes.size():
			if run_state.heroes[hero_index].unique_id == snapshot.runtime_id:
				index = hero_index
				var definition := _registry().get_definition(run_state.heroes[hero_index].definition_id, false) as HeroDefinition
				if definition != null:
					badge = HeroSelectionCard.atlas_texture(HeroSelectionCard.BADGE_REGIONS[HeroSelectionCard.identity_index_of(definition)])
				break
	else:
		for soldier_index in run_state.soldiers.size():
			if run_state.soldiers[soldier_index].unique_id == snapshot.runtime_id:
				index = soldier_index
				break
	var job := _registry().get_definition(snapshot.job_id, false) as JobDefinition
	var glyph := job.display_name.left(1).to_upper() if job != null else "S"
	return {
		"id": snapshot.runtime_id, "kind": kind, "index": index, "team": "player",
		"name": snapshot.display_name, "color": snapshot.placeholder_color, "glyph": glyph, "badge": badge,
		"veterancy": snapshot.veterancy_level if kind == "soldier" else -1,
		"ranged": snapshot.attack_type == &"ranged", "range": snapshot.stats.attack_range, "pos": position, "boss": false,
	}


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
