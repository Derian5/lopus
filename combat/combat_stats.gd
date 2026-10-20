class_name CombatStats
extends RefCounted


const STAT_NAMES: Array[StringName] = [&"max_hp", &"damage", &"attack_speed", &"movement_speed", &"attack_range", &"armor", &"crit_chance", &"crit_multiplier", &"lifesteal", &"dodge", &"hp_regen", &"cooldown_reduction", &"damage_taken", &"armor_penetration"]
const PRIMARY_STAT_NAMES: Array[StringName] = [&"max_hp", &"damage", &"attack_speed", &"movement_speed", &"attack_range", &"armor"]
const SECONDARY_STAT_NAMES: Array[StringName] = [&"crit_chance", &"crit_multiplier", &"lifesteal", &"dodge", &"hp_regen", &"cooldown_reduction", &"damage_taken", &"armor_penetration"]
const DEFAULT_CRIT_MULTIPLIER := 2.0
const MAX_DODGE := 60.0
const MAX_COOLDOWN_REDUCTION := 75.0

var max_hp := 100.0
var damage := 10.0
var attack_speed := 1.0
var movement_speed := 100.0
var attack_range := 48.0
var armor := 0.0
var crit_chance := 0.0
var crit_multiplier := 0.0
var lifesteal := 0.0
var dodge := 0.0
var hp_regen := 0.0
var cooldown_reduction := 0.0
var damage_taken := 0.0
var armor_penetration := 0.0
var breakdowns: Dictionary = {}


static func from_stat_block(block: StatBlock) -> CombatStats:
	var stats := CombatStats.new()
	if block == null:
		return stats
	stats.max_hp = block.max_hp
	stats.damage = block.damage
	stats.attack_speed = block.attack_speed
	stats.movement_speed = block.movement_speed
	stats.attack_range = block.attack_range
	stats.armor = block.armor
	return stats


func duplicate_stats() -> CombatStats:
	var copy := CombatStats.new()
	copy.max_hp = max_hp
	copy.damage = damage
	copy.attack_speed = attack_speed
	copy.movement_speed = movement_speed
	copy.attack_range = attack_range
	copy.armor = armor
	for stat in SECONDARY_STAT_NAMES:
		copy.set(stat, get(stat))
	copy.breakdowns = breakdowns.duplicate(true)
	return copy


func begin_breakdowns(source: String) -> void:
	breakdowns.clear()
	for stat in STAT_NAMES:
		breakdowns[stat] = [{
			"source": source,
			"operation": &"base",
			"operand": float(get(stat)),
			"before": 0.0,
			"after": float(get(stat)),
		}]


func record_change(stat: StringName, source: String, operation: StringName, operand: float, before: float, after: float) -> void:
	if not breakdowns.has(stat) or is_equal_approx(before, after):
		return
	breakdowns[stat].append({
		"source": source,
		"operation": operation,
		"operand": operand,
		"before": before,
		"after": after,
	})


func breakdown_for(stat: StringName) -> Array:
	return breakdowns.get(stat, []).duplicate(true)


func add_stat_block(block: StatBlock) -> void:
	if block == null:
		return
	max_hp += block.max_hp
	damage += block.damage
	attack_speed += block.attack_speed
	movement_speed += block.movement_speed
	attack_range += block.attack_range
	armor += block.armor
	max_hp = maxf(max_hp, 1.0)
	attack_speed = maxf(attack_speed, 0.01)
	movement_speed = maxf(movement_speed, 0.0)
	attack_range = maxf(attack_range, 0.0)
	armor = maxf(armor, 0.0)


func multiply(multiplier: float) -> void:
	max_hp *= multiplier
	damage *= multiplier
	attack_speed *= multiplier
	movement_speed *= multiplier
	attack_range *= multiplier
	armor *= multiplier


func apply_modifiers(modifiers: Array[StatModifier]) -> void:
	for operation in [StatModifier.Operation.ADD, StatModifier.Operation.ADD_PERCENT, StatModifier.Operation.MULTIPLY]:
		if operation == StatModifier.Operation.ADD_PERCENT:
			var sums := {}
			for modifier in modifiers:
				if modifier != null and modifier.operation == operation and _has_stat(modifier.stat):
					sums[modifier.stat] = float(sums.get(modifier.stat, 0.0)) + modifier.value
			for stat in sums:
				set(stat, float(get(stat)) * (1.0 + float(sums[stat]) / 100.0))
			continue
		for modifier in modifiers:
			if modifier == null or modifier.operation != operation or not _has_stat(modifier.stat):
				continue
			set(modifier.stat, modifier.apply_to(float(get(modifier.stat))))
	_clamp_values()


func _has_stat(stat: String) -> bool:
	return StringName(stat) in STAT_NAMES


func _clamp_values() -> void:
	max_hp = maxf(max_hp, 1.0)
	damage = maxf(damage, 0.0)
	attack_speed = maxf(attack_speed, 0.01)
	movement_speed = maxf(movement_speed, 0.0)
	attack_range = maxf(attack_range, 0.0)
	armor = maxf(armor, 0.0)
	crit_chance = clampf(crit_chance, 0.0, 100.0)
	crit_multiplier = maxf(crit_multiplier, 0.0)
	lifesteal = maxf(lifesteal, 0.0)
	dodge = clampf(dodge, 0.0, MAX_DODGE)
	hp_regen = maxf(hp_regen, 0.0)
	cooldown_reduction = clampf(cooldown_reduction, 0.0, MAX_COOLDOWN_REDUCTION)
	damage_taken = maxf(damage_taken, -90.0)
	armor_penetration = clampf(armor_penetration, 0.0, 100.0)
