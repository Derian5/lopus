class_name CombatStatisticsPanel
extends PanelContainer


signal unit_requested(runtime_id: String)

const METRICS: Array[StringName] = [&"damage_dealt", &"damage_tanked", &"effective_healing"]
const METRIC_LABELS := ["DAMAGE", "TANK", "HEAL"]

var team := CombatUnitSnapshot.Team.PLAYER
var selected_metric_index := 0
var statistics: CombatStatistics
var _accent := Color(0.48, 0.76, 1.0)
var _title := ""


func _ready() -> void:
	%DamageTab.pressed.connect(_select_metric.bind(0))
	%TankTab.pressed.connect(_select_metric.bind(1))
	%HealTab.pressed.connect(_select_metric.bind(2))
	_update_tabs()


func setup(title: String, team_id: int) -> void:
	team = team_id
	_title = title
	%Title.text = title
	var accent := Color(0.48, 0.76, 1.0) if team == CombatUnitSnapshot.Team.PLAYER else Color(1.0, 0.48, 0.42)
	_accent = accent
	%Title.add_theme_color_override("font_color", accent)
	var ornament := get_node_or_null("Ornament") as OrnateFrame
	if ornament != null:
		ornament.accent_color = accent


func set_statistics(value: CombatStatistics) -> void:
	statistics = value
	refresh()


func refresh() -> void:
	if statistics == null:
		for child in %Rows.get_children():
			child.free()
		return
	var metric := METRICS[selected_metric_index]
	var rows: Array[Dictionary] = []
	for data: Dictionary in statistics.unit_stats.values():
		if int(data.team) == team:
			rows.append(data)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_value := float(a.get(metric, 0.0))
		var b_value := float(b.get(metric, 0.0))
		if not is_equal_approx(a_value, b_value):
			return a_value > b_value
		if String(a.display_name) != String(b.display_name):
			return String(a.display_name) < String(b.display_name)
		return String(a.runtime_id) < String(b.runtime_id)
	)
	var max_value := 0.0
	var total := 0.0
	for data in rows:
		max_value = maxf(max_value, float(data.get(metric, 0.0)))
		total += float(data.get(metric, 0.0))
	%Title.text = "%s   %s" % [_title, CombatStatRow._format(total)] if total > 0.0 else _title
	# Reuse row controls between refreshes; the meter updates ten times per second.
	while %Rows.get_child_count() > rows.size():
		%Rows.get_child(%Rows.get_child_count() - 1).free()
	while %Rows.get_child_count() < rows.size():
		var new_row := CombatStatRow.new()
		new_row.pressed.connect(func() -> void: _request_unit(String(new_row.get_meta("runtime_id", ""))))
		%Rows.add_child(new_row)
	var registry := get_node_or_null("/root/ContentRegistry")
	for index in rows.size():
		var data := rows[index]
		var row := %Rows.get_child(index) as CombatStatRow
		var runtime_id := String(data.runtime_id)
		if String(row.get_meta("runtime_id", "")) != runtime_id or row.badge.is_empty():
			row.badge = UnitBadge.describe(data, registry)
		row.set_meta("runtime_id", runtime_id)
		var amount := float(data.get(metric, 0.0))
		row.configure(data, amount, max_value, _accent, row.badge, index)
		row.tooltip_text = "%s\n%s: %.1f   Kills: %d" % [String(data.display_name), METRIC_LABELS[selected_metric_index].capitalize(), amount, int(data.get("kills", 0))]


func _select_metric(index: int) -> void:
	selected_metric_index = index
	_update_tabs()
	refresh()


func _update_tabs() -> void:
	%DamageTab.button_pressed = selected_metric_index == 0
	%TankTab.button_pressed = selected_metric_index == 1
	%HealTab.button_pressed = selected_metric_index == 2


func _request_unit(runtime_id: String) -> void:
	unit_requested.emit(runtime_id)
