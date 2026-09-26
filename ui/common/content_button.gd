class_name ContentButton
extends Button


const TOOLTIP_SCENE := preload("res://ui/common/content_tooltip.tscn")

var content_id: StringName
var tooltip_override := ""


func _make_custom_tooltip(_for_text: String) -> Object:
	var tooltip: ContentTooltip = TOOLTIP_SCENE.instantiate()
	tooltip.setup(tooltip_override if not tooltip_override.is_empty() else describe_content(content_id))
	return tooltip


static func describe_content(content_id: StringName) -> String:
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("ContentRegistry")
	if registry == null:
		return String(content_id)
	var definition: ContentDefinition = registry.get_definition(content_id, false)
	if definition == null:
		return String(content_id)
	var lines := PackedStringArray([definition.display_name.to_upper(), definition.description])
	if definition is AbilityDefinition:
		_describe_ability(lines, definition, registry)
	elif definition is JobDefinition:
		lines.append("Attack: %s / AI: %s" % [definition.attack_type, definition.ai_behavior])
		lines.append("Unlock: %d Gold / Capacity: %d Gold" % [definition.unlock_price, definition.capacity_price])
		if not definition.innate_ability_ids.is_empty():
			var innate_names := PackedStringArray()
			for ability_id in definition.innate_ability_ids:
				var ability := registry.get_definition(ability_id, false) as AbilityDefinition
				innate_names.append(ability.display_name if ability != null else String(ability_id))
			lines.append("Innate: %s" % ", ".join(innate_names))
		if definition.stat_modifiers != null:
			lines.append("HP %.1f  DMG %.1f  ARMOR %.1f  RANGE %.1f" % [
				definition.stat_modifiers.max_hp,
				definition.stat_modifiers.damage,
				definition.stat_modifiers.armor,
				definition.stat_modifiers.attack_range,
			])
	elif definition is StatusDefinition:
		_describe_status(lines, definition, registry, "", false)
	elif definition is ItemDefinition:
		lines.append("Rarity: %s" % definition.rarity.to_upper())
		lines.append("Target: %s" % String(definition.allowed_target_type).capitalize())
		if definition.allowed_job_ids.is_empty():
			lines.append("Jobs: Any")
		else:
			var job_names := PackedStringArray()
			for job_id in definition.allowed_job_ids:
				var job: ContentDefinition = registry.get_definition(job_id, false)
				job_names.append(job.display_name if job != null else String(job_id))
			lines.append("Jobs: %s" % ", ".join(job_names))
		lines.append("Effects:")
		for modifier in definition.passive_effects:
			lines.append("- %s" % _modifier_text(modifier))
		lines.append("Buy: %d Gold / Sell: %d Gold" % [definition.price, definition.sell_price])
	elif definition is EncounterDefinition:
		lines.append("Reward: %d Gold / Initial enemies: %d" % [definition.gold_reward, definition.enemy_ids.size()])
		if definition.has_reinforcements():
			var direction := "Right side" if definition.reinforcement_entry_direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE else "All sides"
			var enemy_word := "enemy" if definition.reinforcement_alive_threshold == 1 else "enemies"
			lines.append("Reinforcements: %d at %d %s remaining" % [definition.reinforcement_enemy_ids.size(), definition.reinforcement_alive_threshold, enemy_word])
			lines.append("Reinforcement entry: %s" % direction)
	return "\n".join(lines)


static func _describe_ability(lines: PackedStringArray, ability: AbilityDefinition, registry: Node) -> void:
	var kind: String = String(AbilityDefinition.AbilityKind.keys()[ability.kind]).capitalize()
	var targeting: String = String(AbilityDefinition.TargetingPolicy.keys()[ability.targeting_policy]).capitalize().replace("_", " ")
	var delivery: String = String(AbilityDefinition.DeliveryMethod.keys()[ability.delivery_method]).capitalize().replace("_", " ")
	lines.append("Type: %s" % kind)
	lines.append("Target: %s" % targeting)
	lines.append("Delivery: %s" % delivery)
	if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
		lines.append("Cooldown: %.1f s" % ability.cooldown_seconds)
	if ability.delivery_method == AbilityDefinition.DeliveryMethod.AREA_AROUND_TARGET:
		lines.append("Area radius: %.1f" % ability.area_radius)
	if ability.targeting_policy == AbilityDefinition.TargetingPolicy.RANDOM_ENEMY_WITHOUT_STATUS:
		var excluded_status := registry.get_definition(ability.excluded_target_status_id, false) as StatusDefinition
		lines.append("Excludes targets with: %s" % (excluded_status.display_name if excluded_status != null else String(ability.excluded_target_status_id)))
	if not ability.available_to_heroes:
		lines.append("Heroes: None")
	elif ability.allowed_hero_ids.is_empty():
		lines.append("Heroes: Any")
	else:
		var hero_names := PackedStringArray()
		for hero_id in ability.allowed_hero_ids:
			var hero := registry.get_definition(hero_id, false) as HeroDefinition
			hero_names.append(hero.display_name if hero != null else String(hero_id))
		lines.append("Heroes: %s" % ", ".join(hero_names))
	lines.append("Effects:")
	for effect in ability.effects:
		_describe_effect(lines, effect, registry, "- ", true)
	lines.append("Rarity: %s / Buy: %d Gold" % [ability.rarity.to_upper(), ability.price])


