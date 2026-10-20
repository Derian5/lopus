class_name SimBot
extends RefCounted


## Scripted player for RunSimulator. Every style takes the same free decisions
## (events, Hero level-up rewards, Encounter cards); styles differ only in how Gold is
## spent in the Market:
##   heroes    - items for every Hero (the weakest Hero gets the next item)
##   one_hero  - items only for focus_hero (0..2); it is never executed
##   army      - Job unlocks, capacity and purchased skills for every Job
##   one_job   - all army spending on job_a
##   two_jobs  - army spending split between job_a and job_b
## Army styles buy skill levels through the same Market service as the player.
## A Job can grow up to the whole roster.
##   nothing   - never buys anything

const STYLES := ["heroes", "one_hero", "army", "one_job", "two_jobs", "nothing"]
const STYLE_NAMES := {
	"heroes": "Heroes only",
	"one_hero": "One Hero",
	"army": "Army only",
	"one_job": "One Job",
	"two_jobs": "Two Jobs",
	"nothing": "No upgrades",
}
const ARMY_OFFERS := [&"job_unlock", &"job_capacity", &"job_ability"]
const TIER_RANK := {"Low": 0, "Moderate": 1, "High": 2, "Elite": 3, "Boss": 4}

var style := "nothing"
var job_a: StringName = &"job.warrior"
var job_b: StringName = &"job.archer"
var focus_hero := 0
var encounter_pick := "easiest"
var resurrect := true
var max_rerolls := 1
var registry: Node
var rng := RandomNumberGenerator.new()


func _init(config: Dictionary, content_registry: Node, seed: int) -> void:
	style = String(config.get("style", "nothing"))
	job_a = StringName(config.get("job_a", "job.warrior"))
	job_b = StringName(config.get("job_b", "job.archer"))
	focus_hero = int(config.get("focus_hero", 0))
	encounter_pick = String(config.get("encounter_pick", "easiest"))
	resurrect = bool(config.get("resurrect", true))
	max_rerolls = int(config.get("max_rerolls", 1))
	registry = content_registry
	rng.seed = seed * 7919 + 17


# --- free decisions -------------------------------------------------------------

## Resolves Hero level-up rewards and pending Run Events.
func resolve_pending(run: RunState) -> RunState:
	var guard := 0
	while guard < 30 and (not run.pending_hero_ability_reward.is_empty() or not run.pending_event.is_empty()):
		guard += 1
		if not run.pending_hero_ability_reward.is_empty():
			if run.pending_hero_ability_reward.offers.is_empty():
				var prepared := HeroAbilityRewardService.prepare_reward(run, registry)
				if not prepared.ok or run.pending_hero_ability_reward.offers.is_empty():
					run.pending_hero_ability_reward = PendingHeroAbilityReward.new()
					continue
			var offers := run.pending_hero_ability_reward.offers
			var chosen := HeroAbilityRewardService.choose(run, offers[rng.randi_range(0, offers.size() - 1)].offer_id, registry)
			if chosen.ok:
				run = chosen.run_state
			else:
				run.pending_hero_ability_reward = PendingHeroAbilityReward.new()
			continue
		var event := registry.get_definition(run.pending_event.event_id, false) as RunEventDefinition
		var node := event.get_node_definition(run.pending_event.node_id) if event != null else null
		var available: Array[RunEventChoice] = []
		if node != null:
			for choice in node.choices:
				if choice != null and RunEventService.choice_status(run, choice, registry).ok:
					available.append(choice)
		if available.is_empty():
			run.pending_event.clear()
			continue
		var result := RunEventService.choose(run, available[rng.randi_range(0, available.size() - 1)].choice_id, registry)
		if result.ok:
			run = result.run_state
		else:
			run.pending_event.clear()
	return run


