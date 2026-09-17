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
		lines.append("Cooldown: %.1f s" % definition.cooldown_seconds)
		for effect in definition.effects:
			if effect is DamageEffect:
				lines.append("Damage: %.1f" % effect.amount)
			elif effect is HealEffect:
				lines.append("Healing: %.1f" % effect.amount)
			elif effect is ShieldEffect:
				lines.append("Shield: %.1f for %.1f s" % [effect.amount, effect.duration])
			elif effect is ApplyStatusEffect and effect.status != null:
				lines.append("Status: %s (%.1f s)" % [effect.status.display_name, effect.status.default_duration])
	elif definition is JobDefinition:
		lines.append("Attack: %s / AI: %s" % [definition.attack_type, definition.ai_behavior])
		lines.append("Capacity price: %d Gold" % definition.capacity_price)
		if definition.stat_modifiers != null:
			lines.append("HP %+g  DMG %+g  ARMOR %+g  RANGE %+g" % [
				definition.stat_modifiers.max_hp,
				definition.stat_modifiers.damage,
				definition.stat_modifiers.armor,
				definition.stat_modifiers.attack_range,
			])
	elif definition is StatusDefinition:
		lines.append("Duration: %.1f s / Max stacks: %d" % [definition.default_duration, definition.max_stacks])
	elif definition is ItemDefinition:
		lines.append("Target: %s / Price: %d Gold" % [definition.allowed_target_type, definition.price])
	elif definition is EncounterDefinition:
		lines.append("Reward: %d Gold / Enemies: %d" % [definition.gold_reward, definition.enemy_ids.size()])
	return "\n".join(lines)
