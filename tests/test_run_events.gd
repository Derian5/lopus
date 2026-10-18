extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_definition_and_selection()
	_test_scripted_route_events()
	_test_branching_effects_and_persistence()
	_test_strategy_disagreement_event()
	_test_blocked_ability_choice()
	_test_effect_catalog()
	await _test_management_popup()
	if failures == 0:
		print("Run Event tests passed.")
		quit()
	else:
		push_error("Run Event tests failed: %d" % failures)
		quit(1)


func _test_definition_and_selection() -> void:
	var event := registry.get_definition(&"event.old_shrine", false) as RunEventDefinition
	_check(event != null and event.nodes.size() == 2 and event.soldier_target_count == 2, "Branching Run Event content loads from Resources.")
	_check(event.theme_hero_id == &"hero.ashen_duelist", "Every Run Event authors a Hero whose identity color themes its popup.")
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var old_absence := route.event_absence_percent
	route.event_absence_percent = 100.0
	var absent := DemoRunFactory.create_starting_run(7000)
	var draws_before := absent.event_rng.draw_count
	RunEventService.prepare_event(absent, registry)
	_check(absent.pending_event.is_empty() and absent.event_rng.draw_count == draws_before + 1, "Designer-configured 100% absence prevents an event and persists the roll.")
	route.event_absence_percent = 0.0
	var first := DemoRunFactory.create_starting_run(7001)
	var second := DemoRunFactory.create_starting_run(7001)
	var first_result := RunEventService.prepare_event(first, registry)
	var second_result := RunEventService.prepare_event(second, registry)
	_check(first_result.ok and second_result.ok and not first.pending_event.is_empty(), "An eligible weighted event can be selected after combat.")
	_check(first.pending_event.to_dictionary() == second.pending_event.to_dictionary() and first.event_rng.to_dictionary() == second.event_rng.to_dictionary(), "Event and random Soldier targets are deterministic for equal persisted RNG state.")
	var selected_event := registry.get_definition(first.pending_event.event_id, false) as RunEventDefinition
	_check(selected_event != null and first.pending_event.target_ids.size() == selected_event.soldier_target_count, "Event selection persists the authored number of Soldier targets.")
	if first.pending_event.target_ids.size() == 2:
		_check(first.pending_event.target_ids[0] != first.pending_event.target_ids[1], "Event target selection chooses distinct random Soldiers.")
	var selected_event_id := first.pending_event.event_id
	_check(first.triggered_event_ids.has(selected_event_id), "A one-time event is marked triggered when selected.")
	first.pending_event.clear()
	RunEventService.prepare_event(first, registry)
	_check(first.pending_event.is_empty() or first.pending_event.event_id != selected_event_id, "A completed one-time event cannot be selected again.")
	route.event_absence_percent = old_absence


func _test_scripted_route_events() -> void:
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var opening := DemoRunFactory.create_starting_run(7010)
	var opening_result := RunEventService.prepare_specific_event(opening, route.opening_event_id, registry)
	_check(opening_result.ok and opening.pending_event.event_id == &"event.opening_march" and opening.pending_event.node_id == &"world", "The route's opening story event can be prepared before the first battle.")
	var after_first_battle := DemoRunFactory.create_starting_run(7011)
	after_first_battle.encounter_index = 1
	var old_absence := route.event_absence_percent
	route.event_absence_percent = 100.0
	var strategy_result := RunEventService.prepare_event(after_first_battle, registry)
	_check(strategy_result.ok and after_first_battle.pending_event.event_id == &"event.strategy_disagreement", "Strategy Disagreement is mandatory after the first battle and ignores random event absence.")
	route.event_absence_percent = old_absence


