extends PanelContainer


signal continue_requested


func show_result(result: CombatResult) -> void:
	var timeout_text := " / TIME LIMIT" if result.timed_out else ""
	%ResultTitle.text = ("VICTORY" if result.winner == &"player" else "DEFEAT") + timeout_text
	%DurationLabel.text = "Battle duration: %.1f seconds" % result.duration
	%RewardLabel.text = "GOLD  +%d" % int(result.application_summary.get("gold", 0))
	%TopDamageValue.text = _format_top_unit(result.top_damage, &"damage_dealt")
	%TopHealingValue.text = _format_top_unit(result.top_healing, &"effective_healing")
	%DeathsValue.text = _format_deaths(result.get_player_deaths())
	%ProgressionValue.text = _format_progression(result.application_summary)
	visible = true


func hide_summary() -> void:
	visible = false


func _on_continue_pressed() -> void:
	continue_requested.emit()


func _format_top_unit(data: Dictionary, metric: StringName) -> String:
	if data.is_empty() or float(data.get(metric, 0.0)) <= 0.0:
		return "None"
	return "%s\n%.1f" % [data.display_name, float(data[metric])]


func _format_deaths(deaths: Array[Dictionary]) -> String:
	if deaths.is_empty():
		return "No player losses"
	var lines: PackedStringArray = []
	for death in deaths:
		lines.append("%s  <-  %s / %s" % [
			death.display_name,
			death.killer_id if not String(death.killer_id).is_empty() else "unknown",
			death.last_effect_id if not String(death.last_effect_id).is_empty() else "unknown effect",
		])
	return "\n".join(lines)


func _format_progression(summary: Dictionary) -> String:
	var lines := PackedStringArray()
	for change: Dictionary in summary.get("contribution_changes", []):
		var contribution: Dictionary = change.get("contribution", {})
		var kind := "Hero XP" if int(change.unit_kind) == CombatUnitSnapshot.UnitKind.HERO else "Veterancy XP"
		var outcome := "+%d %s" % [int(change.get("xp", 0)), kind]
		if bool(change.get("lost", false)):
			outcome = "%d XP LOST (DEAD)" % int(change.get("potential_xp", contribution.get("total_xp", 0)))
		var level_text := ""
		if change.has("old_level") and int(change.new_level) > int(change.old_level):
			level_text = " / LEVEL %d" % int(change.new_level) if int(change.unit_kind) == CombatUnitSnapshot.UnitKind.HERO else " / VETERANCY %d" % int(change.new_level)
		var cap_text := " / CAPPED" if bool(contribution.get("was_capped", false)) else ""
		lines.append("%s\n  DMG %.1f (+%d) | HEAL %.1f (+%d) | TANK %.1f (+%d) | %s%s%s" % [
			change.display_name,
			float(contribution.get("damage_dealt", 0.0)), int(contribution.get("damage_xp", 0)),
			float(contribution.get("effective_healing", 0.0)), int(contribution.get("healing_xp", 0)),
			float(contribution.get("damage_tanked", 0.0)), int(contribution.get("tanking_xp", 0)),
			outcome, level_text, cap_text,
		])
	for replacement: Dictionary in summary.get("replacements", []):
		lines.append("New recruit: %s" % replacement.display_name)
	if lines.is_empty():
		return "No progression changes"
	return "\n".join(lines)
