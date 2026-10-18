class_name EncounterChoiceScreen
extends Control

signal encounter_selected(encounter_id: StringName)

const THREAT_COLORS := {
	"Low": Color(0.3, 0.78, 0.42),
	"Moderate": Color(0.95, 0.74, 0.24),
	"High": Color(0.95, 0.45, 0.16),
	"Elite": Color(0.9, 0.3, 0.4),
	"Boss": Color(0.88, 0.2, 0.18),
}
const THREAT_PIPS := {"Low": 1, "Moderate": 2, "High": 3, "Elite": 4, "Boss": 4}
const UNKNOWN_COLOR := Color(0.58, 0.36, 0.95)

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
	for index in run_state.available_encounter_ids.size():
		var encounter_id := run_state.available_encounter_ids[index]
		var encounter := get_node("/root/ContentRegistry").get_definition(encounter_id, false) as EncounterDefinition
		if encounter != null:
			cards.add_child(_build_card(encounter, index))
	status_label.text = "Study the opposition and click a card to march. This choice cannot be changed."


const ROLE_ORDER := [&"boss", &"leaper", &"heavy", &"melee", &"ranged", &"caller", &"healer", &"unknown"]


func _build_card(encounter: EncounterDefinition, _visual_index := 0) -> Control:
	var accent := _threat_color(encounter)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540.0, 700.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(_on_card_input.bind(encounter.id))
	var style := UiStyle.accent_panel(accent, false, 18)
	style.content_margin_left = 30
	style.content_margin_top = 26
	style.content_margin_right = 30
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	# Threat and headcount.
	var threat_row := HBoxContainer.new()
	threat_row.add_theme_constant_override("separation", 6)
	column.add_child(threat_row)
	var gem := OrnateFrame.gem_texture(OrnateFrame.gem_for_color(accent))
	var bronze_gem := OrnateFrame.gem_texture(&"bronze")
	var pips := int(THREAT_PIPS.get(encounter.difficulty_hint, 2))
	for pip in 4:
		var icon := TextureRect.new()
		icon.texture = gem if pip < pips else bronze_gem
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(1.25, 1.25, 1.25, 1.0) if pip < pips else Color(0.7, 0.62, 0.55, 0.75)
		threat_row.add_child(icon)
	var difficulty := Label.new()
	difficulty.text = "  %s THREAT" % encounter.difficulty_hint.to_upper() if not encounter.is_unknown else "  UNKNOWN THREAT"
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty.add_theme_color_override("font_color", accent.lightened(0.28))
	difficulty.add_theme_font_size_override("font_size", 17)
	threat_row.add_child(difficulty)
	var headcount := Label.new()
	headcount.text = _headcount_text(encounter)
	headcount.theme_type_variation = &"NumberLabel"
	headcount.add_theme_color_override("font_color", UiStyle.TEXT)
	headcount.add_theme_font_size_override("font_size", 17)
	threat_row.add_child(headcount)

	var title := Label.new()
	title.text = encounter.display_name.to_upper()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_color_override("font_color", accent.lightened(0.4))
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var description := Label.new()
	description.text = encounter.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	description.add_theme_font_size_override("font_size", 16)
	column.add_child(description)
	column.add_child(HSeparator.new())

	# Forces: one medallion per enemy type with its count.
	column.add_child(_section_label("FORCES"))
	column.add_child(_token_row(encounter.enemy_ids, encounter.is_unknown, false))
	if encounter.has_reinforcements():
		var reinforcement_label := _section_label("REINFORCEMENTS")
		var trigger := Label.new()
		var enemy_word := "enemy remains" if encounter.reinforcement_alive_threshold == 1 else "enemies remain"
		trigger.text = "when %d %s  /  %s" % [encounter.reinforcement_alive_threshold, enemy_word, _entry_direction_text(encounter.reinforcement_entry_direction)]
		trigger.add_theme_color_override("font_color", Color(0.7, 0.62, 0.84))
		trigger.add_theme_font_size_override("font_size", 14)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		header.add_child(reinforcement_label)
		header.add_child(trigger)
		column.add_child(header)
		column.add_child(_token_row(encounter.reinforcement_enemy_ids, encounter.is_unknown, true))

	var properties := Label.new()
	properties.text = _properties_text(encounter)
	properties.visible = not properties.text.is_empty()
	properties.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	properties.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68))
	properties.add_theme_font_size_override("font_size", 15)
	column.add_child(properties)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	column.add_child(_reward_plaque(encounter, accent))

	var frame := UiStyle.add_frame(panel, accent, 0.0, -26.0)
	frame.crest_width = 110.0
	frame.corner_gem_size = 26.0
	panel.mouse_entered.connect(func() -> void: _set_card_glow(frame, true))
	panel.mouse_exited.connect(func() -> void: _set_card_glow(frame, false))
	return panel


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"EyebrowLabel"
	label.add_theme_color_override("font_color", UiStyle.GOLD_DIM)
	label.add_theme_font_size_override("font_size", 14)
	return label


