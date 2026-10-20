class_name ContentButton
extends Button


const TOOLTIP_SCENE := preload("res://ui/common/content_tooltip.tscn")
const TOOLTIP_OFFSET := Vector2(18.0, 18.0)

var content_id: StringName
var tooltip_override := ""
var _hover_generation := 0

static var active_tooltip: ContentTooltip
static var active_tooltip_owner: ContentButton


func _init() -> void:
	# Scaling the tooltip owner makes Godot repeatedly dismiss and recreate its popup.
	set_meta("disable_auto_motion", true)
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	tooltip_text = ""
	mouse_entered.connect(_on_tooltip_mouse_entered)
	mouse_exited.connect(_on_tooltip_mouse_exited)
	tree_exiting.connect(_on_tooltip_owner_exiting)


func _get_tooltip(_at_position: Vector2) -> String:
	# Content tooltips use a stable owner-managed popup instead of Godot's dismiss/recreate lifecycle.
	return ""


func _create_content_tooltip(text: String) -> ContentTooltip:
	var tooltip: ContentTooltip = TOOLTIP_SCENE.instantiate()
	tooltip.setup(text)
	return tooltip


func _on_tooltip_mouse_entered() -> void:
	if _content_tooltip_text().is_empty():
		return
	_hover_generation += 1
	var generation := _hover_generation
	var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	await get_tree().create_timer(maxf(delay, 0.0)).timeout
	if generation == _hover_generation and is_inside_tree() and _pointer_inside():
		_show_custom_tooltip()


func _on_tooltip_mouse_exited() -> void:
	_hover_generation += 1
	_hide_custom_tooltip()


func _on_tooltip_owner_exiting() -> void:
	_hover_generation += 1
	_hide_custom_tooltip()


func _show_custom_tooltip() -> void:
	var tooltip_text_value := _content_tooltip_text()
	if tooltip_text_value.is_empty():
		_hide_custom_tooltip()
		return
	if active_tooltip_owner == self and is_instance_valid(active_tooltip):
		return
	_hide_active_tooltip()
	active_tooltip = _create_content_tooltip(tooltip_text_value)
	active_tooltip_owner = self
	get_tree().root.add_child(active_tooltip)
	active_tooltip.size = active_tooltip.custom_minimum_size
	active_tooltip.z_as_relative = false
	active_tooltip.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	var mouse_position := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	var tooltip_position := mouse_position + TOOLTIP_OFFSET
	if tooltip_position.x + active_tooltip.size.x > viewport_size.x:
		tooltip_position.x = mouse_position.x - active_tooltip.size.x - TOOLTIP_OFFSET.x
	if tooltip_position.y + active_tooltip.size.y > viewport_size.y:
		tooltip_position.y = mouse_position.y - active_tooltip.size.y - TOOLTIP_OFFSET.y
	active_tooltip.position = tooltip_position.max(Vector2.ZERO)


func _hide_custom_tooltip() -> void:
	if active_tooltip_owner == self:
		_hide_active_tooltip()


static func _hide_active_tooltip() -> void:
	if is_instance_valid(active_tooltip):
		active_tooltip.queue_free()
	active_tooltip = null
	active_tooltip_owner = null


func _pointer_inside() -> bool:
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())


func _content_tooltip_text() -> String:
	if not tooltip_override.is_empty():
		return tooltip_override
	if String(content_id).is_empty():
		return ""
	return describe_content(content_id)


const ITEM_STAT_ICONS := {
	"damage": "damage", "max_hp": "heal", "armor": "shield", "attack_speed": "buff", "movement_speed": "buff",
	"crit_chance": "damage", "crit_multiplier": "damage", "lifesteal": "heal", "dodge": "shield",
	"hp_regen": "heal", "cooldown_reduction": "cooldown", "damage_taken": "debuff", "armor_penetration": "damage",
}


