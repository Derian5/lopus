class_name SaveManager
extends RefCounted


const FILE_PREFIX := "run-"
const FILE_EXTENSION := ".json"
const MAX_SAVE_BYTES := 10 * 1024 * 1024

var save_directory := "user://save"


func _init(directory := "user://save") -> void:
	save_directory = directory.trim_suffix("/")


func save_run(run_state: RunState, registry: Node) -> Dictionary:
	if run_state == null:
		return _failure(&"invalid_state", "There is no active run to save.")
	if run_state.run_phase not in [&"management", &"execution"]:
		return _failure(&"invalid_phase", "Autosave is only available between battles.")
	var semantic_error := _validate_run(run_state, registry)
	if not semantic_error.is_empty():
		return _failure(&"invalid_state", "Run cannot be saved: %s" % semantic_error)
	run_state.save_version = RunState.CURRENT_SAVE_VERSION
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_directory))
	if directory_error != OK:
		return _failure(&"io_error", "Could not create the save directory.")
	var generation := _next_generation()
	var final_path := _generation_path(generation)
	var temporary_path := final_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure(&"io_error", "Could not open the temporary save file.")
	file.store_string(JSON.stringify(run_state.to_dictionary(), "\t"))
	file.flush()
	file.close()
	var verification := _read_dictionary(temporary_path)
	if not verification.ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return _failure(&"io_error", "Temporary save verification failed: %s" % verification.message)
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(final_path)
	)
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return _failure(&"io_error", "Could not publish the new save generation.")
	_prune_generations(2)
	return {"ok": true, "code": &"ok", "message": "Run saved.", "path": final_path}


func load_run(registry: Node = null) -> Dictionary:
	var paths := _generation_paths()
	if paths.is_empty():
		return _failure(&"missing", "No saved run was found.", false)
	var parsed := _read_dictionary(paths[-1])
	if not parsed.ok:
		return parsed
	var data: Dictionary = parsed.data
	if not data.has("save_version"):
		return _failure(&"corrupt", "Save file has no save_version.")
	var version := int(data.save_version)
	if version == 8:
		data = _migrate_version_8(data)
		version = RunState.CURRENT_SAVE_VERSION
	if version != RunState.CURRENT_SAVE_VERSION:
		return _failure(&"unsupported_version", "Save version %d is not supported; start a New Game." % version)
	var shape_error := _validate_shape(data)
	if not shape_error.is_empty():
		return _failure(&"corrupt", "%s Start a New Game." % shape_error)
	var run_state := RunState.from_dictionary(data)
	var semantic_error := _validate_run(run_state, registry)
	if not semantic_error.is_empty():
		return _failure(&"corrupt", "%s Start a New Game." % semantic_error)
	return {
		"ok": true,
		"code": &"ok",
		"message": "Saved run loaded.",
		"run_state": run_state,
		"path": paths[-1],
		"exists": true,
	}


func probe(registry: Node = null) -> Dictionary:
	var result := load_run(registry)
	result["exists"] = has_any_save()
	return result


func has_any_save() -> bool:
	return not _generation_paths().is_empty()


