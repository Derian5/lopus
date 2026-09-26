class_name SelectedUnitPanel
extends PanelContainer


var combatant: Combatant


func show_combatant(value: Combatant) -> void:
	combatant = value
	visible = is_instance_valid(combatant)
	refresh()


func clear() -> void:
	combatant = null
	visible = false


func refresh() -> void:
	if not is_instance_valid(combatant):
		clear()
		return
	var snapshot := combatant.snapshot
	var team_name := "ALLY" if snapshot.team == CombatUnitSnapshot.Team.PLAYER else "ENEMY"
	var kind_name: String = String(CombatUnitSnapshot.UnitKind.keys()[snapshot.unit_kind]).capitalize()
	var job_name: String = _content_name(snapshot.job_id) if not String(snapshot.job_id).is_empty() else kind_name
	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON:
		job_name = "Summon / Veterancy %d" % snapshot.veterancy_level
	%UnitName.text = snapshot.display_name
	%Identity.text = "%s  |  %s  |  %s" % [team_name, job_name, "ALIVE" if combatant.is_alive() else "DEAD"]
	%Stats.text = "HP  %.1f / %.1f    DAMAGE  %.1f    ARMOR  %.1f    SPEED  %.2f    RANGE  %.0f" % [
		combatant.current_hp,
		combatant.get_effective_stat(&"max_hp"),
		combatant.get_effective_stat(&"damage"),
		combatant.get_effective_stat(&"armor"),
		combatant.get_effective_stat(&"attack_speed"),
		combatant.get_effective_stat(&"attack_range"),
	]
	var target_name := "none"
	if is_instance_valid(combatant.target):
		target_name = combatant.target.snapshot.display_name
	var shield_total := 0.0
	for shield in combatant.shields:
		shield_total += float(shield.amount)
	%Runtime.text = "STATE  %s    TARGET  %s    SHIELD  %.1f    STATUSES  %s" % [
		Combatant.State.keys()[combatant.state],
		target_name,
		shield_total,
		_status_text(),
	]
	%Abilities.text = _abilities_text()
	%Equipment.text = _equipment_text()
	%Abilities.tooltip_text = _content_tooltip(combatant.snapshot.abilities.map(func(ability: AbilityDefinition) -> StringName: return ability.id))
	%Equipment.tooltip_text = _content_tooltip(combatant.snapshot.equipped_item_definition_ids)


func _abilities_text() -> String:
	var lines := PackedStringArray(["ABILITIES"])
	if combatant.snapshot.abilities.is_empty():
		lines.append("- None")
	for ability in combatant.snapshot.abilities:
		var kind := "ACTIVE" if ability.kind == AbilityDefinition.AbilityKind.ACTIVE else "PASSIVE"
		var cooldown := float(combatant.ability_cooldowns.get(ability.id, 0.0))
		var cooldown_text := " | CD %.1f / %.1f" % [cooldown, ability.cooldown_seconds] if ability.kind == AbilityDefinition.AbilityKind.ACTIVE else ""
		lines.append("- %s [%s]%s" % [ability.display_name, kind, cooldown_text])
	return "\n".join(lines)


func _equipment_text() -> String:
	var lines := PackedStringArray(["WEAPONS & EQUIPMENT"])
	var has_weapon := false
	for definition_id in combatant.snapshot.equipped_item_definition_ids:
		var item := _registry().get_definition(definition_id, false) as ItemDefinition
		if item == null:
			continue
		var weapon := item.tags.has(&"weapon")
		has_weapon = has_weapon or weapon
		lines.append("- %s%s" % [item.display_name, " [WEAPON]" if weapon else ""])
	if not has_weapon:
		lines.append("- %s basic attack" % String(combatant.snapshot.attack_type).capitalize())
	return "\n".join(lines)


func _status_text() -> String:
	if combatant.statuses.is_empty():
		return "none"
	var names := PackedStringArray()
	for status in combatant.statuses:
		names.append("%s x%d" % [status.definition.display_name, status.stacks])
	return ", ".join(names)


func _content_name(content_id: StringName) -> String:
	var definition = _registry().get_definition(content_id, false)
	return definition.display_name if definition != null else String(content_id)


func _content_tooltip(content_ids: Array) -> String:
	var descriptions := PackedStringArray()
	for content_id in content_ids:
		descriptions.append(ContentButton.describe_content(StringName(content_id)))
	return "\n\n".join(descriptions)


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