## MOBA-style item card: category, stat lines with icons, item abilities, price.
static func describe_item(item: ItemDefinition, registry: Node) -> String:
	var lines: Array[String] = []
	lines.append("[font_size=21][color=%s][b]%s[/b][/color][/font_size]" % [AbilityText.TITLE, item.display_name.to_upper()])
	var kind := "%s ITEM" % ItemDefinition.category_name(item.category).to_upper()
	if item.is_unique():
		var names: Array[String] = []
		for hero_id in item.allowed_hero_ids:
			var hero := registry.get_definition(hero_id, false) as HeroDefinition
			names.append(hero.display_name if hero != null else String(hero_id))
		kind = "UNIQUE  -  %s ONLY" % ", ".join(names).to_upper()
	elif item.hero_eligibility != ItemDefinition.HeroEligibility.ANY:
		kind += "  -  %s" % item.eligibility_text().to_upper()
	lines.append("[color=%s]%s[/color]" % [AbilityText.MUTED, kind])
	lines.append("")
	for modifier in item.passive_effects:
		if modifier == null:
			continue
		var text := modifier.display_text()
		var split := text.find(" ")
		var number := text.substr(0, split) if split > 0 else text
		var label := text.substr(split + 1) if split > 0 else ""
		lines.append("%s [b]%s[/b] %s" % [AbilityText.icon(String(ITEM_STAT_ICONS.get(modifier.stat, "buff"))), number, label])
	for ability_id in item.ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		if ability == null:
			continue
		lines.append("")
		var passive := ability.kind == AbilityDefinition.AbilityKind.PASSIVE
		var header := "%s [color=%s]%s[/color]  [color=%s][b]%s[/b][/color]" % [AbilityText.icon("passive" if passive else "active"), AbilityText.MUTED, "PASSIVE" if passive else "ACTIVE", AbilityText.TITLE, ability.display_name]
		lines.append(header)
		var stats := AbilityText.stat_line(ability)
		if not stats.is_empty():
			lines.append(stats)
		lines.append("[color=%s]%s[/color]" % [AbilityText.BODY, AbilityText.render(ability)])
	if not item.description.is_empty():
		lines.append("")
		lines.append("[i][color=%s]%s[/color][/i]" % [AbilityText.MUTED, item.description])
	lines.append("%s [color=%s]%d Gold[/color]   [color=%s]sells for %d[/color]" % [AbilityText.icon("gold"), AbilityText.TAG_STYLES.gold.color, item.price, AbilityText.MUTED, item.sell_price])
	return "\n".join(lines)


static func describe_content(content_id: StringName) -> String:
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("ContentRegistry")
	if registry == null:
		return String(content_id)
	var definition: ContentDefinition = registry.get_definition(content_id, false)
	if definition == null:
		return String(content_id)
	if definition is AbilityDefinition:
		return describe_ability_definition(definition)
	var lines := PackedStringArray([definition.display_name.to_upper(), definition.description])
	if definition is JobDefinition:
		return describe_job(definition, registry)
	elif definition is StatusDefinition:
		_describe_status(lines, definition, registry, "", false)
	elif definition is ItemDefinition:
		return describe_item(definition, registry)
	elif definition is EncounterDefinition:
		lines.append("Reward: %d Gold / Initial enemies: %d" % [definition.gold_reward, definition.enemy_ids.size()])
		if definition.has_reinforcements():
			var direction := "Right side" if definition.reinforcement_entry_direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE else "All sides"
			var enemy_word := "enemy" if definition.reinforcement_alive_threshold == 1 else "enemies"
			lines.append("Reinforcements: %d at %d %s remaining" % [definition.reinforcement_enemy_ids.size(), definition.reinforcement_alive_threshold, enemy_word])
			lines.append("Reinforcement entry: %s" % direction)
	lines[0] = "[font_size=21][color=%s][b]%s[/b][/color][/font_size]" % [AbilityText.TITLE, lines[0]]
	return "\n".join(lines)


## MOBA-style ability tooltip (see AbilityText). level 0 shows every hero level;
## leveled runtime copies (AbilityDefinition.for_hero_level) highlight their own level.
## Job tooltip: role, prices, innate abilities and purchasable skill levels.
static func describe_job(job: JobDefinition, registry: Node) -> String:
	var lines: Array[String] = ["[font_size=21][color=%s][b]%s[/b][/color][/font_size]" % [AbilityText.TITLE, job.display_name.to_upper()]]
	lines.append("[color=%s]%s[/color]" % [AbilityText.BODY, job.description])
	if job.unlock_price > 0 or job.capacity_price > 0:
		lines.append("%s [color=%s]Unlock %d  /  +1 capacity %d Gold[/color]" % [AbilityText.icon("gold"), AbilityText.MUTED, job.unlock_price, job.capacity_price])
	if not job.innate_ability_ids.is_empty():
		lines.append("")
		lines.append("[color=%s]INNATE[/color]" % AbilityText.MUTED)
		for ability_id in job.innate_ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition
			if ability != null:
				lines.append("[b]%s[/b]  %s" % [ability.display_name, AbilityText.render(ability)])
	if not job.available_ability_ids.is_empty():
		lines.append("")
		lines.append("[color=%s]MARKET SKILLS[/color]" % AbilityText.MUTED)
		for ability_id in job.available_ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition
			if ability != null:
				lines.append("[b]Level %d: %s[/b]  -  %d Gold" % [ability.job_skill_level(registry), ability.display_name, ability.price])
	return "\n".join(lines)


