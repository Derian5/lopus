extends Control


signal combat_requested
signal menu_requested
signal run_state_changed(action: StringName)
signal run_event_choice_requested(choice_id: StringName)
signal hero_ability_reward_requested(offer_id: String)

var run_state: RunState
var selected_kind := ""
var selected_index := -1
var selected_job_id: StringName
var selected_ability_slot := 0
var selected_equipment_slot := 0
var job_option_ids: Array[StringName] = []


func _ready() -> void:
	%JobOption.item_selected.connect(_on_job_preview_selected)
	%InventoryDropSlot.accepted_sources.append(&"equipped_item")
	%InventoryDropSlot.target_payload = {"target": &"inventory"}
	%InventoryDropSlot.payload_dropped.connect(_on_management_drop)
	%RunEventPopup.choice_selected.connect(_on_run_event_choice_selected)
	%HeroAbilityRewardPopup.offer_selected.connect(_on_hero_ability_reward_selected)
	call_deferred("_ensure_setup")


func setup(new_run_state: RunState) -> void:
	run_state = new_run_state
	if is_node_ready():
		_refresh_all()
		_show_pending_popups()


func _ensure_setup() -> void:
	if run_state == null:
		run_state = DemoRunFactory.create_starting_run()
	_refresh_all()
	if selected_index < 0:
		for index in run_state.heroes.size():
			if run_state.heroes[index].life_state != HeroState.EXECUTED:
				_select_unit("hero", index)
				break
		if selected_index < 0 and not run_state.soldiers.is_empty():
			_select_unit("soldier", 0)
	%FightButton.grab_focus()
	_show_pending_popups()


func _on_run_event_choice_selected(choice_id: StringName) -> void:
	run_event_choice_requested.emit(choice_id)


func _on_hero_ability_reward_selected(offer_id: String) -> void:
	hero_ability_reward_requested.emit(offer_id)


func _show_pending_popups() -> void:
	%HeroAbilityRewardPopup.show_pending(run_state)
	if run_state.pending_hero_ability_reward.is_empty():
		%RunEventPopup.show_pending(run_state)
	else:
		%RunEventPopup.visible = false


func _refresh_all() -> void:
	%GoldLabel.text = "GOLD  %d" % run_state.gold
	%PhaseLabel.text = "PREPARATION"
	_refresh_job_options()
	_refresh_roster()
	_refresh_job_build_panel()
	_refresh_inventory()
	_refresh_market()
	_refresh_resurrection()
	_refresh_encounter()
	_refresh_selected()


func _refresh_roster() -> void:
	_clear(%Roster)
	var hero_heading := Label.new()
	hero_heading.text = "HEROES"
	hero_heading.add_theme_color_override("font_color", Color("d7a958"))
	%Roster.add_child(hero_heading)
	for index in run_state.heroes.size():
		var hero := run_state.heroes[index]
		if hero.life_state == HeroState.EXECUTED:
			continue
		var definition := _registry().get_definition(hero.definition_id) as HeroDefinition
		var state_suffix := "" if hero.life_state == HeroState.ALIVE else "  [%s]" % String(hero.life_state).to_upper()
		_add_roster_row("H", definition.placeholder_color, definition.display_name + state_suffix, definition.id, "hero", index)
	for job_id in job_option_ids:
		var job := _registry().get_definition(job_id, false) as JobDefinition
		if job == null:
			continue
		var heading := ManagementDropSlot.new()
		heading.text = "%s   %s" % [job.display_name.to_upper(), "UNLIMITED" if job_id == &"job.militia" else "%d / %d" % [_assigned_count(job_id), _capacity(job_id)]]
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.content_id = job.id
		heading.tooltip_text = String(job.id)
		heading.accepted_sources = [&"soldier"]
		heading.target_payload = {"target": &"job", "job_id": job_id}
		heading.payload_dropped.connect(_on_management_drop)
		heading.pressed.connect(_select_job.bind(job_id))
		%Roster.add_child(heading)
		for index in run_state.soldiers.size():
			var soldier := run_state.soldiers[index]
			if soldier.current_job_id == job_id:
				_add_roster_row("S", job.placeholder_color, soldier.generated_name, job.id, "soldier", index)


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
	var button: ContentButton
	if kind == "soldier":
		var draggable := ManagementDragButton.new()
		draggable.drag_payload = {"source": &"soldier", "soldier_index": index}
		button = draggable
	else:
		button = ContentButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = String(content_id)
	button.content_id = content_id
	button.pressed.connect(_select_unit.bind(kind, index))
	row.add_child(button)
	%Roster.add_child(row)