func _test_branching_effects_and_persistence() -> void:
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var old_absence := route.event_absence_percent
	route.event_absence_percent = 0.0
	var run := DemoRunFactory.create_starting_run(7002)
	run.pending_event.event_id = &"event.old_shrine"
	run.pending_event.node_id = &"entry"
	run.pending_event.target_ids = [run.soldiers[0].unique_id, run.soldiers[1].unique_id]
	run.triggered_event_ids.append(run.pending_event.event_id)
	var target_ids := run.pending_event.target_ids.duplicate()
	var selected := RunEventService.choose(run, &"train", registry)
	_check(selected.ok, "A valid event choice applies transactionally.")
	if not selected.ok:
		route.event_absence_percent = old_absence
		return
	run = selected.run_state
	_check(run.pending_event.node_id == &"after_training", "A choice advances to its authored next node.")
	for target_id in target_ids:
		_check(_soldier(run, target_id).veterancy_level == 1, "Choice effects update each preselected Soldier target.")
	var restored := RunState.from_dictionary(run.to_dictionary())
	_check(restored.pending_event.to_dictionary() == run.pending_event.to_dictionary(), "Pending event node and targets survive save serialization.")
	var save_directory := "user://tests/run-events-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(save_directory)
	manager.delete_save()
	var save_result := manager.save_run(restored, registry)
	var load_result := manager.load_run(registry)
	_check(save_result.ok and load_result.ok and load_result.run_state.pending_event.to_dictionary() == restored.pending_event.to_dictionary(), "An in-progress branch and fixed targets survive disk save/load.")
	manager.delete_save()
	var finish := RunEventService.choose(restored, &"fervor", registry)
	_check(finish.ok and finish.run_state.pending_event.is_empty(), "A terminal event choice clears persisted event progress.")
	if finish.ok:
		run = finish.run_state
		for target_id in target_ids:
			var soldier := _soldier(run, target_id)
			_check(soldier.stat_modifiers.size() == 1 and soldier.stat_modifiers[0].battles_remaining == 2, "A temporary event stat modifier stores its battle duration.")
			var base_snapshot := CombatSnapshotBuilder.build_soldier(soldier, null, registry)
			_check(base_snapshot.stats.damage > CombatSnapshotBuilder.MILITIA_BASE_DAMAGE, "Event stat modifier changes the combat snapshot.")
		CombatResultApplicator._consume_runtime_modifiers(run)
		_check(_soldier(run, target_ids[0]).stat_modifiers[0].battles_remaining == 1, "A completed battle consumes one temporary-modifier charge.")
		CombatResultApplicator._consume_runtime_modifiers(run)
		_check(_soldier(run, target_ids[0]).stat_modifiers.is_empty(), "Temporary modifier expires after its configured number of battles.")
	route.event_absence_percent = old_absence


