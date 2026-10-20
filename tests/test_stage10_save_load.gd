extends SceneTree


const MAIN_SCENE := preload("res://main.tscn")

var failures := 0
var registry: Node
var save_directory := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	save_directory = "user://tests/stage10-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(save_directory)
	manager.delete_save()
	_test_disk_round_trip_and_rng(manager)
	_test_version_8_item_migration(manager)
	_test_invalid_saves(manager)
	await _test_main_lifecycle_and_autosave(manager)
	manager.delete_save()
	if failures == 0:
		print("Stage 10 save/load tests passed.")
		quit()
	else:
		push_error("Stage 10 save/load tests failed: %d" % failures)
		quit(1)


func _test_disk_round_trip_and_rng(manager: SaveManager) -> void:
	_check(manager.load_run(registry).code == &"missing", "Missing save is a normal non-crashing state.")
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var run := DemoRunFactory.create_starting_run(101010)
	run.inventory.create_item(&"item.gravedigger_fang")
	run.current_act = 2
	run.encounter_index = route.act_two_battle_count - 1
	run.available_encounter_ids = [&"encounter.act2_pressure", &"encounter.act2_crossbows"]
	run.selected_encounter_id = &"encounter.act2_pressure"
	run.gold = 777
	run.heroes[0].level = 3
	run.heroes[0].xp = 175
	run.unlocked_job_ids.append(&"job.warrior")
	run.soldiers[0].current_job_id = &"job.warrior"
	run.soldiers[0].definition_id = &"job.warrior"
	run.soldiers[0].veterancy_xp = 88
	run.job_capacities["job.warrior"] = 4
	run.tutorial_flags["save_seen"] = true
	var snapshot := ExecutionSnapshot.new()
	snapshot.hero_definition_id = run.heroes[2].definition_id
	snapshot.hero_unique_id = run.heroes[2].unique_id
	snapshot.life_state_at_execution = run.heroes[2].life_state
	snapshot.level = run.heroes[2].level
	snapshot.xp = run.heroes[2].xp
	snapshot.ability_ids = run.heroes[2].ability_ids.duplicate()
	snapshot.owned_ability_ids = run.heroes[2].owned_ability_ids.duplicate()
	snapshot.act = 1
	snapshot.encounter_index = route.act_one_boss_index()
	run.execution_snapshots.append(snapshot)
	run.heroes[2].life_state = HeroState.EXECUTED
	run.heroes[2].ability_ids.clear()
	run.heroes[2].owned_ability_ids.clear()
	var execution_recruit := SoldierState.new()
	execution_recruit.unique_id = "stage10-execution-recruit"
	execution_recruit.generated_name = "Militia 10"
	run.soldiers.append(execution_recruit)
	var blade := StringName(run.inventory.items[0].instance_id)
	EquipmentService.equip_or_swap(run, &"hero", 0, 0, blade, registry)
	run.run_rng.next_u32()
	run.combat_rng.next_u32()
	run.market.offers[0].is_pinned = true
	var expected_market_stream := RngStreamState.from_dictionary(run.market_rng.to_dictionary())
	var expected_market_draw := expected_market_stream.next_u32()
	var market_offers := run.market.to_dictionary()
	var saved_dictionary := run.to_dictionary()
	var save_result := manager.save_run(run, registry)
	_check(save_result.ok, "A complete Management RunState saves to controlled JSON.")
	var load_result := manager.load_run(registry)
	_check(load_result.ok, "A current-version save loads successfully.")
	if load_result.ok:
		var loaded: RunState = load_result.run_state
		_check(loaded.to_dictionary() == saved_dictionary, "Every RunState field survives a disk JSON round-trip.")
		_check(loaded.market.to_dictionary() == market_offers, "Current Market offers are restored exactly instead of regenerated.")
		_check(loaded.market.offers[0].is_pinned, "Locked Market positions survive Save and Load.")
		_check(loaded.market_rng.next_u32() == expected_market_draw, "The next Market RNG draw is identical after Load.")
		_check(loaded.heroes[2].life_state == HeroState.EXECUTED and loaded.execution_snapshots.size() == 1, "Executed Hero state and snapshot cannot be undone by Load.")
		_check(loaded.inventory.get_definition_id(blade) == &"item.gravedigger_fang" and loaded.heroes[0].item_ids.has(blade), "Inventory ownership and equipped instance IDs are restored.")
	var run_state_before_combat := run.run_rng.to_dictionary()
	var market_state_before_combat := run.market_rng.to_dictionary()
	run.combat_rng.next_seed()
	_check(run.run_rng.to_dictionary() == run_state_before_combat and run.market_rng.to_dictionary() == market_state_before_combat, "Combat RNG consumption does not affect Run or Market streams.")
	_check(not _contains_object(saved_dictionary), "Save data contains no Node, CombatSession, or other Object references.")

	manager.save_run(run, registry)
	manager.save_run(run, registry)
	_check(manager._generation_paths().size() == 2, "Atomic generation journal retains two published saves.")
	var temporary_path := "%s/run-99999999.json.tmp" % save_directory
	_write_text(temporary_path, "broken temporary data")
	_check(manager.load_run(registry).ok, "Unpublished temporary files are ignored and the previous generation remains loadable.")