func pick_encounter(run: RunState) -> StringName:
	var ids := run.available_encounter_ids.duplicate()
	if ids.is_empty():
		return &""
	if encounter_pick == "random" or ids.size() == 1:
		return ids[rng.randi_range(0, ids.size() - 1)]
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return _difficulty(a) < _difficulty(b))
	return ids[0] if encounter_pick == "easiest" else ids[-1]


func _difficulty(encounter_id: StringName) -> float:
	var encounter := registry.get_definition(encounter_id, false) as EncounterDefinition
	if encounter == null:
		return 0.0
	return float(TIER_RANK.get(encounter.difficulty_hint, 1)) * 10.0 + encounter.enemy_power


## The Hero to execute after the Act I Boss. The game only allows executing the
## strongest Hero (ExecutionService), so every style - One Hero included - loses it.
func execution_target(run: RunState) -> String:
	return ExecutionService.strongest_hero_id(run, registry)


# --- Management -----------------------------------------------------------------

func manage(run: RunState, report: Dictionary) -> void:
	if resurrect:
		for hero in run.heroes:
			if hero.life_state == HeroState.DEAD and ResurrectionService.resurrect(run, hero.unique_id, registry).ok:
				report.spent.resurrection = int(report.spent.resurrection) + progression_cost()
	if style == "nothing":
		return
	var rerolls := 0
	var guard := 0
	while guard < 20:
		guard += 1
		var offer := _best_offer(run)
		if offer == null:
			var price := MarketService.reroll_price(run.market)
			if rerolls >= max_rerolls or run.gold < price + 150 or not MarketService.reroll(run, registry).ok:
				break
			rerolls += 1
			report.spent.reroll = int(report.spent.reroll) + price
			continue
		var bought := MarketService.buy_offer(run, offer.offer_id, registry)
		if not bought.ok:
			break
		var key := "hero_items" if offer.offer_type == &"hero_item" else String(offer.offer_type)
		report.spent[key] = int(report.spent.get(key, 0)) + offer.price
		if offer.offer_type == &"hero_item":
			_equip_new_item(run, offer.content_id)
	_organize_army(run)


func progression_cost() -> int:
	var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
	return progression.resurrection_cost if progression != null else 0


func _best_offer(run: RunState) -> MarketOffer:
	var best: MarketOffer
	var best_score := -INF
	for offer in run.market.offers:
		if offer.price > run.gold:
			continue
		var score := _offer_score(run, offer)
		if score > best_score:
			best = offer
			best_score = score
	return best if best_score > -INF and best_score > -1000.0 else null


## Higher is better; -INF means the style never buys it.
func _offer_score(run: RunState, offer: MarketOffer) -> float:
	match style:
		"heroes", "one_hero":
			if offer.offer_type != &"hero_item":
				return -INF
			var item := registry.get_definition(offer.content_id, false) as ItemDefinition
			if item == null or _item_target(run, item) < 0:
				return -INF
			return float(item.price)
		"army", "one_job", "two_jobs":
			if offer.offer_type not in ARMY_OFFERS:
				return -INF
			var job_id := StringName(offer.target_id if offer.offer_type == &"job_ability" else String(offer.content_id))
			if not _job_allowed(job_id):
				return -INF
			var capacity := int(run.job_capacities.get(String(job_id), 0))
			if not run.unlocked_job_ids.has(job_id):
				return 300.0 if offer.offer_type == &"job_unlock" else -INF
			if offer.offer_type == &"job_ability":
				return 275.0
			# Extra places: the Job with fewer places goes first, so Two Jobs (and Army)
			# grow evenly. The only limit is the roster size.
			if capacity >= _total_job_slots_left(run, job_id):
				return -INF
			return 250.0 - capacity * 10.0
	return -INF


## A Job never needs more places than there are Soldiers not already in other Jobs.
func _total_job_slots_left(run: RunState, job_id: StringName) -> int:
	var in_other_jobs := 0
	for soldier in run.soldiers:
		if soldier.current_job_id != job_id and soldier.current_job_id != &"job.militia":
			in_other_jobs += 1
	return run.soldiers.size() - in_other_jobs


