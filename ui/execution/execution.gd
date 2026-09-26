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
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(310, 0)
		var select := Button.new()
		select.custom_minimum_size = Vector2(0, 54)
		select.text = "%s%s\n%s - LEVEL %d" % ["> " if selected_hero_id == hero.unique_id else "", definition.display_name.to_upper(), String(hero.life_state).to_upper(), hero.level]
		select.pressed.connect(_select_hero.bind(hero.unique_id))
		card.add_child(select)
		var details := Label.new()
		details.size_flags_vertical = Control.SIZE_EXPAND_FILL
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.text = _hero_details(hero)
		details.tooltip_text = _hero_build_tooltip(hero)
		card.add_child(details)
		%HeroCards.add_child(card)
	%ExecuteButton.disabled = selected_hero_id.is_empty()


func _select_hero(hero_id: String) -> void:
	selected_hero_id = hero_id
	_refresh()
	_set_feedback("Selection is not final until the irreversible confirmation.", false)


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
		ability_lines.append("- %s [LV %d]: %s" % [ability.display_name, hero.ability_level(ability_id), ability.description] if ability != null else "- %s" % ability_id)
	var item_lines := PackedStringArray()
	for instance_id in hero.item_ids:
		var item_id := run_state.inventory.get_definition_id(instance_id)
		var item := _registry().get_definition(item_id, false) as ItemDefinition
		item_lines.append("- %s: %s" % [item.display_name, item.description] if item != null else "- %s" % item_id)
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
