class_name RunState
extends RefCounted


const CURRENT_SAVE_VERSION := 8
const STATUS_ACTIVE: StringName = &"active"
const STATUS_DEFEAT: StringName = &"defeat"
const STATUS_DEMO_COMPLETE: StringName = &"demo_complete"
const ROUTE_DEFINITION_ID: StringName = &"route.demo"

var save_version := CURRENT_SAVE_VERSION
var run_seed := 0
var run_phase: StringName = &"management"
var run_status: StringName = STATUS_ACTIVE
var current_act := 1
var encounter_index := 0
var gold := 0
var heroes: Array[HeroState] = []
var soldiers: Array[SoldierState] = []
var job_builds: Array[JobBuildState] = []
var job_capacities: Dictionary = {}
var unlocked_job_ids: Array[StringName] = []
var inventory := InventoryState.new()
var market := MarketState.new()
var available_encounter_ids: Array[StringName] = []
var selected_encounter_id: StringName
var encounter_committed := false
var execution_snapshots: Array[ExecutionSnapshot] = []
var pending_execution_contributions: Dictionary = {}
var tutorial_flags: Dictionary = {}
var run_rng := RngStreamState.new()
var market_rng := RngStreamState.new()
var combat_rng := RngStreamState.new()
var event_rng := RngStreamState.new()
var hero_ability_reward_rng := RngStreamState.new()
var applied_combat_result_ids: Array[String] = []
var triggered_event_ids: Array[StringName] = []
var pending_event := PendingRunEventState.new()
var pending_hero_ability_reward := PendingHeroAbilityReward.new()
var next_modifier_serial := 1


func initialize_rng_streams(seed: int) -> void:
	run_rng.initialize(seed ^ 0x13579BDF)
	market_rng.initialize(seed ^ 0x2468ACE0)
	combat_rng.initialize(seed ^ 0x5A5A5A5A)
	event_rng.initialize(seed ^ 0x6E7E8E9E)
	hero_ability_reward_rng.initialize(seed ^ 0x4A3B2C1D)


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
		"run_status": String(run_status),
		"current_act": current_act,
		"encounter_index": encounter_index,
		"gold": gold,
		"heroes": hero_data,
		"soldiers": soldier_data,
		"job_builds": job_build_data,
		"job_capacities": job_capacities.duplicate(true),
		"unlocked_job_ids": StateSerialization.names_to_strings(unlocked_job_ids),
		"inventory": inventory.to_dictionary(),
		"market": market.to_dictionary(),
		"available_encounter_ids": StateSerialization.names_to_strings(available_encounter_ids),
		"selected_encounter_id": String(selected_encounter_id),
		"encounter_committed": encounter_committed,
		"execution_snapshots": execution_data,
		"pending_execution_contributions": pending_execution_contributions.duplicate(true),
		"tutorial_flags": tutorial_flags.duplicate(true),
		"run_rng": run_rng.to_dictionary(),
		"market_rng": market_rng.to_dictionary(),
		"combat_rng": combat_rng.to_dictionary(),
		"event_rng": event_rng.to_dictionary(),
		"hero_ability_reward_rng": hero_ability_reward_rng.to_dictionary(),
		"applied_combat_result_ids": applied_combat_result_ids.duplicate(),
		"triggered_event_ids": StateSerialization.names_to_strings(triggered_event_ids),
		"pending_event": pending_event.to_dictionary(),
		"pending_hero_ability_reward": pending_hero_ability_reward.to_dictionary(),
		"next_modifier_serial": next_modifier_serial,
	}


static func from_dictionary(data: Dictionary) -> RunState:
	var state := RunState.new()
	state.save_version = int(data.get("save_version", CURRENT_SAVE_VERSION))
	state.run_seed = int(data.get("run_seed", 0))
	state.run_phase = StringName(data.get("run_phase", "management"))
	state.run_status = StringName(data.get("run_status", STATUS_ACTIVE))
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

	for job_id in Dictionary(data.get("job_capacities", {})):
		state.job_capacities[String(job_id)] = int(data.job_capacities[job_id])
	state.unlocked_job_ids = StateSerialization.strings_to_names(data.get("unlocked_job_ids", []))
	state.inventory = InventoryState.from_dictionary(data.get("inventory", {}))
	state.market = MarketState.from_dictionary(data.get("market", {}))
	state.available_encounter_ids = StateSerialization.strings_to_names(data.get("available_encounter_ids", []))
	state.selected_encounter_id = StringName(data.get("selected_encounter_id", ""))
	state.encounter_committed = bool(data.get("encounter_committed", false))

	for snapshot_data in data.get("execution_snapshots", []):
		if snapshot_data is Dictionary:
			state.execution_snapshots.append(ExecutionSnapshot.from_dictionary(snapshot_data))
	state.pending_execution_contributions = Dictionary(data.get("pending_execution_contributions", {})).duplicate(true)

	state.tutorial_flags = Dictionary(data.get("tutorial_flags", {})).duplicate(true)
	state.run_rng = RngStreamState.from_dictionary(data.get("run_rng", {}))
	state.market_rng = RngStreamState.from_dictionary(data.get("market_rng", {}))
	state.combat_rng = RngStreamState.from_dictionary(data.get("combat_rng", {}))
	state.event_rng = RngStreamState.from_dictionary(data.get("event_rng", {}))
	state.hero_ability_reward_rng = RngStreamState.from_dictionary(data.get("hero_ability_reward_rng", {}))
	for result_id in data.get("applied_combat_result_ids", []):
		state.applied_combat_result_ids.append(String(result_id))
	state.triggered_event_ids = StateSerialization.strings_to_names(data.get("triggered_event_ids", []))
	state.pending_event = PendingRunEventState.from_dictionary(data.get("pending_event", {}))
	state.pending_hero_ability_reward = PendingHeroAbilityReward.from_dictionary(data.get("pending_hero_ability_reward", {}))
	state.next_modifier_serial = maxi(1, int(data.get("next_modifier_serial", 1)))
	return state
