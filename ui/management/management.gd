extends Control


signal combat_requested
signal menu_requested

const JOB_IDS: Array[StringName] = [&"job.militia", &"job.warrior", &"job.archer", &"job.priest"]
const BUILD_JOB_IDS: Array[StringName] = [&"job.warrior", &"job.archer", &"job.priest"]

var run_state: RunState
var selected_kind := ""
var selected_index := -1
var selected_ability_slot := 0
var job_option_ids: Array[StringName] = []
var job_build_option_ids: Array[StringName] = []
var ability_option_ids: Array[StringName] = []
var job_active_ids: Array[StringName] = []
var job_passive_ids: Array[StringName] = []


func _ready() -> void:
	%JobOption.item_selected.connect(_on_job_preview_selected)
	call_deferred("_ensure_setup")


func setup(new_run_state: RunState) -> void:
	run_state = new_run_state
	if is_node_ready():
		_refresh_all()


func _ensure_setup() -> void:
	if run_state == null:
		run_state = DemoRunFactory.create_starting_run()
	_refresh_all()
	if selected_index < 0 and not run_state.heroes.is_empty():
		_select_unit("hero", 0)
	%FightButton.grab_focus()


func _refresh_all() -> void:
	%GoldLabel.text = "GOLD  %d" % run_state.gold
	_refresh_roster()
	_refresh_job_options()
	_refresh_job_build_panel()
	_refresh_inventory()
	_refresh_market()
	_refresh_encounter()
	_refresh_selected()


func _refresh_roster() -> void:
	_clear(%Roster)
	for index in run_state.heroes.size():
		var hero := run_state.heroes[index]
		var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
		_add_roster_row("H", definition.placeholder_color, definition.display_name, definition.id, "hero", index)
	for index in run_state.soldiers.size():
		var soldier := run_state.soldiers[index]
		var job := _registry().get_definition(soldier.current_job_id) as JobDefinition
		_add_roster_row("S", job.placeholder_color, "%s  -  %s" % [soldier.generated_name, job.display_name], job.id, "soldier", index)


func _add_roster_row(
	letter: String,
	color: Color,
	label: String,
	content_id: StringName,
	kind: String,
	index: int
) -> void:
	var row := HBoxContainer.new()
	var icon := Label.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.text = letter
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = color.darkened(0.35)
	icon_style.border_width_left = 1
	icon_style.border_width_top = 1
	icon_style.border_width_right = 1
	icon_style.border_width_bottom = 1
	icon_style.border_color = color
	icon_style.corner_radius_top_left = 5
	icon_style.corner_radius_top_right = 5
	icon_style.corner_radius_bottom_left = 5
	icon_style.corner_radius_bottom_right = 5
	icon.add_theme_stylebox_override("normal", icon_style)
	row.add_child(icon)
	var button := ContentButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = String(content_id)
	button.content_id = content_id
	button.pressed.connect(_select_unit.bind(kind, index))
	row.add_child(button)
	%Roster.add_child(row)


func _select_unit(kind: String, index: int) -> void:
	selected_kind = kind
	selected_index = index
	selected_ability_slot = 0
	%CenterTabs.current_tab = 0
	_refresh_selected()


func _refresh_selected() -> void:
	if run_state == null or selected_index < 0:
		return
	var registry := _registry()
	if selected_kind == "hero" and selected_index < run_state.heroes.size():
		var hero := run_state.heroes[selected_index]
		var definition := registry.get_definition(hero.definition_id) as HeroDefinition
		var snapshot := CombatSnapshotBuilder.build_hero(hero, registry)
		%SelectedTitle.text = definition.display_name.to_upper()
		%DetailsLabel.text = "HERO - Level %d - XP %d - State %s\nHP %.0f  DMG %.0f  ARMOR %.0f  RANGE %.0f" % [
			hero.level, hero.xp, hero.life_state, snapshot.stats.max_hp, snapshot.stats.damage,
			snapshot.stats.armor, snapshot.stats.attack_range,
		]
		%JobControls.visible = false
		%AbilityEditRow.visible = true
		_refresh_hero_abilities(hero)
		%EquipmentLabel.text = "EQUIPMENT  %d / %d\n%s" % [hero.item_ids.size(), HeroState.MAX_ITEM_SLOTS, _names(hero.item_ids)]
	elif selected_kind == "soldier" and selected_index < run_state.soldiers.size():
		var soldier := run_state.soldiers[selected_index]
		var job := registry.get_definition(soldier.current_job_id) as JobDefinition
		var snapshot := CombatSnapshotBuilder.build_soldier(soldier, _job_build(soldier.current_job_id), registry)
		%SelectedTitle.text = soldier.generated_name.to_upper()
		%DetailsLabel.text = "SOLDIER - %s - Veterancy %d (%d XP)\nHP %.0f  DMG %.0f  ARMOR %.0f  RANGE %.0f\nLifetime: %s" % [
			job.display_name, soldier.veterancy_level, soldier.veterancy_xp, snapshot.stats.max_hp,
			snapshot.stats.damage, snapshot.stats.armor, snapshot.stats.attack_range,
			str(soldier.lifetime_statistics),
		]
		%JobControls.visible = true
		%AbilityEditRow.visible = false
		_select_option_by_id(%JobOption, job_option_ids, soldier.current_job_id)
		_update_job_warning(soldier, soldier.current_job_id)
		_refresh_readonly_abilities(snapshot.abilities)
		%EquipmentLabel.text = "EQUIPMENT  %d / %d\n%s" % [soldier.item_ids.size(), SoldierState.MAX_ITEM_SLOTS, _names(soldier.item_ids)]
	_refresh_preview()


