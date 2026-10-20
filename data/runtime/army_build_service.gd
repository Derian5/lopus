class_name ArmyBuildService
extends RefCounted


static func perform_drop(run_state: RunState, source: Dictionary, target: Dictionary, registry: Node) -> Dictionary:
	if run_state == null or run_state.run_phase != &"management":
		return _failure("Army changes are only available during preparation.")
	var staged := RunState.from_dictionary(run_state.to_dictionary())
	var prepared_source := source.duplicate(true)
	if StringName(source.get("source", "")) == &"market":
		var purchase := _purchase_source(staged, source, registry)
		if not purchase.ok:
			return purchase
		prepared_source = purchase.source
	var result := _apply(staged, prepared_source, target, registry)
	if not result.ok:
		return result
	_commit_build_state(run_state, staged)
	result["purchased"] = StringName(source.get("source", "")) == &"market"
	return result


static func _purchase_source(staged: RunState, source: Dictionary, registry: Node) -> Dictionary:
	var offer_id := String(source.get("offer_id", ""))
	var offer: MarketOffer
	for candidate in staged.market.offers:
		if candidate.offer_id == offer_id:
			offer = candidate
			break
	if offer == null:
		return _failure("That Market offer is no longer available.")
	if offer.offer_type not in [&"job_ability", &"hero_item"]:
		return _failure("This offer has no build slot. Double-click it to buy.")
	var old_instances: Dictionary = {}
	for item in staged.inventory.items:
		old_instances[StringName(item.get("instance_id", ""))] = true
	var result := MarketService.buy_offer(staged, offer_id, registry, false)
	if not result.ok:
		return result
	if offer.offer_type == &"hero_item":
		for item in staged.inventory.items:
			var instance_id := StringName(item.get("instance_id", ""))
			if not old_instances.has(instance_id):
				return {"ok": true, "error": "", "source": {
					"source": &"inventory_item",
					"instance_id": instance_id,
				}}
	return {"ok": true, "error": "", "source": {
		"source": &"owned_ability",
		"ability_id": offer.content_id,
		"owner_kind": &"job",
		"owner_id": offer.target_id,
	}}


static func _apply(staged: RunState, source: Dictionary, target: Dictionary, registry: Node) -> Dictionary:
	var source_type := StringName(source.get("source", ""))
	var target_type := StringName(target.get("target", ""))
	if source_type == &"soldier" and target_type == &"job":
		return _assign_job(staged, int(source.get("soldier_index", -1)), StringName(target.get("job_id", "")), registry)
	if source_type == &"inventory_item" and target_type == &"equipment":
		var equipment_result := EquipmentService.equip_or_swap(
			staged,
			StringName(target.get("owner_kind", "")),
			int(target.get("owner_index", -1)),
			int(target.get("slot_index", -1)),
			StringName(source.get("instance_id", "")),
			registry
		)
		if equipment_result.ok:
			equipment_result["action"] = &"equipment_changed"
		return equipment_result
	if source_type == &"equipped_item" and target_type == &"inventory":
		return _return_item_to_inventory(staged, source)
	if source_type == &"owned_ability" and target_type == &"ability":
		return _equip_ability(staged, source, target, registry)
	return _failure("This source cannot be dropped into that slot.")


static func _return_item_to_inventory(staged: RunState, source: Dictionary) -> Dictionary:
	var owner_kind := StringName(source.get("owner_kind", ""))
	var owner_index := int(source.get("owner_index", -1))
	var slot_index := int(source.get("slot_index", -1))
	var item_ids: Array[StringName]
	if owner_kind == &"hero" and owner_index >= 0 and owner_index < staged.heroes.size():
		item_ids = staged.heroes[owner_index].item_ids
	else:
		return _failure("That equipment owner is no longer available.")
	if slot_index < 0 or slot_index >= item_ids.size() or item_ids[slot_index] != StringName(source.get("instance_id", "")):
		return _failure("That equipped item is no longer in this slot.")
	var result := EquipmentService.unequip(staged, owner_kind, owner_index, slot_index)
	if result.ok:
		result["action"] = &"equipment_changed"
	return result


static func _assign_job(staged: RunState, soldier_index: int, job_id: StringName, registry: Node) -> Dictionary:
	if soldier_index < 0 or soldier_index >= staged.soldiers.size():
		return _failure("That soldier is no longer available.")
	if not staged.unlocked_job_ids.has(job_id):
		return _failure("Unlock that Job in the Market first.")
	var soldier := staged.soldiers[soldier_index]
	if soldier.current_job_id == job_id:
		return _failure("This soldier already has that Job.")
	if job_id != &"job.militia" and _assigned_count(staged, job_id) >= int(staged.job_capacities.get(String(job_id), 0)):
		return _failure("Assignment blocked: %s capacity is full." % _display_name(registry, job_id))
	var old_job_name := _display_name(registry, soldier.current_job_id)
	soldier.current_job_id = job_id
	soldier.definition_id = job_id
	SoldierNameGenerator.update_job_name(soldier, old_job_name, _display_name(registry, job_id))
	soldier.veterancy_xp = 0
	soldier.veterancy_level = 0
	return {"ok": true, "error": "", "action": &"job_changed"}