func delete_save() -> Dictionary:
	var directory := DirAccess.open(save_directory)
	if directory == null:
		return {"ok": true, "code": &"ok", "message": "No save to delete."}
	for file_name in directory.get_files():
		if _is_generation_file(file_name) or file_name.ends_with(FILE_EXTENSION + ".tmp"):
			directory.remove(file_name)
	return {"ok": true, "code": &"ok", "message": "Saved run deleted."}


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(&"io_error", "Could not open the save file.")
	if file.get_length() <= 0 or file.get_length() > MAX_SAVE_BYTES:
		return _failure(&"corrupt", "Save file is empty or too large.")
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return _failure(&"corrupt", "Save JSON is damaged near line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	if not parser.data is Dictionary:
		return _failure(&"corrupt", "Save root must be an object.")
	return {"ok": true, "code": &"ok", "message": "", "data": parser.data}


func _migrate_version_8(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["save_version"] = RunState.CURRENT_SAVE_VERSION
	var inventory: Dictionary = data.get("inventory", {})
	for item in inventory.get("items", []):
		if item is Dictionary:
			item.erase("bound_target_id")
	var market: Dictionary = data.get("market", {})
	for offer in market.get("offers", []):
		if offer is Dictionary and StringName(offer.get("offer_type", "")) == &"hero_item":
			offer["target_id"] = ""
	return data


func _validate_shape(data: Dictionary) -> String:
	for key in ["save_version", "run_seed", "run_phase", "run_status", "current_act", "encounter_index", "gold", "selected_encounter_id", "encounter_committed", "next_modifier_serial"]:
		if not data.has(key):
			return "Save field '%s' is missing." % key
	var arrays := ["heroes", "soldiers", "job_builds", "unlocked_job_ids", "available_encounter_ids", "execution_snapshots", "applied_combat_result_ids", "triggered_event_ids"]
	var dictionaries := ["job_capacities", "inventory", "market", "pending_execution_contributions", "tutorial_flags", "run_rng", "market_rng", "combat_rng", "event_rng", "hero_ability_reward_rng", "pending_event", "pending_hero_ability_reward"]
	for key in arrays:
		if not data.has(key) or not data[key] is Array:
			return "Save field '%s' must be an array." % key
	for key in dictionaries:
		if not data.has(key) or not data[key] is Dictionary:
			return "Save field '%s' must be an object." % key
	for key in ["heroes", "soldiers", "job_builds", "execution_snapshots"]:
		for entry in data[key]:
			if not entry is Dictionary:
				return "Save field '%s' contains an invalid entry." % key
	for key in ["event_id", "node_id", "target_ids"]:
		if not data.pending_event.has(key):
			return "Pending Run Event state is incomplete."
	if not data.pending_event.target_ids is Array:
		return "Pending Run Event targets must be an array."
	if not data.pending_hero_ability_reward.has("offers") or not data.pending_hero_ability_reward.offers is Array:
		return "Pending Hero ability reward offers must be an array."
	if data.pending_hero_ability_reward.has("hero_level_up_queue") and not data.pending_hero_ability_reward.hero_level_up_queue is Array:
		return "Pending Hero ability reward queue must be an array."
	for offer in data.pending_hero_ability_reward.offers:
		if not offer is Dictionary:
			return "Pending Hero ability reward contains an invalid offer."
		for field in ["offer_id", "hero_unique_id", "ability_id"]:
			if not offer.has(field):
				return "Pending Hero ability reward offer is incomplete."
	for owner_key in ["heroes", "soldiers", "job_builds"]:
		for entry in data[owner_key]:
			if not entry.has("stat_modifiers") or not entry.stat_modifiers is Array:
				return "Saved %s entry is missing stat modifiers." % owner_key
			for modifier in entry.stat_modifiers:
				if not modifier is Dictionary:
					return "Saved stat modifier is invalid."
	for hero in data.heroes:
		if not hero.has("ability_levels") or not hero.ability_levels is Dictionary:
			return "Saved Hero is missing ability levels."
	for snapshot in data.execution_snapshots:
		if not snapshot.has("ability_levels") or not snapshot.ability_levels is Dictionary:
			return "Execution history is missing ability levels."
	if not data.inventory.has("items") or not data.inventory.items is Array:
		return "Inventory items must be an array."
	if not data.market.has("offers") or not data.market.offers is Array:
		return "Market offers must be an array."
	for offer in data.market.offers:
		if not offer is Dictionary:
			return "Market contains an invalid offer."
	for key in ["run_rng", "market_rng", "combat_rng", "event_rng", "hero_ability_reward_rng"]:
		for field in ["seed", "state", "draw_count"]:
			if not data[key].has(field):
				return "RNG stream '%s' is incomplete." % key
		if not String(data[key].seed).is_valid_int() or not String(data[key].state).is_valid_int():
			return "RNG stream '%s' contains invalid state." % key
	return ""


func _validate_run(run_state: RunState, registry: Node) -> String:
	if run_state.run_phase not in [&"management", &"execution"]:
		return "Active combat sessions cannot be loaded from a save."
	if run_state.run_status not in [RunState.STATUS_ACTIVE, RunState.STATUS_DEFEAT, RunState.STATUS_DEMO_COMPLETE]:
		return "Run status is invalid."
	if run_state.gold < 0:
		return "Gold cannot be negative."
	if run_state.next_modifier_serial < 1:
		return "Runtime modifier serial is invalid."
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition if registry != null else null
	if route == null:
		return "Demo route definition is missing."
	if run_state.run_phase == &"execution":
		if run_state.current_act != 1 or run_state.encounter_index != route.act_one_boss_index():
			return "Execution phase is outside the Act I boss checkpoint."
		var boss_encounter := registry.get_definition(run_state.selected_encounter_id, false) as EncounterDefinition if registry != null else null
		if registry != null and (boss_encounter == null or not boss_encounter.is_boss):
			return "Execution phase does not reference the defeated Boss encounter."
		if run_state.pending_execution_contributions.is_empty():
			return "Execution phase is missing Hero contribution data."
	elif not run_state.pending_execution_contributions.is_empty():
		return "Pending Execution data exists outside the mandatory Execution phase."
	var runtime_ids: Dictionary = {}
	var heroes_by_id: Dictionary = {}
	var equipped_ids: Dictionary = {}
	var unlocked_jobs: Dictionary = {}
	for job_id in run_state.unlocked_job_ids:
		if unlocked_jobs.has(job_id):
			return "Unlocked Jobs contain duplicates."
		if registry != null and not registry.get_definition(job_id, false) is JobDefinition:
			return "Unlocked Jobs reference missing content."
		unlocked_jobs[job_id] = true
	for hero in run_state.heroes:
		if hero.unique_id.is_empty() or runtime_ids.has(hero.unique_id):
			return "Hero runtime IDs are missing or duplicated."
		runtime_ids[hero.unique_id] = true
		heroes_by_id[hero.unique_id] = hero
		if not hero.life_state in [HeroState.ALIVE, HeroState.DEAD, HeroState.EXECUTED]:
			return "Hero %s has an invalid life state." % hero.unique_id
		var hero_definition := registry.get_definition(hero.definition_id, false) as HeroDefinition if registry != null else null
		if registry != null and hero_definition == null:
			return "Hero %s references missing content." % hero.unique_id
		var owned_ability_ids: Dictionary = {}
		for ability_id in hero.owned_ability_ids:
			if owned_ability_ids.has(ability_id):
				return "Hero %s owns a duplicate ability." % hero.unique_id
			owned_ability_ids[ability_id] = true
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition if registry != null else null
			if registry != null and ability == null:
				return "Hero %s owns a missing ability." % hero.unique_id
			if ability != null and not ability.is_allowed_for_hero(hero.definition_id):
				return "Hero %s owns an incompatible ability." % hero.unique_id
			var ability_level := hero.ability_level(ability_id)
			if ability_level < 1 or ability_level > AbilityDefinition.MAX_HERO_ABILITY_LEVEL:
				return "Hero %s has an invalid ability level." % hero.unique_id
		if hero.ability_levels.size() != hero.owned_ability_ids.size():
			return "Hero %s ability levels do not match owned abilities." % hero.unique_id
		var equipped_ability_ids: Dictionary = {}
		for ability_id in hero.ability_ids:
			if not hero.owned_ability_ids.has(ability_id):
				return "Hero %s equips an ability it does not own." % hero.unique_id
			if equipped_ability_ids.has(ability_id):
				return "Hero %s equips a duplicate ability." % hero.unique_id
			equipped_ability_ids[ability_id] = true
		if hero.ability_ids.size() > HeroState.MAX_ABILITY_SLOTS:
			return "Hero %s exceeds its ability slot limit." % hero.unique_id
		if hero.life_state == HeroState.EXECUTED and (not hero.ability_ids.is_empty() or not hero.owned_ability_ids.is_empty() or not hero.ability_levels.is_empty() or not hero.item_ids.is_empty()):
			return "Executed Hero %s still exposes locked build content." % hero.unique_id
		if hero.life_state == HeroState.EXECUTED and not hero.stat_modifiers.is_empty():
			return "Executed Hero %s still has event stat modifiers." % hero.unique_id
		var modifier_error := _validate_modifiers(hero.stat_modifiers)
		if not modifier_error.is_empty():
			return modifier_error
		var equipment_error := _validate_equipment(hero.item_ids, run_state, equipped_ids)
		if not equipment_error.is_empty():
			return equipment_error
		for instance_id in hero.item_ids:
			var item_definition_id := run_state.inventory.get_definition_id(instance_id)
			var item := registry.get_definition(item_definition_id, false) as ItemDefinition if registry != null else null
			if item != null and not item.is_compatible_with_hero(hero_definition):
				return "Hero %s equips an incompatible item." % hero.unique_id
	var non_executed_hero_count := 0
	for hero in run_state.heroes:
		if hero.life_state != HeroState.EXECUTED:
			non_executed_hero_count += 1
	if run_state.current_act == 1 and non_executed_hero_count != 3:
		return "Act I requires exactly three non-Executed Heroes."
	if run_state.current_act == 2 and non_executed_hero_count != 2:
		return "Act II requires exactly two non-Executed Heroes."
	if run_state.run_phase == &"execution":
		var eligible_heroes := 0
		for hero in run_state.heroes:
			if hero.life_state not in [HeroState.ALIVE, HeroState.DEAD]:
				continue
			eligible_heroes += 1
			var candidate_data: Variant = run_state.pending_execution_contributions.get(hero.unique_id)
			if not _valid_execution_contribution(candidate_data):
				return "Execution phase has incomplete Hero contribution data."
		if eligible_heroes != 3:
			return "Execution phase requires exactly three eligible Heroes."
		if run_state.soldiers.size() != 9:
			return "Execution phase requires the restored nine-soldier roster."
	for soldier in run_state.soldiers:
		if soldier.unique_id.is_empty() or runtime_ids.has(soldier.unique_id):
			return "Soldier runtime IDs are missing or duplicated."
		runtime_ids[soldier.unique_id] = true
		if registry != null and not registry.get_definition(soldier.current_job_id, false) is JobDefinition:
			return "Soldier %s references a missing Job." % soldier.unique_id
		if not run_state.unlocked_job_ids.has(soldier.current_job_id):
			return "Soldier %s uses a locked Job." % soldier.unique_id
		var modifier_error := _validate_modifiers(soldier.stat_modifiers)
		if not modifier_error.is_empty():
			return modifier_error
	var executed_history: Dictionary = {}
	var archived_item_ids: Dictionary = {}
	for snapshot in run_state.execution_snapshots:
		if snapshot.hero_unique_id.is_empty() or executed_history.has(snapshot.hero_unique_id):
			return "Execution history has missing or duplicated Hero IDs."
		var executed_hero: HeroState = heroes_by_id.get(snapshot.hero_unique_id)
		if executed_hero == null or executed_hero.life_state != HeroState.EXECUTED or executed_hero.definition_id != snapshot.hero_definition_id:
			return "Execution history does not match an Executed Hero."
		if snapshot.life_state_at_execution not in [HeroState.ALIVE, HeroState.DEAD]:
			return "Execution history has an invalid prior life state."
		for ability_id in snapshot.ability_ids:
			if not snapshot.owned_ability_ids.has(ability_id):
				return "Execution history equips an ability it did not own."
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition if registry != null else null
			if registry != null and ability == null:
				return "Execution history references a missing equipped ability."
			if ability != null and not ability.is_allowed_for_hero(snapshot.hero_definition_id):
				return "Execution history references an incompatible equipped ability."
		for ability_id in snapshot.owned_ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition if registry != null else null
			if registry != null and ability == null:
				return "Execution history references a missing ability."
			if ability != null and not ability.is_allowed_for_hero(snapshot.hero_definition_id):
				return "Execution history references an incompatible ability."
			var ability_level := int(snapshot.ability_levels.get(String(ability_id), 0))
			if ability_level < 1 or ability_level > AbilityDefinition.MAX_HERO_ABILITY_LEVEL:
				return "Execution history contains an invalid ability level."
		if snapshot.ability_levels.size() != snapshot.owned_ability_ids.size():
			return "Execution history ability levels do not match owned abilities."
		if snapshot.item_ids.size() != snapshot.item_definition_ids.size():
			return "Execution history item instances do not match their definitions."
		for item_id in snapshot.item_definition_ids:
			if registry != null and not registry.get_definition(item_id, false) is ItemDefinition:
				return "Execution history references a missing item."
		for instance_id in snapshot.item_ids:
			if String(instance_id).is_empty() or archived_item_ids.has(instance_id):
				return "Execution history has missing or duplicated item instance IDs."
			if run_state.inventory.has_instance(instance_id):
				return "Executed Hero equipment remains available in Inventory."
			archived_item_ids[instance_id] = true
		executed_history[snapshot.hero_unique_id] = true
	for hero in run_state.heroes:
		if hero.life_state == HeroState.EXECUTED and not executed_history.has(hero.unique_id):
			return "Executed Hero is missing from execution history."
	if run_state.run_phase == &"execution" and not run_state.execution_snapshots.is_empty():
		return "Execution checkpoint already contains completed execution history."
	if run_state.execution_snapshots.size() > 1:
		return "The Demo route permits only one Hero Execution."
	if run_state.current_act == 1 and not run_state.execution_snapshots.is_empty():
		return "Act I cannot contain completed Execution history."
	if run_state.current_act == 2:
		if run_state.execution_snapshots.size() != 1:
			return "Act II requires exactly one completed Hero Execution."
		var act_two_snapshot := run_state.execution_snapshots[0]
		if act_two_snapshot.act != 1 or act_two_snapshot.encounter_index != route.act_one_boss_index():
			return "Act II Execution history does not reference the Act I Boss checkpoint."
		if run_state.run_status != RunState.STATUS_DEFEAT and run_state.soldiers.size() != 10:
			return "Active Act II requires ten soldiers after Execution."
	for capacity in run_state.job_capacities.values():
		if int(capacity) < 0:
			return "Job capacity cannot be negative."
	for encounter_id in run_state.available_encounter_ids:
		if registry != null and not registry.get_definition(encounter_id, false) is EncounterDefinition:
			return "Save references a missing encounter."
	if not String(run_state.selected_encounter_id).is_empty() and not run_state.available_encounter_ids.has(run_state.selected_encounter_id):
		return "Selected encounter is not one of the available cards."
	if run_state.encounter_committed and String(run_state.selected_encounter_id).is_empty():
		return "A committed encounter selection cannot be empty."
	if run_state.run_status == RunState.STATUS_ACTIVE:
		var final_index := route.final_encounter_index(run_state.current_act)
		if run_state.current_act not in [1, 2] or run_state.encounter_index < 0 or run_state.encounter_index > final_index:
			return "Active run position is outside the Demo route."
		var fixed_tutorial := (
			run_state.current_act == 1
			and run_state.encounter_index == 0
			and run_state.available_encounter_ids == [DemoRunFactory.FIRST_ENCOUNTER_ID]
			and run_state.selected_encounter_id == DemoRunFactory.FIRST_ENCOUNTER_ID
		)
		if not fixed_tutorial and run_state.available_encounter_ids.size() != EncounterGenerator.MAX_CARDS:
			return "Active run must contain exactly two Encounter Cards after the tutorial."
		var card_ids: Dictionary = {}
		var unknown_count := 0
		for encounter_id in run_state.available_encounter_ids:
			if card_ids.has(encounter_id):
				return "Encounter Cards contain duplicates."
			card_ids[encounter_id] = true
			var encounter := registry.get_definition(encounter_id, false) as EncounterDefinition
			var is_boss_wave: bool = run_state.current_act == 1 and run_state.encounter_index == route.act_one_boss_index()
			if encounter.act != run_state.current_act or encounter.is_boss != is_boss_wave:
				return "Encounter Card does not belong to the current route layer."
			if not encounter.is_boss and (run_state.encounter_index < encounter.min_encounter_index or run_state.encounter_index > encounter.max_encounter_index):
				return "Encounter Card does not belong to the current route layer."
			if encounter.is_unknown:
				unknown_count += 1
		if unknown_count > 1:
			return "Encounter choice contains too many Unknown cards."
	elif run_state.run_status == RunState.STATUS_DEMO_COMPLETE:
		if run_state.current_act != 2 or run_state.encounter_index != route.act_two_battle_count:
			return "Demo completion position is invalid."
	elif run_state.run_status == RunState.STATUS_DEFEAT:
		var defeat_final_index := route.final_encounter_index(run_state.current_act)
		if run_state.current_act not in [1, 2] or run_state.encounter_index < 0 or run_state.encounter_index > defeat_final_index:
			return "Defeat position is outside the Demo route."
	for item in run_state.inventory.items:
		if registry != null and not registry.get_definition(StringName(item.get("definition_id", "")), false) is ItemDefinition:
			return "Inventory references a missing item definition."
	for build in run_state.job_builds:
		if registry != null and not registry.get_definition(build.job_id, false) is JobDefinition:
			return "Job build references a missing Job."
		if not run_state.unlocked_job_ids.has(build.job_id):
			return "A locked Job has an active build."
		for ability_id in build.owned_ability_ids:
			if registry != null and not registry.get_definition(ability_id, false) is AbilityDefinition:
				return "Job build owns a missing ability."
		if not String(build.active_ability_id).is_empty() and not build.owned_ability_ids.has(build.active_ability_id):
			return "Job build equips an ability it does not own."
		for ability_id in build.passive_ability_ids:
			if not build.owned_ability_ids.has(ability_id):
				return "Job build equips an ability it does not own."
		var modifier_error := _validate_modifiers(build.stat_modifiers)
		if not modifier_error.is_empty():
			return modifier_error
	var triggered_ids: Dictionary = {}
	for event_id in run_state.triggered_event_ids:
		if String(event_id).is_empty() or triggered_ids.has(event_id) or (registry != null and not registry.get_definition(event_id, false) is RunEventDefinition):
			return "Triggered Run Events contain invalid or duplicate IDs."
		triggered_ids[event_id] = true
	if not run_state.pending_event.is_empty():
		var pending_definition := registry.get_definition(run_state.pending_event.event_id, false) as RunEventDefinition if registry != null else null
		if pending_definition == null or pending_definition.get_node_definition(run_state.pending_event.node_id) == null:
			return "Pending Run Event references missing content."
		if pending_definition.one_time and not run_state.triggered_event_ids.has(pending_definition.id):
			return "Pending one-time Run Event is missing from history."
		if run_state.pending_event.target_ids.size() != pending_definition.soldier_target_count:
			return "Pending Run Event has an invalid target count."
		var pending_targets: Dictionary = {}
		for target_id in run_state.pending_event.target_ids:
			if target_id.is_empty() or pending_targets.has(target_id) or not runtime_ids.has(target_id):
				return "Pending Run Event has an invalid Soldier target."
			pending_targets[target_id] = true
	if not run_state.pending_hero_ability_reward.is_empty():
		if run_state.run_status != RunState.STATUS_ACTIVE or run_state.run_phase not in [&"management", &"execution"]:
			return "Pending Hero ability reward is outside a supported phase."
		if run_state.pending_hero_ability_reward.hero_level_up_queue.is_empty():
			return "Pending Hero ability reward has no level-up queue."
		if run_state.run_phase == &"execution" and not run_state.pending_hero_ability_reward.offers.is_empty():
			return "Execution can defer Hero level-up rewards but cannot contain active offers."
		if run_state.run_phase == &"management" and (run_state.pending_hero_ability_reward.offers.is_empty() or run_state.pending_hero_ability_reward.offers.size() > HeroAbilityRewardService.OFFER_COUNT):
			return "Pending Hero ability reward must contain one or two offers."
		for queued_hero_id in run_state.pending_hero_ability_reward.hero_level_up_queue:
			if not heroes_by_id.has(queued_hero_id):
				return "Pending Hero ability reward queue references a missing Hero."
		var reward_offer_ids: Dictionary = {}
		var reward_ability_ids: Dictionary = {}
		for offer in run_state.pending_hero_ability_reward.offers:
			if offer == null or offer.offer_id.is_empty() or reward_offer_ids.has(offer.offer_id):
				return "Pending Hero ability reward has invalid offer IDs."
			reward_offer_ids[offer.offer_id] = true
			if reward_ability_ids.has(offer.ability_id):
				return "Pending Hero ability reward contains duplicate abilities."
			reward_ability_ids[offer.ability_id] = true
			var reward_hero: HeroState = heroes_by_id.get(offer.hero_unique_id)
			if offer.hero_unique_id != run_state.pending_hero_ability_reward.hero_level_up_queue[0]:
				return "Pending Hero ability reward offer does not match the current level-up Hero."
			var reward_ability := registry.get_definition(offer.ability_id, false) as AbilityDefinition if registry != null else null
			if reward_hero == null or reward_hero.life_state == HeroState.EXECUTED or reward_ability == null or not reward_ability.is_allowed_for_hero(reward_hero.definition_id):
				return "Pending Hero ability reward references ineligible content."
			if reward_hero.owned_ability_ids.has(offer.ability_id):
				if reward_hero.ability_level(offer.ability_id) >= AbilityDefinition.MAX_HERO_ABILITY_LEVEL:
					return "Pending Hero ability reward references a maximum-level ability."
			elif reward_hero.ability_ids.size() >= HeroState.MAX_ABILITY_SLOTS:
				return "Pending Hero ability reward references a Hero with full slots."
	var offer_ids: Dictionary = {}
	for offer in run_state.market.offers:
		if registry != null:
			var offer_validation := MarketService.validate_offer_schema(run_state, offer, registry)
			if not offer_validation.ok:
				return offer_validation.error
		elif not offer.is_valid():
			return "Market offer is incomplete."
		if offer_ids.has(offer.offer_id):
			return "Market offer IDs are duplicated."
		offer_ids[offer.offer_id] = true
		if registry != null and registry.get_definition(offer.content_id, false) == null:
			return "Market offer references missing content."
	return ""


func _validate_equipment(item_ids: Array[StringName], run_state: RunState, equipped_ids: Dictionary) -> String:
	for instance_id in item_ids:
		if not run_state.inventory.has_instance(instance_id):
			return "Equipped item %s is missing from Inventory." % instance_id
		if equipped_ids.has(instance_id):
			return "Item instance %s is equipped more than once." % instance_id
		equipped_ids[instance_id] = true
	return ""


func _validate_modifiers(modifiers: Array[RuntimeStatModifier]) -> String:
	var ids: Dictionary = {}
	for modifier in modifiers:
		if modifier == null or modifier.instance_id.is_empty() or ids.has(modifier.instance_id):
			return "Runtime stat modifiers have missing or duplicate IDs."
		if modifier.stat not in ContentRegistry.MODIFIABLE_STATS or modifier.operation not in StatModifier.Operation.values():
			return "Runtime stat modifier configuration is invalid."
		if modifier.battles_remaining == 0 or modifier.battles_remaining < -1 or not is_finite(modifier.value):
			return "Runtime stat modifier duration or value is invalid."
		ids[modifier.instance_id] = true
	return ""


func _valid_execution_contribution(data: Variant) -> bool:
	if not data is Dictionary or not data.has("participated") or not data.has("alive"):
		return false
	var contribution: Variant = data.get("contribution")
	if not contribution is Dictionary:
		return false
	for metric in ["damage_dealt", "effective_healing", "damage_tanked", "total_xp"]:
		if not contribution.has(metric):
			return false
	return true


func _next_generation() -> int:
	var generations := _generation_numbers()
	return 1 if generations.is_empty() else generations[-1] + 1


func _generation_path(generation: int) -> String:
	return "%s/%s%08d%s" % [save_directory, FILE_PREFIX, generation, FILE_EXTENSION]


func _generation_paths() -> PackedStringArray:
	var result := PackedStringArray()
	for generation in _generation_numbers():
		result.append(_generation_path(generation))
	return result


func _generation_numbers() -> Array[int]:
	var result: Array[int] = []
	var directory := DirAccess.open(save_directory)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if _is_generation_file(file_name):
			result.append(file_name.trim_prefix(FILE_PREFIX).trim_suffix(FILE_EXTENSION).to_int())
	result.sort()
	return result


func _is_generation_file(file_name: String) -> bool:
	if not file_name.begins_with(FILE_PREFIX) or not file_name.ends_with(FILE_EXTENSION):
		return false
	var serial := file_name.trim_prefix(FILE_PREFIX).trim_suffix(FILE_EXTENSION)
	return serial.length() == 8 and serial.is_valid_int()


func _prune_generations(keep: int) -> void:
	var paths := _generation_paths()
	while paths.size() > keep:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(paths[0]))
		paths.remove_at(0)


func _failure(code: StringName, message: String, exists := true) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "exists": exists}
