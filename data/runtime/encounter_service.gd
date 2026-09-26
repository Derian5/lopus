class_name EncounterService
extends RefCounted


static func begin_choice(run_state: RunState, registry: Node) -> Dictionary:
	if run_state.run_status != RunState.STATUS_ACTIVE:
		return _failure("This run cannot generate another encounter choice.")
	var staged_stream := RngStreamState.from_dictionary(run_state.run_rng.to_dictionary())
	var generated := EncounterGenerator.generate(run_state, registry, staged_stream)
	if not generated.ok:
		return generated
	var encounter_ids: Array[StringName] = []
	for encounter_id in generated.encounter_ids:
		encounter_ids.append(StringName(encounter_id))
	run_state.run_rng = staged_stream
	run_state.available_encounter_ids = encounter_ids
	run_state.selected_encounter_id = &""
	run_state.encounter_committed = false
	return {"ok": true, "error": ""}


static func select_encounter(run_state: RunState, encounter_id: StringName) -> Dictionary:
	if run_state.run_status != RunState.STATUS_ACTIVE:
		return _failure("This run is already over.")
	if run_state.run_phase != &"management":
		return _failure("The encounter is locked after combat begins.")
	if run_state.encounter_committed:
		return _failure("The encounter was committed when combat began and cannot be changed.")
	if not run_state.available_encounter_ids.has(encounter_id):
		return _failure("That encounter card is no longer available.")
	run_state.selected_encounter_id = encounter_id
	return {"ok": true, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