static func _describe_effect(lines: PackedStringArray, effect: AbilityEffect, registry: Node, prefix: String, include_status_details: bool) -> void:
	if effect is DamageEffect:
		lines.append("%sDamage %.1f" % [prefix, effect.amount])
	elif effect is HealEffect:
		lines.append("%sHealing %.1f" % [prefix, effect.amount])
	elif effect is ShieldEffect:
		lines.append("%sShield %.1f for %s" % [prefix, effect.amount, _duration_text(effect.duration)])
	elif effect is StatModifierEffect:
		lines.append("%s%s for %s" % [prefix, _modifier_text(effect.modifier), _duration_text(effect.duration)])
	elif effect is ApplyStatusEffect and effect.status != null:
		lines.append("%sApplies %s" % [prefix, effect.status.display_name])
		if include_status_details:
			_describe_status(lines, effect.status, registry, "  ", true)
	elif effect is SummonEffect and effect.summoned_unit != null:
		lines.append("%sSummons %s (max alive: %d / owner contribution: %.0f%%)" % [prefix, effect.summoned_unit.display_name, effect.max_active_summons, effect.summoner_contribution_percent])
	elif effect is LastStandEffect:
		lines.append("%sLast stand %.1f s" % [prefix, effect.duration])
	elif effect is FarthestAttackEffect:
		lines.append("%sAttack range +%.0f; targets farthest enemy" % [prefix, effect.attack_range_bonus])
	elif effect is CleanseEffect:
		lines.append("%sRemoves one random negative status" % prefix)
	elif effect is SacrificeSoldierEffect:
		lines.append("%sSacrifice radius %.0f; permanent stat gain %.0f%%" % [prefix, effect.radius, effect.stat_gain_percent])
	elif effect is MeleeTeleportEffect:
		lines.append("%sTeleport %.0f after melee damage (%.1f s cooldown)" % [prefix, effect.distance, effect.cooldown_seconds])
	elif effect is AttackSpeedAuraEffect:
		lines.append("%sEnemy attack speed x%.2f within %.0f" % [prefix, effect.multiplier, effect.radius])
	elif effect is BasicAttackEmpowerEffect:
		lines.append("%sBasic attack lifesteal %.0f%% / Size x%.2f for %.1f s" % [prefix, effect.lifesteal_percent, effect.size_multiplier, effect.duration])
	else:
		lines.append("%s%s" % [prefix, effect.get_class()])


static func _describe_status(lines: PackedStringArray, status: StatusDefinition, registry: Node, prefix: String, include_description: bool) -> void:
	if include_description and not status.description.is_empty():
		lines.append("%s%s" % [prefix, status.description])
	var policy: String = String(StatusDefinition.StackPolicy.keys()[status.stack_policy]).capitalize().replace("_", " ")
	var polarity: String = String(StatusDefinition.Polarity.keys()[status.polarity]).capitalize()
	lines.append("%sPolarity: %s" % [prefix, polarity])
	var duration := "Until battle ends" if status.default_duration <= 0.0 else "%.1f s" % status.default_duration
	lines.append("%sDuration: %s / Max stacks: %d / Stack policy: %s" % [prefix, duration, status.max_stacks, policy])
	if status.prevents_actions:
		lines.append("%sPrevents all actions" % prefix)
	for modifier in status.stat_modifiers:
		lines.append("%s%s" % [prefix, _modifier_text(modifier)])
	if status.periodic_interval > 0.0:
		lines.append("%sEvery %.1f s per stack:" % [prefix, status.periodic_interval])
		for effect in status.periodic_effects:
			_describe_effect(lines, effect, registry, "%s- " % prefix, false)


static func _modifier_text(modifier: StatModifier) -> String:
	if modifier == null:
		return "Invalid stat modifier"
	var stat_name := modifier.stat.replace("_", " ").capitalize()
	if modifier.operation == StatModifier.Operation.MULTIPLY:
		return "%s x%.2f" % [stat_name, modifier.value]
	return "%s %+.1f" % [stat_name, modifier.value]


static func _duration_text(duration: float) -> String:
	return "unlimited" if duration <= 0.0 else "%.1f s" % duration
