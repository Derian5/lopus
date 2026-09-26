class_name ResurrectionService
extends RefCounted


const PROGRESSION_ID := &"progression.demo"


static func resurrect(run_state: RunState, hero_id: String, registry: Node) -> Dictionary:
	if run_state == null or run_state.run_status != RunState.STATUS_ACTIVE or run_state.run_phase != &"management":
		return {"ok": false, "error": "Resurrection is only available during an active Management phase."}
	var hero := _find_hero(run_state, hero_id)
	if hero == null:
		return {"ok": false, "error": "Hero not found."}
	if hero.life_state != HeroState.DEAD:
		return {"ok": false, "error": "Only a dead Hero can be resurrected."}
	var progression := registry.get_definition(PROGRESSION_ID, false) as ProgressionDefinition
	if progression == null:
		return {"ok": false, "error": "Resurrection balance data is missing."}
	var cost := progression.resurrection_cost
	if run_state.gold < cost:
		return {"ok": false, "error": "Not enough Gold. Resurrection costs %d Gold." % cost}
	var snapshot := CombatSnapshotBuilder.build_hero(hero, run_state.inventory, registry)
	if snapshot == null:
		return {"ok": false, "error": "Hero content is missing."}

	run_state.gold -= cost
	hero.life_state = HeroState.ALIVE
	hero.current_hp = snapshot.stats.max_hp
	return {"ok": true, "cost": cost, "hero": hero}


static func _find_hero(run_state: RunState, hero_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == hero_id:
			return hero
	return null
