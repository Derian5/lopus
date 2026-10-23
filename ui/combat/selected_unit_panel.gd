class_name SelectedUnitPanel
extends PanelContainer

signal close_requested


const UI_ATLAS := preload("res://graphics/ui/atlas_ui.png")
const STAT_SPECS := [
	{"key": &"hp", "caption": "HEALTH", "region": Rect2(610, 445, 66, 66)},
	{"key": &"damage", "caption": "DAMAGE", "region": Rect2(686, 445, 66, 66)},
	{"key": &"attack_speed", "caption": "ATTACK SPEED", "region": Rect2(755, 445, 66, 66)},
	{"key": &"move_speed", "caption": "MOVE SPEED", "region": Rect2(832, 445, 66, 66)},
	{"key": &"range", "caption": "RANGE", "region": Rect2(915, 444, 66, 66)},
	{"key": &"armor", "caption": "ARMOR", "region": Rect2(994, 444, 66, 66)},
]

var combatant: Combatant
var stat_values: Dictionary = {}
var stat_tiles: Dictionary = {}


const STAT_BASE_COLOR := Color(0.96, 0.86, 0.66)
const STAT_RAISED_COLOR := Color(0.62, 0.9, 0.5)
const STAT_LOWERED_COLOR := Color(0.95, 0.5, 0.42)

func _ready() -> void:
	_build_stat_grid()
	%CloseButton.pressed.connect(func() -> void: close_requested.emit())


func show_combatant(value: Combatant) -> void:
	combatant = value
	visible = is_instance_valid(combatant)
	_clear_icon_slots(%AbilityIcons)
	_clear_icon_slots(%ItemIcons)
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
	stat_values[&"hp"].text = "%.0f / %.0f" % [combatant.current_hp, combatant.get_effective_stat(&"max_hp")]
	stat_values[&"damage"].text = "%.1f" % combatant.get_effective_stat(&"damage")
	stat_values[&"attack_speed"].text = "%.2f" % combatant.get_effective_stat(&"attack_speed")
	stat_values[&"move_speed"].text = "%.0f" % combatant.get_effective_stat(&"movement_speed")
	stat_values[&"range"].text = "%.0f" % combatant.get_effective_stat(&"attack_range")
	stat_values[&"armor"].text = "%.1f" % combatant.get_effective_stat(&"armor")
	var stat_keys := {
		&"hp": &"max_hp",
		&"damage": &"damage",
		&"attack_speed": &"attack_speed",
		&"move_speed": &"movement_speed",
		&"range": &"attack_range",
		&"armor": &"armor",
	}
	for key in stat_keys:
		_set_control_tooltip(stat_tiles[key], StatBreakdownFormatter.from_combatant(combatant, stat_keys[key]))
		stat_values[key].add_theme_color_override("font_color", _stat_value_color(stat_keys[key]))
	var target_name := "none"
	if is_instance_valid(combatant.target):
		target_name = combatant.target.snapshot.display_name
	var state_names := ["Idle", "Choosing a target", "Moving", "Attacking", "Recovering", "Defeated"]
	var activity: String = state_names[combatant.state]
	if combatant.is_alive():
		if combatant.is_stunned():
			activity = "Stunned"
		elif combatant.is_feared():
			activity = "Feared"
		elif combatant.is_rooted() and combatant.state == Combatant.State.MOVE_INTO_RANGE:
			activity = "Rooted"
	%Runtime.text = "%s  ·  Target: %s" % [
		activity,
		target_name,
	]
	var extra := secondary_stats_text(func(stat: StringName) -> float: return combatant.get_effective_stat(stat))
	if not extra.is_empty():
		%Runtime.text += "\n" + extra
	_refresh_content_slots()
	_refresh_status_icons()


