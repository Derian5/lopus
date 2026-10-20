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
		for entry in _group_additions(entries):
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
	if stat == &"armor":
		lines.append_array(armor_explanation(final_value))
	return "\n".join(lines)


## Simplified armor formula shown under the armor breakdown.
static func armor_explanation(armor: float) -> PackedStringArray:
	var safe_armor := maxf(armor, 0.0)
	var taken := CombatRules.calculate_damage(100.0, safe_armor)
	return PackedStringArray([
		"",
		"DAMAGE REDUCTION: %s%%" % _number(snappedf(100.0 - taken, 0.1)),
		"Damage taken = Damage x 100 / (100 + Armor)",
		"Now: 100 damage -> %s" % _number(snappedf(taken, 0.1)),
		"100 Armor halves damage, 300 Armor cuts it to a quarter.",
		"Each extra point of Armor matters a little less.",
	])


## Collapse repeated sources within each additive stage; never move bonuses across
## multipliers or other operations, where doing so would change their meaning.
static func _group_additions(entries: Array) -> Array:
	var grouped: Array = []
	var source_indices: Dictionary = {}
	for entry in entries:
		if StringName(entry.operation) != &"add":
			source_indices.clear()
			grouped.append(entry.duplicate())
			continue
		var source := String(entry.source)
		if not source_indices.has(source):
			source_indices[source] = grouped.size()
			grouped.append(entry.duplicate())
		else:
			var existing: Dictionary = grouped[int(source_indices[source])]
			existing.operand = float(existing.operand) + float(entry.operand)
			grouped[int(source_indices[source])] = existing
		var delta := float(entry.after) - float(entry.before)
		var grouped_entry: Dictionary = grouped[int(source_indices[source])]
		grouped_entry["grouped_delta"] = float(grouped_entry.get("grouped_delta", 0.0)) + delta
	# Rebuild intermediate totals after grouping, preserving actual applied deltas.
	var value := float(entries[0].before) if not entries.is_empty() else 0.0
	for step in grouped:
		if StringName(step.operation) == &"add":
			step.before = value
			step.after = value + float(step.grouped_delta)
		value = float(step.after)
	return grouped


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%.0f" % value
	if absf(value) < 10.0:
		return "%.2f" % value
	return "%.1f" % value