func _job_allowed(job_id: StringName) -> bool:
	if job_id == &"job.militia":
		return false
	match style:
		"one_job":
			return job_id == job_a
		"two_jobs":
			return job_id == job_a or job_id == job_b
	return true


func _assigned(run: RunState, job_id: StringName) -> int:
	return run.soldiers.filter(func(s: SoldierState) -> bool: return s.current_job_id == job_id).size()


## Index of the Hero who should wear a new item, or -1.
func _item_target(run: RunState, item: ItemDefinition) -> int:
	var best := -1
	var lowest := INF
	for index in run.heroes.size():
		var hero := run.heroes[index]
		if hero.life_state == HeroState.EXECUTED:
			continue
		if style == "one_hero" and index != focus_hero:
			continue
		var definition := registry.get_definition(hero.definition_id, false) as HeroDefinition
		if not item.is_compatible_with_hero(definition):
			continue
		if hero.item_ids.size() >= HeroState.MAX_ITEM_SLOTS and _cheapest_item_price(run, hero) >= item.price:
			continue
		var score := MarketGenerator.hero_main_score(run, hero, registry)
		if score < lowest:
			lowest = score
			best = index
	return best


func _cheapest_item_price(run: RunState, hero: HeroState) -> int:
	var cheapest := 1 << 30
	for instance_id in hero.item_ids:
		var item := registry.get_definition(run.inventory.get_definition_id(instance_id), false) as ItemDefinition
		if item != null:
			cheapest = mini(cheapest, item.price)
	return cheapest


func _equip_new_item(run: RunState, item_id: StringName) -> void:
	var item := registry.get_definition(item_id, false) as ItemDefinition
	var instance_id: StringName
	for entry in EquipmentService.get_unequipped_items(run):
		if StringName(entry.definition_id) == item_id:
			instance_id = StringName(entry.instance_id)
	if item == null or String(instance_id).is_empty():
		return
	var hero_index := _item_target(run, item)
	if hero_index < 0:
		return
	var hero := run.heroes[hero_index]
	var slot := hero.item_ids.size()
	var replaced: StringName
	if slot >= HeroState.MAX_ITEM_SLOTS:
		var cheapest := 1 << 30
		for index in hero.item_ids.size():
			var old := registry.get_definition(run.inventory.get_definition_id(hero.item_ids[index]), false) as ItemDefinition
			if old != null and old.price < cheapest:
				cheapest = old.price
				slot = index
				replaced = hero.item_ids[index]
	if EquipmentService.equip_or_swap(run, &"hero", hero_index, slot, instance_id, registry).ok and not String(replaced).is_empty():
		MarketService.sell_item(run, replaced, registry)


## Moves Militia into Jobs with free capacity and fills Job ability slots.
func _organize_army(run: RunState) -> void:
	for job_id in run.unlocked_job_ids:
		if job_id == &"job.militia":
			continue
		var free := int(run.job_capacities.get(String(job_id), 0)) - _assigned(run, job_id)
		while free > 0:
			var candidate := -1
			var lowest_veterancy := 1 << 30
			for index in run.soldiers.size():
				var soldier := run.soldiers[index]
				if soldier.current_job_id == &"job.militia" and soldier.veterancy_level < lowest_veterancy:
					lowest_veterancy = soldier.veterancy_level
					candidate = index
			if candidate < 0:
				break
			var moved := ArmyBuildService.perform_drop(run, {"source": &"soldier", "soldier_index": candidate}, {"target": &"job", "job_id": job_id}, registry)
			if not moved.ok:
				break
			free -= 1
	for build in run.job_builds:
		for ability_id in build.owned_ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition
			if ability == null:
				continue
			if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
				if build.active_ability_id.is_empty():
					build.set_active_ability(ability_id)
			elif not build.passive_ability_ids.has(ability_id):
				build.add_passive_ability(ability_id)