func _select_unit(kind: String, index: int) -> void:
	if kind == "hero" and (index < 0 or index >= run_state.heroes.size() or run_state.heroes[index].life_state == HeroState.EXECUTED):
		_set_feedback("Executed Heroes are sealed in the run history.", true)
		return
	selected_kind = kind
	selected_index = index
	selected_job_id = &""
	selected_ability_slot = 0
	selected_equipment_slot = 0
	_refresh_selected()


func _select_job(job_id: StringName) -> void:
	selected_kind = "job"
	selected_index = -1
	selected_job_id = job_id
	_refresh_job_build_panel()
	_refresh_selected()


func _refresh_selected() -> void:
	if run_state == null or (selected_index < 0 and selected_kind != "job"):
		return
	var registry := _registry()
	if selected_kind == "hero" and selected_index < run_state.heroes.size():
		var hero := run_state.heroes[selected_index]
		if hero.life_state == HeroState.EXECUTED:
			selected_index = -1
			return
		var definition := registry.get_definition(hero.definition_id) as HeroDefinition
		var snapshot := CombatSnapshotBuilder.build_hero(hero, run_state.inventory, registry)
		%SelectedTitle.text = definition.display_name.to_upper()
		%DetailsLabel.text = "HERO - Level %d - XP %d - State %s\nHP %.0f  DMG %.0f  ARMOR %.0f  RANGE %.0f" % [
			hero.level, hero.xp, hero.life_state, snapshot.stats.max_hp, snapshot.stats.damage,
			snapshot.stats.armor, snapshot.stats.attack_range,
		]
		%JobControls.visible = false
		%JobBuildControls.visible = false
		_refresh_hero_abilities(hero)
		_refresh_equipment(hero.item_ids, HeroState.MAX_ITEM_SLOTS)
	elif selected_kind == "soldier" and selected_index < run_state.soldiers.size():
		var soldier := run_state.soldiers[selected_index]
		var job := registry.get_definition(soldier.current_job_id) as JobDefinition
		var snapshot := CombatSnapshotBuilder.build_soldier(soldier, _job_build(soldier.current_job_id), run_state.inventory, registry)
		%SelectedTitle.text = soldier.generated_name.to_upper()
		%DetailsLabel.text = "SOLDIER - %s - Veterancy %d (%d XP)\nHP %.0f  DMG %.0f  ARMOR %.0f  RANGE %.0f" % [
			job.display_name, soldier.veterancy_level, soldier.veterancy_xp, snapshot.stats.max_hp,
			snapshot.stats.damage, snapshot.stats.armor, snapshot.stats.attack_range,
		]
		%JobControls.visible = true
		%JobBuildControls.visible = false
		_select_option_by_id(%JobOption, job_option_ids, soldier.current_job_id)
		_update_job_warning(soldier, soldier.current_job_id)
		_refresh_readonly_abilities(snapshot.abilities)
		_refresh_equipment(soldier.item_ids, SoldierState.MAX_ITEM_SLOTS)
	elif selected_kind == "job" and not String(selected_job_id).is_empty():
		var job := registry.get_definition(selected_job_id, false) as JobDefinition
		if job == null:
			return
		%SelectedTitle.text = "%s COMPANY" % job.display_name.to_upper()
		%DetailsLabel.text = "SHARED JOB BUILD\n%d assigned / %s capacity\nDrop soldiers onto the Job heading at left. Buy a matching Market ability to equip it automatically, or drag an offer onto a specific slot." % [
			_assigned_count(job.id), "unlimited" if job.id == &"job.militia" else str(_capacity(job.id)),
		]
		%JobControls.visible = false
		%JobBuildControls.visible = true
		_clear(%EquipmentRows)
		%EquipmentCount.text = "JOB ABILITIES"
		_refresh_job_ability_slots(job.id)
	_refresh_preview()


