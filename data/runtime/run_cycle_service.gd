class_name RunCycleService
extends RefCounted


static func prepare_next_choice(run_state: RunState, registry: Node) -> Dictionary:
	if run_state.run_status != RunState.STATUS_ACTIVE:
		return {"ok": true, "error": ""}
	var staged := RunState.from_dictionary(run_state.to_dictionary())
	var ability_reward_result := HeroAbilityRewardService.prepare_reward(staged, registry)
	if not ability_reward_result.ok:
		return ability_reward_result
	var market_result := MarketService.begin_visit(staged, registry)
	if not market_result.ok:
		return market_result
	var encounter_result := EncounterService.begin_choice(staged, registry)
	if not encounter_result.ok:
		return encounter_result
	var event_result := RunEventService.prepare_event(staged, registry)
	if not event_result.ok:
		return event_result

	run_state.market = staged.market
	run_state.market_rng = staged.market_rng
	run_state.run_rng = staged.run_rng
	run_state.event_rng = staged.event_rng
	run_state.hero_ability_reward_rng = staged.hero_ability_reward_rng
	run_state.available_encounter_ids = staged.available_encounter_ids
	run_state.selected_encounter_id = staged.selected_encounter_id
	run_state.encounter_committed = staged.encounter_committed
	run_state.pending_event = staged.pending_event
	run_state.triggered_event_ids = staged.triggered_event_ids
	run_state.pending_hero_ability_reward = staged.pending_hero_ability_reward
	return {"ok": true, "error": ""}
