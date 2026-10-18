extends Control


signal execution_completed(run_state: RunState)
signal menu_requested

var run_state: RunState
var selected_hero_id := ""


func setup(new_run_state: RunState) -> void:
	run_state = new_run_state
	if is_node_ready():
		_refresh()


func _ready() -> void:
	call_deferred("_ensure_setup")


func _ensure_setup() -> void:
	if run_state == null:
		return
	_refresh()


func _refresh() -> void:
	_clear(%HeroCards)
	for hero in run_state.heroes:
		if hero.life_state not in [HeroState.ALIVE, HeroState.DEAD]:
			continue
		var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
		%HeroCards.add_child(_build_card(hero, definition))
	%ExecuteButton.disabled = selected_hero_id.is_empty()


func _build_card(hero: HeroState, definition: HeroDefinition) -> Control:
	var condemned := selected_hero_id == hero.unique_id
	var accent := definition.placeholder_color
	var card := PanelContainer.new()
	card.name = "Card_%s" % hero.unique_id
	card.custom_minimum_size = Vector2(380, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = _hero_build_tooltip(hero)
	var style := UiStyle.accent_panel(UiStyle.RED if condemned else accent, condemned, 20)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	card.gui_input.connect(_on_card_input.bind(hero.unique_id))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)

	var portrait := TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.custom_minimum_size = Vector2(0, 300)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = _portrait_top(definition.portrait)
	if hero.life_state == HeroState.DEAD:
		portrait.modulate = Color(0.55, 0.55, 0.6)
	if condemned:
		portrait.modulate = Color(1.0, 0.62, 0.58)
	column.add_child(portrait)

	var name_label := Label.new()
	name_label.text = definition.display_name.to_upper()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", (UiStyle.RED if condemned else accent).lightened(0.35))
	column.add_child(name_label)
	var state_label := Label.new()
	state_label.text = "%s  /  LEVEL %d" % [String(hero.life_state).to_upper(), hero.level]
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.add_theme_color_override("font_color", accent.lightened(0.15))
	state_label.add_theme_font_size_override("font_size", 15)
	column.add_child(state_label)

	var details_panel := PanelContainer.new()
	details_panel.theme_type_variation = &"InsetPanel"
	details_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(details_panel)
	var details := Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 15)
	details.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	details.text = _hero_details(hero)
	details_panel.add_child(details)

	var frame := UiStyle.add_frame(card, UiStyle.RED if condemned else accent, 1.0 if condemned else 0.0, -10.0)
	frame.crest_width = 100.0
	frame.side_notches = condemned
	if not condemned:
		card.mouse_entered.connect(func() -> void: _set_card_glow(frame, true))
		card.mouse_exited.connect(func() -> void: _set_card_glow(frame, false))
	return card


func _on_card_input(event: InputEvent, hero_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_hero(hero_id)


func _set_card_glow(frame: OrnateFrame, enabled: bool) -> void:
	if not is_instance_valid(frame):
		return
	frame.pulse = enabled
	frame.create_tween().tween_property(frame, "glow", 0.6 if enabled else 0.0, 0.18)


func _portrait_top(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var source := texture.get_size()
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = Rect2(0, 0, source.x, minf(source.y, source.x * 0.8))
	return crop


func _select_hero(hero_id: String) -> void:
	selected_hero_id = hero_id
	_refresh()
	_set_feedback("", false)


func _on_execute_pressed() -> void:
	var hero := _find_hero(selected_hero_id)
	if hero == null:
		_set_feedback("Choose a Hero first.", true)
		return
	var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
	%ConfirmationDialog.dialog_text = "%s will be permanently executed. Their abilities and equipment will be sealed in history and cannot be recovered. Act II will begin with two Heroes and ten soldiers." % definition.display_name
	%ConfirmationDialog.popup_centered()


func _on_execution_confirmed() -> void:
	var result := ExecutionService.execute(run_state, selected_hero_id, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	%ExecuteButton.disabled = true
	_set_feedback("Execution recorded. Preparing Act II...", false)
	execution_completed.emit(result.run_state)


func _hero_details(hero: HeroState) -> String:
	var ability_lines := PackedStringArray()
	for ability_id in hero.ability_ids:
		var ability := _registry().get_definition(ability_id, false) as AbilityDefinition
		ability_lines.append("- %s  [LV %d]" % [ability.display_name, hero.ability_level(ability_id)] if ability != null else "- %s" % ability_id)
	var item_lines := PackedStringArray()
	for instance_id in hero.item_ids:
		var item_id := run_state.inventory.get_definition_id(instance_id)
		var item := _registry().get_definition(item_id, false) as ItemDefinition
		item_lines.append("- %s" % item.display_name if item != null else "- %s" % item_id)
	var battle: Dictionary = run_state.pending_execution_contributions.get(hero.unique_id, {})
	var contribution: Dictionary = battle.get("contribution", {})
	return "MAIN SCORE  %.0f\nXP  %d\n\nABILITIES\n%s\n\nEQUIPMENT / BONUSES\n%s\n\nBOSS CONTRIBUTION\nDamage %.0f  Healing %.0f  Tanking %.0f\nContribution XP %d%s" % [
		MarketGenerator.hero_main_score(run_state, hero, _registry()),
		hero.xp,
		"\n".join(ability_lines) if not ability_lines.is_empty() else "None",
		"\n".join(item_lines) if not item_lines.is_empty() else "None",
		float(contribution.get("damage_dealt", 0.0)),
		float(contribution.get("effective_healing", 0.0)),
		float(contribution.get("damage_tanked", 0.0)),
		int(contribution.get("total_xp", 0)),
		"\nDid not participate in the Boss battle." if not bool(battle.get("participated", false)) else "",
	]


func _hero_build_tooltip(hero: HeroState) -> String:
	var descriptions := PackedStringArray()
	for ability_id in hero.ability_ids:
		descriptions.append("LEVEL %d\n%s" % [hero.ability_level(ability_id), ContentButton.describe_content(ability_id)])
	for instance_id in hero.item_ids:
		descriptions.append(ContentButton.describe_content(run_state.inventory.get_definition_id(instance_id)))
	return "\n\n".join(descriptions)


func _find_hero(hero_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == hero_id:
			return hero
	return null


func _set_feedback(message: String, is_error: bool) -> void:
	%FeedbackLabel.text = message
	%FeedbackLabel.modulate = Color(1.0, 0.42, 0.34) if is_error else Color(0.9, 0.67, 0.32)


func _on_menu_pressed() -> void:
	menu_requested.emit()


func _clear(container: Node) -> void:
	for child in container.get_children():
		child.free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
