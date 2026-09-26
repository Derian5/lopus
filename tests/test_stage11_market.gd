extends SceneTree


const MAIN_SCENE := preload("res://main.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_generation_and_bias()
	_test_buy_transactions()
	_test_reroll_transactions()
	_test_sell_transactions()
	await _test_post_combat_visit()
	if failures == 0:
		print("Stage 11 economy and Market tests passed.")
		quit()
	else:
		push_error("Stage 11 Market tests failed: %d" % failures)
		quit(1)


func _test_generation_and_bias() -> void:
	var first := DemoRunFactory.create_starting_run(1111)
	var second := DemoRunFactory.create_starting_run(1111)
	_check(first.market.offers.size() >= 5 and first.market.offers.size() <= 7, "Market generates five to seven offers.")
	_check(first.market.to_dictionary() == second.market.to_dictionary(), "Equal seeds generate identical persisted offers.")
	_check(first.market_rng.to_dictionary() == second.market_rng.to_dictionary(), "Equal generation consumes identical Market RNG draws.")
	var offer_ids: Dictionary = {}
	var has_hero_offer := false
	var has_army_offer := false
	for offer in first.market.offers:
		_check(offer.is_valid(), "Every generated offer has a complete schema.")
		_check(not offer_ids.has(offer.offer_id), "Generated offer IDs are unique.")
		offer_ids[offer.offer_id] = true
		has_hero_offer = has_hero_offer or offer.target_type == &"hero"
		has_army_offer = has_army_offer or offer.target_type != &"hero"
		_check(offer.offer_type != &"hero_ability", "Hero abilities never appear in generated Market offers.")
	_check(has_hero_offer and has_army_offer, "Every assortment creates a Hero versus army decision.")

	var eligible_types: Dictionary = {}
	var has_innate_summon_offer := false
	for candidate in MarketGenerator._collect_candidates(first, registry):
		eligible_types[candidate.offer_type] = true
		_check(candidate.offer_type != &"hero_ability", "Hero abilities are absent from the complete Market candidate pool.")
		has_innate_summon_offer = has_innate_summon_offer or candidate.content_id in [&"ability.summoner_job_summon", &"ability.enemy_summon"]
	for offer_type in [&"hero_item", &"job_unlock", &"job_capacity", &"job_ability"]:
		_check(eligible_types.has(offer_type), "Offer type %s has eligible data-driven content." % offer_type)
	_check(not eligible_types.has(&"soldier_item"), "The current prototype has no Soldier item offers.")
	_check(not has_innate_summon_offer, "Innate Job and enemy summon abilities stay hidden from the Market.")
	var malformed := _offer("malformed", &"soldier_item", &"item.hero.vanguard_blade", 1, &"soldier", "")
	_check(not MarketService.validate_offer_schema(first, malformed, registry).ok, "Offer restrictions must match their referenced content.")
	malformed.target_type = &"hero"
	_check(not malformed.is_valid(), "Offer types reject contradictory target types.")

	var executed_id := first.heroes[1].unique_id
	first.heroes[1].life_state = HeroState.EXECUTED
	var staged := RngStreamState.from_dictionary(first.market_rng.to_dictionary())
	var generated := MarketGenerator.generate_offers(first, registry, staged, first.market.next_offer_serial)
	_check(generated.ok, "Market remains generatable after a Hero is executed.")
	if generated.ok:
		for offer in generated.offers:
			_check(offer.target_id != executed_id, "Executed Heroes never receive offers.")

	first.job_capacities["job.warrior"] = first.soldiers.size()
	for candidate in MarketGenerator._collect_candidates(first, registry):
		_check(
			candidate.offer_type != &"job_capacity" or candidate.content_id != &"job.warrior",
			"Capacity offers are omitted when no soldier can use the upgrade."
		)

	var main := first.heroes[0]
	var neglected := first.heroes[2]
	main.level = 5
	var expensive_item := first.inventory.create_item(&"item.hero.titan_seal")
	main.item_ids.append(expensive_item)
	var main_score := MarketGenerator.hero_main_score(first, main, registry)
	var neglected_score := MarketGenerator.hero_main_score(first, neglected, registry)
	var main_bias := MarketGenerator.hero_bias_multiplier(first, main, "rare", registry)
	var neglected_bias := MarketGenerator.hero_bias_multiplier(first, neglected, "rare", registry)
	_check(main_score > neglected_score, "Main Score includes level, owned abilities, and equipped item value.")
	_check(neglected_bias > main_bias and neglected_bias < 3.0, "Neglected Heroes receive a soft, non-guaranteed quality weight increase.")


func _test_buy_transactions() -> void:
	var run := DemoRunFactory.create_starting_run(2222)
	run.gold = 1000
	var purchase_cases: Array[Dictionary] = [
		{"offer": _offer("buy-hi", &"hero_item", &"item.hero.vanguard_blade", 45, &"hero", run.heroes[0].unique_id), "kind": "hero_item"},
		{"offer": _offer("buy-ju", &"job_unlock", &"job.archer", 50, &"job", "job.archer"), "kind": "job_unlock"},
		{"offer": _offer("buy-jc", &"job_capacity", &"job.warrior", 55, &"job", "job.warrior"), "kind": "job_capacity"},
		{"offer": _offer("buy-ja", &"job_ability", &"ability.whirlwind", 60, &"job", "job.warrior"), "kind": "job_ability"},
	]
	for test_case in purchase_cases:
		var offer: MarketOffer = test_case.offer
		run.market.offers.append(offer)
		var gold_before := run.gold
		var items_before := run.inventory.items.size()
		var capacity_before := int(run.job_capacities.get("job.warrior", 0))
		var result := MarketService.buy_offer(run, offer.offer_id, registry)
		_check(result.ok, "%s purchase succeeds." % test_case.kind)
		_check(run.gold == gold_before - offer.price and not run.market.offers.has(offer), "%s atomically spends Gold and removes its offer." % test_case.kind)
		match test_case.kind:
			"hero_item":
				_check(run.inventory.items.size() == items_before + 1, "Hero item purchase creates exactly one stable inventory instance.")
				var purchased := run.inventory.items[-1]
				_check(purchased.bound_target_id == run.heroes[0].unique_id, "Hero item purchase persists its advertised Hero restriction.")
				var wrong_hero := EquipmentService.equip_or_swap(run, &"hero", 1, 0, StringName(purchased.instance_id), registry)
				_check(not wrong_hero.ok, "A Hero-bound item cannot be equipped by another Hero.")
			"job_unlock": _check(run.unlocked_job_ids.has(&"job.archer") and int(run.job_capacities["job.archer"]) == 1, "Job purchase unlocks the Job with usable capacity.")
			"job_capacity": _check(int(run.job_capacities["job.warrior"]) == capacity_before + 1, "Capacity purchase applies exactly one upgrade.")
			"job_ability": _check(_job_build(run, &"job.warrior").owned_ability_ids.has(offer.content_id), "Job Ability purchase grants shared ownership.")

	var blocked := _offer("blocked", &"hero_ability", &"ability.fire_bolt", 999, &"hero", run.heroes[0].unique_id)
	run.market.offers.append(blocked)
	_check(not blocked.is_valid() and not MarketService.validate_offer_schema(run, blocked, registry).ok, "A forged Hero Ability Market offer is rejected by the schema.")
	run.gold = 0
	var before := run.to_dictionary()
	var failed := MarketService.buy_offer(run, blocked.offer_id, registry)
	_check(not failed.ok and run.to_dictionary() == before, "A rejected purchase changes neither Gold, ownership, nor offer state.")


func _test_reroll_transactions() -> void:
	var run := DemoRunFactory.create_starting_run(3333)
	var restored := RunState.from_dictionary(run.to_dictionary())
	run.gold = 1000
	restored.gold = 1000
	var first := MarketService.reroll(run, registry)
	var restored_first := MarketService.reroll(restored, registry)
	_check(first.ok and restored_first.ok and first.price == 50, "The first reroll costs 50 Gold.")
	_check(run.market.to_dictionary() == restored.market.to_dictionary(), "The next reroll after Load produces the same assortment.")
	_check(run.market_rng.to_dictionary() == restored.market_rng.to_dictionary(), "Reroll commits the same persisted RNG state after Load.")
	var second := MarketService.reroll(run, registry)
	_check(second.ok and second.price == 75 and run.market.reroll_count == 2, "Sequential rerolls increase in price within one visit.")
	var visit := MarketService.begin_visit(run, registry)
	_check(visit.ok and run.market.reroll_count == 0 and MarketService.reroll_price(run.market) == 50, "A new Market visit resets reroll escalation.")

	run.gold = 0
	var before := run.to_dictionary()
	var failed := MarketService.reroll(run, registry)
	_check(not failed.ok and run.to_dictionary() == before, "A rejected reroll consumes neither Gold nor RNG state.")


func _test_sell_transactions() -> void:
	var run := DemoRunFactory.create_starting_run(4444)
	var equipped_id := StringName(run.inventory.items[0].instance_id)
	EquipmentService.equip_or_swap(run, &"hero", 0, 0, equipped_id, registry)
	var equipped_before := run.to_dictionary()
	var blocked := MarketService.sell_item(run, equipped_id, registry)
	_check(not blocked.ok and run.to_dictionary() == equipped_before, "Equipped items cannot be sold and remain unchanged.")

	var sold_id := StringName(run.inventory.items[1].instance_id)
	var sold_definition := registry.get_definition(run.inventory.get_definition_id(sold_id)) as ItemDefinition
	var gold_before := run.gold
	var sold := MarketService.sell_item(run, sold_id, registry)
	_check(sold.ok and not run.inventory.has_instance(sold_id), "Selling removes exactly the selected unequipped instance.")
	_check(run.gold == gold_before + sold_definition.sell_price, "Selling grants the data-driven sell price.")


func _test_post_combat_visit() -> void:
	var save_directory := "user://tests/stage11-%d" % Time.get_ticks_usec()
	var manager := SaveManager.new(save_directory)
	manager.delete_save()
	var main = MAIN_SCENE.instantiate()
	main.save_manager = manager
	root.add_child(main)
	await process_frame
	main.active_run = DemoRunFactory.create_starting_run(5555)
	main.active_run.market.reroll_count = 3
	main.active_run.run_phase = &"combat"
	var old_offer_ids := PackedStringArray()
	for offer in main.active_run.market.offers:
		old_offer_ids.append(offer.offer_id)
	main._return_from_combat()
	await process_frame
	var new_offer_ids := PackedStringArray()
	for offer in main.active_run.market.offers:
		new_offer_ids.append(offer.offer_id)
	_check(main.active_run.market.reroll_count == 0 and old_offer_ids != new_offer_ids, "Returning from combat starts exactly one fresh Market visit.")
	var loaded := manager.load_run(registry)
	_check(loaded.ok and loaded.run_state.market.to_dictionary() == main.active_run.market.to_dictionary(), "The post-combat Market visit is autosaved without regeneration on Load.")
	main.free()
	manager.delete_save()


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


func _job_build(run: RunState, job_id: StringName) -> JobBuildState:
	for build in run.job_builds:
		if build.job_id == job_id:
			return build
	return null


func _find_hero(run: RunState, unique_id: String) -> HeroState:
	for hero in run.heroes:
		if hero.unique_id == unique_id:
			return hero
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