func _test_strategy_disagreement_event() -> void:
	var event := registry.get_definition(&"event.strategy_disagreement", false) as RunEventDefinition
	_check(event != null and event.nodes.size() == 7 and event.soldier_target_count == 0, "The strategy disagreement event loads its complete branching graph.")

	var warrior_run := _strategy_run(7101)
	var stale_warrior_offer := MarketOffer.new()
	stale_warrior_offer.offer_id = "event-warrior-unlock"
	stale_warrior_offer.offer_type = &"job_unlock"
	stale_warrior_offer.content_id = &"job.warrior"
	stale_warrior_offer.price = 999
	stale_warrior_offer.target_type = &"job"
	stale_warrior_offer.target_id = "job.warrior"
	stale_warrior_offer.allowed_job_ids.append(&"job.warrior")
	warrior_run.market.offers.append(stale_warrior_offer)
	warrior_run = _choose_event(warrior_run, &"focus_units")
	warrior_run = _choose_event(warrior_run, &"choose_melee")
	warrior_run = _choose_event(warrior_run, &"accept_warriors")
	_check(warrior_run.unlocked_job_ids.has(&"job.warrior") and int(warrior_run.job_capacities.get("job.warrior", 0)) == 2, "The melee branch unlocks Warrior and grants two positions.")
	var converted_offer: MarketOffer
	for offer in warrior_run.market.offers:
		if offer.offer_id == stale_warrior_offer.offer_id:
			converted_offer = offer
			break
	var warrior := registry.get_definition(&"job.warrior") as JobDefinition
	_check(converted_offer != null and converted_offer.offer_type == &"job_capacity" and converted_offer.price == warrior.capacity_price, "An event unlock converts the existing Market Job offer into a capacity purchase.")
	var capacity_purchase := MarketService.buy_offer(warrior_run, converted_offer.offer_id, registry) if converted_offer != null else {"ok": false}
	_check(capacity_purchase.ok and int(warrior_run.job_capacities["job.warrior"]) == 3, "The Job remains purchasable in Market after the event unlocks it.")

	var archer_run := _strategy_run(7102)
	archer_run = _choose_event(archer_run, &"focus_units")
	archer_run = _choose_event(archer_run, &"choose_ranged")
	archer_run = _choose_event(archer_run, &"accept_archers")
	_check(archer_run.unlocked_job_ids.has(&"job.archer") and int(archer_run.job_capacities.get("job.archer", 0)) == 2, "The ranged branch unlocks Archer and grants two positions.")

	var summoner_run := _strategy_run(7103)
	summoner_run = _choose_event(summoner_run, &"focus_units")
	summoner_run = _choose_event(summoner_run, &"choose_summoners")
	summoner_run = _choose_event(summoner_run, &"accept_summoner")
	_check(summoner_run.unlocked_job_ids.has(&"job.summoner") and int(summoner_run.job_capacities.get("job.summoner", 0)) == 1, "The summoner branch unlocks Summoner and grants one position.")

	var wealth_run := _strategy_run(7104)
	var gold_before := wealth_run.gold
	wealth_run = _choose_event(wealth_run, &"focus_wealth")
	wealth_run = _choose_event(wealth_run, &"accept_wealth")
	_check(wealth_run.gold == gold_before + 250, "The wealth branch grants 250 Gold.")

	var hero_run := _strategy_run(7105)
	var item_count := hero_run.inventory.items.size()
	hero_run = _choose_event(hero_run, &"focus_heroes")
	hero_run = _choose_event(hero_run, &"accept_hero_focus")
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	var all_heroes_gained_xp := true
	for hero in hero_run.heroes:
		all_heroes_gained_xp = all_heroes_gained_xp and hero.xp == 100 and hero.level == progression.hero_level_for_xp(100)
	var reward_item: Dictionary = hero_run.inventory.items.back()
	var reward_definition := registry.get_definition(StringName(reward_item.get("definition_id", "")), false) as ItemDefinition
	_check(all_heroes_gained_xp, "The Hero branch grants 100 XP to every Hero and updates their levels.")
	_check(
		hero_run.inventory.items.size() == item_count + 1
		and not reward_item.has("bound_target_id")
		and reward_definition != null,
		"The Hero branch grants a random item without binding it to one Hero."
	)
	_check(warrior_run.pending_event.is_empty() and archer_run.pending_event.is_empty() and summoner_run.pending_event.is_empty() and wealth_run.pending_event.is_empty() and hero_run.pending_event.is_empty(), "Every strategy branch closes after its result is accepted.")


func _test_blocked_ability_choice() -> void:
	_ensure_test_job_ability()
	var run := DemoRunFactory.create_starting_run(7003)
	run.pending_event.event_id = &"event.old_shrine"
	run.pending_event.node_id = &"entry"
	run.pending_event.target_ids = [run.soldiers[0].unique_id, run.soldiers[1].unique_id]
	var effect := RunEventEffect.new()
	effect.effect_id = &"event_effect.test_full_job_slot"
	effect.effect_type = RunEventEffect.EffectType.GRANT_JOB_ABILITY
	run.unlocked_job_ids.append(&"job.archer")
	var archer_build := JobBuildState.new()
	archer_build.job_id = &"job.archer"
	archer_build.set_active_ability(&"ability.test_job_active")
	run.job_builds.append(archer_build)
	effect.job_id = &"job.archer"
	effect.content_id = &"ability.test_job_active"
	var choice := RunEventChoice.new()
	choice.choice_id = &"blocked"
	choice.text = "Blocked"
	choice.effects = [effect]
	var before := run.to_dictionary()
	var status := RunEventService.choice_status(run, choice, registry)
	_check(not status.ok and run.to_dictionary() == before, "A Job ability choice is blocked when its matching slot is occupied and leaves state unchanged.")