func _refresh_hero_abilities(hero: HeroState) -> void:
	_clear(%AbilityRows)
	var ids := hero.ability_priority if not hero.ability_priority.is_empty() else hero.ability_ids
	for index in ids.size():
		var ability := _registry().get_definition(ids[index]) as AbilityDefinition
		var row := HBoxContainer.new()
		var select := ContentButton.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.text = "A  %d.  %s" % [index + 1, ability.display_name]
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.content_id = ability.id
		select.tooltip_text = String(ability.id)
		select.pressed.connect(_select_ability_slot.bind(index))
		row.add_child(select)
		var up := Button.new()
		up.text = "UP"
		up.disabled = index == 0
		up.pressed.connect(_move_hero_ability.bind(index, -1))
		row.add_child(up)
		var down := Button.new()
		down.text = "DN"
		down.disabled = index == ids.size() - 1
		down.pressed.connect(_move_hero_ability.bind(index, 1))
		row.add_child(down)
		%AbilityRows.add_child(row)
	_refresh_ability_options()


func _refresh_readonly_abilities(abilities: Array[AbilityDefinition]) -> void:
	_clear(%AbilityRows)
	if abilities.is_empty():
		var empty := Label.new()
		empty.text = "No Job abilities selected. Configure the shared Job build."
		%AbilityRows.add_child(empty)
		return
	for ability in abilities:
		var button := ContentButton.new()
		button.text = "A  %s" % ability.display_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.content_id = ability.id
		button.tooltip_text = String(ability.id)
		%AbilityRows.add_child(button)


func _refresh_ability_options() -> void:
	%AbilityOption.clear()
	ability_option_ids.clear()
	for definition in _definitions(AbilityDefinition):
		%AbilityOption.add_item(definition.display_name)
		ability_option_ids.append(definition.id)


func _refresh_job_options() -> void:
	%JobOption.clear()
	job_option_ids.clear()
	for job_id in JOB_IDS:
		var job := _registry().get_definition(job_id) as JobDefinition
		%JobOption.add_item(job.display_name)
		job_option_ids.append(job_id)
	%JobBuildOption.clear()
	job_build_option_ids.clear()
	for job_id in BUILD_JOB_IDS:
		var job := _registry().get_definition(job_id) as JobDefinition
		%JobBuildOption.add_item(job.display_name)
		job_build_option_ids.append(job_id)


func _refresh_job_build_panel() -> void:
	if job_build_option_ids.is_empty():
		return
	var option_index := clampi(%JobBuildOption.selected, 0, job_build_option_ids.size() - 1)
	var job_id := job_build_option_ids[option_index]
	var job := _registry().get_definition(job_id) as JobDefinition
	var build := _job_build(job_id)
	%CapacityLabel.text = "CAPACITY  %d / %d assigned" % [_assigned_count(job_id), _capacity(job_id)]
	%CapacityLabel.tooltip_text = String(job_id)
	%JobActiveOption.clear()
	%JobPassiveOption.clear()
	job_active_ids.clear()
	job_passive_ids.clear()
	for ability_id in job.available_ability_ids:
		var ability := _registry().get_definition(ability_id) as AbilityDefinition
		if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
			%JobActiveOption.add_item(ability.display_name)
			job_active_ids.append(ability.id)
		else:
			%JobPassiveOption.add_item(ability.display_name)
			job_passive_ids.append(ability.id)
	if build != null:
		_select_option_by_id(%JobActiveOption, job_active_ids, build.active_ability_id)
		%JobPassivesLabel.text = "Selected: %s" % _names(build.passive_ability_ids)
	else:
		%JobPassivesLabel.text = "Selected: None"
	%JobPassiveOption.disabled = job_passive_ids.is_empty()