func _refresh_equipment(item_ids: Array[StringName], max_slots: int) -> void:
	_clear(%EquipmentRows)
	selected_equipment_slot = clampi(selected_equipment_slot, 0, max_slots - 1)
	for slot_index in max_slots:
		var occupied := slot_index < item_ids.size()
		var definition := _item_definition(item_ids[slot_index]) if occupied else null
		var button := ManagementDropSlot.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%sSLOT %d  %s" % ["> " if selected_equipment_slot == slot_index else "", slot_index + 1, "[I] %s" % (definition.display_name if definition != null else item_ids[slot_index]) if occupied else "DROP ITEM"]
		if definition != null:
			button.content_id = definition.id
			button.tooltip_text = String(definition.id)
			button.drag_payload = {
				"source": &"equipped_item",
				"owner_kind": StringName(selected_kind),
				"owner_index": selected_index,
				"slot_index": slot_index,
				"instance_id": item_ids[slot_index],
			}
		button.accepted_sources = [&"inventory_item", &"market"]
		button.target_payload = {"target": &"equipment", "owner_kind": StringName(selected_kind), "owner_index": selected_index, "slot_index": slot_index}
		button.payload_dropped.connect(_on_management_drop)
		button.pressed.connect(_select_equipment_slot.bind(slot_index))
		%EquipmentRows.add_child(button)
	%EquipmentCount.text = "EQUIPMENT  %d / %d" % [item_ids.size(), max_slots]


func _refresh_hero_abilities(hero: HeroState) -> void:
	_clear(%AbilityRows)
	var ids := hero.ability_priority if not hero.ability_priority.is_empty() else hero.ability_ids
	for index in HeroState.MAX_ABILITY_SLOTS:
		var occupied := index < ids.size()
		var ability := _registry().get_definition(ids[index]) as AbilityDefinition if occupied else null
		var row := HBoxContainer.new()
		var select := ManagementDropSlot.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.text = "%sA  %d.  %s" % ["> " if selected_ability_slot == index else "", index + 1, "%s  [LV %d]" % [ability.display_name, hero.ability_level(ability.id)] if occupied else "EMPTY"]
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if ability != null:
			select.content_id = ability.id
			select.tooltip_text = String(ability.id)
		select.accepted_sources = []
		select.target_payload = {"target": &"ability", "owner_kind": &"hero", "owner_index": selected_index, "slot_index": index}
		select.payload_dropped.connect(_on_management_drop)
		select.pressed.connect(_select_ability_slot.bind(index))
		row.add_child(select)
		if occupied:
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


func _refresh_job_options() -> void:
	%JobOption.clear()
	job_option_ids.clear()
	for definition in _definitions(JobDefinition):
		var job := definition as JobDefinition
		if run_state.unlocked_job_ids.has(job.id):
			%JobOption.add_item(job.display_name)
			job_option_ids.append(job.id)


func _refresh_job_build_panel() -> void:
	if selected_kind != "job" or String(selected_job_id).is_empty():
		%CapacityLabel.text = "NO SPECIALIST JOBS UNLOCKED"
		return
	var job_id := selected_job_id
	var job := _registry().get_definition(job_id) as JobDefinition
	if job == null:
		return
	%CapacityLabel.text = (
		"CAPACITY  %d assigned / UNLIMITED" % _assigned_count(job_id)
		if job_id == &"job.militia"
		else "CAPACITY  %d / %d assigned" % [_assigned_count(job_id), _capacity(job_id)]
	)
	%CapacityLabel.tooltip_text = String(job_id)
	_refresh_job_ability_slots(job_id)