func refresh_cooldowns() -> void:
	if not is_instance_valid(combatant):
		return
	var abilities := _displayed_abilities()
	for index in mini(abilities.size(), %AbilityIcons.get_child_count()):
		var ability := abilities[index] as AbilityDefinition
		var slot := %AbilityIcons.get_child(index) as AbilityCooldownIcon
		var remaining := float(combatant.ability_cooldowns.get(ability.id, 0.0))
		var total := maxf(maxf(ability.cooldown_seconds, ability.initial_cooldown_seconds), remaining)
		slot.set_cooldown(remaining if ability.kind == AbilityDefinition.AbilityKind.ACTIVE else 0.0, total)
	for raw_slot in %ItemIcons.get_children():
		var slot := raw_slot as AbilityCooldownIcon
		var item := _registry().get_definition(slot.content_id, false) as ItemDefinition if not slot.content_id.is_empty() else null
		var cooldown := _item_cooldown(item)
		slot.set_cooldown(cooldown.x, cooldown.y)


## Read the item's actual battle timers; this inspector never advances them.
## Multiple item abilities share one icon, which shows the longest remaining timer.
func _item_cooldown(item: ItemDefinition) -> Vector2:
	var result := Vector2.ZERO
	if item == null:
		return result
	for ability_id in item.ability_ids:
		var ability := _registry().get_definition(ability_id, false) as AbilityDefinition
		if ability != null and ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
			var remaining := maxf(0.0, float(combatant.ability_cooldowns.get(ability_id, 0.0)))
			if remaining > result.x or result.y <= 0.0:
				var total := maxf(maxf(combatant.cooldown_for(ability), ability.initial_cooldown_seconds), remaining)
				result = Vector2(remaining, total)
		# Periodic item effects have an interval timer rather than an AI cooldown.
		for pulse in combatant.items.pulse_heals:
			if StringName(pulse.ability_id) == ability_id:
				var remaining := maxf(0.0, float(pulse.remaining))
				if remaining > result.x or result.y <= 0.0:
					result = Vector2(remaining, maxf(float(pulse.interval), remaining))
	return result


## Item abilities are shown on their item slots, not in the ability row.
func _displayed_abilities() -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	for ability in combatant.snapshot.abilities:
		if ability != null and not ability.tags.has(&"item"):
			result.append(ability)
	return result


func _refresh_content_slots() -> void:
	var abilities := _displayed_abilities()
	var ability_slot_count := maxi(HeroState.MAX_ABILITY_SLOTS, abilities.size())
	_ensure_icon_slots(%AbilityIcons, ability_slot_count, true)
	for index in ability_slot_count:
		var ability: AbilityDefinition = abilities[index] if index < abilities.size() else null
		var badge := str(index + 1)
		if ability != null:
			if ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK:
				badge = "R"
			elif ability.kind == AbilityDefinition.AbilityKind.PASSIVE:
				badge = "P"
			else:
				badge = "A"
		var slot := %AbilityIcons.get_child(index) as ContentIconButton
		slot.visible = ability != null
		var ability_id: StringName = ability.id if ability != null else &""
		if slot.content_id != ability_id or slot.custom_minimum_size == Vector2.ZERO:
			slot.configure(ability, &"ability", badge, false, ContentButton.describe_ability_definition(ability) if ability != null else "")
		else:
			slot.set_badge(badge)
		slot.custom_minimum_size = ContentIconButton.SLOT_SIZE

	%Abilities.get_node("Title").text = "ABILITIES" if not abilities.is_empty() else "NO ABILITIES"
	var show_items := not combatant.snapshot.equipped_item_definition_ids.is_empty()
	if combatant.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
		_ensure_icon_slots(%ItemIcons, HeroState.MAX_ITEM_SLOTS, true)
	%Equipment.visible = show_items
	if not show_items:
		refresh_cooldowns()
		return
	_ensure_icon_slots(%ItemIcons, HeroState.MAX_ITEM_SLOTS, true)
	for index in HeroState.MAX_ITEM_SLOTS:
		var definition: ItemDefinition
		if index < combatant.snapshot.equipped_item_definition_ids.size():
			definition = _registry().get_definition(combatant.snapshot.equipped_item_definition_ids[index], false) as ItemDefinition
		var slot := %ItemIcons.get_child(index) as ContentIconButton
		slot.visible = definition != null
		var item_id: StringName = definition.id if definition != null else &""
		if slot.content_id != item_id or slot.custom_minimum_size == Vector2.ZERO:
			slot.configure(definition, &"item", str(index + 1))
		slot.custom_minimum_size = ContentIconButton.SLOT_SIZE
	refresh_cooldowns()


