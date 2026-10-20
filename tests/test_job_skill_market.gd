extends SceneTree


const MANAGEMENT := preload("res://ui/management/management.tscn")
const JOBS: Array[StringName] = [&"job.archer", &"job.warrior", &"job.shieldbearer", &"job.priest", &"job.summoner"]
var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	for job_id in JOBS:
		_test_purchase_chain(job_id)
	_test_full_passive_upgrade_and_drag()
	await _test_management()
	if failures == 0:
		print("Job skill Market tests passed: sequential purchases, shared upgrades, previews, icons, drag-and-drop and saves.")
		quit()
	else:
		quit(1)


func _test_purchase_chain(job_id: StringName) -> void:
	var job := registry.get_definition(job_id) as JobDefinition
	var first := registry.get_definition(job.available_ability_ids[0]) as AbilityDefinition
	var second := registry.get_definition(job.available_ability_ids[1]) as AbilityDefinition
	_check(first.presentation_icon != null and second.presentation_icon != null, "%s has artwork for both Market skill levels." % job_id)
	_check(first.job_skill_level(registry) == 1 and second.job_skill_level(registry) == 2 and second.upgrades_ability_id == first.id, "%s defines a sequential two-level skill." % job_id)
	for count in [1, 3, 6]:
		var unpaid := _run_with_job(job_id, count)
		for unit in CombatSnapshotBuilder.build_player_army(unpaid, registry):
			_check(not unit.abilities.has(first) and not unit.abilities.has(second), "Assignment count %d never unlocks %s." % [count, job_id])
	var run := _run_with_job(job_id, 3)
	var bot := SimBot.new({"style": "army"}, registry, 73051)
	_check(bot._offer_score(run, _offer(first, job_id, "bot-skill")) > 0.0, "Army simulation strategies can buy Job skills even at full capacity.")
	var pool := _pool(run, job_id)
	_check(pool == [first.id], "%s initially offers only Level I." % job_id)
	var forged := _offer(second, job_id, "early-upgrade")
	run.market.offers.append(forged)
	var before := run.to_dictionary()
	_check(not MarketService.buy_offer(run, forged.offer_id, registry).ok and run.to_dictionary() == before, "%s rejects an upgrade before its prerequisite without mutation." % job_id)
	run.market.offers.erase(forged)
	var first_offer := _offer(first, job_id, "first")
	var duplicate := _offer(first, job_id, "duplicate")
	duplicate.is_pinned = true
	run.market.offers.assign([first_offer, duplicate])
	var gold_before := run.gold
	_check(MarketService.buy_offer(run, first_offer.offer_id, registry).ok, "%s Level I can be bought." % job_id)
	var build := _build(run, job_id)
	_check(run.gold == gold_before - first.price and not run.market.offers.has(duplicate), "Purchase charges once and removes stale duplicate skill offers.")
	_check(_equipped(build).has(first.id) and _pool(run, job_id) == [second.id], "Purchase equips the shared skill and exposes only its next upgrade.")
	var captured := CombatSnapshotBuilder.build_player_army(run, registry)
	var upgrade := _offer(second, job_id, "upgrade")
	run.market.offers.append(upgrade)
	_check(MarketService.buy_offer(run, upgrade.offer_id, registry).ok, "%s Level II can be bought after Level I." % job_id)
	_check(_equipped(build).has(second.id) and not _equipped(build).has(first.id) and build.owned_ability_ids.has(first.id), "Upgrade replaces the equipped level while retaining prerequisite purchase history.")
	_check(_pool(run, job_id).is_empty(), "Maxed skills are not sold again.")
	for unit in CombatSnapshotBuilder.build_player_army(run, registry):
		if unit.job_id == job_id:
			_check(unit.abilities.has(second) and not unit.abilities.has(first), "Every Soldier receives exactly the purchased higher level.")
	for unit in captured:
		if unit.job_id == job_id:
			_check(unit.abilities.has(first) and not unit.abilities.has(second), "Existing combat snapshots are not mutated by later upgrades.")
	run.soldiers[3].current_job_id = job_id
	var reinforcement := CombatSnapshotBuilder.build_soldier(run.soldiers[3], build, registry)
	_check(reinforcement.abilities.has(second), "A newly assigned Soldier inherits the shared purchased level.")
	var manager := SaveManager.new("user://job-skill-market-tests")
	manager.delete_save()
	var saved := manager.save_run(run, registry)
	_check(saved.ok, "Purchased skills save successfully: %s" % saved.message)
	if saved.ok:
		var loaded := manager.load_run(registry)
		_check(loaded.ok and _equipped(_build(loaded.run_state, job_id)).has(second.id), "Purchased level and equipped upgrade survive Save/Load.")
	manager.delete_save()
	var malformed := RunState.from_dictionary(run.to_dictionary())
	_build(malformed, job_id).owned_ability_ids.erase(first.id)
	_check(manager._validate_run(malformed, registry).contains("preceding"), "Save validation rejects a higher level without purchase history.")
	var old_level := ArmyBuildService.perform_drop(run, {"source": &"owned_ability", "ability_id": first.id, "owner_kind": &"job", "owner_id": String(job_id)}, {"target": &"ability", "owner_kind": &"job", "owner_id": String(job_id), "slot_kind": &"active" if first.kind == AbilityDefinition.AbilityKind.ACTIVE else &"passive", "slot_index": 0}, registry)
	_check(not old_level.ok, "An obsolete lower level cannot be re-equipped alongside its upgrade.")


