class_name RunEventCondition
extends Resource


enum ConditionType {
	ALWAYS,
	ACT_RANGE,
	MIN_GOLD,
	HERO_AVAILABLE,
	JOB_UNLOCKED,
	MIN_SOLDIER_COUNT,
	HAS_ITEM,
	TARGET_VETERANCY_RANGE,
}

@export var condition_type := ConditionType.ALWAYS
@export var inverted := false
@export var content_id: StringName
@export var minimum := 0
@export var maximum := 999999
@export var target_index := 0


func is_met(run_state: RunState, target_ids: Array[String], registry: Node) -> bool:
	var result := false
	match condition_type:
		ConditionType.ALWAYS:
			result = true
		ConditionType.ACT_RANGE:
			result = run_state.current_act >= minimum and run_state.current_act <= maximum
		ConditionType.MIN_GOLD:
			result = run_state.gold >= minimum
		ConditionType.HERO_AVAILABLE:
			for hero in run_state.heroes:
				if hero.definition_id == content_id and hero.life_state != HeroState.EXECUTED:
					result = true
					break
		ConditionType.JOB_UNLOCKED:
			result = run_state.unlocked_job_ids.has(content_id)
		ConditionType.MIN_SOLDIER_COUNT:
			result = run_state.soldiers.size() >= minimum
		ConditionType.HAS_ITEM:
			for item in run_state.inventory.items:
				if StringName(item.get("definition_id", "")) == content_id:
					result = true
					break
		ConditionType.TARGET_VETERANCY_RANGE:
			if target_index >= 0 and target_index < target_ids.size():
				var soldier := _find_soldier(run_state, target_ids[target_index])
				result = soldier != null and soldier.veterancy_level >= minimum and soldier.veterancy_level <= maximum
	return not result if inverted else result


func _find_soldier(run_state: RunState, runtime_id: String) -> SoldierState:
	for soldier in run_state.soldiers:
		if soldier.unique_id == runtime_id:
			return soldier
	return null
