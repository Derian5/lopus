class_name RunEventEffect
extends Resource


enum EffectType {
	GRANT_ITEM,
	GRANT_HERO_ABILITY,
	GRANT_JOB_ABILITY,
	STAT_MODIFIER,
	HERO_LEVEL_DELTA,
	SOLDIER_VETERANCY_DELTA,
	JOB_CAPACITY_DELTA,
	GOLD_DELTA,
	HERO_XP_DELTA,
	GRANT_RANDOM_HERO_ITEM,
}

enum TargetScope {
	HERO,
	SOLDIER_TARGET,
	JOB,
}

@export var effect_id: StringName
@export var effect_type := EffectType.GRANT_ITEM
@export var content_id: StringName
@export var hero_definition_id: StringName
@export var job_id: StringName
@export var target_scope := TargetScope.SOLDIER_TARGET
@export var target_index := 0
@export var all_soldier_targets := false
@export var amount := 1
@export_enum("max_hp", "damage", "attack_speed", "movement_speed", "attack_range", "armor") var stat := "max_hp"
@export var modifier_operation := StatModifier.Operation.ADD
@export var modifier_value := 0.0
@export_range(-1, 100, 1) var battles_remaining := -1