func _refresh_inventory() -> void:
	if run_state.inventory.items.is_empty():
		%InventoryLabel.text = "INVENTORY / EQUIPMENT\n\nNo unequipped items.\n\nHero slots: 6\nSoldier slots: 2\nItems and restrictions will appear here as they enter the run."
		return
	var lines := PackedStringArray(["INVENTORY / EQUIPMENT", ""])
	for item in run_state.inventory.items:
		var definition_id := StringName(item.get("definition_id", ""))
		var definition: ContentDefinition = _registry().get_definition(definition_id, false)
		lines.append("[I] %s" % (definition.display_name if definition != null else definition_id))
	%InventoryLabel.text = "\n".join(lines)


func _refresh_market() -> void:
	_clear(%MarketRows)
	var title := Label.new()
	title.text = "JOB CAPACITY MARKET"
	title.add_theme_font_size_override("font_size", 19)
	%MarketRows.add_child(title)
	for job_id in BUILD_JOB_IDS:
		var job := _registry().get_definition(job_id) as JobDefinition
		var row := HBoxContainer.new()
		var icon := Label.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.text = "J"
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(icon)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s capacity +1\nOwned: %d" % [job.display_name, _capacity(job_id)]
		row.add_child(label)
		var buy := ContentButton.new()
		buy.text = "BUY  %d G" % job.capacity_price
		buy.content_id = job.id
		buy.tooltip_text = String(job.id)
		buy.tooltip_override = "%s CAPACITY OFFER\nPrice: %d Gold\nCurrent capacity: %d\nAllows one additional soldier assignment." % [job.display_name, job.capacity_price, _capacity(job_id)]
		buy.pressed.connect(_buy_capacity.bind(job_id))
		row.add_child(buy)
		%MarketRows.add_child(row)


func _refresh_encounter() -> void:
	if run_state.available_encounter_ids.is_empty():
		%EncounterLabel.text = "No encounter selected."
		%FightButton.disabled = true
		return
	var encounter := _registry().get_definition(run_state.available_encounter_ids[0]) as EncounterDefinition
	var enemy_counts: Dictionary = {}
	for enemy_id in encounter.enemy_ids:
		var enemy := _registry().get_definition(enemy_id) as EnemyDefinition
		enemy_counts[enemy.display_name] = int(enemy_counts.get(enemy.display_name, 0)) + 1
	var lines := PackedStringArray([encounter.display_name.to_upper(), encounter.description, "", "THREATS"])
	for enemy_name in enemy_counts:
		lines.append("[E] %s x %d" % [enemy_name, enemy_counts[enemy_name]])
	lines.append("\nREWARD  %d GOLD" % encounter.gold_reward)
	%EncounterLabel.text = "\n".join(lines)
	%EncounterLabel.tooltip_text = String(encounter.id)
	%FightButton.disabled = false
	_refresh_preview()


func _refresh_preview() -> void:
	if run_state == null:
		return
	var snapshots := CombatSnapshotBuilder.build_player_army(run_state, _registry())
	var melee := 0
	var ranged := 0
	for snapshot in snapshots:
		if snapshot.attack_type == &"ranged":
			ranged += 1
		else:
			melee += 1
	%PreviewLabel.text = "ARMY PREVIEW\n%d units - %d melee - %d ranged\nBuild changes apply to the next battle immediately." % [snapshots.size(), melee, ranged]


func _on_change_job_pressed() -> void:
	if selected_kind != "soldier" or selected_index < 0:
		_set_feedback("Select a soldier before changing Job.", true)
		return
	var soldier := run_state.soldiers[selected_index]
	var target_id := job_option_ids[%JobOption.selected]
	if target_id == soldier.current_job_id:
		_set_feedback("This soldier already has that Job.", true)
		return
	if target_id != &"job.militia" and _assigned_count(target_id) >= _capacity(target_id):
		_set_feedback("Assignment blocked: %s capacity is full. Buy capacity in Market." % _display_name(target_id), true)
		return
	var old_job := _display_name(soldier.current_job_id)
	soldier.current_job_id = target_id
	soldier.definition_id = target_id
	soldier.veterancy_xp = 0
	soldier.veterancy_level = 0
	_set_feedback("%s changed from %s to %s. Veterancy reset." % [soldier.generated_name, old_job, _display_name(target_id)], false)
	_refresh_all()


func _on_job_preview_selected(_index: int) -> void:
	if selected_kind == "soldier" and selected_index >= 0:
		_update_job_warning(run_state.soldiers[selected_index], job_option_ids[%JobOption.selected])


func _update_job_warning(soldier: SoldierState, target_id: StringName) -> void:
	var capacity_text := "unlimited" if target_id == &"job.militia" else "%d/%d assigned" % [_assigned_count(target_id), _capacity(target_id)]
	%JobWarning.text = "Changing Job resets Veterancy %d and %d XP. Capacity: %s." % [soldier.veterancy_level, soldier.veterancy_xp, capacity_text]


func _select_ability_slot(index: int) -> void:
	selected_ability_slot = index
	_set_feedback("Ability slot %d selected." % (index + 1), false)


