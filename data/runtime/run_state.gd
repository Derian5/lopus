class_name RunState
extends RefCounted


const CURRENT_SAVE_VERSION := 1

var save_version := CURRENT_SAVE_VERSION
var run_seed := 0
var run_phase: StringName = &"management"
var current_act := 1
var encounter_index := 0
var gold := 0
var heroes: Array[HeroState] = []
var soldiers: Array[SoldierState] = []
var job_builds: Array[JobBuildState] = []
var job_capacities: Dictionary = {}
var inventory := InventoryState.new()
var market := MarketState.new()
var available_encounter_ids: Array[StringName] = []
var execution_snapshots: Array[ExecutionSnapshot] = []
var tutorial_flags: Dictionary = {}
var rng_states: Dictionary = {}
var applied_combat_result_ids: Array[String] = []


func to_dictionary() -> Dictionary:
	var hero_data: Array = []
	for hero in heroes:
		hero_data.append(hero.to_dictionary())

	var soldier_data: Array = []
	for soldier in soldiers:
		soldier_data.append(soldier.to_dictionary())

	var job_build_data: Array = []
	for job_build in job_builds:
		job_build_data.append(job_build.to_dictionary())

	var execution_data: Array = []
	for snapshot in execution_snapshots:
		execution_data.append(snapshot.to_dictionary())

	return {
		"save_version": save_version,
		"run_seed": run_seed,
		"run_phase": String(run_phase),
		"current_act": current_act,
		"encounter_index": encounter_index,
		"gold": gold,
		"heroes": hero_data,
		"soldiers": soldier_data,
		"job_builds": job_build_data,
		"job_capacities": job_capacities.duplicate(true),
		"inventory": inventory.to_dictionary(),
		"market": market.to_dictionary(),
		"available_encounter_ids": StateSerialization.names_to_strings(available_encounter_ids),
		"execution_snapshots": execution_data,
		"tutorial_flags": tutorial_flags.duplicate(true),
		"rng_states": rng_states.duplicate(true),
		"applied_combat_result_ids": applied_combat_result_ids.duplicate(),
	}


static func from_dictionary(data: Dictionary) -> RunState:
	var state := RunState.new()
	state.save_version = int(data.get("save_version", CURRENT_SAVE_VERSION))
	state.run_seed = int(data.get("run_seed", 0))
	state.run_phase = StringName(data.get("run_phase", "management"))
	state.current_act = int(data.get("current_act", 1))
	state.encounter_index = int(data.get("encounter_index", 0))
	state.gold = int(data.get("gold", 0))

	for hero_data in data.get("heroes", []):
		if hero_data is Dictionary:
			state.heroes.append(HeroState.from_dictionary(hero_data))

	for soldier_data in data.get("soldiers", []):
		if soldier_data is Dictionary:
			state.soldiers.append(SoldierState.from_dictionary(soldier_data))

	for job_build_data in data.get("job_builds", []):
		if job_build_data is Dictionary:
			state.job_builds.append(JobBuildState.from_dictionary(job_build_data))

	state.job_capacities = Dictionary(data.get("job_capacities", {})).duplicate(true)
	state.inventory = InventoryState.from_dictionary(data.get("inventory", {}))
	state.market = MarketState.from_dictionary(data.get("market", {}))
	state.available_encounter_ids = StateSerialization.strings_to_names(data.get("available_encounter_ids", []))

	for snapshot_data in data.get("execution_snapshots", []):
		if snapshot_data is Dictionary:
			state.execution_snapshots.append(ExecutionSnapshot.from_dictionary(snapshot_data))

	state.tutorial_flags = Dictionary(data.get("tutorial_flags", {})).duplicate(true)
	state.rng_states = Dictionary(data.get("rng_states", {})).duplicate(true)
	for result_id in data.get("applied_combat_result_ids", []):
		state.applied_combat_result_ids.append(String(result_id))
	return state
