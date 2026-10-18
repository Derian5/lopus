extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	_test_definitions_and_validation(registry)
	_test_inventory_identity()
	_test_equipment_transactions_and_snapshots(registry)
	await _test_management_actions(registry)
	if failures == 0:
		print("Stage 9 item and inventory tests passed.")
		quit()
	else:
		push_error("Stage 9 item tests failed: %d" % failures)
		quit(1)


func _test_definitions_and_validation(registry: Node) -> void:
	var hero_item := registry.get_definition(&"item.hero.vanguard_blade") as ItemDefinition
	_check(not hero_item.passive_effects.is_empty(), "Hero item uses the generic ItemDefinition and passive modifiers.")
	_check(hero_item.price > 0 and hero_item.sell_price > 0, "Item economy fields are populated without a rarity classification.")
	_check(hero_item.hero_eligibility == ItemDefinition.HeroEligibility.ANY, "Items default to compatibility with every Hero.")
	var item_count := 0
	for definition in registry.definitions.values():
		if definition is ItemDefinition:
			item_count += 1
	_check(item_count == 2, "The prototype exposes exactly two Hero item definitions.")

func _test_inventory_identity() -> void:
	_check(DemoRunFactory.create_starting_run(9008).inventory.items.is_empty(), "A new run starts with an empty Inventory.")
	var inventory := InventoryState.new()
	var first := inventory.create_item(&"item.hero.vanguard_blade")
	var second := inventory.create_item(&"item.hero.vanguard_blade")
	_check(first != second and inventory.get_definition_id(first) == inventory.get_definition_id(second), "Identical definitions create distinct stable item instances.")
	var restored := InventoryState.from_dictionary(inventory.to_dictionary())
	_check(restored.get_definition_id(first) == &"item.hero.vanguard_blade", "Item identity and definition mapping survive serialization.")
	var third := restored.create_item(&"item.hero.vanguard_blade")
	_check(third != first and third != second, "Inventory serial survives load and never reuses an item ID.")
	var sanitized := InventoryState.from_dictionary({
		"items": [
			{"instance_id": "item-custom", "definition_id": "item.hero.vanguard_blade"},
			{"instance_id": "item-custom", "definition_id": "item.hero.titan_seal"},
			{"instance_id": "", "definition_id": "item.hero.titan_seal"},
		],
	})
	_check(sanitized.items.size() == 1, "Malformed and duplicate inventory records are safely rejected.")