func _test_full_passive_upgrade_and_drag() -> void:
	var job := registry.get_definition(&"job.warrior") as JobDefinition
	var first := registry.get_definition(job.available_ability_ids[0]) as AbilityDefinition
	var second := registry.get_definition(job.available_ability_ids[1]) as AbilityDefinition
	for use_drag in [false, true]:
		var run := _run_with_job(job.id, 1)
		var build := JobBuildState.new()
		build.job_id = job.id
		build.add_passive_ability(first.id)
		build.add_passive_ability(&"ability.test_spare_passive_a")
		build.add_passive_ability(&"ability.test_spare_passive_b")
		run.job_builds.append(build)
		var offer := _offer(second, job.id, "full-passive-upgrade")
		run.market.offers.append(offer)
		var result := ArmyBuildService.perform_drop(run, {"source": &"market", "offer_id": offer.offer_id}, {"target": &"ability", "owner_kind": &"job", "owner_id": String(job.id), "slot_kind": &"passive", "slot_index": 0}, registry) if use_drag else MarketService.buy_offer(run, offer.offer_id, registry)
		_check(result.ok and _build(run, job.id).passive_ability_ids == [second.id, &"ability.test_spare_passive_a", &"ability.test_spare_passive_b"], "Upgrading a full passive build replaces the same slot through purchase or drag-and-drop.")


func _test_management() -> void:
	var run := _run_with_job(&"job.archer", 6)
	var job := registry.get_definition(&"job.archer") as JobDefinition
	var first := registry.get_definition(job.available_ability_ids[0]) as AbilityDefinition
	var second := registry.get_definition(job.available_ability_ids[1]) as AbilityDefinition
	run.market.offers.assign([_offer(first, job.id, "ui-first")])
	var screen = MANAGEMENT.instantiate()
	root.add_child(screen)
	screen.setup(run)
	await process_frame
	screen._select_unit("soldier", 0)
	var previews := screen.get_node("%AbilityRows").get_children().filter(func(slot: Node) -> bool: return slot is ContentIconButton and slot.content_id in job.available_ability_ids)
	_check(previews.size() == 2 and previews.all(func(slot: ContentIconButton) -> bool: return slot.locked and slot.badge_text == "NOT BOUGHT" and slot.tooltip_override.contains("NOT PURCHASED")), "Both unpaid levels remain visible with a purchase explanation despite six assignments.")
	var market_row := screen.get_node("%MarketRows").get_child(2)
	_check((market_row.get_child(0) as TextureRect).texture == first.presentation_icon, "Market displays the actual skill icon rather than a category gem.")
	screen._select_unit("hero", 0)
	screen._buy_market_offer("ui-first")
	_check(_build(run, job.id).active_ability_id == first.id, "Buying a skill applies it to its target Job even while a Hero is selected.")
	await process_frame
	run.market.offers.assign([_offer(second, job.id, "ui-upgrade")])
	screen._refresh_market()
	market_row = screen.get_node("%MarketRows").get_child(2)
	_check((market_row.get_child(1) as Button).text.contains("UPGRADE") and (market_row.get_child(0) as TextureRect).texture == second.presentation_icon, "The Market labels Level II as an upgrade and uses its icon.")
	screen._buy_market_offer("ui-upgrade")
	await process_frame
	screen._select_unit("soldier", 0)
	previews = screen.get_node("%AbilityRows").get_children().filter(func(slot: Node) -> bool: return slot is ContentIconButton and slot.content_id == second.id)
	_check(previews.size() == 1 and not previews[0].locked and previews[0].badge_text == "LV 2", "Purchased Level II becomes an unlocked shared-build preview.")
	screen.free()


func _run_with_job(job_id: StringName, count: int) -> RunState:
	var run := DemoRunFactory.create_starting_run(73051)
	run.gold = 10000
	run.unlocked_job_ids.append(job_id)
	run.job_capacities[String(job_id)] = 9
	for index in count:
		run.soldiers[index].current_job_id = job_id
	return run


func _pool(run: RunState, job_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for candidate in MarketGenerator._collect_candidates(run, registry):
		if candidate.offer_type == &"job_ability" and candidate.target_id == String(job_id):
			ids.append(candidate.content_id)
	return ids


func _build(run: RunState, job_id: StringName) -> JobBuildState:
	for build in run.job_builds:
		if build.job_id == job_id:
			return build
	return null


func _equipped(build: JobBuildState) -> Array[StringName]:
	var result := build.passive_ability_ids.duplicate()
	if not build.active_ability_id.is_empty():
		result.append(build.active_ability_id)
	return result


func _offer(ability: AbilityDefinition, job_id: StringName, id: String) -> MarketOffer:
	var offer := MarketOffer.new()
	offer.offer_id = id
	offer.offer_type = &"job_ability"
	offer.content_id = ability.id
	offer.price = ability.price
	offer.target_type = &"job"
	offer.target_id = String(job_id)
	offer.allowed_job_ids = [job_id]
	return offer


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