## One line with every non-zero secondary stat: "Crit 25% (x2.5)  Lifesteal 25%  ...".
static func secondary_stats_text(value_of: Callable) -> String:
	var parts: Array[String] = []
	var crit: float = value_of.call(&"crit_chance")
	if crit > 0.0:
		var multiplier: float = value_of.call(&"crit_multiplier")
		parts.append("CRIT %s%% (x%s)" % [StatModifier.format_number(crit), StatModifier.format_number(multiplier if multiplier > 1.0 else CombatStats.DEFAULT_CRIT_MULTIPLIER)])
	for entry in [[&"lifesteal", "LIFESTEAL %s%%"], [&"dodge", "DODGE %s%%"], [&"hp_regen", "REGEN %s/s"], [&"cooldown_reduction", "CDR %s%%"], [&"armor_penetration", "ARMOR PEN %s%%"]]:
		var amount: float = value_of.call(entry[0])
		if amount > 0.0:
			parts.append(String(entry[1]) % StatModifier.format_number(snappedf(amount, 0.1)))
	var taken: float = value_of.call(&"damage_taken")
	if not is_zero_approx(taken):
		parts.append("DAMAGE TAKEN %s%s%%" % ["+" if taken > 0.0 else "", StatModifier.format_number(snappedf(taken, 0.1))])
	return "    ".join(parts)


func _ensure_icon_slots(container: Container, count: int, cooldown_slots := false) -> void:
	while container.get_child_count() < count:
		container.add_child(AbilityCooldownIcon.new() if cooldown_slots else ContentIconButton.new())
	while container.get_child_count() > count:
		container.get_child(container.get_child_count() - 1).free()


func _clear_icon_slots(container: Container) -> void:
	for child in container.get_children():
		child.free()


func _build_stat_grid() -> void:
	for spec in STAT_SPECS:
		var tile := MarginContainer.new()
		tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tile.add_theme_constant_override("margin_left", 2)
		tile.add_theme_constant_override("margin_top", 3)
		tile.add_theme_constant_override("margin_right", 2)
		tile.add_theme_constant_override("margin_bottom", 3)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		tile.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var texture := AtlasTexture.new()
		texture.atlas = UI_ATLAS
		texture.region = spec.region
		icon.texture = texture
		row.add_child(icon)
		var text_column := VBoxContainer.new()
		text_column.add_theme_constant_override("separation", -2)
		row.add_child(text_column)
		var value := Label.new()
		value.add_theme_color_override("font_color", Color(0.96, 0.86, 0.66))
		value.add_theme_font_size_override("font_size", 17)
		text_column.add_child(value)
		var caption := Label.new()
		caption.text = spec.caption
		caption.add_theme_color_override("font_color", Color(0.56, 0.62, 0.7))
		caption.add_theme_font_size_override("font_size", 10)
		text_column.add_child(caption)
		%StatsGrid.add_child(tile)
		stat_values[spec.key] = value
		stat_tiles[spec.key] = tile


## Highlights stats changed from the unit's base value (levels, items, act threat,
## encounter strength, buffs) so players know to hover for the explanation.
func _stat_value_color(stat: StringName) -> Color:
	var breakdown := combatant.get_stat_breakdown(stat)
	var entries: Array = breakdown.entries
	if entries.is_empty():
		return STAT_BASE_COLOR
	var base := float(entries[0].after)
	var final_value := float(breakdown.value)
	if final_value > base * 1.005 + 0.01:
		return STAT_RAISED_COLOR
	if final_value < base * 0.995 - 0.01:
		return STAT_LOWERED_COLOR
	return STAT_BASE_COLOR


