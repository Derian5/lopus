class_name ProgressionDefinition
extends ContentDefinition


enum XpRounding {
	FLOOR,
	ROUND,
	CEIL,
}


@export var hero_level_xp_thresholds := PackedInt32Array([0, 100, 250, 500, 900])
@export_range(0.0, 1.0, 0.01) var hero_stat_growth_per_level := 0.08
@export var veterancy_xp_thresholds := PackedInt32Array([0, 40, 100, 180, 300])
@export_range(0.0, 1.0, 0.01) var veterancy_stat_growth_per_level := 0.05
@export_range(0.0, 1000.0, 0.01) var damage_xp_rate := 0.1
@export_range(0.0, 1000.0, 0.01) var healing_xp_rate := 0.1
@export_range(0.0, 1000.0, 0.01) var tanking_xp_rate := 0.1
@export var xp_rounding_mode := XpRounding.FLOOR
@export_range(0, 1000000, 1) var max_contribution_xp := 0


func hero_level_for_xp(xp: int) -> int:
	return _level_for_xp(xp, hero_level_xp_thresholds)


func veterancy_level_for_xp(xp: int) -> int:
	return _level_for_xp(xp, veterancy_xp_thresholds) - 1


func contribution_breakdown(statistics: Dictionary) -> Dictionary:
	var damage := maxf(0.0, float(statistics.get("damage_dealt", 0.0)))
	var healing := maxf(0.0, float(statistics.get("effective_healing", statistics.get("healing", 0.0))))
	var tanking := maxf(0.0, float(statistics.get("damage_tanked", 0.0)))
	var damage_xp := _round_xp(damage * damage_xp_rate)
	var healing_xp := _round_xp(healing * healing_xp_rate)
	var tanking_xp := _round_xp(tanking * tanking_xp_rate)
	var uncapped_total := damage_xp + healing_xp + tanking_xp
	var total := uncapped_total
	if max_contribution_xp > 0:
		total = mini(total, max_contribution_xp)
	return {
		"damage_dealt": damage,
		"effective_healing": healing,
		"damage_tanked": tanking,
		"damage_xp": damage_xp,
		"healing_xp": healing_xp,
		"tanking_xp": tanking_xp,
		"uncapped_total_xp": uncapped_total,
		"total_xp": total,
		"was_capped": total < uncapped_total,
	}


func _round_xp(value: float) -> int:
	match xp_rounding_mode:
		XpRounding.ROUND:
			return maxi(0, roundi(value))
		XpRounding.CEIL:
			return maxi(0, ceili(value))
		_:
			return maxi(0, floori(value))


func _level_for_xp(xp: int, thresholds: PackedInt32Array) -> int:
	var result := 1
	for index in thresholds.size():
		if xp >= thresholds[index]:
			result = index + 1
	return result
