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
	_test_deterministic_generation()
	_test_new_ability_and_upgrade()
	_test_full_slots_and_duplicate_fallback()
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


func _test_deterministic_generation() -> void:
	var first := DemoRunFactory.create_starting_run(8101)
	var second := DemoRunFactory.create_starting_run(8101)
	var first_result := HeroAbilityRewardService.prepare_reward(first, registry)
	var second_result := HeroAbilityRewardService.prepare_reward(second, registry)
	_check(first_result.ok and second_result.ok and first.pending_hero_ability_reward.offers.size() == 3, "A post-battle reward generates three choices.")
	_check(first.pending_hero_ability_reward.to_dictionary() == second.pending_hero_ability_reward.to_dictionary(), "Equal persisted RNG produces identical Hero ability choices.")
	_check(first.hero_ability_reward_rng.to_dictionary() == second.hero_ability_reward_rng.to_dictionary(), "Reward generation persists identical RNG consumption.")
	var ability_ids: Dictionary = {}
	for offer in first.pending_hero_ability_reward.offers:
		ability_ids[offer.ability_id] = true
		var hero := _hero(first, offer.hero_unique_id)
		var ability := registry.get_definition(offer.ability_id) as AbilityDefinition
		_check(hero != null and ability.is_allowed_for_hero(hero.definition_id), "Every reward card is assigned to a compatible non-executed Hero.")
	_check(ability_ids.size() == 3, "Reward generation prefers three different abilities while the pool permits it.")


func _test_new_ability_and_upgrade() -> void:
	var run := DemoRunFactory.create_starting_run(8102)
	_set_offer(run, run.heroes[0], &"ability.fire_bolt")
	var claimed := HeroAbilityRewardService.choose(run, "test-offer", registry)
	_check(claimed.ok, "A new Hero ability reward can be claimed.")
	if not claimed.ok:
		return
	run = claimed.run_state
	var hero := run.heroes[0]
	_check(hero.owned_ability_ids.has(&"ability.fire_bolt") and hero.ability_ids.has(&"ability.fire_bolt") and hero.ability_level(&"ability.fire_bolt") == 1, "A new ability is owned, immediately equipped, and starts at Level 1.")
	_check(run.pending_hero_ability_reward.is_empty(), "Claiming one card consumes the complete reward choice.")
	for expected_level in [2, 3, 4]:
		_set_offer(run, hero, &"ability.fire_bolt")
		claimed = HeroAbilityRewardService.choose(run, "test-offer", registry)
		_check(claimed.ok, "A known ability advances to Level %d." % expected_level)
		if not claimed.ok:
			return
		run = claimed.run_state
		hero = run.heroes[0]
		_check(hero.ability_level(&"ability.fire_bolt") == expected_level and hero.ability_ids.count(&"ability.fire_bolt") == 1, "Upgrade changes only the level and never duplicates the slot.")
	_set_offer(run, hero, &"ability.fire_bolt")
	var before := run.to_dictionary()
	var blocked := HeroAbilityRewardService.choose(run, "test-offer", registry)
	_check(not blocked.ok and run.to_dictionary() == before, "A Level 4 ability cannot be upgraded and a rejected claim is atomic.")
	var snapshot := CombatSnapshotBuilder.build_hero(hero, run.inventory, registry)
	var runtime_ability: AbilityDefinition
	for ability in snapshot.abilities:
		if ability.id == &"ability.fire_bolt":
			runtime_ability = ability
			break
	var authored := registry.get_definition(&"ability.fire_bolt") as AbilityDefinition
	_check(runtime_ability != null and runtime_ability.cooldown_seconds == authored.hero_levels[3].cooldown_seconds, "Combat snapshot uses the selected ability level parameters.")
	_check(runtime_ability.effects[0] is DamageEffect and runtime_ability.effects[0].amount == authored.hero_levels[3].effects[0].amount, "Combat snapshot uses the authored Level 4 effects.")


func _test_full_slots_and_duplicate_fallback() -> void:
	var run := DemoRunFactory.create_starting_run(8103)
	for index in [1, 2]:
		run.heroes[index].life_state = HeroState.EXECUTED
	var hero := run.heroes[0]
	var equipped: Array[StringName] = [&"ability.fire_bolt", &"ability.stunning_blow", &"ability.whirlwind", &"ability.battle_fury"]
	for ability_id in equipped:
		hero.unlock_ability(ability_id)
		hero.equip_ability(ability_id)
		hero.ability_levels[String(ability_id)] = 4
	hero.ability_levels["ability.fire_bolt"] = 3
	var result := HeroAbilityRewardService.prepare_reward(run, registry)
	_check(result.ok and run.pending_hero_ability_reward.offers.size() == 3, "A small eligible pool still produces three cards by allowing fallback duplicates.")
	for offer in run.pending_hero_ability_reward.offers:
		_check(offer.ability_id == &"ability.fire_bolt", "Full slots exclude new abilities while a known non-max ability remains eligible.")
	hero.ability_levels["ability.fire_bolt"] = 4
	run.pending_hero_ability_reward.clear()
	result = HeroAbilityRewardService.prepare_reward(run, registry)
	_check(result.ok and run.pending_hero_ability_reward.is_empty(), "No reward is generated when every eligible slotted ability is Level 4.")