func _set_control_tooltip(control: Control, text: String) -> void:
	var binding: StatTooltipBinding = control.get_meta("stat_tooltip_binding") as StatTooltipBinding if control.has_meta("stat_tooltip_binding") else null
	if binding == null:
		binding = StatTooltipBinding.new()
		binding.bind(control)
	binding.set_text(text)
	control.tooltip_text = ""
	for child in control.find_children("*", "Control", true, false):
		var child_control := child as Control
		child_control.tooltip_text = ""
		child_control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_status_icons() -> void:
	var entries := _status_entries()
	%StatusIcons.visible = not entries.is_empty()
	while %StatusIcons.get_child_count() < entries.size():
		%StatusIcons.add_child(StatusEffectIcon.new())
	while %StatusIcons.get_child_count() > entries.size():
		%StatusIcons.get_child(%StatusIcons.get_child_count() - 1).free()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var icon := %StatusIcons.get_child(index) as StatusEffectIcon
		icon.configure_status(entry.title, entry.details, entry.polarity, entry.duration, entry.stacks, entry.icon)


func _status_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var current: Dictionary = {}
	for raw_line in _statuses_text().split("\n"):
		var line := String(raw_line)
		if line.begins_with("- "):
			if not current.is_empty():
				entries.append(current)
			current = {}
			var summary := line.substr(2)
			if summary == "None":
				continue
			var title_end := summary.length()
			var colon_index := summary.find(":")
			var bracket_index := summary.find(" [")
			if colon_index >= 0:
				title_end = mini(title_end, colon_index)
			if bracket_index >= 0:
				title_end = mini(title_end, bracket_index)
			current = {
				"title": summary.left(title_end),
				"details": summary,
				"polarity": StatusDefinition.Polarity.POSITIVE if summary.contains("[BUFF") else (StatusDefinition.Polarity.NEGATIVE if summary.contains("[DEBUFF") else StatusDefinition.Polarity.NEUTRAL),
				"duration": _duration_from_summary(summary),
				"stacks": 1,
				"icon": null,
			}
		elif line.begins_with("  ") and not current.is_empty():
			current.details += "\n%s" % line.strip_edges()
	if not current.is_empty():
		entries.append(current)
	for entry in entries:
		for status in combatant.statuses:
			if status.definition != null and String(entry.title) == status.definition.display_name:
				entry.duration = status.remaining_duration
				entry.stacks = status.stacks
				entry.icon = status.definition.icon
				break
	return entries


func _duration_from_summary(summary: String) -> float:
	var end_index := summary.rfind("]")
	var separator_index := summary.rfind("| ")
	if separator_index < 0 or end_index <= separator_index:
		return -1.0
	var duration_text := summary.substr(separator_index + 2, end_index - separator_index - 2).strip_edges()
	if not duration_text.ends_with(" s"):
		return -1.0
	return duration_text.left(duration_text.length() - 2).to_float()


func status_summary_text() -> String:
	return _statuses_text()


