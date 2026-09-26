class_name CombatStatisticsPanel
extends PanelContainer


signal unit_requested(runtime_id: String)

const METRICS: Array[StringName] = [&"damage_dealt", &"damage_tanked", &"effective_healing"]
const METRIC_LABELS := ["DAMAGE", "TANK", "HEAL"]

var team := CombatUnitSnapshot.Team.PLAYER
var selected_metric_index := 0
var statistics: CombatStatistics


func _ready() -> void:
	%DamageTab.pressed.connect(_select_metric.bind(0))
	%TankTab.pressed.connect(_select_metric.bind(1))
	%HealTab.pressed.connect(_select_metric.bind(2))
	_update_tabs()


func setup(title: String, team_id: int) -> void:
	team = team_id
	%Title.text = title
	%Title.add_theme_color_override("font_color", Color(0.48, 0.76, 1.0) if team == CombatUnitSnapshot.Team.PLAYER else Color(1.0, 0.48, 0.42))


func set_statistics(value: CombatStatistics) -> void:
	statistics = value
	refresh()


func refresh() -> void:
	for child in %Rows.get_children():
		child.free()
	if statistics == null:
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
	for data in rows:
		var row := Button.new()
		row.custom_minimum_size = Vector2(0.0, 30.0)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.text = "%s%s  |  %.1f" % ["" if bool(data.alive) else "[DEAD] ", data.display_name, float(data.get(metric, 0.0))]
		row.tooltip_text = "%s: %.1f\nClick to inspect this unit." % [METRIC_LABELS[selected_metric_index].capitalize(), float(data.get(metric, 0.0))]
		row.pressed.connect(_request_unit.bind(String(data.runtime_id)))
		%Rows.add_child(row)


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
