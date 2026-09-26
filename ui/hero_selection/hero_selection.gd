class_name HeroSelection
extends Control


signal selection_confirmed(hero_ids: Array[StringName])
signal back_requested

const REQUIRED_HEROES := 3

var heroes: Array[HeroDefinition] = []
var selected_hero_ids: Array[StringName] = []
var current_index := 0


func _ready() -> void:
	_load_heroes()
	_refresh()
	%SelectButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_on_previous_pressed()
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_on_next_pressed()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _load_heroes() -> void:
	heroes.clear()
	for definition in _registry().definitions.values():
		if definition is HeroDefinition and definition.available_in_new_game:
			heroes.append(definition)
	heroes.sort_custom(func(a: HeroDefinition, b: HeroDefinition) -> bool:
		if a.selection_order == b.selection_order:
			return a.id < b.id
		return a.selection_order < b.selection_order
	)


func _refresh() -> void:
	var has_heroes := not heroes.is_empty()
	%PreviousButton.disabled = not has_heroes
	%NextButton.disabled = not has_heroes
	%SelectButton.disabled = not has_heroes
	%StartButton.disabled = selected_hero_ids.size() != REQUIRED_HEROES
	%ProgressLabel.text = "%d / %d HEROES CHOSEN" % [selected_hero_ids.size(), REQUIRED_HEROES]
	%SelectedRoster.text = _selected_roster_text()
	if not has_heroes:
		%HeroName.text = "NO SELECTABLE HEROES"
		%Description.text = "Add HeroDefinition resources with available_in_new_game enabled."
		%Feedback.text = "Hero selection content is missing."
		return
	current_index = posmod(current_index, heroes.size())
	var hero := heroes[current_index]
	var selected_order := selected_hero_ids.find(hero.id)
	%CounterLabel.text = "HERO %d / %d" % [current_index + 1, heroes.size()]
	%HeroName.text = hero.display_name.to_upper()
	%RoleLabel.text = _role_text(hero)
	%Description.text = hero.description
	%HpValue.text = _number(hero.base_stats.max_hp)
	%DamageValue.text = _number(hero.base_stats.damage)
	%AttackSpeedValue.text = _number(hero.base_stats.attack_speed)
	%MoveSpeedValue.text = _number(hero.base_stats.movement_speed)
	%RangeValue.text = _number(hero.base_stats.attack_range)
	%ArmorValue.text = _number(hero.base_stats.armor)
	%Portrait.texture = hero.portrait
	%Portrait.visible = hero.portrait != null
	%PortraitPlaceholder.visible = hero.portrait == null
	%Initials.text = _initials(hero.display_name)
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = hero.placeholder_color.darkened(0.42)
	portrait_style.border_width_left = 2
	portrait_style.border_width_top = 2
	portrait_style.border_width_right = 2
	portrait_style.border_width_bottom = 2
	portrait_style.border_color = hero.placeholder_color
	portrait_style.corner_radius_top_left = 8
	portrait_style.corner_radius_top_right = 8
	portrait_style.corner_radius_bottom_left = 8
	portrait_style.corner_radius_bottom_right = 8
	%PortraitPlaceholder.add_theme_stylebox_override("panel", portrait_style)
	%Initials.add_theme_color_override("font_color", hero.placeholder_color.lightened(0.3))
	%SelectedOverlay.visible = selected_order >= 0
	%SelectedOverlay.text = "SELECTED  #%d" % (selected_order + 1) if selected_order >= 0 else ""
	%SelectButton.text = "REMOVE" if selected_order >= 0 else "SELECT"
	%SelectButton.disabled = selected_order < 0 and selected_hero_ids.size() >= REQUIRED_HEROES
	%Feedback.text = "Choose SELECT to remove one Hero first." if %SelectButton.disabled else ""


func _on_previous_pressed() -> void:
	if heroes.is_empty():
		return
	current_index = posmod(current_index - 1, heroes.size())
	_refresh()


func _on_next_pressed() -> void:
	if heroes.is_empty():
		return
	current_index = posmod(current_index + 1, heroes.size())
	_refresh()


func _on_select_pressed() -> void:
	if heroes.is_empty():
		return
	var hero_id := heroes[current_index].id
	var selected_index := selected_hero_ids.find(hero_id)
	if selected_index >= 0:
		selected_hero_ids.remove_at(selected_index)
	elif selected_hero_ids.size() < REQUIRED_HEROES:
		selected_hero_ids.append(hero_id)
	_refresh()


func _on_start_pressed() -> void:
	if selected_hero_ids.size() == REQUIRED_HEROES:
		selection_confirmed.emit(selected_hero_ids.duplicate())


func _on_back_pressed() -> void:
	back_requested.emit()


func set_feedback(message: String) -> void:
	%Feedback.text = message


func _selected_roster_text() -> String:
	if selected_hero_ids.is_empty():
		return "No heroes selected"
	var entries := PackedStringArray()
	for index in selected_hero_ids.size():
		var definition := _registry().get_definition(selected_hero_ids[index], false) as HeroDefinition
		entries.append("%d. %s" % [index + 1, definition.display_name if definition != null else selected_hero_ids[index]])
	return "   |   ".join(entries)


func _role_text(hero: HeroDefinition) -> String:
	var roles := PackedStringArray()
	for tag in hero.tags:
		if tag != &"hero" and tag != &"test":
			roles.append(String(tag).to_upper())
	return " / ".join(roles)


func _initials(display_name: String) -> String:
	var result := ""
	for word in display_name.split(" ", false):
		result += word.left(1).to_upper()
	return result.left(3)


func _number(value: float) -> String:
	return "%.2f" % value if not is_equal_approx(value, roundf(value)) else "%d" % int(value)


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