func _test_pending_save_load() -> void:
	var run := DemoRunFactory.create_starting_run(8104)
	HeroAbilityRewardService.prepare_reward(run, registry)
	var directory := "user://tests/hero-ability-reward-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(directory)
	manager.delete_save()
	var saved := manager.save_run(run, registry)
	var loaded := manager.load_run(registry)
	_check(saved.ok and loaded.ok, "A pending Hero ability reward saves and loads.")
	if loaded.ok:
		_check(loaded.run_state.pending_hero_ability_reward.to_dictionary() == run.pending_hero_ability_reward.to_dictionary(), "Save/load preserves all assigned Hero ability cards.")
		_check(loaded.run_state.hero_ability_reward_rng.to_dictionary() == run.hero_ability_reward_rng.to_dictionary(), "Save/load preserves the dedicated reward RNG stream.")
	var malformed := DemoRunFactory.create_starting_run(8199)
	var malformed_hero := malformed.heroes[0]
	for ability_id in [&"ability.fire_bolt", &"ability.stunning_blow", &"ability.whirlwind", &"ability.battle_fury", &"ability.hero_summon"]:
		malformed_hero.owned_ability_ids.append(ability_id)
		malformed_hero.ability_ids.append(ability_id)
		malformed_hero.ability_priority.append(ability_id)
		malformed_hero.ability_levels[String(ability_id)] = 1
	_check(not manager._validate_run(RunState.from_dictionary(malformed.to_dictionary()), registry).is_empty(), "Save validation rejects an overfull Hero ability build instead of silently truncating it.")
	manager.delete_save()


func _test_popup() -> void:
	var run := DemoRunFactory.create_starting_run(8105)
	HeroAbilityRewardService.prepare_reward(run, registry)
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	await process_frame
	var popup = screen.get_node("%HeroAbilityRewardPopup")
	_check(popup.visible and popup.get_node("%Offers").get_child_count() == 3, "Management displays the persisted three-card Hero ability reward modal.")
	_check(not screen.get_node("%RunEventPopup").visible, "Hero ability reward has priority over a simultaneous Run Event popup.")
	screen.free()


func _test_main_flow() -> void:
	var directory := "user://tests/hero-ability-main-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(directory)
	manager.delete_save()
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	main.active_run = DemoRunFactory.create_starting_run(8106)
	main.active_run.run_phase = &"combat"
	main._return_from_combat()
	await process_frame
	_check(main.current_screen.name == "EncounterChoice", "Returning from combat shows Encounter choice before the Hero ability reward.")
	main._on_encounter_selected(main.active_run.available_encounter_ids[0])
	await process_frame
	_check(main.current_screen.name == "Management" and main.current_screen.get_node("%HeroAbilityRewardPopup").visible, "Choosing the next Encounter opens its Management screen with the pending Hero ability reward.")
	var offer: HeroAbilityRewardOffer = main.active_run.pending_hero_ability_reward.offers[0]
	main._on_hero_ability_reward_requested(offer.offer_id)
	await process_frame
	_check(main.current_screen.name == "Management" and main.active_run.pending_hero_ability_reward.is_empty(), "A saved reward claim returns to preparation for the selected Encounter.")
	var loaded := manager.load_run(registry)
	_check(loaded.ok and loaded.run_state.pending_hero_ability_reward.is_empty(), "The transactional reward claim is committed to disk before navigation.")
	main.free()
	manager.delete_save()


func _set_offer(run: RunState, hero: HeroState, ability_id: StringName) -> void:
	run.pending_hero_ability_reward.clear()
	var offer := HeroAbilityRewardOffer.new()
	offer.offer_id = "test-offer"
	offer.hero_unique_id = hero.unique_id
	offer.ability_id = ability_id
	run.pending_hero_ability_reward.offers.append(offer)


func _hero(run: RunState, unique_id: String) -> HeroState:
	for hero in run.heroes:
		if hero.unique_id == unique_id:
			return hero
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
