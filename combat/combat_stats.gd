class_name CombatStats
extends RefCounted


var max_hp := 100.0
var damage := 10.0
var attack_speed := 1.0
var movement_speed := 100.0
var attack_range := 48.0
var armor := 0.0


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
	return copy


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