static func describe_ability_definition(ability: AbilityDefinition, level := 0, extra_lines: Array[String] = []) -> String:
	if ability == null:
		return ""
	if level <= 0 and ability.has_meta(&"hero_level"):
		level = int(ability.get_meta(&"hero_level"))
	var lines := extra_lines.duplicate()
	if ability.price > 0:
		lines.append("")
		lines.append("%s [color=%s]%d Gold[/color]" % [AbilityText.icon("gold"), AbilityText.TAG_STYLES.gold.color, ability.price])
	return AbilityText.tooltip(ability, level, lines)


static func _describe_ability(lines: PackedStringArray, ability: AbilityDefinition, registry: Node) -> void:
	lines.append("")
	var traits := PackedStringArray(["ACTIVE" if ability.kind == AbilityDefinition.AbilityKind.ACTIVE else "PASSIVE"])
	if ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK:
		traits.append("ATTACK MODIFIER")
	if ability.delivery_method == AbilityDefinition.DeliveryMethod.PROJECTILE:
		traits.append("PROJECTILE")
	elif ability.area_radius > 0.0:
		traits.append("AREA")
	lines.append(" | ".join(traits))
	var metrics := PackedStringArray()
	if ability.kind == AbilityDefinition.AbilityKind.ACTIVE:
		metrics.append("Cooldown: %s s" % _compact_number(ability.cooldown_seconds))
		if ability.initial_cooldown_seconds > 0.0:
			metrics.append("Starts after: %s s" % _compact_number(ability.initial_cooldown_seconds))
	if ability.target_search_radius > 0.0:
		metrics.append("Search: %s" % _compact_number(ability.target_search_radius))
	if ability.cast_range > 0.0:
		metrics.append("Range: %s" % _compact_number(ability.cast_range))
	if ability.area_radius > 0.0:
		metrics.append("Radius: %s" % _compact_number(ability.area_radius))
	if not metrics.is_empty():
		lines.append(" | ".join(metrics))
	for effect in ability.effects:
		_describe_effect(lines, effect, registry, "", false)
	if ability.price > 0:
		lines.append("Cost: %d Gold" % ability.price)


