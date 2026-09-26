class_name EncounterChoiceScreen
extends Control

signal encounter_selected(encounter_id: StringName)

var run_state: RunState

@onready var route_label: Label = %RouteLabel
@onready var cards: HBoxContainer = %Cards
@onready var status_label: Label = %StatusLabel


func set_run_state(value: RunState) -> void:
	run_state = value
	if not is_node_ready():
		await ready
	_render()


func _set_feedback(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("e38375") if is_error else Color("91c99a"))


func _render() -> void:
	for child in cards.get_children():
		child.queue_free()
	if run_state == null:
		status_label.text = "No active expedition."
		return
	route_label.text = "ACT %d  /  BATTLE %d" % [run_state.current_act, run_state.encounter_index + 1]
	for encounter_id in run_state.available_encounter_ids:
		var encounter := get_node("/root/ContentRegistry").get_definition(encounter_id, false) as EncounterDefinition
		if encounter != null:
			cards.add_child(_build_card(encounter))
	status_label.text = "Study the opposition. This choice cannot be changed after you proceed."


func _build_card(encounter: EncounterDefinition) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(410.0, 430.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18202b")
	style.border_color = Color("65788d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var difficulty := Label.new()
	difficulty.text = "%s THREAT" % encounter.difficulty_hint.to_upper()
	difficulty.add_theme_color_override("font_color", Color("d7a958"))
	difficulty.add_theme_font_size_override("font_size", 15)
	column.add_child(difficulty)
	var title := Label.new()
	title.text = encounter.display_name.to_upper()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	var divider := HSeparator.new()
	column.add_child(divider)
	var description := Label.new()
	description.text = encounter.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_color_override("font_color", Color("b9c3cf"))
	column.add_child(description)
	var properties := Label.new()
	properties.text = _properties_text(encounter)
	properties.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	properties.add_theme_color_override("font_color", Color("d6dde5"))
	column.add_child(properties)
	var reward := Label.new()
	reward.text = "REWARD  %d GOLD" % encounter.gold_reward
	reward.add_theme_color_override("font_color", Color("e4c36e"))
	reward.add_theme_font_size_override("font_size", 18)
	column.add_child(reward)
	var choose := Button.new()
	choose.text = "CHOOSE ENCOUNTER"
	choose.custom_minimum_size.y = 54.0
	choose.add_theme_font_size_override("font_size", 16)
	choose.pressed.connect(func() -> void: encounter_selected.emit(encounter.id))
	column.add_child(choose)
	return panel


func _properties_text(encounter: EncounterDefinition) -> String:
	var lines: Array[String] = []
	for property in encounter.key_properties:
		lines.append("+  %s" % property)
	if lines.is_empty():
		lines.append("+  Opposition details unknown")
	if encounter.has_reinforcements():
		if not encounter.is_unknown:
			lines.append("+  Initial: %s" % _enemy_composition(encounter.enemy_ids))
			lines.append("+  Reinforcements: %s" % _enemy_composition(encounter.reinforcement_enemy_ids))
		else:
			lines.append("+  Reinforcement composition concealed")
		var enemy_word := "enemy" if encounter.reinforcement_alive_threshold == 1 else "enemies"
		lines.append("+  Reinforcements arrive at %d %s remaining" % [encounter.reinforcement_alive_threshold, enemy_word])
		lines.append("+  Entry: %s" % _entry_direction_text(encounter.reinforcement_entry_direction))
	return "\n".join(lines)


func _enemy_composition(enemy_ids: Array[StringName]) -> String:
	var counts: Dictionary = {}
	for enemy_id in enemy_ids:
		var enemy := get_node("/root/ContentRegistry").get_definition(enemy_id, false) as EnemyDefinition
		var enemy_name := enemy.display_name if enemy != null else String(enemy_id)
		counts[enemy_name] = int(counts.get(enemy_name, 0)) + 1
	var parts := PackedStringArray()
	for enemy_name in counts:
		parts.append("%s x%d" % [enemy_name, counts[enemy_name]])
	return ", ".join(parts)


func _entry_direction_text(direction: int) -> String:
	return "right side" if direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE else "all sides"
