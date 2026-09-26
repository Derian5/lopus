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


static func can_change_job(run_state: RunState, soldier_index: int, job_id: StringName, registry: Node) -> Dictionary:
	var target_data := _target_data(run_state, &"soldier", soldier_index)
	if not target_data.ok:
		return target_data
	for instance_id in target_data.item_ids:
		var item := _item_definition(run_state, instance_id, registry)
		if item == null:
			return _failure("Equipped item %s is missing." % instance_id)
		if not item.allowed_job_ids.is_empty() and not item.allowed_job_ids.has(job_id):
			return _failure("Unequip %s before changing to %s." % [item.display_name, _display_name(registry, job_id)])
	return {"ok": true, "error": ""}


static func is_instance_equipped(run_state: RunState, instance_id: StringName) -> bool:
	if String(instance_id).is_empty():
		return false
	for hero in run_state.heroes:
		if hero.item_ids.has(instance_id):
			return true
	for soldier in run_state.soldiers:
		if soldier.item_ids.has(instance_id):
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
	if item.allowed_target_type != target_kind:
		return _failure("%s can only be equipped by a %s." % [item.display_name, item.allowed_target_type])
	var instance := run_state.inventory.get_item(instance_id)
	var bound_target_id := String(instance.get("bound_target_id", ""))
	if target_kind == &"hero" and not bound_target_id.is_empty() and target.unique_id != bound_target_id:
		return _failure("%s was offered specifically to another Hero." % item.display_name)
	if target_kind == &"soldier" and not item.allowed_job_ids.is_empty() and not item.allowed_job_ids.has(target.current_job_id):
		return _failure("%s cannot be equipped by the %s Job." % [item.display_name, _display_name(registry, target.current_job_id)])
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
	if target_kind == &"soldier" and target_index >= 0 and target_index < run_state.soldiers.size():
		return {
			"ok": true,
			"error": "",
			"target": run_state.soldiers[target_index],
			"item_ids": run_state.soldiers[target_index].item_ids,
			"max_slots": SoldierState.MAX_ITEM_SLOTS,
		}
	return _failure("Select a valid Hero or Soldier.")


static func _display_name(registry: Node, content_id: StringName) -> String:
	var definition: ContentDefinition = registry.get_definition(content_id, false)
	return definition.display_name if definition != null else String(content_id)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