func _test_equipment_transactions_and_snapshots(registry: Node) -> void:
	var run := DemoRunFactory.create_starting_run(9009)
	run.inventory.create_item(&"item.hero.vanguard_blade")
	run.inventory.create_item(&"item.hero.titan_seal")
	var blade := _instance_for(run, &"item.hero.vanguard_blade")
	var seal := _instance_for(run, &"item.hero.titan_seal")
	var base_hero := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, registry)
	var equip := EquipmentService.equip_or_swap(run, &"hero", 0, 0, blade, registry)
	_check(equip.ok, "A Hero item equips through the shared transaction service.")
	var equipped_hero := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, registry)
	_check(is_equal_approx(equipped_hero.stats.damage, base_hero.stats.damage + 6.0), "Equipping immediately updates preview and combat snapshot stats.")
	_check(equipped_hero.equipped_item_instance_ids == [blade] and equipped_hero.equipped_item_definition_ids == [&"item.hero.vanguard_blade"], "Combat snapshots retain exact equipment for selected-unit details.")
	var duplicated_hero := equipped_hero.duplicate_snapshot()
	equipped_hero.equipped_item_instance_ids.clear()
	_check(duplicated_hero.equipped_item_instance_ids == [blade], "Duplicated combat snapshots own independent equipment arrays.")
	var duplicate_before := run.heroes[1].item_ids.duplicate()
	_check(not EquipmentService.equip_or_swap(run, &"hero", 1, 0, blade, registry).ok and run.heroes[1].item_ids == duplicate_before, "One physical item instance cannot be equipped twice.")
	_check(not EquipmentService.equip_or_swap(run, &"soldier", 0, 0, seal, registry).ok, "Only Heroes can be equipment targets.")

	var swap := EquipmentService.equip_or_swap(run, &"hero", 0, 0, seal, registry)
	_check(swap.ok and StringName(swap.replaced_instance_id) == blade, "Equipping into an occupied slot swaps the previous item to inventory.")
	var sealed_hero := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, registry)
	_check(sealed_hero.stats.max_hp > base_hero.stats.max_hp and is_equal_approx(sealed_hero.stats.damage, base_hero.stats.damage), "Swap immediately replaces the applied passive effects.")
	_check(EquipmentService.get_unequipped_items(run).any(func(item: Dictionary) -> bool: return StringName(item.instance_id) == blade), "The swapped item remains owned and becomes unequipped.")
	_check(EquipmentService.unequip(run, &"hero", 0, 0).ok and run.heroes[0].item_ids.is_empty(), "Unequip returns the exact instance to available inventory.")
	_check(EquipmentService.equip_or_swap(run, &"hero", 1, 0, blade, registry).ok, "An unrestricted item can move from one Hero to another.")
	EquipmentService.unequip(run, &"hero", 1, 0)

	_check(not EquipmentService.equip_or_swap(run, &"soldier", 2, 0, blade, registry).ok, "Hero item cannot equip to a Soldier.")
	_check(not EquipmentService.equip_or_swap(run, &"hero", 0, 0, &"missing-instance", registry).ok, "Unknown item instances are rejected.")

	var melee_only := ItemDefinition.new()
	melee_only.id = &"item.hero.runtime_melee"
	melee_only.display_name = "Runtime Melee"
	melee_only.hero_eligibility = ItemDefinition.HeroEligibility.MELEE
	var ranged_only := ItemDefinition.new()
	ranged_only.id = &"item.hero.runtime_ranged"
	ranged_only.display_name = "Runtime Ranged"
	ranged_only.hero_eligibility = ItemDefinition.HeroEligibility.RANGED
	_check(registry.register_definition(melee_only, false) and registry.register_definition(ranged_only, false), "Melee-only and ranged-only item definitions register without Hero IDs.")
	var melee_instance := run.inventory.create_item(melee_only.id)
	var ranged_instance := run.inventory.create_item(ranged_only.id)
	_check(EquipmentService.equip_or_swap(run, &"hero", 0, 0, melee_instance, registry).ok, "A melee Hero can equip a melee-only item.")
	EquipmentService.unequip(run, &"hero", 0, 0)
	_check(not EquipmentService.equip_or_swap(run, &"hero", 1, 0, melee_instance, registry).ok, "A ranged Hero cannot equip a melee-only item.")
	_check(EquipmentService.equip_or_swap(run, &"hero", 1, 0, ranged_instance, registry).ok, "A ranged Hero can equip a ranged-only item.")
	EquipmentService.unequip(run, &"hero", 1, 0)
	_check(not EquipmentService.equip_or_swap(run, &"hero", 0, 0, ranged_instance, registry).ok, "A melee Hero cannot equip a ranged-only item.")

	var generic := ItemDefinition.new()
	generic.id = &"item.hero.runtime_generic"
	generic.display_name = "Runtime Generic"
	var multiply := StatModifier.new()
	multiply.stat = "max_hp"
	multiply.operation = StatModifier.Operation.MULTIPLY
	multiply.value = 1.5
	var add := StatModifier.new()
	add.stat = "max_hp"
	add.operation = StatModifier.Operation.ADD
	add.value = 20.0
	generic.passive_effects = [multiply, add]
	_check(registry.register_definition(generic, false), "A new simple item registers without core-code changes.")
	var generic_instance := run.inventory.create_item(generic.id)
	EquipmentService.equip_or_swap(run, &"hero", 0, 0, generic_instance, registry)
	var generic_snapshot := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, registry)
	_check(is_equal_approx(generic_snapshot.stats.max_hp, (base_hero.stats.max_hp + 20.0) * 1.5), "ADD modifiers apply before MULTIPLY regardless of resource order.")

	var restored := RunState.from_dictionary(run.to_dictionary())
	_check(restored.inventory.get_definition_id(generic_instance) == generic.id and restored.heroes[0].item_ids.has(generic_instance), "Equipped instance ownership survives a RunState round-trip.")


