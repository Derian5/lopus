class_name HeroAbilityRewardPopup
extends Control


signal offer_selected(offer_id: String)

var run_state: RunState


func show_pending(new_run_state: RunState) -> void:
	run_state = new_run_state
	if run_state == null or run_state.pending_hero_ability_reward.is_empty():
		visible = false
		return
	_clear_offers()
	%Feedback.text = ""
	var first_button: Button
	for offer in run_state.pending_hero_ability_reward.offers:
		var hero := _find_hero(offer.hero_unique_id)
		var hero_definition := _registry().get_definition(hero.definition_id, false) as HeroDefinition if hero != null else null
		var ability := _registry().get_definition(offer.ability_id, false) as AbilityDefinition
		if hero_definition == null or ability == null:
			continue
		var target_level := HeroAbilityRewardService.offer_level(run_state, offer)
		var leveled := ability.for_hero_level(target_level)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 112)
		button.text = "%s\n%s  %s\n%s\n%s" % [
			hero_definition.display_name.to_upper(),
			ability.display_name,
			"NEW - LEVEL 1" if hero.ability_level(ability.id) == 0 else "LEVEL %d -> %d" % [target_level - 1, target_level],
			ability.description,
			_level_summary(leveled),
		]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_offer_pressed.bind(offer.offer_id))
		%Offers.add_child(button)
		if first_button == null:
			first_button = button
	visible = true
	if first_button != null:
		first_button.grab_focus()


func set_feedback(message: String) -> void:
	%Feedback.text = message


func _level_summary(ability: AbilityDefinition) -> String:
	var parts: PackedStringArray = []
	if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
		parts.append("Cooldown %.1fs" % ability.cooldown_seconds)
	if ability.area_radius > 0.0:
		parts.append("Radius %.0f" % ability.area_radius)
	for effect in ability.effects:
		if effect is DamageEffect:
			parts.append("Damage %.1f" % effect.amount)
		elif effect is HealEffect:
			parts.append("Healing %.1f" % effect.amount)
		elif effect is ShieldEffect:
			parts.append("Shield %.1f / %.1fs" % [effect.amount, effect.duration])
		elif effect is StatModifierEffect:
			parts.append("Buff %.1fs" % effect.duration)
		elif effect is SummonEffect:
			parts.append("Summons %d max" % effect.max_active_summons)
		elif effect is LastStandEffect:
			parts.append("Last stand %.0fs" % effect.duration)
		elif effect is FarthestAttackEffect:
			parts.append("Range +%.0f" % effect.attack_range_bonus)
		elif effect is CleanseEffect:
			parts.append("Cleanses 1 debuff")
		elif effect is SacrificeSoldierEffect:
			parts.append("Gain %.0f%% stats" % effect.stat_gain_percent)
		elif effect is MeleeTeleportEffect:
			parts.append("Teleport %.0f" % effect.distance)
		elif effect is AttackSpeedAuraEffect:
			parts.append("Slow %.0f%% / Radius %.0f" % [(1.0 - effect.multiplier) * 100.0, effect.radius])
	return "  |  ".join(parts)


func _find_hero(unique_id: String) -> HeroState:
	for hero in run_state.heroes:
		if hero.unique_id == unique_id:
			return hero
	return null


func _on_offer_pressed(offer_id: String) -> void:
	offer_selected.emit(offer_id)


func _clear_offers() -> void:
	for child in %Offers.get_children():
		child.visible = false
		child.queue_free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