func _statuses_text() -> String:
	var lines := PackedStringArray(["STATUSES"])
	for status in combatant.statuses:
		if status.definition == null:
			continue
		var polarity := "BUFF" if status.definition.polarity == StatusDefinition.Polarity.POSITIVE else ("DEBUFF" if status.definition.polarity == StatusDefinition.Polarity.NEGATIVE else "STATUS")
		var stacks := " x%d" % status.stacks if status.stacks > 1 else ""
		var details := ": %s" % status.definition.description if not status.definition.description.is_empty() else ""
		lines.append("- %s%s%s [%s | %s]" % [status.definition.display_name, stacks, details, polarity, _duration_text(status.remaining_duration)])
		for modifier in status.definition.stat_modifiers:
			lines.append("  %s" % _modifier_text(modifier, status.stacks))
	for entry in combatant.temporary_modifiers:
		lines.append("- %s: %s [%s | %s]" % [
			_entry_name(entry, "Stat modifier"),
			_modifier_text(entry.modifier),
			_modifier_polarity(entry.modifier),
			_duration_text(float(entry.remaining)),
		])
	for shield in combatant.shields:
		lines.append("- %s: Shield +%.1f [BUFF | %s]" % [
			_entry_name(shield, "Shield"),
			float(shield.amount),
			_duration_text(float(shield.remaining)),
		])
	for metadata in combatant.runtime_status_metadata:
		lines.append("- %s: %s [%s | %s]" % [
			String(metadata.name),
			String(metadata.details),
			String(metadata.polarity),
			_duration_text(float(metadata.remaining)),
		])
	if combatant.lust_death_scaling_percent > 0.0:
		var death_count: int = combatant.session.get_lust_allied_death_count(combatant)
		lines.append("- Fallen Devotion: %d allied deaths, HP/Damage/Armor +%.0f%% [BUFF | active]" % [death_count, death_count * combatant.lust_death_scaling_percent])
	if is_instance_valid(combatant.lust_bond_partner):
		lines.append("- Fatal Bond with %s: %.0f%% all-damage lifesteal, Attack Speed x%.1f [BUFF | permanent]" % [
			combatant.lust_bond_partner.snapshot.display_name,
			combatant.lust_bond_lifesteal_percent,
			combatant.lust_bond_attack_speed_multiplier,
		])
	var lust_slow_multiplier: float = combatant.session.get_lust_target_attack_speed_multiplier(combatant)
	if lust_slow_multiplier < 1.0:
		lines.append("- Beguiling Presence: Attack Speed -%.0f%% while targeting Lust [DEBUFF | active]" % ((1.0 - lust_slow_multiplier) * 100.0))
	var attack_speed_aura_multiplier: float = combatant.session.get_enemy_attack_speed_aura_multiplier(combatant)
	if attack_speed_aura_multiplier < 1.0:
		lines.append("- Enemy aura: Attack Speed %.0f%% [DEBUFF | active]" % ((attack_speed_aura_multiplier - 1.0) * 100.0))
	var gluttony_aura: Dictionary = combatant.session.get_gluttony_lifesteal_aura(combatant)
	if float(gluttony_aura.percent) > 0.0:
		lines.append("- Shared Feast: Basic-attack lifesteal %.0f%% [BUFF | active in aura]" % float(gluttony_aura.percent))
	if combatant.gluttony_regeneration_max_stacks > 0:
		lines.append("- Bottomless Recovery: %d/%d stacks, %.1f HP per second [BUFF | battle]" % [combatant.gluttony_regeneration_stacks, combatant.gluttony_regeneration_max_stacks, combatant.gluttony_regeneration_per_second()])
	if combatant.gluttony_damage_aura_damage > 0.0:
		lines.append("- Ravenous Miasma: %.1f damage every %.1f s within %.0f [BUFF | active]" % [combatant.gluttony_damage_aura_damage, combatant.gluttony_damage_aura_interval, combatant.gluttony_damage_aura_radius])
	if combatant.gluttony_death_explosion_damage > 0.0 and not combatant.gluttony_death_explosion_triggered:
		lines.append("- Final Course: %.1f damage within %.0f on final death [BUFF | ready]" % [combatant.gluttony_death_explosion_damage, combatant.gluttony_death_explosion_radius])
	if combatant.despair_slow_stacks > 0:
		lines.append("- Withering Touch: %d/%d stacks, Attack Speed -%.0f%% [DEBUFF | battle]" % [combatant.despair_slow_stacks, combatant.despair_slow_max_stacks, combatant.despair_slow_applied_percent])
	if combatant.despair_sanctuary_remaining > 0.0:
		lines.append("- Still Sanctuary: Action locked, hostile immunity, heals %.0f%% max HP every %.1f s [BUFF | %.1f s]" % [combatant.despair_sanctuary_heal_percent, combatant.despair_sanctuary_interval, combatant.despair_sanctuary_remaining])
	if not combatant.despair_growth_bonus_percent.is_empty():
		lines.append("- Endless Descent: HP/DMG/ARM/MOVE +%.1f%%, Attack Speed +%.1f%% [BUFF | battle]" % [
			float(combatant.despair_growth_bonus_percent.get(&"max_hp", 0.0)),
			float(combatant.despair_growth_bonus_percent.get(&"attack_speed", 0.0)),
		])
	if combatant.envy_strongest_ally_damage_percent > 0.0:
		var copied_damage: float = combatant.session.get_strongest_non_hero_ally_damage(combatant) * combatant.envy_strongest_ally_damage_percent / 100.0
		if copied_damage > 0.0:
			lines.append("- Borrowed Might: Damage +%.1f [BUFF | active]" % copied_damage)
	if combatant.basic_attack_range_bonus > 0.0:
		lines.append("- Farthest attack: Range +%.1f [BUFF | active]" % combatant.basic_attack_range_bonus)
	if combatant.snapshot.is_boss and combatant.boss_phase > 1:
		lines.append("- Boss Phase %d: Damage x%.2f, Attack Speed x%.2f [BUFF | active]" % [
			combatant.boss_phase,
			pow(combatant.snapshot.boss_phase_damage_multiplier, combatant.boss_phase - 1),
			pow(combatant.snapshot.boss_phase_attack_speed_multiplier, combatant.boss_phase - 1),
		])
	if combatant.frenzy_remaining > 0.0:
		lines.append("- %s: Attack Speed x%.2f [BUFF | %.1f s]" % [
			_content_name(combatant.frenzy_ability_id) if not combatant.frenzy_ability_id.is_empty() else "Frenzy",
			combatant.frenzy_attack_speed_multiplier,
			combatant.frenzy_remaining,
		])
	if combatant.stealth_remaining > 0.0:
		lines.append("- %s [BUFF | %.1f s]" % [
			_content_name(combatant.stealth_ability_id) if not combatant.stealth_ability_id.is_empty() else "Stealth",
			combatant.stealth_remaining,
		])
	if combatant.last_stand_remaining > 0.0:
		lines.append("- Last Stand [BUFF | %.1f s]" % combatant.last_stand_remaining)
	for empowerment in combatant.basic_attack_empowerments:
		lines.append("- %s: Basic attacks %.1f%% lifesteal, size x%.2f [BUFF | %s]" % [
			_entry_name(empowerment, "Basic attack empowerment"),
			float(empowerment.lifesteal_percent),
			float(empowerment.size_multiplier),
			_duration_text(float(empowerment.remaining)),
		])
	if lines.size() == 1:
		lines.append("- None")
	return "\n".join(lines)


func _entry_name(entry: Dictionary, fallback: String) -> String:
	var ability_id := StringName(entry.get("ability_id", &""))
	return _content_name(ability_id) if not ability_id.is_empty() else fallback


func _modifier_text(modifier: StatModifier, stacks := 1) -> String:
	return modifier.display_text(stacks)


func _modifier_polarity(modifier: StatModifier) -> String:
	var beneficial := modifier.value >= 1.0 if modifier.operation == StatModifier.Operation.MULTIPLY else modifier.value >= 0.0
	if modifier.stat == "damage_taken":
		beneficial = not beneficial
	return "BUFF" if beneficial else "DEBUFF"


func _duration_text(remaining: float) -> String:
	return "permanent" if remaining < 0.0 else "%.1f s" % remaining


func _content_name(content_id: StringName) -> String:
	var definition = _registry().get_definition(content_id, false)
	return definition.display_name if definition != null else String(content_id)


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