func _test_effect_catalog() -> void:
	_ensure_test_job_ability()
	var run := DemoRunFactory.create_starting_run(7005)
	run.pending_event.event_id = &"event.old_shrine"
	run.pending_event.node_id = &"entry"
	run.pending_event.target_ids = [run.soldiers[0].unique_id, run.soldiers[1].unique_id]
	run.unlocked_job_ids.append(&"job.archer")
	run.job_capacities["job.archer"] = 1
	var archer_build := JobBuildState.new()
	archer_build.job_id = &"job.archer"
	run.job_builds.append(archer_build)
	var effects: Array[RunEventEffect] = []
	effects.append(_effect(RunEventEffect.EffectType.GRANT_ITEM, &"item.hero.titan_seal"))
	var hero_ability := _effect(RunEventEffect.EffectType.GRANT_HERO_ABILITY, &"ability.greed_dagger_nova")
	hero_ability.hero_definition_id = &"hero.test_vanguard"
	effects.append(hero_ability)
	var job_ability := _effect(RunEventEffect.EffectType.GRANT_JOB_ABILITY, &"ability.test_job_active")
	job_ability.job_id = &"job.archer"
	effects.append(job_ability)
	var hero_level := _effect(RunEventEffect.EffectType.HERO_LEVEL_DELTA)
	hero_level.hero_definition_id = &"hero.test_vanguard"
	hero_level.amount = 1
	effects.append(hero_level)
	var veterancy := _effect(RunEventEffect.EffectType.SOLDIER_VETERANCY_DELTA)
	veterancy.amount = 1
	effects.append(veterancy)
	var capacity := _effect(RunEventEffect.EffectType.JOB_CAPACITY_DELTA)
	capacity.job_id = &"job.warrior"
	capacity.amount = 1
	effects.append(capacity)
	var hero_stat := _effect(RunEventEffect.EffectType.STAT_MODIFIER)
	hero_stat.target_scope = RunEventEffect.TargetScope.HERO
	hero_stat.hero_definition_id = &"hero.test_vanguard"
	hero_stat.stat = "max_hp"
	hero_stat.modifier_value = 12.0
	hero_stat.battles_remaining = -1
	effects.append(hero_stat)
	var job_stat := _effect(RunEventEffect.EffectType.STAT_MODIFIER)
	job_stat.target_scope = RunEventEffect.TargetScope.JOB
	job_stat.job_id = &"job.archer"
	job_stat.stat = "damage"
	job_stat.modifier_value = -2.0
	job_stat.battles_remaining = 3
	effects.append(job_stat)
	var choice := RunEventChoice.new()
	choice.choice_id = &"catalog"
	choice.text = "Catalog"
	choice.effects = effects
	var item_count := run.inventory.items.size()
	var result := RunEventService._apply_choice(run, choice, registry)
	_check(result.ok and run.inventory.items.size() == item_count + 1, "Event effects can grant an unequipped Inventory item.")
	_check(run.heroes[0].ability_ids.has(&"ability.greed_dagger_nova") and run.heroes[0].level == 2, "Event effects equip a Hero ability and synchronize a Hero level with XP.")
	_check(archer_build.active_ability_id == &"ability.test_job_active", "Event Job ability is immediately available to the shared Job build.")
	_check(run.soldiers[0].veterancy_level == 1 and int(run.job_capacities["job.warrior"]) == 1, "Event effects change Soldier Veterancy and Job capacity.")
	_check(run.heroes[0].stat_modifiers.size() == 1 and archer_build.stat_modifiers.size() == 1, "Permanent individual and temporary Job stat modifiers are persisted.")


