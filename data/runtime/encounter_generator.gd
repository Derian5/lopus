class_name EncounterGenerator
extends RefCounted


const MIN_CARDS := 2
const MAX_CARDS := 2


static func generate(run_state: RunState, registry: Node, stream: RngStreamState) -> Dictionary:
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition
	if route == null:
		return {"ok": false, "error": "Demo route definition is missing."}
	var known: Array[EncounterDefinition] = []
	var unknown: Array[EncounterDefinition] = []
	for definition in registry.definitions.values():
		if not definition is EncounterDefinition:
			continue
		var encounter := definition as EncounterDefinition
		if encounter.act != run_state.current_act:
			continue
		var is_boss_wave: bool = run_state.current_act == 1 and run_state.encounter_index == route.act_one_boss_index()
		if encounter.is_boss != is_boss_wave:
			continue
		if not encounter.is_boss and (run_state.encounter_index < encounter.min_encounter_index or run_state.encounter_index > encounter.max_encounter_index):
			continue
		if encounter.is_unknown:
			unknown.append(encounter)
		else:
			known.append(encounter)
	known.sort_custom(func(a: EncounterDefinition, b: EncounterDefinition) -> bool: return a.id < b.id)
	unknown.sort_custom(func(a: EncounterDefinition, b: EncounterDefinition) -> bool: return a.id < b.id)
	if known.size() < MIN_CARDS:
		return {"ok": false, "error": "Not enough encounters for Act %d battle %d." % [run_state.current_act, run_state.encounter_index]}

	var desired_count := mini(MAX_CARDS, known.size() + mini(1, unknown.size()))
	var include_unknown := not unknown.is_empty() and (stream.next_u32() % 4 == 0)
	if desired_count > known.size():
		include_unknown = true
	var selected: Array[StringName] = []
	var known_count := desired_count - (1 if include_unknown else 0)
	var final_index := route.final_encounter_index(run_state.current_act)
	for _index in known_count:
		var picked := _weighted_pick(known, run_state.encounter_index, final_index, stream)
		selected.append(known[picked].id)
		known.remove_at(picked)
	if include_unknown:
		selected.append(unknown[int(stream.next_u32() % unknown.size())].id)
	for index in range(selected.size() - 1, 0, -1):
		var swap_index := int(stream.next_u32() % (index + 1))
		var value := selected[index]
		selected[index] = selected[swap_index]
		selected[swap_index] = value
	return {"ok": true, "error": "", "encounter_ids": selected}


## Picks an index proportionally to each encounter's difficulty weight at this point of the act.
static func _weighted_pick(pool: Array[EncounterDefinition], encounter_index: int, final_index: int, stream: RngStreamState) -> int:
	var weights: Array[float] = []
	var total := 0.0
	for encounter in pool:
		var weight := maxf(encounter.selection_weight(encounter_index, final_index), 0.0)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return int(stream.next_u32() % pool.size())
	var roll := float(stream.next_u32()) / 4294967296.0 * total
	for index in weights.size():
		roll -= weights[index]
		if roll < 0.0:
			return index
	return weights.size() - 1