func _test_management_actions(registry: Node) -> void:
	var run := DemoRunFactory.create_starting_run(9010)
	run.inventory.create_item(&"item.hero.vanguard_blade")
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	var changed_actions: Array[StringName] = []
	screen.run_state_changed.connect(func(action: StringName) -> void: changed_actions.append(action))
	await process_frame
	await process_frame
	EncounterService.select_encounter(run, run.available_encounter_ids[0])
	var blade := _instance_for(run, &"item.hero.vanguard_blade")
	screen._select_unit("hero", 0)
	var empty_slot: Button = screen.get_node("%EquipmentRows").get_child(0)
	empty_slot.pressed.emit()
	await process_frame
	_check(screen.selected_equipment_slot == 0 and screen.get_node("%EquipmentRows").get_child_count() == HeroState.MAX_ITEM_SLOTS and screen.get_node("%EquipmentRows").get_child(0) is ContentIconButton, "All six Hero equipment icon slots remain visible after selection.")
	_emit_double_click(_inventory_button(screen, blade))
	await process_frame
	_check(run.heroes[0].item_ids == [blade], "Double-clicking Inventory equips the selected item without an Equip button.")
	_check(screen.get_node("%EquipmentRows").get_child_count() >= 2, "Management UI renders occupied and available equipment slots.")
	var occupied_slot := screen.get_node("%EquipmentRows").get_child(0) as ManagementDropSlot
	var inventory_drop := screen.get_node("%InventoryDropSlot") as ManagementDropSlot
	inventory_drop._drop_data(Vector2.ZERO, occupied_slot.drag_payload)
	_check(run.heroes[0].item_ids.is_empty(), "Dragging equipped gear to shared Inventory unequips it.")
	_check(changed_actions.count(&"equipment_changed") == 2, "Equip and inventory return each request one autosave.")
	screen._select_unit("soldier", 0)
	await process_frame
	_check(not screen.get_node("%EquipmentRows").visible and not screen.get_node("%EquipmentCount").visible, "Soldiers expose no equipment section.")
	_emit_double_click(_inventory_button(screen, blade))
	await process_frame
	_check(screen.get_node("%FeedbackLabel").text.contains("Select the Hero"), "Management UI explains that items require a selected Hero.")
	var tooltip := ContentButton.describe_content(&"item.hero.vanguard_blade")
	_check(not tooltip.contains("COMMON") and not tooltip.contains("RARE") and not tooltip.contains("Any Hero") and tooltip.contains("Damage +6.0") and tooltip.contains("Sell: 50"), "Item tooltips omit rarity and redundant universal Hero compatibility while retaining modifiers and prices.")
	_check(screen.get_node("%InventoryRows").get_child_count() > 0, "Management Inventory lists available physical item instances.")
	screen.free()


func _instance_for(run: RunState, definition_id: StringName, occurrence := 0) -> StringName:
	var found := 0
	for item in run.inventory.items:
		if StringName(item.definition_id) != definition_id:
			continue
		if found == occurrence:
			return StringName(item.instance_id)
		found += 1
	return &""


func _inventory_button(screen: Control, instance_id: StringName) -> ManagementDragButton:
	for row in screen.get_node("%InventoryRows").get_children():
		var button := row.get_child(0) as ManagementDragButton if row is HBoxContainer and row.get_child_count() > 0 else null
		if button != null and StringName(button.drag_payload.get("instance_id", "")) == instance_id:
			return button
	return null


func _emit_double_click(button: Control) -> void:
	if button == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	button.gui_input.emit(event)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
