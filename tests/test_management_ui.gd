extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var run := DemoRunFactory.create_starting_run(7070)
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
	_check(screen.get_node("%EncounterLabel").text.contains("TRAINING SKIRMISH") and not screen.get_node("%FightButton").disabled, "The fixed tutorial encounter appears compactly in the header and enables preparation.")
	_check(run.market.offers.size() >= 5 and run.market.offers.size() <= 7, "Market generates five to seven offers.")
	_check(screen.get_node("%MarketRows").get_child_count() == run.market.offers.size() + 2, "Market shows every offer and its reroll action.")
	var item_offer := _offer("test-item-tooltip", &"hero_item", &"item.hero.vanguard_blade", 1, &"hero", run.heroes[0].unique_id)
	run.market.offers.append(item_offer)
	screen._refresh_market()
	var item_row: HBoxContainer = screen.get_node("%MarketRows").get_child(screen.get_node("%MarketRows").get_child_count() - 1)
	var item_content := item_row.get_child(1) as ContentButton
	var item_tooltip := item_content._make_custom_tooltip("") if item_content != null else null
	_check(item_content != null and item_content.content_id == &"item.hero.vanguard_blade" and item_tooltip is ContentTooltip, "Market item names expose the full custom hover tooltip.")
	if item_tooltip != null:
		root.add_child(item_tooltip)
		await process_frame
		await process_frame
		item_tooltip.size = Vector2(320.0, 1080.0)
		await process_frame
		var tooltip_panel := item_tooltip.get_node("Panel") as PanelContainer
		_check(tooltip_panel.size.y <= item_tooltip._get_minimum_size().y + 2.0 and tooltip_panel.size.y < item_tooltip.size.y, "The visible tooltip panel follows its rendered text even if Godot stretches the wrapper.")
		item_tooltip.free()

	var warrior_option: int = screen.job_option_ids.find(&"job.warrior")
	for soldier_index in 3:
		screen._select_unit("soldier", soldier_index)
		screen.get_node("%JobOption").select(warrior_option)
		screen._on_change_job_pressed()
		_check(run.soldiers[soldier_index].current_job_id == &"job.warrior", "Available Warrior capacity accepts assignment %d." % soldier_index)
	screen._select_unit("soldier", 3)
	screen.get_node("%JobOption").select(warrior_option)
	var actions_before_rejection := changed_actions.size()
	screen._on_change_job_pressed()
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
	var archer_option: int = screen.job_option_ids.find(&"job.archer")
	screen.get_node("%JobOption").select(archer_option)
	screen._on_job_preview_selected(archer_option)
	_check(screen.get_node("%JobWarning").text.contains("3") and screen.get_node("%JobWarning").text.contains("75"), "Job preview shows veterancy loss before confirmation.")
	screen._on_change_job_pressed()
	_check(run.soldiers[0].veterancy_level == 0 and run.soldiers[0].veterancy_xp == 0, "Confirmed Job change resets veterancy.")

	screen._select_unit("hero", 0)
	_check(run.heroes[0].ability_ids.is_empty() and screen.get_node("%AbilityRows").get_child_count() == HeroState.MAX_ABILITY_SLOTS, "A new Hero exposes all empty drag-and-drop ability slots.")
	_check(screen.find_child("OwnedTitle", true, false) == null and screen.find_child("OwnedAbilityRows", true, false) == null, "Management no longer displays an Owned Abilities section.")
	for ability_id in [&"ability.fire_bolt", &"ability.whirlwind", &"ability.battle_fury"]:
		run.heroes[0].unlock_ability(ability_id)
		run.heroes[0].equip_ability(ability_id)
	screen._refresh_selected()
	_check(screen.get_node("%AbilityRows").get_child(0).get_child(0).text.contains("LV 1"), "Management displays the persisted Hero ability level.")
	var old_first := run.heroes[0].ability_priority[0]
	screen._move_hero_ability(1, -1)
	_check(run.heroes[0].ability_priority[1] == old_first, "Hero ability priority moves up and down.")
	var gold_before_direct_item := run.gold
	screen._buy_market_offer(item_offer.offer_id)
	_check(run.gold == gold_before_direct_item - 1 and run.heroes[0].item_ids.size() == 1, "A purchased item automatically equips on the selected Hero.")
	await process_frame
	screen._select_unit("hero", 0)
	screen._select_equipment_slot(5)
	await process_frame
	var seal_instance := _inventory_instance(run, &"item.hero.titan_seal")
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
	var blocked_item := _offer("test-blocked-direct-item", &"hero_item", &"item.hero.titan_seal", 1, &"hero", run.heroes[0].unique_id)
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
	var job_ability_offer := _offer("test-job-drag", &"job_ability", &"ability.whirlwind", 1, &"job", "job.warrior")
	run.market.offers.append(job_ability_offer)
	screen._select_unit("soldier", 1)
	screen._buy_market_offer(job_ability_offer.offer_id)
	_check(screen._job_build(&"job.warrior").active_ability_id == &"ability.whirlwind", "A purchased Job ability automatically equips in the selected Soldier's shared build.")
	var soldier_item := ItemDefinition.new()
	soldier_item.id = &"item.test.auto_soldier"
	soldier_item.display_name = "Auto Soldier Item"
	soldier_item.allowed_target_type = &"soldier"
	soldier_item.allowed_job_ids = [&"job.warrior"]
	root.get_node("ContentRegistry").register_definition(soldier_item, false)
	var soldier_item_offer := _offer("test-auto-soldier-item", &"soldier_item", soldier_item.id, 1, &"soldier", "")
	soldier_item_offer.allowed_job_ids = [&"job.warrior"]
	run.market.offers.append(soldier_item_offer)
	screen._buy_market_offer(soldier_item_offer.offer_id)
	_check(run.soldiers[1].item_ids.size() == 1, "A purchased Soldier item automatically equips on the selected compatible Soldier.")
	_check(changed_actions.has(&"job_changed") and changed_actions.has(&"hero_priority_changed"), "Hero priority and Soldier management mutations request autosave.")
	_check(changed_actions.has(&"market_purchase") and changed_actions.has(&"job_build_changed"), "Market and Job build mutations request autosave.")
	var tooltip := ContentButton.describe_content(&"ability.fire_bolt")
	_check(tooltip.contains("Cooldown: 6.0") and tooltip.contains("Damage 4.0") and tooltip.contains("Max stacks: 3"), "Unified tooltip reads complete ability and status values.")
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
	if failures == 0:
		print("Management UI tests passed.")
		quit()
	else:
		push_error("Management UI tests failed: %d" % failures)
		quit(1)


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
	offer.rarity = "common"
	offer.price = price
	offer.target_type = target_type
	offer.target_id = target_id
	if offer_type in [&"job_unlock", &"job_capacity", &"job_ability"]:
		offer.allowed_job_ids.append(StringName(target_id))
	return offer