func _test_version_8_item_migration(manager: SaveManager) -> void:
	manager.delete_save()
	var run := DemoRunFactory.create_starting_run(101011)
	run.inventory.create_item(&"item.gravedigger_fang")
	var data := run.to_dictionary()
	data["save_version"] = 8
	data.inventory.items[0]["bound_target_id"] = String(data.heroes[0].unique_id)
	for offer in data.market.offers:
		if StringName(offer.offer_type) == &"hero_item":
			offer.target_id = String(data.heroes[0].unique_id)
	_write_generation(data)
	var migrated := manager.load_run(registry)
	var migrated_items: Array = migrated.run_state.inventory.items if migrated.ok else []
	var migrated_offers: Array[MarketOffer] = migrated.run_state.market.offers if migrated.ok else []
	_check(migrated.ok and not migrated_items[0].has("bound_target_id"), "Version 8 item instances migrate without personal Hero bindings.")
	_check(migrated.ok and migrated_offers.all(func(offer: MarketOffer) -> bool: return offer.offer_type != &"hero_item" or offer.target_id.is_empty()), "Version 8 Market item offers migrate to shared Hero compatibility.")


func _test_invalid_saves(manager: SaveManager) -> void:
	manager.delete_save()
	_write_generation({"save_version": RunState.CURRENT_SAVE_VERSION - 2})
	var legacy := manager.load_run(registry)
	_check(legacy.code == &"unsupported_version" and legacy.message.contains("New Game"), "Pre-vertical-slice route saves are rejected with a clear recovery message.")
	manager.delete_save()
	_write_generation({"save_version": RunState.CURRENT_SAVE_VERSION + 1})
	var incompatible := manager.load_run(registry)
	_check(incompatible.code == &"unsupported_version" and incompatible.message.contains("New Game"), "Unknown save versions are rejected with a clear recovery message.")
	manager.delete_save()
	_write_generation({})
	_check(manager.load_run(registry).code == &"corrupt", "A versionless save is rejected as corrupt.")
	manager.delete_save()
	_write_text("%s/run-00000001.json" % save_directory, "{truncated")
	_check(manager.load_run(registry).code == &"corrupt", "Damaged JSON is handled without a crash.")
	manager.delete_save()
	var wrong_shape := DemoRunFactory.create_starting_run(10).to_dictionary()
	wrong_shape.heroes = "not-an-array"
	_write_generation(wrong_shape)
	_check(manager.load_run(registry).code == &"corrupt", "Valid JSON with invalid field types is rejected safely.")
	manager.delete_save()
	var combat_run := DemoRunFactory.create_starting_run(11)
	combat_run.run_phase = &"combat"
	_check(manager.save_run(combat_run, registry).code == &"invalid_phase" and not manager.has_any_save(), "An active CombatSession state is never serialized.")