static func _describe_effect(lines: PackedStringArray, effect: AbilityEffect, registry: Node, prefix: String, include_status_details: bool) -> void:
	if effect is DamageEffect:
		lines.append("%sDamage: %s" % [prefix, _compact_number(effect.amount)])
	elif effect is HealEffect:
		var veterancy_text := " (+%s%% per Veterancy)" % _compact_number(effect.veterancy_bonus_percent_per_level) if effect.veterancy_bonus_percent_per_level > 0.0 else ""
		lines.append("%sHealing: %s%s" % [prefix, _compact_number(effect.amount), veterancy_text])
	elif effect is ShieldEffect:
		lines.append("%sShield: %s | Duration: %s" % [prefix, _compact_number(effect.amount), _duration_text(effect.duration)])
	elif effect is StatModifierEffect:
		lines.append("%s%s for %s" % [prefix, _modifier_text(effect.modifier), _duration_text(effect.duration)])
	elif effect is ApplyStatusEffect and effect.status != null:
		lines.append("%sApplies: %s" % [prefix, effect.status.display_name])
		if include_status_details:
			_describe_status(lines, effect.status, registry, "  ", true)
	elif effect is SummonEffect and effect.summoned_unit != null:
		lines.append("%sSummons %s (max alive: %d / owner contribution: %.0f%%)" % [prefix, effect.summoned_unit.display_name, effect.max_active_summons, effect.summoner_contribution_percent])
	elif effect is SummonMergeEffect and effect.merged_unit != null:
		lines.append("%sMerges owned summons into %s for %.1f s: summed HP, damage, and armor x%.1f; base attack speed +%.0f%% per summon" % [prefix, effect.merged_unit.display_name, effect.duration, effect.stat_multiplier, effect.attack_speed_bonus_per_summon * 100.0])
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
	elif effect is GoldArmyScalingEffect:
		lines.append("%sArmy stats +%.2f%% per unspent Gold (except movement)" % [prefix, effect.percent_per_gold])
	elif effect is ItemStatScalingEffect:
		lines.append("%sEquipped item stats +%.0f%%" % [prefix, effect.bonus_percent])
	elif effect is TeleportStealthEffect:
		lines.append("%sTeleport to farthest enemy; stealth %.1f s" % [prefix, effect.duration])
	elif effect is KillRewardEffect:
		lines.append("%sPersonal kill: +%d Gold and +%.1f permanent damage" % [prefix, effect.gold_per_kill, effect.permanent_damage_per_kill])
	elif effect is RadialEnemyDamageEffect:
		lines.append("%sDamage: %s" % [prefix, _compact_number(effect.damage)])
	elif effect is SmokeBombEffect:
		lines.append("%sEnemy within %.0f: smoke radius %.0f for %.1f s; %.0f%% dodge" % [prefix, effect.activation_enemy_radius, effect.radius, effect.duration, effect.dodge_percent])
	elif effect is MeleeRetaliationEffect:
		lines.append("%sAllies within %.0f retaliate at x%.1f damage" % [prefix, effect.radius, effect.damage_multiplier])
	elif effect is AttackReflectEffect:
		lines.append("%sReflects %.0f%% of basic attack HP damage to the attacker" % [prefix, effect.reflect_percent])
	elif effect is FocusedDamageEffect:
		lines.append("%sSame-target hits gain +%.1f damage per independent %.1f s stack" % [prefix, effect.damage_per_stack, effect.stack_duration])
	elif effect is FrenzyEffect:
		lines.append("%sAfter first enemy damage + 3 s: attack speed x%.1f for %.1f s; random movement and friendly fire" % [prefix, effect.attack_speed_multiplier, effect.duration])
	elif effect is LeapSlamEffect:
		lines.append("%sDamage: %s | Knockback: %s | Stun: %s s" % [prefix, _compact_number(effect.damage), _compact_number(effect.knockback_distance), _compact_number(effect.stun_duration)])
	elif effect is ThresholdGuardEffect:
		lines.append("%sAt %.0f%% HP: shield x%.1f max HP and armor x%.1f for %.1f s (%.1f s cooldown)" % [prefix, effect.health_threshold * 100.0, effect.shield_max_hp_multiplier, effect.armor_multiplier, effect.duration, effect.cooldown_seconds])
	elif effect is GroundSlamEffect:
		lines.append("%sNext attack: x%.1f damage within %.0f around target" % [prefix, effect.damage_multiplier, effect.radius])
	elif effect is EnvyStatTheftEffect:
		lines.append("%sSteal %.0f%% max HP, damage, attack speed, and armor for %.1f s" % [prefix, effect.steal_percent, effect.duration])
	elif effect is EnvyStrongestAllyDamageEffect:
		lines.append("%sDamage +%.0f%% of strongest allied non-Hero's current damage" % [prefix, effect.bonus_percent])
	elif effect is EnvyIllusionEffect:
		lines.append("%sIllusion of strongest non-boss enemy at %.0f%% current stats, with exact current movement speed; basic attacks only" % [prefix, effect.stat_percent])
	elif effect is EnvyExecuteEffect:
		lines.append("%sExecute a non-boss enemy at or below %.0f%% HP" % [prefix, effect.health_threshold * 100.0])
	elif effect is EnvyPostCombatXpEffect:
		lines.append("%sHero XP and surviving Soldier Veterancy XP +%.0f%%" % [prefix, effect.bonus_percent])
	elif effect is EnvyDartVolleyEffect:
		lines.append("%sUp to %d enemies: %.1f poison damage every second and permanent %.0f%% movement slow (non-stacking)" % [prefix, effect.max_targets, effect.damage, effect.movement_slow_percent])
	elif effect is LustGuardTauntEffect:
		lines.append("%sEnemy within %.0f; highest-max-HP other ally within %.0f gains +%.0f armor and globally taunts enemies for %.1f s" % [prefix, effect.activation_radius, effect.ally_radius, effect.armor_bonus, effect.duration])
	elif effect is LustDeathScalingEffect:
		lines.append("%sMax HP, damage, and armor +%.0f%% per allied death" % [prefix, effect.percent_per_death])
	elif effect is LustRecruitEffect:
		lines.append("%sRecruit nearest non-boss enemy within %.0f below %.0f current HP" % [prefix, effect.radius, effect.hp_threshold])
	elif effect is LustTargetSlowEffect:
		lines.append("%sEnemies targeting Lust attack %.0f%% slower" % [prefix, effect.slow_percent])
	elif effect is LustBondEffect:
		lines.append("%sBond: %.0f%% all-damage lifesteal, attack speed x%.1f, shared death" % [prefix, effect.lifesteal_percent, effect.attack_speed_multiplier])
	elif effect is LustBasicKnockbackEffect:
		lines.append("%sEvery %d successful basic hits: knockback %.0f, stun %.1f s" % [prefix, effect.hits_required, effect.knockback_distance, effect.stun_duration])
	elif effect is GluttonyLifestealAuraEffect:
		lines.append("%sAllies within %.0f gain %.0f%% basic-attack lifesteal" % [prefix, effect.radius, effect.lifesteal_percent])
	elif effect is GluttonyRegenerationEffect:
		lines.append("%sEnemy basic HP hits grant up to %d stacks; each heals %.1f%% current max HP per second" % [prefix, effect.max_stacks, effect.max_hp_percent_per_stack])
	elif effect is GluttonyDamageAuraEffect:
		lines.append("%s%.1f damage every %.1f s to enemies within %.0f" % [prefix, effect.damage, effect.interval, effect.radius])
	elif effect is GluttonySiphonEffect:
		lines.append("%sMelee damage %.1f; heal for actual damage dealt" % [prefix, effect.damage])
	elif effect is GluttonyDeathExplosionEffect:
		lines.append("%sOn final death: %.1f damage to enemies within %.0f" % [prefix, effect.damage, effect.radius])
	elif effect is GluttonyGreaseEffect:
		lines.append("%sBasic attacks miss %.0f%% for %.1f s" % [prefix, effect.miss_percent, effect.duration])
	elif effect is DespairTeamProcEffect:
		lines.append("%sAllied basic attacks: %.0f%% chance for %.0f%% total damage" % [prefix, effect.proc_chance_percent, effect.total_damage_percent])
	elif effect is DespairAttackSlowEffect:
		lines.append("%sHP-damaging basic hits: -%.0f%% attack speed per stack, max %d stacks / %.0f%%" % [prefix, effect.attack_speed_reduction_per_stack, effect.max_stacks, effect.maximum_reduction_percent])
	elif effect is DespairSleepEffect:
		lines.append("%sSleep %.1f s; breaks on HP damage" % [prefix, effect.duration])
	elif effect is DespairSanctuaryEffect:
		lines.append("%sOther ally below %.0f%% HP: untargetable by enemies, action locked, heals %.0f%% max HP every %.1f s for %.1f s" % [prefix, effect.health_threshold * 100.0, effect.max_hp_heal_percent, effect.interval, effect.duration])
	elif effect is DespairVinesEffect:
		lines.append("%s%d distinct random enemies: root and %.1f armored damage every %.1f s for %.1f s" % [prefix, effect.target_count, effect.damage, effect.interval, effect.duration])
	elif effect is DespairGrowthEffect:
		lines.append("%sPer second: HP +%.1f%%, damage +%.1f%%, armor +%.1f%%, movement +%.1f%%, attack speed +%.1f%%; each caps at +%.0f%%" % [prefix, effect.max_hp_percent_per_second, effect.damage_percent_per_second, effect.armor_percent_per_second, effect.movement_speed_percent_per_second, effect.attack_speed_percent_per_second, effect.maximum_bonus_percent])
	elif effect is DespairPressureShieldEffect:
		lines.append("%sMost-targeted ally: %.0f shield and attack speed x%.2f for %.1f s" % [prefix, effect.shield_amount, effect.attack_speed_multiplier, effect.duration])
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
	elif status.prevents_movement:
		lines.append("%sPrevents movement" % prefix)
	if status.breaks_on_hp_damage:
		lines.append("%sBreaks after HP damage" % prefix)
	if status.grants_negative_status_immunity:
		lines.append("%sImmune to new negative statuses" % prefix)
	for modifier in status.stat_modifiers:
		lines.append("%s%s" % [prefix, _modifier_text(modifier)])
	if status.periodic_interval > 0.0:
		lines.append("%sEvery %.1f s per stack:" % [prefix, status.periodic_interval])
		for effect in status.periodic_effects:
			_describe_effect(lines, effect, registry, "%s- " % prefix, false)


static func _modifier_text(modifier: StatModifier) -> String:
	if modifier == null:
		return "Invalid stat modifier"
	return modifier.display_text()


static func _duration_text(duration: float) -> String:
	return "Unlimited" if duration <= 0.0 else "%s s" % _compact_number(duration)


static func _compact_number(value: float) -> String:
	return "%.0f" % value if is_equal_approx(value, roundf(value)) else "%.1f" % value