static func _equip_ability(staged: RunState, source: Dictionary, target: Dictionary, registry: Node) -> Dictionary:
	var owner_kind := StringName(target.get("owner_kind", ""))
	var ability_id := StringName(source.get("ability_id", ""))
	if StringName(source.get("owner_kind", "")) != owner_kind:
		return _failure("That ability belongs to a different build type.")
	var ability := registry.get_definition(ability_id, false) as AbilityDefinition
	if ability == null:
		return _failure("That ability content is missing.")
	if owner_kind == &"hero":
		var hero_index := int(target.get("owner_index", -1))
		if hero_index < 0 or hero_index >= staged.heroes.size():
			return _failure("Select a valid Hero.")
		var hero := staged.heroes[hero_index]
		if source.get("owner_id", "") != hero.unique_id or not hero.owned_ability_ids.has(ability_id):
			return _failure("That ability is not owned by this Hero.")
		if not ability.is_allowed_for_hero(hero.definition_id):
			return _failure("That ability is not compatible with this Hero.")
		var slot_index := int(target.get("slot_index", -1))
		if slot_index < 0 or slot_index >= HeroState.MAX_ABILITY_SLOTS:
			return _failure("Select a valid Hero ability slot.")
		if hero.ability_ids.has(ability_id):
			return _failure("That ability is already equipped.")
		if slot_index >= hero.ability_ids.size():
			if not hero.equip_ability(ability_id):
				return _failure("All Hero ability slots are full.")
		else:
			hero.ability_ids[slot_index] = ability_id
		return {"ok": true, "error": "", "action": &"hero_ability_changed"}
	if owner_kind == &"job":
		var job_id := StringName(target.get("owner_id", ""))
		if StringName(source.get("owner_id", "")) != job_id:
			return _failure("That ability belongs to another Job.")
		var job := registry.get_definition(job_id, false) as JobDefinition
		var build := _job_build(staged, job_id)
		if job == null or not job.available_ability_ids.has(ability_id) or not build.owned_ability_ids.has(ability_id):
			return _failure("That ability is not owned by this Job.")
		if build.has_owned_upgrade(ability_id, registry):
			return _failure("That skill level has been replaced by its purchased upgrade.")
		var slot_kind := StringName(target.get("slot_kind", ""))
		if slot_kind == &"active":
			if ability.kind != AbilityDefinition.AbilityKind.ACTIVE:
				return _failure("Only active abilities fit this slot.")
			build.set_active_ability(ability_id)
		elif slot_kind == &"passive":
			if ability.kind != AbilityDefinition.AbilityKind.PASSIVE:
				return _failure("Only passive abilities fit this slot.")
			var slot_index := int(target.get("slot_index", -1))
			if slot_index < 0 or slot_index >= 3:
				return _failure("Select a valid Job passive slot.")
			if build.passive_ability_ids.has(ability_id):
				return _failure("That passive is already equipped.")
			if build.passive_ability_ids.has(ability.upgrades_ability_id):
				build.passive_ability_ids[build.passive_ability_ids.find(ability.upgrades_ability_id)] = ability_id
				return {"ok": true, "error": "", "action": &"job_build_changed"}
			if slot_index < build.passive_ability_ids.size():
				build.passive_ability_ids[slot_index] = ability_id
			elif not build.add_passive_ability(ability_id):
				return _failure("All Job passive slots are full.")
		else:
			return _failure("Select a valid Job ability slot.")
		return {"ok": true, "error": "", "action": &"job_build_changed"}
	return _failure("Select a Hero or Job ability slot.")


static func _commit_build_state(target: RunState, source: RunState) -> void:
	target.gold = source.gold
	target.heroes = source.heroes
	target.soldiers = source.soldiers
	target.job_builds = source.job_builds
	target.job_capacities = source.job_capacities
	target.unlocked_job_ids = source.unlocked_job_ids
	target.inventory = source.inventory
	target.market = source.market


static func _assigned_count(run_state: RunState, job_id: StringName) -> int:
	var count := 0
	for soldier in run_state.soldiers:
		if soldier.current_job_id == job_id:
			count += 1
	return count


static func _job_build(run_state: RunState, job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	var build := JobBuildState.new()
	build.job_id = job_id
	run_state.job_builds.append(build)
	return build


static func _display_name(registry: Node, content_id: StringName) -> String:
	var definition: ContentDefinition = registry.get_definition(content_id, false)
	return definition.display_name if definition != null else String(content_id)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