func _test_main_lifecycle_and_autosave(manager: SaveManager) -> void:
	manager.delete_save()
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	_check(main.current_screen.name == "MainMenu" and main.current_screen.get_node("%ContinueButton").disabled, "Continue is disabled when no save exists.")
	main._start_new_game()
	await process_frame
	_check(main.current_screen.name == "HeroSelection" and not manager.has_any_save(), "New Game waits for Hero selection before creating a save.")
	main._begin_new_game(DemoRunFactory.HERO_IDS)
	await process_frame
	_check(main.current_screen.name == "Combat" and main.active_run.pending_event.event_id == &"event.opening_march" and manager.has_any_save(), "New Game creates an initial autosave and opens the story over the battlefield.")
	for step in 4:
		var event := registry.get_definition(main.active_run.pending_event.event_id) as RunEventDefinition
		var node := event.get_node_definition(main.active_run.pending_event.node_id)
		main._on_run_event_choice_requested(node.choices[0].choice_id)
	main.active_run.run_phase = &"management"
	main.show_management()
	var management = main.current_screen
	main.active_run.unlocked_job_ids.append(&"job.warrior")
	main.active_run.job_capacities["job.warrior"] = 1
	management._refresh_all()
	management._on_management_drop(
		{"source": &"soldier", "soldier_index": 0},
		{"target": &"job", "job_id": &"job.warrior"}
	)
	await process_frame
	var changed := manager.load_run(registry)
	_check(changed.ok and changed.run_state.soldiers[0].current_job_id == &"job.warrior", "A successful management action autosaves its transaction.")

	var persisted_combat_draw_count := int(changed.run_state.combat_rng.draw_count)
	main._request_combat()
	await process_frame
	_check(main.current_screen.name == "Combat" and main.active_run.run_phase == &"combat", "Combat starts with an in-memory battle state.")
	var rollback := manager.load_run(registry)
	_check(rollback.ok and rollback.run_state.run_phase == &"management" and rollback.run_state.combat_rng.draw_count == persisted_combat_draw_count, "Pre-combat save remains the rollback point while battle is active.")
	_check(rollback.run_state.encounter_committed, "Pre-combat rollback persists the encounter commitment lock.")
	main.show_main_menu()
	await process_frame
	main._continue_game()
	await process_frame
	_check(main.current_screen.name == "Management" and main.active_run.combat_rng.draw_count == persisted_combat_draw_count, "Continue after leaving combat restores the pre-combat run.")
	var alternate_id := &"encounter.raider_line"
	_check(not EncounterService.select_encounter(main.active_run, alternate_id).ok, "Continue can retry the committed battle but cannot choose another encounter.")

	main.active_run.gold += 55
	main.active_run.run_phase = &"combat"
	main.post_combat_prepared = true
	main._return_from_combat()
	await process_frame
	var post_combat := manager.load_run(registry)
	_check(post_combat.ok and post_combat.run_state.gold == main.active_run.gold, "Returning to Management autosaves post-combat consequences.")
	main.show_main_menu()
	await process_frame
	_check(not main.current_screen.get_node("%ContinueButton").disabled, "A valid save enables Continue on the main menu.")
	main.free()


func _write_generation(data: Dictionary) -> void:
	_write_text("%s/run-00000001.json" % save_directory, JSON.stringify(data))


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_directory))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _contains_object(value: Variant) -> bool:
	if value is Object:
		return true
	if value is Array:
		for entry in value:
			if _contains_object(entry):
				return true
	if value is Dictionary:
		for entry in value.values():
			if _contains_object(entry):
				return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