func _move_hero_ability(index: int, direction: int) -> void:
	var hero := run_state.heroes[selected_index]
	var target := index + direction
	if target < 0 or target >= hero.ability_priority.size():
		return
	var value := hero.ability_priority[index]
	hero.ability_priority[index] = hero.ability_priority[target]
	hero.ability_priority[target] = value
	selected_ability_slot = target
	_refresh_selected()
	_set_feedback("Hero priority updated for the next battle.", false)


func _on_replace_ability_pressed() -> void:
	if selected_kind != "hero" or selected_index < 0 or ability_option_ids.is_empty():
		_set_feedback("Select a hero ability slot first.", true)
		return
	var hero := run_state.heroes[selected_index]
	var ability_id := ability_option_ids[%AbilityOption.selected]
	if hero.ability_ids.has(ability_id):
		_set_feedback("That ability is already equipped.", true)
		return
	if selected_ability_slot >= hero.ability_priority.size():
		selected_ability_slot = 0
	var old_id := hero.ability_priority[selected_ability_slot]
	var ability_index := hero.ability_ids.find(old_id)
	if ability_index >= 0:
		hero.ability_ids[ability_index] = ability_id
	hero.ability_priority[selected_ability_slot] = ability_id
	_refresh_selected()
	_set_feedback("Hero ability replaced. Combat preview updated.", false)


func _on_job_build_selected(_index: int) -> void:
	_refresh_job_build_panel()


func _on_apply_job_active_pressed() -> void:
	if job_active_ids.is_empty():
		_set_feedback("This Job has no active ability choices.", true)
		return
	var job_id := job_build_option_ids[%JobBuildOption.selected]
	var build := _job_build(job_id)
	build.set_active_ability(job_active_ids[%JobActiveOption.selected])
	_refresh_all()
	_set_feedback("%s active ability updated for every assigned soldier." % _display_name(job_id), false)


func _on_toggle_job_passive_pressed() -> void:
	if job_passive_ids.is_empty():
		_set_feedback("This Job has no passive ability choices.", true)
		return
	var job_id := job_build_option_ids[%JobBuildOption.selected]
	var build := _job_build(job_id)
	var ability_id := job_passive_ids[%JobPassiveOption.selected]
	if build.passive_ability_ids.has(ability_id):
		build.passive_ability_ids.erase(ability_id)
		_set_feedback("Passive removed from the shared %s build." % _display_name(job_id), false)
	elif not build.add_passive_ability(ability_id):
		_set_feedback("Passive slots are full (maximum 3).", true)
	else:
		_set_feedback("Passive added to the shared %s build." % _display_name(job_id), false)
	_refresh_all()


func _buy_capacity(job_id: StringName) -> void:
	var job := _registry().get_definition(job_id) as JobDefinition
	if run_state.gold < job.capacity_price:
		_set_feedback("Purchase blocked: need %d Gold, have %d." % [job.capacity_price, run_state.gold], true)
		return
	run_state.gold -= job.capacity_price
	run_state.job_capacities[String(job_id)] = _capacity(job_id) + 1
	_refresh_all()
	_set_feedback("Purchased +1 %s capacity." % job.display_name, false)


func _on_fight_button_pressed() -> void:
	combat_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()


func _job_build(job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	var build := JobBuildState.new()
	build.job_id = job_id
	run_state.job_builds.append(build)
	return build


func _assigned_count(job_id: StringName) -> int:
	var count := 0
	for soldier in run_state.soldiers:
		if soldier.current_job_id == job_id:
			count += 1
	return count


func _capacity(job_id: StringName) -> int:
	return int(run_state.job_capacities.get(String(job_id), 0))


func _definitions(script_type: Variant) -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	for definition in _registry().definitions.values():
		if is_instance_of(definition, script_type):
			result.append(definition)
	result.sort_custom(func(a: ContentDefinition, b: ContentDefinition) -> bool: return a.display_name < b.display_name)
	return result


func _select_option_by_id(option: OptionButton, ids: Array[StringName], content_id: StringName) -> void:
	var index := ids.find(content_id)
	if index >= 0:
		option.select(index)


func _display_name(content_id: StringName) -> String:
	var definition: ContentDefinition = _registry().get_definition(content_id, false)
	return definition.display_name if definition != null else String(content_id)


func _names(ids: Array[StringName]) -> String:
	if ids.is_empty():
		return "Empty"
	var names := PackedStringArray()
	for content_id in ids:
		names.append(_display_name(content_id))
	return ", ".join(names)


func _set_feedback(message: String, is_error: bool) -> void:
	%FeedbackLabel.text = message
	%FeedbackLabel.modulate = Color(1.0, 0.48, 0.4) if is_error else Color(0.62, 0.82, 0.68)


func _clear(container: Node) -> void:
	for child in container.get_children():
		child.free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
