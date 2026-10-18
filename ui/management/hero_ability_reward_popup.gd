class_name HeroAbilityRewardPopup
extends Control


signal offer_selected(offer_id: String)

var run_state: RunState


func show_pending(new_run_state: RunState) -> void:
	run_state = new_run_state
	if run_state == null or run_state.pending_hero_ability_reward.is_empty():
		visible = false
		return
	_clear_offers()
	%Feedback.text = ""
	for offer in run_state.pending_hero_ability_reward.offers:
		var hero := _find_hero(offer.hero_unique_id)
		var hero_definition := _registry().get_definition(hero.definition_id, false) as HeroDefinition if hero != null else null
		var ability := _registry().get_definition(offer.ability_id, false) as AbilityDefinition
		if hero_definition == null or ability == null:
			continue
		var target_level := HeroAbilityRewardService.offer_level(run_state, offer)
		%Offers.add_child(_offer_card(offer.offer_id, hero, hero_definition, ability, target_level))
	visible = true
	get_viewport().gui_release_focus()


func set_feedback(message: String) -> void:
	%Feedback.text = message


## One clickable card per offer: ability icon, hero, NEW / level chip and the
## formatted tooltip with the target level highlighted among all levels.
func _offer_card(offer_id: String, hero: HeroState, hero_definition: HeroDefinition, ability: AbilityDefinition, target_level: int) -> Control:
	var accent := hero_definition.placeholder_color
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := _card_style(accent, false)
	var hover := _card_style(accent, true)
	card.add_theme_stylebox_override("panel", normal)
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", normal))
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_offer_pressed(offer_id)
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	var icon := TextureRect.new()
	icon.texture = ability.presentation_icon if ability.presentation_icon != null else ability.icon
	icon.custom_minimum_size = Vector2(84, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(titles)
	var hero_label := Label.new()
	hero_label.text = hero_definition.display_name.to_upper()
	hero_label.theme_type_variation = &"EyebrowLabel"
	hero_label.add_theme_color_override("font_color", accent.lightened(0.3))
	hero_label.add_theme_font_size_override("font_size", 15)
	titles.add_child(hero_label)
	var name_label := Label.new()
	name_label.text = ability.display_name.to_upper()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.88, 0.7))
	titles.add_child(name_label)
	var chip := Label.new()
	var is_new := hero.ability_level(ability.id) == 0
	chip.text = "NEW ABILITY" if is_new else "LEVEL %d  >  %d" % [target_level - 1, target_level]
	chip.add_theme_font_size_override("font_size", 14)
	chip.add_theme_color_override("font_color", Color(0.12, 0.08, 0.04) if is_new else Color(0.98, 0.9, 0.7))
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = UiStyle.GOLD if is_new else Color(accent.darkened(0.45), 0.95)
	chip_style.set_corner_radius_all(3)
	chip_style.content_margin_left = 8
	chip_style.content_margin_right = 8
	chip_style.content_margin_top = 1
	chip_style.content_margin_bottom = 1
	chip.add_theme_stylebox_override("normal", chip_style)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	titles.add_child(chip)

	var details := RichTextLabel.new()
	details.bbcode_enabled = true
	details.fit_content = true
	details.scroll_active = false
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_font_size_override("normal_font_size", 17)
	details.add_theme_font_size_override("bold_font_size", 17)
	details.add_theme_constant_override("line_separation", 4)
	details.add_theme_color_override("default_color", Color(0.85, 0.81, 0.74))
	var compare := target_level - 1 if not is_new else 0
	var lines: Array[String] = [AbilityText.type_line(ability, target_level)]
	var stats := AbilityText.stat_line(ability, target_level, compare)
	if not stats.is_empty():
		lines.append(stats)
	lines.append("")
	lines.append(AbilityText.render(ability, target_level, compare))
	details.text = "\n".join(lines)
	column.add_child(details)
	return card


func _card_style(accent: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.035, 0.97) if not hovered else Color(0.1, 0.07, 0.045, 0.98)
	style.border_color = Color(accent, 0.55) if not hovered else UiStyle.GOLD
	style.set_border_width_all(1 if not hovered else 2)
	style.border_width_top = 3
	style.set_corner_radius_all(6)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(accent, 0.25) if hovered else Color(0, 0, 0, 0.4)
	style.shadow_size = 10 if hovered else 4
	return style


func _find_hero(unique_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == unique_id:
			return hero
	return null


func _on_offer_pressed(offer_id: String) -> void:
	offer_selected.emit(offer_id)


func _clear_offers() -> void:
	for child in %Offers.get_children():
		child.visible = false
		child.queue_free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