## One line per enemy type (role order, then name): medallion, name, signature
## abilities and count. Concealed forces only show how many groups wait.
func _token_row(enemy_ids: Array[StringName], concealed: bool, reinforcement: bool) -> Control:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if concealed:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for index in clampi(roundi(enemy_ids.size() / 3.0), 1, 4):
			var token := EnemyToken.new()
			row.add_child(token)
			token.setup(null, 0, true, reinforcement, false)
		var hint := Label.new()
		hint.text = "  Scouts could not make out who waits."
		hint.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
		hint.add_theme_font_size_override("font_size", 15)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hint)
		list.add_child(row)
		return list
	var registry := get_node("/root/ContentRegistry")
	var counts := {}
	var definitions := {}
	for enemy_id in enemy_ids:
		counts[enemy_id] = int(counts.get(enemy_id, 0)) + 1
		definitions[enemy_id] = registry.get_definition(enemy_id, false)
	var ordered := counts.keys()
	ordered.sort_custom(func(a: StringName, b: StringName) -> bool:
		var role_a := ROLE_ORDER.find(EnemyToken.role_of(definitions[a]))
		var role_b := ROLE_ORDER.find(EnemyToken.role_of(definitions[b]))
		return role_a < role_b if role_a != role_b else String(a) < String(b)
	)
	for enemy_id in ordered:
		var definition := definitions[enemy_id] as EnemyDefinition
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var token := EnemyToken.new()
		row.add_child(token)
		token.setup(definition, int(counts[enemy_id]), false, reinforcement, false)
		row.tooltip_text = token.tooltip_text
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", -2)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := Label.new()
		name_label.text = definition.display_name if definition != null else String(enemy_id)
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", UiStyle.TEXT)
		text.add_child(name_label)
		var traits := Label.new()
		traits.text = _ability_names(definition, registry)
		traits.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		traits.add_theme_font_size_override("font_size", 14)
		traits.add_theme_color_override("font_color", Color(0.72, 0.62, 0.84) if reinforcement else UiStyle.TEXT_MUTED)
		text.add_child(traits)
		row.add_child(text)
		var count := Label.new()
		count.text = "x%d" % int(counts[enemy_id])
		count.theme_type_variation = &"NumberLabel"
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		count.add_theme_font_size_override("font_size", 22)
		count.add_theme_color_override("font_color", UiStyle.GOLD if not reinforcement else Color(0.78, 0.68, 0.92))
		row.add_child(count)
		list.add_child(row)
	return list


func _ability_names(definition: EnemyDefinition, registry: Node) -> String:
	if definition == null:
		return ""
	var names: Array[String] = []
	for ability_id in definition.ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		if ability != null:
			names.append(ability.display_name)
	return "  /  ".join(names) if not names.is_empty() else ("Ranged" if definition.attack_type == &"ranged" else "Melee")


func _headcount_text(encounter: EncounterDefinition) -> String:
	var total := encounter.enemy_ids.size() + encounter.reinforcement_enemy_ids.size()
	if encounter.is_unknown:
		return "%d-%d FOES" % [maxi(1, total - 2), total + 2]
	return "%d FOES" % total


func _reward_plaque(encounter: EncounterDefinition, accent: Color) -> Control:
	var plaque := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.03, 0.95)
	style.border_color = Color(UiStyle.GOLD, 0.55)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(4)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(accent, 0.12)
	style.shadow_size = 6
	plaque.add_theme_stylebox_override("panel", style)
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	plaque.add_child(row)
	var caption := Label.new()
	caption.text = "REWARD"
	caption.theme_type_variation = &"EyebrowLabel"
	caption.add_theme_color_override("font_color", UiStyle.GOLD_DIM)
	caption.add_theme_font_size_override("font_size", 15)
	row.add_child(caption)
	var coin := CoinIcon.new()
	coin.custom_minimum_size = Vector2(34, 34)
	row.add_child(coin)
	var amount := Label.new()
	amount.text = "%d" % encounter.gold_reward
	amount.theme_type_variation = &"NumberLabel"
	amount.add_theme_font_size_override("font_size", 34)
	amount.add_theme_color_override("font_color", UiStyle.GOLD)
	row.add_child(amount)
	var unit := Label.new()
	unit.text = "GOLD"
	unit.add_theme_color_override("font_color", UiStyle.GOLD)
	unit.add_theme_font_size_override("font_size", 17)
	row.add_child(unit)
	return plaque


## Stamped gold coin drawn in code so it matches the bronze UI at any size.
class CoinIcon:
	extends Control

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5 - 1.0
		var c := size * 0.5
		draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.4))
		draw_circle(c, r, Color(0.62, 0.42, 0.14))
		draw_circle(c, r - 2.0, UiStyle.GOLD)
		draw_arc(c, r - 5.0, 0.0, TAU, 32, Color(0.62, 0.42, 0.14), 1.5, true)
		draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.22, Color(1, 0.94, 0.7, 0.55))
		var font := get_theme_default_font()
		draw_string(font, c + Vector2(-r, r * 0.38), "G", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.05), Color(0.5, 0.32, 0.1))


func _on_card_input(event: InputEvent, encounter_id: StringName) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		encounter_selected.emit(encounter_id)


func _set_card_glow(frame: OrnateFrame, enabled: bool) -> void:
	if not is_instance_valid(frame):
		return
	frame.pulse = enabled
	var tween := frame.create_tween()
	tween.tween_property(frame, "glow", 0.85 if enabled else 0.0, 0.18)


func _threat_color(encounter: EncounterDefinition) -> Color:
	if encounter.is_unknown:
		return UNKNOWN_COLOR
	return THREAT_COLORS.get(encounter.difficulty_hint, THREAT_COLORS["Moderate"])


func _properties_text(encounter: EncounterDefinition) -> String:
	var lines: Array[String] = []
	if encounter.is_unknown:
		return ""
	for property in encounter.key_properties:
		lines.append("+  %s" % property)
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
