class_name CombatRules
extends RefCounted


static func calculate_damage(raw_damage: float, armor: float) -> float:
	var safe_damage := maxf(raw_damage, 0.0)
	var safe_armor := maxf(armor, 0.0)
	return safe_damage * 100.0 / (100.0 + safe_armor)