func _refresh_job_ability_slots(job_id: StringName) -> void:
	_clear(%AbilityRows)
	var build := _job_build(job_id)
	var active := _registry().get_definition(build.active_ability_id, false) as AbilityDefinition
	var active_slot := _job_ability_drop_slot(job_id, &"active", 0, "ACTIVE  %s" % (active.display_name if active != null else "DROP ABILITY"))
	if active != null:
		active_slot.content_id = active.id
		active_slot.tooltip_text = String(active.id)
	%AbilityRows.add_child(active_slot)
	for index in 3:
		var ability_id: StringName = build.passive_ability_ids[index] if index < build.passive_ability_ids.size() else &""
		var passive := _registry().get_definition(ability_id, false) as AbilityDefinition
		var slot := _job_ability_drop_slot(job_id, &"passive", index, "PASSIVE %d  %s" % [index + 1, passive.display_name if passive != null else "DROP ABILITY"])
		if passive != null:
			slot.content_id = passive.id
			slot.tooltip_text = String(passive.id)
		%AbilityRows.add_child(slot)


func _job_ability_drop_slot(job_id: StringName, slot_kind: StringName, slot_index: int, label: String) -> ManagementDropSlot:
	var slot := ManagementDropSlot.new()
	slot.text = label
	slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
	slot.accepted_sources = [&"market"]
	slot.target_payload = {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": slot_kind, "slot_index": slot_index}
	slot.payload_dropped.connect(_on_management_drop)
	return slot


func _refresh_inventory() -> void:
	_clear(%InventoryRows)
	var unequipped := EquipmentService.get_unequipped_items(run_state)
	if unequipped.is_empty():
		var empty := Label.new()
		empty.text = "No unequipped items. Drag equipped gear onto the Inventory heading to return it."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		%InventoryRows.add_child(empty)
		return
	for item in unequipped:
		var instance_id := StringName(item.instance_id)
		var definition := _registry().get_definition(StringName(item.definition_id), false) as ItemDefinition
		var row := HBoxContainer.new()
		var button := ManagementDragButton.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		var binding := String(item.get("bound_target_id", ""))
		button.text = "[I] %s%s  /  %s" % [
			definition.display_name if definition != null else item.definition_id,
			" (bound to %s)" % _hero_name(binding) if not binding.is_empty() else "",
			instance_id,
		]
		if definition != null:
			button.content_id = definition.id
			button.tooltip_text = String(definition.id)
		button.gui_input.connect(_on_inventory_item_gui_input.bind(instance_id))
		button.drag_payload = {"source": &"inventory_item", "instance_id": instance_id}
		row.add_child(button)
		var sell := Button.new()
		sell.text = "SELL"
		sell.pressed.connect(_sell_inventory_item.bind(instance_id))
		row.add_child(sell)
		%InventoryRows.add_child(row)


func _refresh_market() -> void:
	_clear(%MarketRows)
	var title := Label.new()
	title.text = "MARKET  /  DOUBLE-CLICK TO BUY & EQUIP"
	title.add_theme_font_size_override("font_size", 19)
	%MarketRows.add_child(title)
	var reroll := Button.new()
	reroll.text = "REROLL  %d G" % MarketService.reroll_price(run_state.market)
	reroll.pressed.connect(_on_market_reroll_pressed)
	%MarketRows.add_child(reroll)
	for offer in run_state.market.offers:
		var definition: ContentDefinition = _registry().get_definition(offer.content_id, false)
		if definition == null:
			continue
		var row := HBoxContainer.new()
		var icon := Label.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.text = _market_offer_icon(offer.offer_type)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(icon)
		var content := ManagementDragButton.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.alignment = HORIZONTAL_ALIGNMENT_LEFT
		content.flat = true
		content.focus_mode = Control.FOCUS_NONE
		content.text = "%s  /  %d G\n%s - %s" % [definition.display_name, offer.price, _market_offer_target(offer), offer.rarity.to_upper()]
		content.content_id = definition.id
		content.tooltip_text = String(definition.id)
		content.tooltip_override = "%s\n%s\nOffer price: %d Gold\n\n%s" % [
			_market_offer_type_name(offer.offer_type),
			_market_offer_target(offer),
			offer.price,
			ContentButton.describe_content(definition.id),
		]
		content.gui_input.connect(_on_market_offer_gui_input.bind(offer.offer_id))
		content.drag_payload = {
			"source": &"market",
			"offer_id": offer.offer_id,
			"offer_type": offer.offer_type,
			"content_id": offer.content_id,
		}
		row.add_child(content)
		%MarketRows.add_child(row)


func _refresh_resurrection() -> void:
	_clear(%ResurrectionRows)
	var progression := _registry().get_definition(&"progression.demo", false) as ProgressionDefinition
	var cost := progression.resurrection_cost if progression != null else 0
	var dead_count := 0
	for hero in run_state.heroes:
		if hero.life_state != HeroState.DEAD:
			continue
		dead_count += 1
		var definition := _registry().get_definition(hero.definition_id, false) as HeroDefinition
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\nLevel %d - build and equipment retained" % [definition.display_name if definition != null else hero.unique_id, hero.level]
		row.add_child(label)
		var resurrect := Button.new()
		resurrect.text = "RESURRECT  %d G" % cost
		resurrect.disabled = progression == null or run_state.gold < cost
		resurrect.pressed.connect(_resurrect_hero.bind(hero.unique_id))
		row.add_child(resurrect)
		%ResurrectionRows.add_child(row)
	%ResurrectionEmpty.visible = dead_count == 0


func _refresh_encounter() -> void:
	%EncounterTitle.text = "ACT %s  /  BATTLE %d" % [_roman(run_state.current_act), run_state.encounter_index + 1]
	if run_state.available_encounter_ids.is_empty():
		%EncounterLabel.text = "NO ENCOUNTER"
		%FightButton.disabled = true
		return
	if String(run_state.selected_encounter_id).is_empty():
		%EncounterLabel.text = "CHOOSE THE NEXT BATTLE"
		%EncounterLabel.tooltip_text = ""
		%FightButton.disabled = true
		%FightButton.text = "CHOOSE AN ENCOUNTER"
		_refresh_preview()
		return
	var encounter := _registry().get_definition(run_state.selected_encounter_id, false) as EncounterDefinition
	if encounter == null:
		%EncounterLabel.text = "Selected encounter content is missing."
		%FightButton.disabled = true
		return
	%EncounterLabel.text = "%s  /  %s THREAT  /  %d GOLD" % [encounter.display_name.to_upper(), encounter.difficulty_hint.to_upper(), encounter.gold_reward]
	if encounter.has_reinforcements():
		%EncounterLabel.text += "  /  REINFORCEMENTS AT %d" % encounter.reinforcement_alive_threshold
	%EncounterLabel.tooltip_text = String(encounter.id)
	%FightButton.disabled = false
	%FightButton.text = "COMMIT TO BATTLE"
	_refresh_preview()


func _select_encounter(encounter_id: StringName) -> void:
	var result := EncounterService.select_encounter(run_state, encounter_id)
	if not result.ok:
		_set_feedback(result.error, true)
		return
	call_deferred("_refresh_all")
	_set_feedback("Encounter selected. Rebuild the army for the revealed threat.", false)
	run_state_changed.emit(&"encounter_selected")


func _on_management_drop(source: Dictionary, target: Dictionary) -> void:
	var result := ArmyBuildService.perform_drop(run_state, source, target, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	# The drop target is locked until Control._drop_data() returns.
	call_deferred("_refresh_all")
	var action := StringName(result.get("action", &"build_changed"))
	_set_feedback("Purchased and equipped." if bool(result.get("purchased", false)) else "Build updated.", false)
	run_state_changed.emit(action)


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
	if not _require_preparation():
		return
	if selected_kind != "soldier" or selected_index < 0:
		_set_feedback("Select a soldier before changing Job.", true)
		return
	var soldier := run_state.soldiers[selected_index]
	var target_id := job_option_ids[%JobOption.selected]
	if not run_state.unlocked_job_ids.has(target_id):
		_set_feedback("Unlock that Job in the Market first.", true)
		return
	if target_id == soldier.current_job_id:
		_set_feedback("This soldier already has that Job.", true)
		return
	if target_id != &"job.militia" and _assigned_count(target_id) >= _capacity(target_id):
		_set_feedback("Assignment blocked: %s capacity is full. Buy capacity in Market." % _display_name(target_id), true)
		return
	var equipment_validation := EquipmentService.can_change_job(run_state, selected_index, target_id, _registry())
	if not equipment_validation.ok:
		_set_feedback(equipment_validation.error, true)
		return
	var old_job := _display_name(soldier.current_job_id)
	soldier.current_job_id = target_id
	soldier.definition_id = target_id
	soldier.veterancy_xp = 0
	soldier.veterancy_level = 0
	_set_feedback("%s changed from %s to %s. Veterancy reset." % [soldier.generated_name, old_job, _display_name(target_id)], false)
	_refresh_all()
	run_state_changed.emit(&"job_changed")


func _on_job_preview_selected(_index: int) -> void:
	if selected_kind == "soldier" and selected_index >= 0:
		_update_job_warning(run_state.soldiers[selected_index], job_option_ids[%JobOption.selected])


func _update_job_warning(soldier: SoldierState, target_id: StringName) -> void:
	var capacity_text := "unlimited" if target_id == &"job.militia" else "%d/%d assigned" % [_assigned_count(target_id), _capacity(target_id)]
	%JobWarning.text = "Changing Job resets Veterancy %d and %d XP. Capacity: %s." % [soldier.veterancy_level, soldier.veterancy_xp, capacity_text]


func _select_ability_slot(index: int) -> void:
	selected_ability_slot = index
	_set_feedback("Ability slot %d selected." % (index + 1), false)


func _select_equipment_slot(index: int) -> void:
	selected_equipment_slot = index
	call_deferred("_refresh_selected")
	_set_feedback("Equipment slot %d selected." % (index + 1), false)


func _on_inventory_item_gui_input(event: InputEvent, instance_id: StringName) -> void:
	if _is_left_double_click(event):
		call_deferred("_equip_inventory_item", instance_id)


func _equip_inventory_item(instance_id: StringName) -> void:
	if not _require_preparation():
		return
	if selected_kind not in ["hero", "soldier"] or selected_index < 0:
		_set_feedback("Select the Hero or Soldier who should receive this item.", true)
		return
	var item_count := run_state.heroes[selected_index].item_ids.size() if selected_kind == "hero" else run_state.soldiers[selected_index].item_ids.size()
	var max_slots := HeroState.MAX_ITEM_SLOTS if selected_kind == "hero" else SoldierState.MAX_ITEM_SLOTS
	var target_slot := item_count if item_count < max_slots else selected_equipment_slot
	var result := EquipmentService.equip_or_swap(
		run_state,
		StringName(selected_kind),
		selected_index,
		target_slot,
		instance_id,
		_registry()
	)
	if not result.ok:
		_set_feedback(result.error, true)
		return
	var swapped := not String(result.replaced_instance_id).is_empty()
	_refresh_all()
	_set_feedback("Item %s. Preview stats updated immediately." % ("swapped" if swapped else "equipped"), false)
	run_state_changed.emit(&"equipment_changed")


func _move_hero_ability(index: int, direction: int) -> void:
	if not _require_preparation():
		return
	var hero := run_state.heroes[selected_index]
	var target := index + direction
	if target < 0 or target >= hero.ability_priority.size():
		return
	var value := hero.ability_priority[index]
	hero.ability_priority[index] = hero.ability_priority[target]
	hero.ability_priority[target] = value
	selected_ability_slot = target
	call_deferred("_refresh_selected")
	_set_feedback("Hero priority updated for the next battle.", false)
	run_state_changed.emit(&"hero_priority_changed")


func _buy_market_offer(offer_id: String) -> void:
	var offer := _market_offer(offer_id)
	if offer == null:
		_set_feedback("That Market offer is no longer available.", true)
		return
	if offer.offer_type not in [&"job_ability", &"hero_item", &"soldier_item"]:
		var purchase := MarketService.buy_offer(run_state, offer_id, _registry())
		if not purchase.ok:
			_set_feedback(purchase.error, true)
			return
		call_deferred("_refresh_all")
		_set_feedback("Purchased %s." % _display_name(purchase.offer.content_id), false)
		run_state_changed.emit(&"market_purchase")
		return
	var target := _automatic_market_target(offer)
	if not target.ok:
		_set_feedback(target.error, true)
		return
	var result := ArmyBuildService.perform_drop(
		run_state,
		{"source": &"market", "offer_id": offer.offer_id},
		target.target,
		_registry()
	)
	if not result.ok:
		_set_feedback(result.error, true)
		return
	call_deferred("_refresh_all")
	_set_feedback("Purchased and equipped %s." % _display_name(offer.content_id), false)
	run_state_changed.emit(StringName(result.get("action", &"market_purchase")))


func _market_offer(offer_id: String) -> MarketOffer:
	for offer in run_state.market.offers:
		if offer.offer_id == offer_id:
			return offer
	return null


func _automatic_market_target(offer: MarketOffer) -> Dictionary:
	if selected_kind == "hero" and selected_index >= 0 and selected_index < run_state.heroes.size():
		var hero := run_state.heroes[selected_index]
		if offer.offer_type == &"hero_item":
			if offer.target_id != hero.unique_id:
				return _target_failure("Select the Hero named on this item offer.")
			var item_slot := hero.item_ids.size() if hero.item_ids.size() < HeroState.MAX_ITEM_SLOTS else selected_equipment_slot
			return {"ok": true, "target": {"target": &"equipment", "owner_kind": &"hero", "owner_index": selected_index, "slot_index": item_slot}}
	if selected_kind == "soldier" and selected_index >= 0 and selected_index < run_state.soldiers.size():
		var soldier := run_state.soldiers[selected_index]
		if offer.offer_type == &"job_ability":
			if offer.target_id != String(soldier.current_job_id):
				return _target_failure("Select a Soldier with the Job named on this ability offer.")
			return _automatic_job_ability_target(offer, soldier.current_job_id)
		if offer.offer_type == &"soldier_item":
			var item_slot := soldier.item_ids.size() if soldier.item_ids.size() < SoldierState.MAX_ITEM_SLOTS else selected_equipment_slot
			return {"ok": true, "target": {"target": &"equipment", "owner_kind": &"soldier", "owner_index": selected_index, "slot_index": item_slot}}
	if selected_kind == "job" and offer.offer_type == &"job_ability":
		if offer.target_id != String(selected_job_id):
			return _target_failure("Select the Job named on this ability offer.")
		return _automatic_job_ability_target(offer, selected_job_id)
	return _target_failure("Select the Hero or Soldier who should receive this purchase.")


func _automatic_job_ability_target(offer: MarketOffer, job_id: StringName) -> Dictionary:
	var ability := _registry().get_definition(offer.content_id, false) as AbilityDefinition
	if ability == null:
		return _target_failure("That ability content is missing.")
	if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
		return {"ok": true, "target": {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": &"active", "slot_index": 0}}
	var passive_count := 0
	for build in run_state.job_builds:
		if build.job_id == job_id:
			passive_count = build.passive_ability_ids.size()
			break
	if passive_count >= 3:
		return _target_failure("All Job passive slots are full. Drag the offer onto a passive slot to replace it.")
	return {"ok": true, "target": {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": &"passive", "slot_index": passive_count}}


func _target_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _on_market_offer_gui_input(event: InputEvent, offer_id: String) -> void:
	if _is_left_double_click(event):
		call_deferred("_buy_market_offer", offer_id)


func _buy_capacity(job_id: StringName) -> void:
	for offer in run_state.market.offers:
		if offer.content_id == job_id and offer.offer_type == &"job_capacity":
			_buy_market_offer(offer.offer_id)
			return
	_set_feedback("No capacity offer is available for %s." % _display_name(job_id), true)


func _on_market_reroll_pressed() -> void:
	var result := MarketService.reroll(run_state, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	call_deferred("_refresh_all")
	_set_feedback("Market rerolled for %d Gold." % result.price, false)
	run_state_changed.emit(&"market_reroll")


func _resurrect_hero(hero_id: String) -> void:
	var result := ResurrectionService.resurrect(run_state, hero_id, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	_refresh_all()
	_set_feedback("%s returned to life at full HP for %d Gold." % [_display_name(result.hero.definition_id), result.cost], false)
	run_state_changed.emit(&"hero_resurrected")


func _sell_inventory_item(instance_id: StringName) -> void:
	var result := MarketService.sell_item(run_state, instance_id, _registry())
	if not result.ok:
		_set_feedback(result.error, true)
		return
	_refresh_all()
	_set_feedback("Sold %s for %d Gold." % [_display_name(result.item_id), result.gold], false)
	run_state_changed.emit(&"market_sale")


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


func _is_left_double_click(event: InputEvent) -> bool:
	return (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and event.double_click
	)


func _display_name(content_id: StringName) -> String:
	var definition: ContentDefinition = _registry().get_definition(content_id, false)
	return definition.display_name if definition != null else String(content_id)


func _market_offer_icon(offer_type: StringName) -> String:
	match offer_type:
		&"hero_item": return "HI"
		&"job_unlock": return "JU"
		&"job_capacity": return "JC"
		&"job_ability": return "JA"
		&"soldier_item": return "SI"
	return "?"


func _market_offer_type_name(offer_type: StringName) -> String:
	return String(offer_type).replace("_", " ").to_upper()


func _market_offer_target(offer: MarketOffer) -> String:
	if offer.target_type == &"hero":
		for hero in run_state.heroes:
			if hero.unique_id == offer.target_id:
				return "For %s" % _display_name(hero.definition_id)
	if offer.target_type == &"job" and not offer.target_id.is_empty():
		return "For %s" % _display_name(StringName(offer.target_id))
	if not offer.allowed_job_ids.is_empty():
		return "Jobs: %s" % _names(offer.allowed_job_ids)
	return "For any Soldier"


func _encounter_card_text(encounter: EncounterDefinition) -> String:
	var heading := "UNKNOWN ENCOUNTER" if encounter.is_unknown else encounter.display_name.to_upper()
	var details := "Composition concealed" if encounter.is_unknown else _enemy_composition(encounter.enemy_ids)
	if encounter.has_reinforcements():
		var direction := "right side" if encounter.reinforcement_entry_direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE else "all sides"
		details += "\nReinforcements at %d from %s" % [encounter.reinforcement_alive_threshold, direction]
		if not encounter.is_unknown:
			details += ": %s" % _enemy_composition(encounter.reinforcement_enemy_ids)
	var properties := "Risk concealed" if encounter.is_unknown else "; ".join(encounter.key_properties)
	return "%s\n%s | %d GOLD\n%s\n%s" % [heading, encounter.difficulty_hint.to_upper(), encounter.gold_reward, details, properties]


func _enemy_composition(enemy_ids: Array[StringName]) -> String:
	var counts: Dictionary = {}
	for enemy_id in enemy_ids:
		var enemy := _registry().get_definition(enemy_id, false) as EnemyDefinition
		var name := enemy.display_name if enemy != null else String(enemy_id)
		counts[name] = int(counts.get(name, 0)) + 1
	var parts := PackedStringArray()
	for enemy_name in counts:
		parts.append("%s x%d" % [enemy_name, counts[enemy_name]])
	return ", ".join(parts)


func _require_preparation() -> bool:
	if not String(run_state.selected_encounter_id).is_empty():
		return true
	_set_feedback("Choose an Encounter Card before rebuilding the army.", true)
	return false


func _roman(value: int) -> String:
	return "II" if value == 2 else "I"


func _hero_name(unique_id: String) -> String:
	for hero in run_state.heroes:
		if hero.unique_id == unique_id:
			return _display_name(hero.definition_id)
	return unique_id


func _item_definition(instance_id: StringName) -> ItemDefinition:
	return _registry().get_definition(run_state.inventory.get_definition_id(instance_id), false) as ItemDefinition


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
