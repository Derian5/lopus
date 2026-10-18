extends PanelContainer


signal continue_requested

const TAB_EXPERIENCE := 0
## Experience sources in bar order, matching the colors of the statistics tabs.
const XP_SOURCES := [
	{"key": "damage_xp", "label": "DAMAGE", "color": Color(0.92, 0.36, 0.3)},
	{"key": "tanking_xp", "label": "TANKING", "color": Color(0.42, 0.68, 0.96)},
	{"key": "healing_xp", "label": "HEALING", "color": Color(0.38, 0.84, 0.58)},
]
const TAB_DAMAGE := 1
const TAB_TANKING := 2
const TAB_HEALING := 3
const TAB_LOSSES := 4

var selected_tab := TAB_EXPERIENCE
var current_result: CombatResult

@onready var tab_buttons: Array[Button] = [
	%ExperienceTab,
	%DamageTab,
	%TankingTab,
	%HealingTab,
	%LossesTab,
]


func _ready() -> void:
	for index in tab_buttons.size():
		tab_buttons[index].pressed.connect(_select_tab.bind(index))


func show_result(result: CombatResult) -> void:
	current_result = result
	var timeout_text := " / TIME LIMIT" if result.timed_out else ""
	%ResultTitle.text = ("VICTORY" if result.winner == &"player" else "DEFEAT") + timeout_text
	var victory := result.winner == &"player"
	%ResultTitle.add_theme_color_override("font_color", UiStyle.GOLD if victory else Color(0.95, 0.38, 0.32))
	var ornament := get_node_or_null("Ornament") as OrnateFrame
	if ornament != null:
		ornament.accent_color = UiStyle.GOLD if victory else UiStyle.RED
		ornament.corner_gem = &"gold" if victory else &"red"
		ornament.play_flash(0.7)
	%XpLabel.text = "TOTAL XP EARNED  %d" % _total_earned_xp(result)
	%RewardLabel.text = "GOLD  +%d" % int(result.application_summary.get("gold", 0))
	var seconds := int(roundf(result.duration))
	var meta := "DURATION  %d:%02d" % [seconds / 60, seconds % 60]
	var best := {}
	for data: Dictionary in _player_statistics():
		if best.is_empty() or float(data.get("damage_dealt", 0.0)) > float(best.get("damage_dealt", 0.0)):
			best = data
	if not best.is_empty() and float(best.get("damage_dealt", 0.0)) > 0.0:
		meta += "      MVP  %s" % String(best.get("display_name", ""))
	%MetaLabel.text = meta
	_select_tab(TAB_EXPERIENCE)
	visible = true


func hide_summary() -> void:
	visible = false


func _on_continue_pressed() -> void:
	continue_requested.emit()


func _select_tab(tab_index: int) -> void:
	selected_tab = clampi(tab_index, TAB_EXPERIENCE, TAB_LOSSES)
	for index in tab_buttons.size():
		tab_buttons[index].set_pressed_no_signal(index == selected_tab)
	_clear_rows()
	_xp_legend().visible = selected_tab == TAB_EXPERIENCE
	if current_result == null:
		return
	match selected_tab:
		TAB_EXPERIENCE:
			_show_experience()
		TAB_DAMAGE:
			_show_metric(&"damage_dealt", "DAMAGE DEALT", "TOTAL DAMAGE", Color(0.92, 0.36, 0.3))
		TAB_TANKING:
			_show_metric(&"damage_tanked", "DAMAGE TANKED", "TOTAL TANKED", Color(0.42, 0.68, 0.96))
		TAB_HEALING:
			_show_metric(&"effective_healing", "EFFECTIVE HEALING", "TOTAL HEALING", Color(0.38, 0.84, 0.58))
		TAB_LOSSES:
			_show_losses()


func _show_losses() -> void:
	var deaths := current_result.get_player_deaths()
	%TabEyebrow.text = "BATTLE CONSEQUENCES"
	%TabTitle.text = "PLAYER LOSSES"
	%TabSummary.text = "%d UNIT%s LOST" % [deaths.size(), "" if deaths.size() == 1 else "S"]
	_set_headers("UNIT", "KILLED BY", "FINAL BLOW")
	if deaths.is_empty():
		_add_empty_row("No Heroes or Soldiers were lost.")
	else:
		for death in deaths:
			_add_row(
				String(death.get("display_name", "Unknown unit")),
				_unit_name(String(death.get("killer_id", ""))),
				_effect_name(String(death.get("last_effect_id", ""))),
				Color(0.88, 0.4, 0.36),
				death,
				0.0,
				true
			)
