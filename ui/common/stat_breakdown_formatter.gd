class_name StatBreakdownFormatter
extends RefCounted


const TITLES := {
	&"max_hp": "MAX HEALTH",
	&"damage": "DAMAGE",
	&"attack_speed": "ATTACK SPEED",
	&"movement_speed": "MOVE SPEED",
	&"attack_range": "ATTACK RANGE",
	&"armor": "ARMOR",
}


static func from_stats(stats: CombatStats, stat: StringName, current_hp := -1.0) -> String:
	return format(stat, float(stats.get(stat)), stats.breakdown_for(stat), current_hp)


static func from_combatant(combatant: Combatant, stat: StringName) -> String:
	var breakdown := combatant.get_stat_breakdown(stat)
	return format(stat, float(breakdown.value), breakdown.entries, combatant.current_hp if stat == &"max_hp" else -1.0)


static func format(stat: StringName, final_value: float, entries: Array, current_hp := -1.0) -> String:
	var lines := PackedStringArray([String(TITLES.get(stat, String(stat).replace("_", " ").to_upper()))])
	if current_hp >= 0.0:
		lines.append("Current: %s / %s" % [_number(current_hp), _number(final_value)])
	if entries.is_empty():
		lines.append("Snapshot base: %s" % _number(final_value))
	else:
		for entry in entries:
			var operation := StringName(entry.operation)
			match operation:
				&"base":
					lines.append("%s: %s" % [entry.source, _number(float(entry.after))])
				&"add":
					lines.append("%s: %s%s  ->  %s" % [entry.source, "+" if float(entry.operand) >= 0.0 else "", _number(float(entry.operand)), _number(float(entry.after))])
				&"multiply":
					lines.append("%s: x%s  ->  %s" % [entry.source, _number(float(entry.operand)), _number(float(entry.after))])
				_:
					lines.append("%s: %s" % [entry.source, _number(float(entry.after))])
	lines.append("FINAL: %s" % _number(final_value))
	return "\n".join(lines)


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%.0f" % value
	if absf(value) < 10.0:
		return "%.2f" % value
	return "%.1f" % value
