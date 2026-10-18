class_name EquipmentService
extends RefCounted


static func equip_or_swap(
	run_state: RunState,
	target_kind: StringName,
	target_index: int,
	slot_index: int,
	instance_id: StringName,
	registry: Node
) -> Dictionary:
	var target_data := _target_data(run_state, target_kind, target_index)
	if not target_data.ok:
		return target_data
	var item_ids: Array[StringName] = target_data.item_ids
	if slot_index < 0 or slot_index > item_ids.size() or slot_index >= int(target_data.max_slots):
		return _failure("Invalid equipment slot.")
	if is_instance_equipped(run_state, instance_id):
		return _failure("That item instance is already equipped.")
	var validation := _validate_item_for_target(run_state, instance_id, target_kind, target_data.target, registry)
	if not validation.ok:
		return validation
	var replaced_id: StringName = item_ids[slot_index] if slot_index < item_ids.size() else &""
	if slot_index == item_ids.size():
		item_ids.append(instance_id)
	else:
		item_ids[slot_index] = instance_id
	return {
		"ok": true,
		"error": "",
		"replaced_instance_id": replaced_id,
	}


static func unequip(run_state: RunState, target_kind: StringName, target_index: int, slot_index: int) -> Dictionary:
	var target_data := _target_data(run_state, target_kind, target_index)
	if not target_data.ok:
		return target_data
	var item_ids: Array[StringName] = target_data.item_ids
	if slot_index < 0 or slot_index >= item_ids.size():
		return _failure("Select an occupied equipment slot.")
	var instance_id := item_ids[slot_index]
	item_ids.remove_at(slot_index)
	return {"ok": true, "error": "", "instance_id": instance_id}


static func is_instance_equipped(run_state: RunState, instance_id: StringName) -> bool:
	if String(instance_id).is_empty():
		return false
	for hero in run_state.heroes:
		if hero.item_ids.has(instance_id):
			return true
	return false


static func get_unequipped_items(run_state: RunState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in run_state.inventory.items:
		var instance_id := StringName(item.get("instance_id", ""))
		if not is_instance_equipped(run_state, instance_id):
			result.append(item.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.instance_id) < String(b.instance_id)
	)
	return result


static func _validate_item_for_target(
	run_state: RunState,
	instance_id: StringName,
	target_kind: StringName,
	target: Variant,
	registry: Node
) -> Dictionary:
	var item := _item_definition(run_state, instance_id, registry)
	if item == null:
		return _failure("Unknown item instance or definition: %s." % instance_id)
	if target_kind != &"hero":
		return _failure("Only Heroes can equip items.")
	var hero_definition := registry.get_definition(target.definition_id, false) as HeroDefinition
	if not item.is_compatible_with_hero(hero_definition):
		return _failure("%s can only be equipped by %s." % [item.display_name, item.eligibility_text()])
	return {"ok": true, "error": ""}


static func _item_definition(run_state: RunState, instance_id: StringName, registry: Node) -> ItemDefinition:
	var definition_id := run_state.inventory.get_definition_id(instance_id)
	if String(definition_id).is_empty():
		return null
	return registry.get_definition(definition_id, false) as ItemDefinition


static func _target_data(run_state: RunState, target_kind: StringName, target_index: int) -> Dictionary:
	if target_kind == &"hero" and target_index >= 0 and target_index < run_state.heroes.size():
		if run_state.heroes[target_index].life_state == HeroState.EXECUTED:
			return _failure("Executed Heroes cannot use equipment.")
		return {
			"ok": true,
			"error": "",
			"target": run_state.heroes[target_index],
			"item_ids": run_state.heroes[target_index].item_ids,
			"max_slots": HeroState.MAX_ITEM_SLOTS,
		}
	return _failure("Select a valid Hero.")


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