func _show_experience() -> void:
	var changes: Array = current_result.application_summary.get("contribution_changes", [])
	%TabEyebrow.text = "POST-BATTLE PROGRESSION"
	%TabTitle.text = "EXPERIENCE ACQUIRED"
	%TabSummary.text = ""
	_set_headers("UNIT", "XP", "PROGRESSION")
	if changes.is_empty():
		_add_empty_row("No experience was acquired.")
		return
	var max_xp := 0
	for change: Dictionary in changes:
		max_xp = maxi(max_xp, int(change.get("xp", 0)))
	for change: Dictionary in changes:
		var lost := bool(change.get("lost", false))
		var xp := int(change.get("xp", 0))
		var detail := "HERO XP" if int(change.get("unit_kind", -1)) == CombatUnitSnapshot.UnitKind.HERO else "VETERANCY XP"
		if lost:
			detail = "%d XP LOST WITH UNIT" % int(change.get("potential_xp", 0))
		elif change.has("old_level") and int(change.get("new_level", 0)) > int(change.get("old_level", 0)):
			detail += " / LEVEL %d" % int(change.get("new_level", 0))
		if int(change.get("bonus_xp", 0)) > 0:
			detail += " / ENVY +%d" % int(change.get("bonus_xp", 0))
		var unit_data := current_result.get_unit_statistics(String(change.get("runtime_id", "")))
		var leveled := change.has("old_level") and int(change.get("new_level", 0)) > int(change.get("old_level", 0))
		_add_row(
			String(change.get("display_name", "Unknown unit")),
			"+%d" % xp if not lost else "+0",
			detail,
			Color(0.9, 0.72, 0.32) if not lost else Color(0.78, 0.38, 0.36),
			unit_data,
			float(xp) / float(max_xp) if max_xp > 0 else 0.0,
			lost or bool(change.get("died", false)),
			leveled
		)
		if not lost:
			var row := %Rows.get_child(-1) as PostBattleRow
			var contribution: Dictionary = change.get("contribution", {})
			row.segments = _xp_segments(contribution)
			row.tooltip_text = _xp_tooltip(contribution, int(change.get("bonus_xp", 0)))


## Splits the XP bar by source, proportional to the XP each source granted.
static func _xp_segments(contribution: Dictionary) -> Array:
	var total := 0.0
	for source: Dictionary in XP_SOURCES:
		total += maxf(0.0, float(contribution.get(source.key, 0)))
	if total <= 0.0:
		return []
	var segments := []
	for source: Dictionary in XP_SOURCES:
		var amount := maxf(0.0, float(contribution.get(source.key, 0)))
		if amount > 0.0:
			segments.append({"share": amount / total, "color": source.color})
	return segments


static func _xp_tooltip(contribution: Dictionary, bonus_xp: int) -> String:
	var parts: Array[String] = []
	for source: Dictionary in XP_SOURCES:
		parts.append("%s +%d" % [String(source.label).capitalize(), int(contribution.get(source.key, 0))])
	var text := "  ·  ".join(parts)
	if bool(contribution.get("was_capped", false)):
		text += "\nCapped at %d XP" % int(contribution.get("total_xp", 0))
	if bonus_xp > 0:
		text += "\nBonus +%d" % bonus_xp
	return text


## Small color key shown next to the title on the Experience tab.
func _xp_legend() -> HBoxContainer:
	var existing := %TabSummary.get_parent().get_node_or_null("XpLegend") as HBoxContainer
	if existing != null:
		return existing
	var legend := HBoxContainer.new()
	legend.name = "XpLegend"
	legend.alignment = BoxContainer.ALIGNMENT_END
	legend.add_theme_constant_override("separation", 14)
	for source: Dictionary in XP_SOURCES:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.color = source.color
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)
		var label := Label.new()
		label.text = String(source.label)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
		item.add_child(label)
		legend.add_child(item)
	%TabSummary.get_parent().add_child(legend)
	return legend


func _total_earned_xp(result: CombatResult) -> int:
	var total := 0
	for change: Dictionary in result.application_summary.get("contribution_changes", []):
		if not bool(change.get("lost", false)):
			total += int(change.get("xp", 0))
	return total


func _show_metric(metric: StringName, title: String, total_label: String, color: Color) -> void:
	var statistics := _player_statistics()
	statistics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_value := float(a.get(metric, 0.0))
		var b_value := float(b.get(metric, 0.0))
		if not is_equal_approx(a_value, b_value):
			return a_value > b_value
		return String(a.get("display_name", "")) < String(b.get("display_name", ""))
	)
	var total := 0.0
	for data: Dictionary in statistics:
		total += float(data.get(metric, 0.0))
	%TabEyebrow.text = "COMPANY PERFORMANCE"
	%TabTitle.text = title
	%TabSummary.text = "%s  %.1f" % [total_label, total]
	_set_headers("UNIT", "AMOUNT", "SHARE")
	if statistics.is_empty():
		_add_empty_row("No company statistics were recorded.")
		return
	var max_value := 0.0
	for data: Dictionary in statistics:
		max_value = maxf(max_value, float(data.get(metric, 0.0)))
	for index in statistics.size():
		var data: Dictionary = statistics[index]
		var value := float(data.get(metric, 0.0))
		var share := value / total * 100.0 if total > 0.0 else 0.0
		var kills := int(data.get("kills", 0))
		var detail := "%.1f%% OF COMPANY" % share
		if kills > 0:
			detail += "   ·   %d KILL%s" % [kills, "" if kills == 1 else "S"]
		_add_row(
			String(data.get("display_name", "Unknown unit")),
			"%.1f" % value,
			detail,
			color,
			data,
			value / max_value if max_value > 0.0 else 0.0,
			int(data.get("deaths", 0)) > 0,
			index == 0 and value > 0.0,
			index
		)


