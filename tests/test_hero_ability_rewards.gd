extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")
const MAIN_SCENE := preload("res://main.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_level_content()
	_test_no_reward_without_level_up()
	_test_deterministic_generation()
	_test_weight_priority()
	_test_sequential_level_up_choices()
	_test_new_ability_and_upgrade()
	_test_full_slots_and_empty_pool()
	_test_pending_save_load()
	await _test_popup()
	await _test_main_flow()
	if failures == 0:
		print("Hero ability reward tests passed.")
		quit()
	else:
		push_error("Hero ability reward tests failed: %d" % failures)
		quit(1)


func _test_level_content() -> void:
	for definition in registry.definitions.values():
		if not definition is AbilityDefinition or not definition.available_to_heroes:
			continue
		var ability := definition as AbilityDefinition
		_check(ability.hero_levels.size() == 4, "%s defines four authored Hero levels." % ability.id)
		for level in ability.hero_levels:
			_check(level != null and not level.effects.is_empty(), "%s has a complete non-empty level." % ability.id)


func _test_no_reward_without_level_up() -> void:
	var run := DemoRunFactory.create_starting_run(8100)
	var before_rng := run.hero_ability_reward_rng.to_dictionary()
	var result := HeroAbilityRewardService.prepare_reward(run, registry)
	_check(result.ok and run.pending_hero_ability_reward.is_empty(), "An encounter without a Hero level-up grants no ability choice.")
	_check(run.hero_ability_reward_rng.to_dictionary() == before_rng, "Skipping a reward consumes no reward RNG.")


func _test_deterministic_generation() -> void:
	var first := DemoRunFactory.create_starting_run(8101)
	var second := DemoRunFactory.create_starting_run(8101)
	_queue(first, first.heroes[0], 1)
	_queue(second, second.heroes[0], 1)
	var first_result := HeroAbilityRewardService.prepare_reward(first, registry)
	var second_result := HeroAbilityRewardService.prepare_reward(second, registry)
	_check(first_result.ok and second_result.ok and first.pending_hero_ability_reward.offers.size() == 2, "One Hero level-up generates at most two choices.")
	_check(first.pending_hero_ability_reward.to_dictionary() == second.pending_hero_ability_reward.to_dictionary(), "Equal persisted RNG produces identical level-up choices.")
	_check(first.hero_ability_reward_rng.to_dictionary() == second.hero_ability_reward_rng.to_dictionary(), "Level-up generation persists identical RNG consumption.")
	var ability_ids: Dictionary = {}
	for offer in first.pending_hero_ability_reward.offers:
		ability_ids[offer.ability_id] = true
		var ability := registry.get_definition(offer.ability_id) as AbilityDefinition
		_check(offer.hero_unique_id == first.heroes[0].unique_id and ability.is_allowed_for_hero(first.heroes[0].definition_id), "Every card belongs to the Hero who leveled and is compatible with that Hero.")
	_check(ability_ids.size() == first.pending_hero_ability_reward.offers.size(), "A level-up choice never contains duplicate abilities.")


func _test_weight_priority() -> void:
	var run := DemoRunFactory.create_starting_run(8102)
	var hero := run.heroes[0]
	for ability_id in [&"ability.greed_golden_reserve", &"ability.greed_gilded_armory"]:
		hero.unlock_ability(ability_id)
		hero.equip_ability(ability_id)
	hero.ability_levels["ability.greed_golden_reserve"] = 1
	hero.ability_levels["ability.greed_gilded_armory"] = 3
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var candidates := HeroAbilityRewardService._candidates(hero, registry, route)
	var weights: Dictionary = {}
	for candidate in candidates:
		weights[String(candidate.ability_id)] = float(candidate.weight)
	_check(weights["ability.greed_shadowstep"] > weights["ability.greed_golden_reserve"], "A compatible new ability has more weight than an upgrade.")
	_check(weights["ability.greed_golden_reserve"] > weights["ability.greed_gilded_armory"], "A lower-level known ability has more weight than a higher-level one.")


func _test_sequential_level_up_choices() -> void:
	var run := DemoRunFactory.create_starting_run(8103)
	_queue(run, run.heroes[0], 2)
	_queue(run, run.heroes[2], 1)
	HeroAbilityRewardService.prepare_reward(run, registry)
	_check(run.pending_hero_ability_reward.hero_level_up_queue.size() == 3 and _offers_target(run, run.heroes[0].unique_id), "Multiple gained levels create an ordered reward queue.")
	var claimed := HeroAbilityRewardService.choose(run, run.pending_hero_ability_reward.offers[0].offer_id, registry)
	_check(claimed.ok, "The first level-up choice can be claimed.")
	if not claimed.ok:
		return
	run = claimed.run_state
	_check(run.pending_hero_ability_reward.hero_level_up_queue.size() == 2 and _offers_target(run, run.heroes[0].unique_id), "A second level gained by the same Hero immediately opens another choice.")
	claimed = HeroAbilityRewardService.choose(run, run.pending_hero_ability_reward.offers[0].offer_id, registry)
	_check(claimed.ok, "The second level-up choice can be claimed.")
	if not claimed.ok:
		return
	run = claimed.run_state
	_check(run.pending_hero_ability_reward.hero_level_up_queue.size() == 1 and _offers_target(run, run.heroes[2].unique_id), "The queue advances to the next Hero who gained a level.")
	claimed = HeroAbilityRewardService.choose(run, run.pending_hero_ability_reward.offers[0].offer_id, registry)
	_check(claimed.ok and claimed.run_state.pending_hero_ability_reward.is_empty(), "Completing every level-up choice clears the reward queue.")


func _test_new_ability_and_upgrade() -> void:
	var run := DemoRunFactory.create_starting_run(8104)
	_set_offer(run, run.heroes[0], &"ability.greed_dagger_nova")
	var claimed := HeroAbilityRewardService.choose(run, "test-offer", registry)
	_check(claimed.ok, "A new Hero ability can be claimed at level-up.")
	if not claimed.ok:
		return
	run = claimed.run_state
	var hero := run.heroes[0]
	_check(hero.owned_ability_ids.has(&"ability.greed_dagger_nova") and hero.ability_ids.has(&"ability.greed_dagger_nova") and hero.ability_level(&"ability.greed_dagger_nova") == 1, "A new ability is owned, equipped, and starts at Level 1.")
	run.pending_hero_ability_reward.clear()
	for expected_level in [2, 3, 4]:
		_set_offer(run, hero, &"ability.greed_dagger_nova")
		claimed = HeroAbilityRewardService.choose(run, "test-offer", registry)
		_check(claimed.ok, "A known ability advances to Level %d." % expected_level)
		if not claimed.ok:
			return
		run = claimed.run_state
		hero = run.heroes[0]
		run.pending_hero_ability_reward.clear()
		_check(hero.ability_level(&"ability.greed_dagger_nova") == expected_level and hero.ability_ids.count(&"ability.greed_dagger_nova") == 1, "An upgrade changes only ability level and never duplicates its slot.")
	_set_offer(run, hero, &"ability.greed_dagger_nova")
	var before := run.to_dictionary()
	var blocked := HeroAbilityRewardService.choose(run, "test-offer", registry)
	_check(not blocked.ok and run.to_dictionary() == before, "A Level 4 ability cannot be upgraded and rejection is atomic.")
	var snapshot := CombatSnapshotBuilder.build_hero(hero, run.inventory, registry)
	var runtime_ability: AbilityDefinition
	for ability in snapshot.abilities:
		if ability.id == &"ability.greed_dagger_nova":
			runtime_ability = ability
	var authored := registry.get_definition(&"ability.greed_dagger_nova") as AbilityDefinition
	_check(runtime_ability != null and runtime_ability.cooldown_seconds == authored.hero_levels[3].cooldown_seconds, "Combat uses the selected Level 4 parameters.")


func _test_full_slots_and_empty_pool() -> void:
	var run := DemoRunFactory.create_starting_run(8105)
	var hero := run.heroes[0]
	var equipped: Array[StringName] = [&"ability.greed_golden_reserve", &"ability.greed_gilded_armory", &"ability.greed_shadowstep", &"ability.greed_bounty_hunter"]
	for ability_id in equipped:
		hero.unlock_ability(ability_id)
		hero.equip_ability(ability_id)
		hero.ability_levels[String(ability_id)] = 4
	hero.ability_levels["ability.greed_golden_reserve"] = 3
	_queue(run, hero, 1)
	var result := HeroAbilityRewardService.prepare_reward(run, registry)
	_check(result.ok and run.pending_hero_ability_reward.offers.size() == 1 and run.pending_hero_ability_reward.offers[0].ability_id == &"ability.greed_golden_reserve", "A one-candidate pool displays one card without duplicates.")
	hero.ability_levels["ability.greed_golden_reserve"] = 4
	run.pending_hero_ability_reward.offers.clear()
	result = HeroAbilityRewardService.prepare_reward(run, registry)
	_check(result.ok and run.pending_hero_ability_reward.is_empty(), "A queued choice is skipped when that Hero has no eligible ability.")


func _test_pending_save_load() -> void:
	var run := DemoRunFactory.create_starting_run(8106)
	_queue(run, run.heroes[0], 2)
	_queue(run, run.heroes[1], 1)
	HeroAbilityRewardService.prepare_reward(run, registry)
	var directory := "user://tests/hero-ability-reward-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(directory)
	manager.delete_save()
	var saved := manager.save_run(run, registry)
	var loaded := manager.load_run(registry)
	_check(saved.ok and loaded.ok, "An active level-up reward queue saves and loads.")
	if loaded.ok:
		_check(loaded.run_state.pending_hero_ability_reward.to_dictionary() == run.pending_hero_ability_reward.to_dictionary(), "Save/load preserves current offers and all queued level-ups.")
		_check(loaded.run_state.hero_ability_reward_rng.to_dictionary() == run.hero_ability_reward_rng.to_dictionary(), "Save/load preserves the dedicated reward RNG stream.")
	var legacy_offer_data: Array = []
	var legacy_ability_ids := [&"ability.greed_golden_reserve", &"ability.greed_gilded_armory", &"ability.greed_shadowstep"]
	for index in legacy_ability_ids.size():
		legacy_offer_data.append({"offer_id": "legacy-%d" % index, "hero_unique_id": run.heroes[0].unique_id, "ability_id": String(legacy_ability_ids[index])})
	var legacy := PendingHeroAbilityReward.from_dictionary({"offers": legacy_offer_data})
	_check(legacy.hero_level_up_queue == [run.heroes[0].unique_id] and legacy.offers.size() == 2, "A version 8 three-card reward migrates to one queued two-card choice.")
	manager.delete_save()


func _test_popup() -> void:
	var run := DemoRunFactory.create_starting_run(8107)
	_queue(run, run.heroes[0], 1)
	HeroAbilityRewardService.prepare_reward(run, registry)
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	await process_frame
	var popup = screen.get_node("%HeroAbilityRewardPopup")
	_check(popup.visible and popup.get_node("%Offers").get_child_count() == 2, "Management displays the persisted two-card level-up modal.")
	_check(root.gui_get_focus_owner() == null, "Opening an ability reward does not preselect its first offer.")
	_check(not screen.get_node("%RunEventPopup").visible, "A Hero level-up reward has priority over a simultaneous Run Event popup.")
	screen.free()


func _test_main_flow() -> void:
	var directory := "user://tests/hero-ability-main-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(directory)
	manager.delete_save()
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	main.active_run = DemoRunFactory.create_starting_run(8108)
	_queue(main.active_run, main.active_run.heroes[0], 1)
	main.active_run.run_phase = &"combat"
	main._return_from_combat()
	await process_frame
	_check(main.current_screen.name == "EncounterChoice", "Returning from combat still shows Encounter choice before a level-up reward.")
	main._on_encounter_selected(main.active_run.available_encounter_ids[0])
	await process_frame
	_check(main.current_screen.name == "Management" and main.current_screen.get_node("%HeroAbilityRewardPopup").visible, "Choosing the Encounter opens Management with the pending level-up reward.")
	var offer: HeroAbilityRewardOffer = main.active_run.pending_hero_ability_reward.offers[0]
	main._on_hero_ability_reward_requested(offer.offer_id)
	await process_frame
	_check(main.current_screen.name == "Management" and main.active_run.pending_hero_ability_reward.is_empty(), "A saved final claim returns to preparation.")
	var loaded := manager.load_run(registry)
	_check(loaded.ok and loaded.run_state.pending_hero_ability_reward.is_empty(), "The reward claim is committed before navigation.")
	main.free()
	manager.delete_save()


func _queue(run: RunState, hero: HeroState, count: int) -> void:
	run.pending_hero_ability_reward.queue_level_ups(hero.unique_id, count)


func _set_offer(run: RunState, hero: HeroState, ability_id: StringName) -> void:
	run.pending_hero_ability_reward.clear()
	_queue(run, hero, 1)
	var offer := HeroAbilityRewardOffer.new()
	offer.offer_id = "test-offer"
	offer.hero_unique_id = hero.unique_id
	offer.ability_id = ability_id
	run.pending_hero_ability_reward.offers.append(offer)


func _offers_target(run: RunState, hero_unique_id: String) -> bool:
	if run.pending_hero_ability_reward.offers.is_empty():
		return false
	for offer in run.pending_hero_ability_reward.offers:
		if offer.hero_unique_id != hero_unique_id:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
