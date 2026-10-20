extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var test_job_ability := AbilityDefinition.new()
	test_job_ability.id = &"ability.test_job_active"
	test_job_ability.display_name = "Test Job Active"
	test_job_ability.available_to_heroes = false
	registry.register_definition(test_job_ability, false)
	(registry.get_definition(&"job.archer") as JobDefinition).available_ability_ids.append(test_job_ability.id)
	var run := DemoRunFactory.create_starting_run(7070)
	run.inventory.create_item(&"item.bone_bell")
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	var changed_actions: Array[StringName] = []
	screen.run_state_changed.connect(func(action: StringName) -> void: changed_actions.append(action))
	await process_frame
	await process_frame

	var draggable_soldiers := 0
	for row in screen.get_node("%Roster").get_children():
		if row is HBoxContainer and row.get_child_count() > 1 and row.get_child(1) is ManagementDragButton:
			draggable_soldiers += 1
	_check(draggable_soldiers == 9, "Army roster groups and exposes all nine soldiers as draggable units.")
	_check(screen.get_node("%GoldLabel").text.contains("300"), "Gold is visible.")
	_check(not run.unlocked_job_ids.has(&"job.warrior") and int(run.job_capacities.get("job.warrior", 0)) == 0, "A new run starts with Warrior locked and without free capacity.")
	_check(not screen.get_node("%Roster").get_children().any(func(row: Node) -> bool: return row is ManagementDropSlot and row.target_payload.get("job_id", &"") == &"job.warrior"), "Management hides the Warrior 0 / 0 row while the Job is locked.")
	_check(screen.get_node("%EncounterLabel").text.contains("OGRES ON THE ROAD") and not screen.get_node("%FightButton").disabled, "The fixed tutorial encounter appears compactly in the header and enables preparation.")
	_check(run.market.offers.size() >= 5 and run.market.offers.size() <= 7, "Market generates five to seven offers.")
	_check(screen.get_node("%MarketRows").get_child_count() == run.market.offers.size() + 2, "Market shows every offer and its reroll action.")
	var first_market_row := screen.get_node("%MarketRows").get_child(2) as HBoxContainer
	var first_pin := first_market_row.get_child(2) as Button
	first_pin.toggled.emit(true)
	await process_frame
	_check(run.market.offers[0].is_pinned and changed_actions.has(&"market_pin_changed"), "The Market lock control persists its position and requests autosave.")
	first_market_row = screen.get_node("%MarketRows").get_child(2) as HBoxContainer
	_check((first_market_row.get_child(2) as Button).text == "LOCKED", "A locked Market position is visibly marked.")
	_check(screen.find_child("MarketFilters", true, false) == null, "Market shows all offer types in one list without category filters.")
	var item_offer := _offer("test-item-tooltip", &"hero_item", &"item.gravedigger_fang", 1, &"hero", "")
	run.market.offers.append(item_offer)
	screen._refresh_market()
	var item_row: HBoxContainer = screen.get_node("%MarketRows").get_child(screen.get_node("%MarketRows").get_child_count() - 1)
	var item_content := item_row.get_child(1) as ContentButton
	var item_tooltip := item_content._create_content_tooltip(item_content._content_tooltip_text()) if item_content != null else null
	_check(item_content != null and item_content.content_id == &"item.gravedigger_fang" and item_tooltip is ContentTooltip and item_content.has_meta("disable_auto_motion") and item_content.tooltip_text.is_empty(), "Market item names expose only the owner-managed hover tooltip without transform animation.")
	if item_tooltip != null:
		root.add_child(item_tooltip)
		await process_frame
		await process_frame
		_check(item_content.get_node_or_null("AutoButtonMotion") == null, "Tooltip owners do not receive the global hover-scale component.")
		_check(item_tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE and item_tooltip.get_node("Margin").mouse_filter == Control.MOUSE_FILTER_IGNORE and item_tooltip.get_node("Margin/Text").mouse_filter == Control.MOUSE_FILTER_IGNORE, "Custom content tooltips are fully transparent to pointer hover.")
		var stable_size: Vector2 = item_tooltip.custom_minimum_size
		await process_frame
		_check(item_tooltip.custom_minimum_size == stable_size and stable_size.y > 40.0, "Custom content tooltips have their final size before display and never resize after opening.")
		item_tooltip.free()
	item_content._show_custom_tooltip()
	await process_frame
	var persistent_tooltip_id := ContentButton.active_tooltip.get_instance_id() if is_instance_valid(ContentButton.active_tooltip) else 0
	await create_timer(1.2).timeout
	_check(persistent_tooltip_id != 0 and is_instance_valid(ContentButton.active_tooltip) and ContentButton.active_tooltip.get_instance_id() == persistent_tooltip_id, "Owner-managed content tooltip remains the same instance until its source loses hover.")
	item_content._hide_custom_tooltip()
	await process_frame
	_check(not is_instance_valid(ContentButton.active_tooltip), "Owner-managed content tooltip closes when its source loses hover.")
	var empty_slot := ManagementDropSlot.new()
	root.add_child(empty_slot)
	empty_slot._show_custom_tooltip()
	await process_frame
	_check(not is_instance_valid(ContentButton.active_tooltip), "Empty ability and equipment slots never create content tooltips.")
	empty_slot.free()
	run.unlocked_job_ids.append(&"job.warrior")
	run.job_capacities["job.warrior"] = 3
	screen._refresh_all()
	for soldier_index in 3:
		screen._on_management_drop(
			{"source": &"soldier", "soldier_index": soldier_index},
			{"target": &"job", "job_id": &"job.warrior"}
		)
		_check(run.soldiers[soldier_index].current_job_id == &"job.warrior", "Available Warrior capacity accepts assignment %d." % soldier_index)
	var actions_before_rejection := changed_actions.size()
	screen._on_management_drop(
		{"source": &"soldier", "soldier_index": 3},
		{"target": &"job", "job_id": &"job.warrior"}
	)
	_check(run.soldiers[3].current_job_id == &"job.militia", "A fourth Warrior assignment is blocked at capacity.")
	_check(screen.get_node("%FeedbackLabel").text.contains("capacity is full"), "Blocked assignment explains the capacity problem.")
	_check(changed_actions.size() == actions_before_rejection, "Rejected management actions do not request autosave.")

	run.soldiers[0].veterancy_level = 3
	run.soldiers[0].veterancy_xp = 75
	var unlock_offer := _offer("test-unlock-archer", &"job_unlock", &"job.archer", 180, &"job", "job.archer")
	run.market.offers.append(unlock_offer)
	screen._buy_market_offer(unlock_offer.offer_id)
	await process_frame
	screen._select_unit("soldier", 0)
	_check(screen.find_child("JobControls", true, false) == null and screen.find_child("JobOption", true, false) == null and screen.find_child("ChangeJobButton", true, false) == null, "The soldier inspector omits duplicate Job assignment controls.")
	screen._on_management_drop(
		{"source": &"soldier", "soldier_index": 0},
		{"target": &"job", "job_id": &"job.archer"}
	)
	_check(run.soldiers[0].veterancy_level == 0 and run.soldiers[0].veterancy_xp == 0, "Changing Job by dropping a soldier onto a profession resets veterancy.")

	screen._select_unit("hero", 0)
	_check(screen.find_child("ArmyNavButton", true, false) == null and screen.find_child("MarketNavButton", true, false) == null and screen.find_child("RosterSearch", true, false) == null, "Management omits the redundant Army/Market navigation and roster search controls.")
	_check(screen.find_child("InspectorTabs", true, false) == null and screen.get_node("%BehaviorControls").visible and screen.get_node("%AbilityRows").visible and screen.get_node("%EquipmentRows").visible, "The Hero inspector shows behavior, abilities, and equipment together without tabs.")
	var selected_hero_snapshot := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, root.get_node("ContentRegistry"))
	_check(screen.get_node("%StatsGrid").visible and screen.get_node("%HpStatValue").text == "%.0f" % selected_hero_snapshot.stats.max_hp and screen.get_node("%DamageStatValue").text == "%.0f" % selected_hero_snapshot.stats.damage, "The Hero summary exposes calculated combat stats in the icon grid.")
	var hp_tooltip: String = (screen.get_node("%StatsGrid").get_node("HpStat").get_meta("stat_tooltip_binding") as StatTooltipBinding).text
	_check(hp_tooltip.contains("MAX HEALTH") and hp_tooltip.contains("Base:") and hp_tooltip.contains("FINAL:"), "Management stat hover explains the base value and final result.")
	_check(screen.get_node("%BehaviorControls").visible and screen.get_node("%TargetClosestButton").button_pressed and screen.get_node("%AcceptDamageButton").button_pressed, "A melee Hero defaults to the nearest enemy and does not avoid damage.")
	screen.get_node("%TargetFarthestButton").pressed.emit()
	screen.get_node("%AvoidDamageButton").pressed.emit()
	_check(run.heroes[0].targeting_mode == &"farthest" and run.heroes[0].damage_avoidance_override == 1, "The four behavior buttons persist the selected Hero settings.")
	_check(changed_actions.count(&"combat_behavior_changed") == 2, "Each combat behavior change requests an autosave.")
	var first_empty_ability := screen.get_node("%AbilityRows").get_child(0).get_child(0) as ContentIconButton
	_check(run.heroes[0].ability_ids.is_empty() and screen.get_node("%AbilityRows").get_child_count() == HeroState.MAX_ABILITY_SLOTS and first_empty_ability.content_id.is_empty(), "A new Hero exposes four empty ability icon slots.")
	_check(screen.find_child("OwnedTitle", true, false) == null and screen.find_child("OwnedAbilityRows", true, false) == null, "Management no longer displays an Owned Abilities section.")
	for ability_id in [&"ability.greed_dagger_nova", &"ability.greed_shadowstep", &"ability.greed_smoke_bomb"]:
		run.heroes[0].unlock_ability(ability_id)
		run.heroes[0].equip_ability(ability_id)
	screen._refresh_selected()
	_check(screen.get_node("%AbilityRows").get_child(0).get_child(0).badge_text == "L1", "Management displays the persisted Hero ability level on its icon.")
	_check(screen.get_node("%AbilityRows").get_children().all(func(cell: Node) -> bool: return cell.get_child_count() == 1), "Hero ability slots expose no manual order controls.")
	var gold_before_direct_item := run.gold
	screen._buy_market_offer(item_offer.offer_id)
	_check(run.gold == gold_before_direct_item - 1 and run.heroes[0].item_ids.size() == 1, "A purchased item automatically equips on the selected Hero.")
	await process_frame
	screen._select_unit("hero", 0)
	_check((screen.get_node("%StatsGrid").get_node("DamageStat").get_meta("stat_tooltip_binding") as StatTooltipBinding).text.contains("Item:"), "Management stat hover attributes equipped item modifiers.")
	screen._select_equipment_slot(5)
	await process_frame
	var seal_instance := _inventory_instance(run, &"item.bone_bell")
	var seal_button := _inventory_item_button(screen, seal_instance)
	_emit_double_click(seal_button)
	await process_frame
	_check(run.heroes[0].item_ids.size() == 2 and run.heroes[0].item_ids[1] == seal_instance, "Double-clicking Inventory fills the first free slot without selecting an inventory item or equipment slot.")
	_check(screen.find_child("UnequipItemButton", true, false) == null and screen.find_child("SellItemButton", true, false) == null, "Management removes selected-item and selected-slot inventory actions.")
	var equipped_slot := screen.get_node("%EquipmentRows").get_child(0) as ManagementDropSlot
	var returned_instance := StringName(equipped_slot.drag_payload.get("instance_id", ""))
	var inventory_drop := screen.get_node("%InventoryDropSlot") as ManagementDropSlot
	inventory_drop._drop_data(Vector2.ZERO, equipped_slot.drag_payload)
	_check(not run.heroes[0].item_ids.has(returned_instance) and not EquipmentService.is_instance_equipped(run, returned_instance), "Dragging equipped gear onto shared Inventory returns it without an Unequip button.")
	var blocked_item := _offer("test-blocked-direct-item", &"hero_item", &"item.bone_bell", 1, &"hero", "")
	run.market.offers.append(blocked_item)
	var gold_before_blocked_item := run.gold
	screen._on_management_drop(
		{"source": &"market", "offer_id": blocked_item.offer_id},
		{"target": &"equipment", "owner_kind": &"soldier", "owner_index": 1, "slot_index": 0}
	)
	_check(run.gold == gold_before_blocked_item and run.market.offers.has(blocked_item), "A rejected Market drop preserves Gold and the original offer.")

	var old_gold := run.gold
	var old_capacity := int(run.job_capacities["job.archer"])
	var capacity_offer := _offer("test-capacity-archer", &"job_capacity", &"job.archer", 110, &"job", "job.archer")
	run.market.offers.append(capacity_offer)
	screen._buy_capacity(&"job.archer")
	_check(run.gold == old_gold - 110 and int(run.job_capacities["job.archer"]) == old_capacity + 1, "Market purchase spends real Gold and increases capacity.")
	screen._on_management_drop(
		{"source": &"soldier", "soldier_index": 4},
		{"target": &"job", "job_id": &"job.archer"}
	)
	_check(run.soldiers[4].current_job_id == &"job.archer", "Dropping a soldier onto a profession assigns the Job through capacity validation.")
	await process_frame
	var militia_source: ManagementDragButton
	var warrior_target: ManagementDropSlot
	for row in screen.get_node("%Roster").get_children():
		if row is ManagementDropSlot and row.target_payload.get("job_id", &"") == &"job.warrior":
			warrior_target = row
		if row is HBoxContainer and row.get_child_count() > 1 and row.get_child(1) is ManagementDragButton:
			var candidate := row.get_child(1) as ManagementDragButton
			if int(candidate.drag_payload.get("soldier_index", -1)) == 5:
				militia_source = candidate
	_check(militia_source != null and warrior_target != null, "Management exposes a real soldier source and profession drop target.")
	if militia_source != null and warrior_target != null:
		warrior_target._drop_data(Vector2.ZERO, militia_source.drag_payload)
		_check(run.soldiers[5].current_job_id == &"job.warrior", "A real drop signal applies the profession change before deferred UI rebuilding.")
		await process_frame
	var job_ability_offer := _offer("test-job-drag", &"job_ability", &"ability.test_job_active", 1, &"job", "job.archer")
	run.market.offers.append(job_ability_offer)
	screen._select_unit("soldier", 0)
	screen._buy_market_offer(job_ability_offer.offer_id)
	_check(screen._job_build(&"job.archer").active_ability_id == &"ability.test_job_active", "A purchased Job ability automatically equips in the selected Soldier's shared build.")
	screen._select_unit("soldier", 1)
	await process_frame
	_check(not screen.get_node("%EquipmentRows").visible and not screen.get_node("%EquipmentCount").visible, "The Soldier inspector contains no item slots.")
	_check(screen.get_node("%AbilityRows").get_child_count() >= HeroState.MAX_ABILITY_SLOTS and screen.get_node("%AbilityRows").get_child(3) is ContentIconButton, "The Soldier inspector reserves at least four ability icon slots.")
	_check(changed_actions.has(&"job_changed") and not changed_actions.has(&"hero_priority_changed"), "Soldier management mutations request autosave without obsolete Hero priority actions.")
	_check(changed_actions.has(&"market_purchase") and changed_actions.has(&"job_build_changed"), "Market and Job build mutations request autosave.")
	var tooltip := ContentButton.describe_content(&"ability.greed_dagger_nova")
	_check(tooltip.contains("ACTIVE") and tooltip.contains("cooldown.png[/img] [b]8") and tooltip.contains("radius.png[/img] [b]200[/b]") and tooltip.contains("70") and tooltip.contains("damage") and not tooltip.contains("Target:") and not tooltip.contains("Delivery:"), "Ability tooltip uses a compact player-facing MOBA layout.")
	_check(ContentButton.describe_content(&"status.burn").contains("Max stacks: 3"), "Unified tooltip supports statuses.")

	var snapshots := CombatSnapshotBuilder.build_player_army(run, root.get_node("ContentRegistry"))
	_check(snapshots.size() == 12 and snapshots[3].job_id == &"job.archer", "Management changes immediately affect combat preview snapshots.")
	screen.size = Vector2(800, 600)
	screen.get_node("%DetailsLabel").text += "\n" + "Long inspector detail\n".repeat(30)
	await process_frame
	await process_frame
	var columns_scroll := screen.get_node("Page/Layout/ColumnsScroll") as ScrollContainer
	var inspector_scroll := screen.get_node("Page/Layout/ColumnsScroll/Columns/InspectorCard/Margin/InspectorScroll") as ScrollContainer
	var screen_bottom: float = screen.get_global_rect().end.y
	_check(columns_scroll.is_visible_in_tree() and inspector_scroll.get_v_scroll_bar().visible, "Oversized Management content scrolls inside the inspector column.")
	_check(screen.get_node("Page/Layout/Header").get_global_rect().position.y >= screen.get_global_rect().position.y, "Management header remains visible in a narrow viewport.")
	_check(screen.get_node("Page/Layout/Footer").get_global_rect().end.y <= screen_bottom, "Management battle action remains visible in a narrow viewport.")

	screen.free()
	_test_roster_market_icons()
	if failures == 0:
		print("Management UI tests passed.")
		quit()
	else:
		push_error("Management UI tests failed: %d" % failures)
		quit(1)