func _player_statistics() -> Array[Dictionary]:
	var statistics: Array[Dictionary] = []
	for data: Dictionary in current_result.unit_statistics:
		if (
			int(data.get("team", -1)) == CombatUnitSnapshot.Team.PLAYER
			and int(data.get("unit_kind", -1)) in [CombatUnitSnapshot.UnitKind.HERO, CombatUnitSnapshot.UnitKind.SOLDIER]
		):
			statistics.append(data)
	return statistics


func _unit_name(runtime_id: String) -> String:
	if runtime_id.is_empty():
		return "UNKNOWN"
	var data := current_result.get_unit_statistics(runtime_id)
	return String(data.get("display_name", runtime_id))


func _effect_name(effect_id: String) -> String:
	if effect_id.is_empty():
		return "Unknown"
	if effect_id in ["basic", "basic_attack", "attack"]:
		return "Basic attack"
	var definition = get_node("/root/ContentRegistry").get_definition(StringName(effect_id), false)
	if definition is ContentDefinition:
		return (definition as ContentDefinition).display_name
	return effect_id.get_slice(".", effect_id.get_slice_count(".") - 1).replace("_", " ").capitalize()


func _set_headers(primary: String, value: String, detail: String) -> void:
	%PrimaryHeader.text = primary
	%ValueHeader.text = value
	%DetailHeader.text = detail


func _clear_rows() -> void:
	for child in %Rows.get_children():
		child.free()


func _add_empty_row(message: String) -> void:
	var label := Label.new()
	label.custom_minimum_size.y = 76.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.73))
	label.add_theme_font_size_override("font_size", 18)
	%Rows.add_child(label)


func _add_row(
	primary: String,
	value: String,
	detail: String,
	accent: Color,
	data: Dictionary = {},
	fraction := 0.0,
	dead := false,
	mvp := false,
	rank := -1
) -> void:
	var panel := PostBattleRow.new()
	panel.fraction = fraction
	panel.accent = accent
	panel.highlighted = mvp
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.032, 0.022, 0.92) if not dead else Color(0.035, 0.026, 0.02, 0.85)
	style.set_corner_radius_all(6)
	style.corner_detail = 1
	style.border_width_left = 3
	style.border_color = Color(accent.r, accent.g, accent.b, 0.82) if not dead else Color(0.5, 0.2, 0.18, 0.8)
	if mvp:
		style.set_border_width_all(1)
		style.border_width_left = 3
		style.border_color = UiStyle.GOLD
		style.shadow_color = Color(UiStyle.GOLD.r, UiStyle.GOLD.g, UiStyle.GOLD.b, 0.18)
		style.shadow_size = 6
	style.content_margin_left = 10.0
	style.content_margin_top = 5.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", style)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	panel.add_child(columns)

	var name_cell := HBoxContainer.new()
	name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_cell.size_flags_stretch_ratio = 3
	name_cell.add_theme_constant_override("separation", 8)
	columns.add_child(name_cell)
	if rank >= 0:
		var rank_label := Label.new()
		rank_label.text = "%d" % (rank + 1)
		rank_label.custom_minimum_size.x = 20.0
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rank_label.theme_type_variation = &"NumberLabel"
		rank_label.add_theme_font_size_override("font_size", 15)
		rank_label.add_theme_color_override("font_color", UiStyle.GOLD if mvp else UiStyle.TEXT_MUTED)
		name_cell.add_child(rank_label)
	var badge := UnitBadgeView.new()
	badge.custom_minimum_size = Vector2(30, 30)
	badge.setup(UnitBadge.describe(data, get_node_or_null("/root/ContentRegistry")) if not data.is_empty() else {}, dead, mvp)
	name_cell.add_child(badge)
	var name_label := StrikeLabel.new()
	name_label.text = primary
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color(0.62, 0.57, 0.5) if dead else Color(0.92, 0.88, 0.8))
	name_label.struck = dead
	name_cell.add_child(name_label)

	var value_label := _row_label(value, 1, HORIZONTAL_ALIGNMENT_RIGHT, accent if not dead else Color(0.78, 0.4, 0.36))
	value_label.theme_type_variation = &"NumberLabel"
	value_label.add_theme_font_size_override("font_size", 17)
	columns.add_child(value_label)
	var detail_label := _row_label(detail, 2, HORIZONTAL_ALIGNMENT_LEFT, Color(0.66, 0.6, 0.52))
	detail_label.add_theme_font_size_override("font_size", 15)
	columns.add_child(detail_label)
	%Rows.add_child(panel)


func _row_label(text: String, stretch_ratio: float, alignment: HorizontalAlignment, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = stretch_ratio
	label.horizontal_alignment = alignment
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 18)
	return label