func _effect(effect_type: int, content_id: StringName = &"") -> RunEventEffect:
	var effect := RunEventEffect.new()
	effect.effect_id = StringName("event_effect.test_%d" % effect_type)
	effect.effect_type = effect_type
	effect.content_id = content_id
	return effect


func _ensure_test_job_ability() -> void:
	if registry.get_definition(&"ability.test_job_active", false) == null:
		var ability := AbilityDefinition.new()
		ability.id = &"ability.test_job_active"
		ability.display_name = "Test Job Active"
		ability.available_to_heroes = false
		registry.register_definition(ability, false)
	var archer := registry.get_definition(&"job.archer") as JobDefinition
	if not archer.available_ability_ids.has(&"ability.test_job_active"):
		archer.available_ability_ids.append(&"ability.test_job_active")


func _test_management_popup() -> void:
	var run := DemoRunFactory.create_starting_run(7004)
	run.pending_event.event_id = &"event.old_shrine"
	run.pending_event.node_id = &"entry"
	run.pending_event.target_ids = [run.soldiers[0].unique_id, run.soldiers[1].unique_id]
	run.triggered_event_ids.append(run.pending_event.event_id)
	var management = MANAGEMENT_SCENE.instantiate()
	root.add_child(management)
	management.setup(run)
	await process_frame
	var popup: Control = management.get_node("%RunEventPopup")
	_check(popup.visible and popup.get_node("%EventTitle").text == "The Drillmaster's Shrine", "Pending event opens as a modal over Management.")
	var event := registry.get_definition(&"event.old_shrine") as RunEventDefinition
	var hero := registry.get_definition(event.theme_hero_id) as HeroDefinition
	var popup_style: StyleBox = popup.get_node("Center/Panel").get_theme_stylebox("panel")
	var popup_color: Color = (popup_style as StyleBoxTexture).modulate_color if popup_style is StyleBoxTexture else (popup_style as StyleBoxFlat).border_color
	_check(popup_color.is_equal_approx(hero.placeholder_color.lightened(0.22)), "The atlas event popup uses its authored Hero identity color.")
	_check(popup.get_node("%Choices").get_child_count() == 3 and popup.get_node("%EventBody").text.contains(run.soldiers[0].generated_name), "Event popup renders authored choices and persisted Soldier names.")
	_check(root.gui_get_focus_owner() == null, "Opening an event does not preselect its first choice.")
	management.run_event_choice_requested.connect(func(choice_id: StringName) -> void:
		var result := RunEventService.choose(run, choice_id, registry)
		if result.ok:
			management.setup(result.run_state)
	)
	var train_button := popup.get_node("%Choices").get_child(0) as Button
	train_button.pressed.emit()
	await process_frame
	_check(popup.visible and popup.get_node("%EventTitle").text == "The Final Inscription" and popup.get_node("%Choices").get_child_count() == 2, "A choice can synchronously rebuild the popup without freeing its locked pressed button.")
	management.free()


func _strategy_run(seed: int) -> RunState:
	var run := DemoRunFactory.create_starting_run(seed)
	run.pending_event.event_id = &"event.strategy_disagreement"
	run.pending_event.node_id = &"entry"
	run.triggered_event_ids.append(run.pending_event.event_id)
	return run


func _choose_event(run: RunState, choice_id: StringName) -> RunState:
	var result := RunEventService.choose(run, choice_id, registry)
	_check(result.ok, "Strategy event choice applies: %s." % choice_id)
	return result.run_state if result.ok else run


func _soldier(run: RunState, runtime_id: String) -> SoldierState:
	for soldier in run.soldiers:
		if soldier.unique_id == runtime_id:
			return soldier
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