func _test_roster_market_icons() -> void:
	var registry := root.get_node("ContentRegistry")
	var run := DemoRunFactory.create_starting_run(7071)
	var jobs: Array[StringName] = [&"job.militia", &"job.archer", &"job.priest", &"job.summoner", &"job.warrior", &"job.shieldbearer"]
	run.market.offers.clear()
	for index in jobs.size():
		var job_id := jobs[index]
		run.soldiers[index].current_job_id = job_id
		if not run.unlocked_job_ids.has(job_id):
			run.unlocked_job_ids.append(job_id)
			run.job_capacities[String(job_id)] = 9
		if job_id != &"job.militia":
			run.market.offers.append(_offer("roster-icon-%s" % job_id, &"job_capacity", job_id, 100, &"job", String(job_id)))
	# Check both authored textures and the same fallback used by capacity offers.
	var warrior := registry.get_definition(&"job.warrior") as JobDefinition
	var previous_icon: Texture2D = warrior.icon
	warrior.icon = (registry.get_definition(&"item.gravedigger_fang") as ItemDefinition).icon
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	for row in screen.get_node("%Roster").get_children():
		if not row is HBoxContainer or row.get_child_count() < 2 or not row.get_child(1) is ManagementDragButton:
			continue
		var drag := row.get_child(1) as ManagementDragButton
		var soldier_index := int(drag.drag_payload.get("soldier_index", -1))
		var job_id := run.soldiers[soldier_index].current_job_id
		var icon := row.get_child(0) as TextureRect
		_check(icon != null and icon.texture != null and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Soldier roster rows use image icons without blocking selection or dragging.")
		if job_id == &"job.militia" or icon == null:
			continue
		var market_button := _market_offer_button(screen, "roster-icon-%s" % job_id)
		var market_icon := market_button.get_parent().get_child(0) as TextureRect
		_check(_same_texture(icon.texture, market_icon.texture), "%s uses the same icon in the roster and Market." % job_id)
		for heading in screen.get_node("%Roster").get_children():
			if heading is ManagementDropSlot and heading.target_payload.get("job_id", &"") == job_id:
				_check(_same_texture(heading.icon, market_icon.texture), "The Job heading also uses the Market's icon.")
	warrior.icon = previous_icon
	screen.free()


func _same_texture(first: Texture2D, second: Texture2D) -> bool:
	if first == second:
		return true
	return first is AtlasTexture and second is AtlasTexture and first.atlas == second.atlas and first.region == second.region


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _emit_double_click(button: Control) -> void:
	if button == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	button.gui_input.emit(event)


func _market_offer_button(screen: Control, offer_id: String) -> ManagementDragButton:
	for row in screen.get_node("%MarketRows").get_children():
		if row is HBoxContainer and row.get_child_count() > 1:
			var button := row.get_child(1) as ManagementDragButton
			if button != null and button.drag_payload.get("offer_id", "") == offer_id:
				return button
	return null


func _inventory_item_button(screen: Control, instance_id: StringName) -> ManagementDragButton:
	for row in screen.get_node("%InventoryRows").get_children():
		var button := row.get_child(0) as ManagementDragButton if row is HBoxContainer and row.get_child_count() > 0 else null
		if button != null and StringName(button.drag_payload.get("instance_id", "")) == instance_id:
			return button
	return null


func _inventory_instance(run: RunState, definition_id: StringName) -> StringName:
	for item in run.inventory.items:
		if StringName(item.get("definition_id", "")) == definition_id and not EquipmentService.is_instance_equipped(run, StringName(item.get("instance_id", ""))):
			return StringName(item.get("instance_id", ""))
	return &""


func _offer(
	offer_id: String,
	offer_type: StringName,
	content_id: StringName,
	price: int,
	target_type: StringName,
	target_id: String
) -> MarketOffer:
	var offer := MarketOffer.new()
	offer.offer_id = offer_id
	offer.offer_type = offer_type
	offer.content_id = content_id
	offer.price = price
	offer.target_type = target_type
	offer.target_id = target_id
	if offer_type in [&"job_unlock", &"job_capacity", &"job_ability"]:
		offer.allowed_job_ids.append(StringName(target_id))
	return offer
