class_name ExecutionService
extends RefCounted


static func execute(run_state: RunState, hero_id: String, registry: Node) -> Dictionary:
	if run_state == null or run_state.run_status != RunState.STATUS_ACTIVE or run_state.run_phase != &"execution":
		return {"ok": false, "error": "Execution is only available after defeating the Act I Boss."}
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition
	if route == null:
		return {"ok": false, "error": "Demo route definition is missing."}
	if run_state.current_act != 1 or run_state.encounter_index != route.act_one_boss_index() or not run_state.execution_snapshots.is_empty():
		return {"ok": false, "error": "This run has no unresolved Act I Execution."}
	var encounter := registry.get_definition(run_state.selected_encounter_id, false) as EncounterDefinition
	if encounter == null or not encounter.is_boss or run_state.pending_execution_contributions.is_empty():
		return {"ok": false, "error": "The defeated Boss checkpoint is incomplete."}
	var eligible_count := 0
	for candidate in run_state.heroes:
		if candidate.life_state in [HeroState.ALIVE, HeroState.DEAD]:
			eligible_count += 1
			var candidate_data: Variant = run_state.pending_execution_contributions.get(candidate.unique_id)
			if not _valid_contribution_data(candidate_data):
				return {"ok": false, "error": "Boss contribution data is incomplete for one or more Heroes."}
	if eligible_count != 3:
		return {"ok": false, "error": "Act I Execution requires exactly three eligible Heroes."}
	if run_state.soldiers.size() != 9:
		return {"ok": false, "error": "Act I Execution requires the restored nine-soldier roster."}
	var source_hero := _find_hero(run_state, hero_id)
	if source_hero == null or source_hero.life_state not in [HeroState.ALIVE, HeroState.DEAD]:
		return {"ok": false, "error": "Choose an Alive or Dead Hero who has not been executed."}
	for existing in run_state.execution_snapshots:
		if existing.hero_unique_id == hero_id:
			return {"ok": false, "error": "That Hero has already been executed."}

	var staged := RunState.from_dictionary(run_state.to_dictionary())
	var hero := _find_hero(staged, hero_id)
	var snapshot := _create_snapshot(staged, hero, registry)
	if snapshot == null:
		return {"ok": false, "error": "Hero content is missing; Execution was not applied."}
	for instance_id in hero.item_ids:
		staged.inventory.remove_item(instance_id)
	hero.item_ids.clear()
	hero.ability_ids.clear()
	hero.owned_ability_ids.clear()
	hero.ability_levels.clear()
	hero.cooldowns.clear()
	hero.statuses.clear()
	hero.stat_modifiers.clear()
	hero.current_hp = 0.0
	hero.life_state = HeroState.EXECUTED
	staged.execution_snapshots.append(snapshot)
	staged.soldiers.append(_create_militia(staged, registry))
	staged.current_act = 2
	staged.encounter_index = 0
	staged.run_phase = &"management"
	staged.pending_execution_contributions.clear()
	var cycle_result := RunCycleService.prepare_next_choice(staged, registry)
	if not cycle_result.ok:
		return {"ok": false, "error": cycle_result.error}
	return {"ok": true, "error": "", "run_state": staged, "snapshot": snapshot}


static func _create_snapshot(run_state: RunState, hero: HeroState, registry: Node) -> ExecutionSnapshot:
	if not registry.get_definition(hero.definition_id, false) is HeroDefinition:
		return null
	var snapshot := ExecutionSnapshot.new()
	snapshot.hero_definition_id = hero.definition_id
	snapshot.hero_unique_id = hero.unique_id
	snapshot.life_state_at_execution = hero.life_state
	snapshot.level = hero.level
	snapshot.xp = hero.xp
	snapshot.ability_ids = hero.ability_ids.duplicate()
	snapshot.owned_ability_ids = hero.owned_ability_ids.duplicate()
	snapshot.ability_levels = hero.ability_levels.duplicate(true)
	snapshot.item_ids = hero.item_ids.duplicate()
	for instance_id in hero.item_ids:
		snapshot.item_definition_ids.append(run_state.inventory.get_definition_id(instance_id))
	snapshot.main_score = MarketGenerator.hero_main_score(run_state, hero, registry)
	snapshot.battle_contribution = Dictionary(run_state.pending_execution_contributions.get(hero.unique_id, {})).duplicate(true)
	snapshot.act = run_state.current_act
	snapshot.encounter_index = run_state.encounter_index
	return snapshot


static func _create_militia(run_state: RunState, registry: Node) -> SoldierState:
	var soldier := SoldierState.new()
	var serial := run_state.execution_snapshots.size()
	soldier.unique_id = "execution-militia-%02d" % serial
	while _has_runtime_id(run_state, soldier.unique_id):
		serial += 1
		soldier.unique_id = "execution-militia-%02d" % serial
	var militia := registry.get_definition(&"job.militia") as JobDefinition
	SoldierNameGenerator.assign_name(soldier, militia.display_name, run_state.run_seed, run_state.soldiers)
	return soldier


static func _find_hero(run_state: RunState, hero_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == hero_id:
			return hero
	return null


static func _has_runtime_id(run_state: RunState, runtime_id: String) -> bool:
	for hero in run_state.heroes:
		if hero.unique_id == runtime_id:
			return true
	for soldier in run_state.soldiers:
		if soldier.unique_id == runtime_id:
			return true
	return false


static func _valid_contribution_data(data: Variant) -> bool:
	if not data is Dictionary or not data.has("participated") or not data.has("alive"):
		return false
	var contribution: Variant = data.get("contribution")
	if not contribution is Dictionary:
		return false
	for metric in ["damage_dealt", "effective_healing", "damage_tanked", "total_xp"]:
		if not contribution.has(metric):
			return false
	return true
