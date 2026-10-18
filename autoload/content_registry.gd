extends Node


const CONTENT_DIRECTORIES: Array[String] = ["res://content/demo"]
const ENCOUNTER_DIFFICULTIES: Array[String] = ["Low", "Moderate", "High", "Elite", "Boss"]
const MODIFIABLE_STATS: Array[String] = ["max_hp", "damage", "attack_speed", "movement_speed", "attack_range", "armor"]
const MIN_SELECTABLE_HEROES := 3

var definitions: Dictionary = {}
var validation_errors: PackedStringArray = []


func _ready() -> void:
	reload_content()


func reload_content() -> bool:
	definitions.clear()
	validation_errors.clear()

	var paths: Array[String] = []
	for directory in CONTENT_DIRECTORIES:
		_collect_resource_paths(directory, paths)
	paths.sort()

	for path in paths:
		var resource := ResourceLoader.load(path)
		if resource is ContentDefinition:
			register_definition(resource)
	validate_registered_definitions()

	return validation_errors.is_empty()


func register_definition(definition: ContentDefinition, report_error := true) -> bool:
	if definition == null:
		return _record_error("Cannot register a null content definition.", report_error)

	if String(definition.id).is_empty():
		return _record_error("Content definition has an empty ID.", report_error)

	if definitions.has(definition.id):
		return _record_error("Duplicate content ID: %s" % definition.id, report_error)

	var forbidden_path := _find_forbidden_value(definition, "definition:%s" % definition.id)
	if not forbidden_path.is_empty():
		return _record_error("Content definition contains Node or NodePath at %s." % forbidden_path, report_error)

	definitions[definition.id] = definition
	return true


func get_definition(content_id: StringName, report_missing := true) -> ContentDefinition:
	var definition: ContentDefinition = definitions.get(content_id)
	if definition == null:
		_record_error("Missing content ID: %s" % content_id, report_missing)
	return definition


func has_definition(content_id: StringName) -> bool:
	return definitions.has(content_id)


func get_definition_count() -> int:
	return definitions.size()


func validate_registered_definitions(report_error := true) -> bool:
	var valid := true
	var selectable_hero_orders: Dictionary = {}
	var selectable_hero_count := 0
	var route := definitions.get(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	if route == null:
		valid = _record_error("Demo route definition is missing.", report_error) and valid
	elif route.act_one_boss_wave < 2 or route.act_two_battle_count < 1:
		valid = _record_error("Demo route battle counts are invalid.", report_error) and valid
	elif route.event_absence_percent < 0.0 or route.event_absence_percent > 100.0:
		valid = _record_error("Demo route event absence percentage is outside 0..100.", report_error) and valid
	elif route.new_hero_ability_weight <= route.hero_ability_upgrade_weight or route.hero_ability_upgrade_weight <= 0.0 or route.hero_ability_upgrade_level_penalty <= 0.0:
		valid = _record_error("Demo route Hero ability reward weights are invalid.", report_error) and valid
	for definition in definitions.values():
		if definition is BossDefinition:
			if not _validate_enemy(definition, report_error) or not _validate_boss(definition, report_error):
				valid = false
		elif definition is EnemyDefinition and not _validate_enemy(definition, report_error):
			valid = false
		elif definition is JobDefinition and not _validate_job(definition, report_error):
			valid = false
		elif definition is HeroDefinition:
			if not _validate_hero(definition, report_error):
				valid = false
			if definition.available_in_new_game:
				selectable_hero_count += 1
				if selectable_hero_orders.has(definition.selection_order):
					valid = _record_error("Selectable Heroes have duplicate selection_order %d." % definition.selection_order, report_error) and valid
				selectable_hero_orders[definition.selection_order] = true
		elif definition is RunEventDefinition and not _validate_run_event(definition, report_error):
			valid = false
		elif definition is ItemDefinition and not _validate_item(definition, report_error):
			valid = false
		elif definition is AbilityDefinition and not _validate_ability(definition, report_error):
			valid = false
		elif definition is StatusDefinition and not _validate_status(definition, report_error):
			valid = false
		elif definition is EncounterDefinition and not _validate_encounter(definition, report_error):
			valid = false
	if route != null and not _validate_encounter_routes(route, report_error):
		valid = false
	if route != null:
		if not definitions.get(route.opening_event_id) is RunEventDefinition:
			valid = _record_error("Demo route references an unknown opening Run Event.", report_error) and valid
		if route.act_one_post_battle_event_ids.size() > route.act_one_boss_wave:
			valid = _record_error("Demo route defines too many Act I post-battle events.", report_error) and valid
		for event_id in route.act_one_post_battle_event_ids:
			if not String(event_id).is_empty() and not definitions.get(event_id) is RunEventDefinition:
				valid = _record_error("Demo route references an unknown post-battle Run Event %s." % event_id, report_error) and valid
	if selectable_hero_count < MIN_SELECTABLE_HEROES:
		valid = _record_error("New Game requires at least three selectable Heroes.", report_error) and valid
	return valid


func _validate_hero(hero: HeroDefinition, report_error: bool) -> bool:
	if hero.base_stats == null:
		return _record_error("Hero %s has no base stats." % hero.id, report_error)
	return true


func _validate_boss(boss: BossDefinition, report_error: bool) -> bool:
	var valid := true
	if boss.phase_count < 1 or boss.phase_health_thresholds.size() != boss.phase_count - 1:
		valid = _record_error("Boss %s phase thresholds do not match phase_count." % boss.id, report_error) and valid
	var previous := 1.0
	for threshold in boss.phase_health_thresholds:
		if threshold <= 0.0 or threshold >= previous:
			valid = _record_error("Boss %s phase thresholds must descend between zero and one." % boss.id, report_error) and valid
		previous = threshold
	if boss.phase_damage_multiplier < 1.0 or boss.phase_attack_speed_multiplier < 1.0:
		valid = _record_error("Boss %s phase multipliers cannot weaken later phases." % boss.id, report_error) and valid
	return valid


func _validate_ability(ability: AbilityDefinition, report_error: bool) -> bool:
	var valid := true
	if ability.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK and ability.kind != AbilityDefinition.AbilityKind.ACTIVE:
		valid = _record_error("Replacement ability %s must be active." % ability.id, report_error) and valid
	if ability.price < 0:
		valid = _record_error("Ability %s has a negative price." % ability.id, report_error) and valid
	if ability.targeting_policy == AbilityDefinition.TargetingPolicy.RANDOM_ENEMY_WITHOUT_STATUS:
		if String(ability.excluded_target_status_id).is_empty() or not definitions.get(ability.excluded_target_status_id) is StatusDefinition:
			valid = _record_error("Ability %s requires a valid excluded target status." % ability.id, report_error) and valid
	var hero_ids: Dictionary = {}
	for hero_id in ability.allowed_hero_ids:
		if String(hero_id).is_empty() or hero_ids.has(hero_id):
			valid = _record_error("Ability %s has an empty or duplicate allowed Hero ID." % ability.id, report_error) and valid
		elif not definitions.get(hero_id) is HeroDefinition:
			valid = _record_error("Ability %s references unknown Hero %s." % [ability.id, hero_id], report_error) and valid
		hero_ids[hero_id] = true
	if not ability.available_to_heroes and not ability.allowed_hero_ids.is_empty():
		valid = _record_error("Ability %s is unavailable to Heroes but has allowed Hero IDs." % ability.id, report_error) and valid
	if ability.available_to_heroes:
		if ability.hero_levels.size() != AbilityDefinition.MAX_HERO_ABILITY_LEVEL:
			valid = _record_error("Hero ability %s must define exactly four levels." % ability.id, report_error) and valid
		for level_index in ability.hero_levels.size():
			var level := ability.hero_levels[level_index]
			if level == null or level.effects.is_empty():
				valid = _record_error("Hero ability %s contains an invalid level." % ability.id, report_error) and valid
				continue
			if ability.delivery_method == AbilityDefinition.DeliveryMethod.AREA_AROUND_TARGET and level.area_radius <= 0.0:
				valid = _record_error("Hero ability %s Level %d has no area radius." % [ability.id, level_index + 1], report_error) and valid
			for effect in level.effects:
				if not _validate_ability_effect(ability, effect, " Level %d" % (level_index + 1), report_error):
					valid = false
	for effect in ability.effects:
		if not _validate_ability_effect(ability, effect, "", report_error):
			valid = false
	return valid


func _validate_ability_effect(ability: AbilityDefinition, effect: AbilityEffect, context: String, report_error: bool) -> bool:
	if effect == null:
		return _record_error("Ability %s%s contains a null effect." % [ability.id, context], report_error)
	if effect is ApplyStatusEffect and effect.status == null:
		return _record_error("Ability %s%s contains an empty status effect." % [ability.id, context], report_error)
	if effect is StatModifierEffect and effect.modifier == null:
		return _record_error("Ability %s%s contains an empty stat modifier effect." % [ability.id, context], report_error)
	if effect is LastStandEffect and effect.duration <= 0.0:
		return _record_error("Ability %s%s has an invalid last stand duration." % [ability.id, context], report_error)
	if effect is FarthestAttackEffect and effect.attack_range_bonus <= 0.0:
		return _record_error("Ability %s%s has an invalid attack range bonus." % [ability.id, context], report_error)
	if effect is CleanseEffect and ability.targeting_policy != AbilityDefinition.TargetingPolicy.NEAREST_NEGATIVE_STATUS_ALLY:
		return _record_error("Cleanse ability %s%s must target the nearest affected ally." % [ability.id, context], report_error)
	if effect is SacrificeSoldierEffect and (effect.radius <= 0.0 or effect.stat_gain_percent <= 0.0):
		return _record_error("Ability %s%s has invalid sacrifice values." % [ability.id, context], report_error)
	if effect is MeleeTeleportEffect and (effect.distance <= 0.0 or effect.cooldown_seconds <= 0.0):
		return _record_error("Ability %s%s has invalid melee teleport values." % [ability.id, context], report_error)
	if effect is AttackSpeedAuraEffect and (effect.radius <= 0.0 or effect.multiplier < 0.0 or effect.multiplier >= 1.0):
		return _record_error("Ability %s%s has invalid attack speed aura values." % [ability.id, context], report_error)
	if effect is BasicAttackEmpowerEffect and (effect.lifesteal_percent < 0.0 or effect.size_multiplier <= 0.0 or effect.duration <= 0.0):
		return _record_error("Ability %s%s has invalid basic attack empowerment values." % [ability.id, context], report_error)
	if effect is GoldArmyScalingEffect and effect.percent_per_gold <= 0.0:
		return _record_error("Ability %s%s has an invalid Gold scaling percentage." % [ability.id, context], report_error)
	if effect is ItemStatScalingEffect and effect.bonus_percent <= 0.0:
		return _record_error("Ability %s%s has an invalid item scaling percentage." % [ability.id, context], report_error)
	if effect is TeleportStealthEffect and effect.duration <= 0.0:
		return _record_error("Ability %s%s has an invalid stealth duration." % [ability.id, context], report_error)
	if effect is KillRewardEffect and (effect.gold_per_kill <= 0 or effect.permanent_damage_per_kill <= 0.0):
		return _record_error("Ability %s%s has invalid kill rewards." % [ability.id, context], report_error)
	if effect is RadialEnemyDamageEffect and (effect.radius <= 0.0 or effect.damage <= 0.0):
		return _record_error("Ability %s%s has invalid radial damage values." % [ability.id, context], report_error)
	if effect is SmokeBombEffect and (effect.radius <= 0.0 or effect.activation_enemy_radius <= 0.0 or effect.duration <= 0.0 or effect.dodge_percent <= 0.0 or effect.dodge_percent > 100.0):
		return _record_error("Ability %s%s has invalid smoke bomb values." % [ability.id, context], report_error)
	if effect is MeleeRetaliationEffect and (effect.radius <= 0.0 or effect.damage_multiplier <= 0.0):
		return _record_error("Ability %s%s has invalid melee retaliation values." % [ability.id, context], report_error)
	if effect is AttackReflectEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.reflect_percent <= 0.0 or effect.reflect_percent > 100.0):
		return _record_error("Ability %s%s has an invalid attack reflection percentage." % [ability.id, context], report_error)
	if effect is FocusedDamageEffect and (effect.damage_per_stack <= 0.0 or effect.stack_duration <= 0.0):
		return _record_error("Ability %s%s has invalid focused damage values." % [ability.id, context], report_error)
	if effect is FrenzyEffect and (effect.attack_speed_multiplier <= 0.0 or effect.duration <= 0.0):
		return _record_error("Ability %s%s has invalid frenzy values." % [ability.id, context], report_error)
	if effect is LeapSlamEffect and (effect.damage <= 0.0 or effect.impact_radius <= 0.0 or effect.knockback_distance <= 0.0 or effect.stun_duration <= 0.0):
		return _record_error("Ability %s%s has invalid leap slam values." % [ability.id, context], report_error)
	if effect is ThresholdGuardEffect and (effect.health_threshold <= 0.0 or effect.health_threshold > 1.0 or effect.shield_max_hp_multiplier <= 0.0 or effect.armor_multiplier <= 0.0 or effect.duration <= 0.0 or effect.cooldown_seconds <= 0.0):
		return _record_error("Ability %s%s has invalid threshold guard values." % [ability.id, context], report_error)
	if effect is GroundSlamEffect and (effect.damage_multiplier <= 0.0 or effect.radius <= 0.0):
		return _record_error("Ability %s%s has invalid ground slam values." % [ability.id, context], report_error)
	if effect is EnvyStatTheftEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.steal_percent <= 0.0 or effect.duration <= 0.0):
		return _record_error("Ability %s%s has invalid Envy stat theft values." % [ability.id, context], report_error)
	if effect is EnvyStrongestAllyDamageEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.bonus_percent <= 0.0):
		return _record_error("Ability %s%s has an invalid Envy damage-copy percentage." % [ability.id, context], report_error)
	if effect is EnvyIllusionEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.stat_percent <= 0.0 or effect.max_active_summons < 1):
		return _record_error("Ability %s%s has invalid Envy illusion values." % [ability.id, context], report_error)
	if effect is EnvyExecuteEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.health_threshold <= 0.0 or effect.health_threshold > 1.0):
		return _record_error("Ability %s%s has an invalid Envy execute threshold." % [ability.id, context], report_error)
	if effect is EnvyPostCombatXpEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.bonus_percent <= 0.0):
		return _record_error("Ability %s%s has an invalid Envy XP bonus." % [ability.id, context], report_error)
	if effect is EnvyDartVolleyEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.damage <= 0.0 or effect.movement_slow_percent <= 0.0 or effect.movement_slow_percent >= 100.0 or effect.max_targets < 1):
		return _record_error("Ability %s%s has invalid Envy dart values." % [ability.id, context], report_error)
	if effect is LustGuardTauntEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.activation_radius <= 0.0 or effect.ally_radius <= 0.0 or effect.armor_bonus <= 0.0 or effect.duration <= 0.0):
		return _record_error("Ability %s%s has invalid Lust guard values." % [ability.id, context], report_error)
	if effect is LustDeathScalingEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.percent_per_death <= 0.0):
		return _record_error("Ability %s%s has invalid Lust death scaling." % [ability.id, context], report_error)
	if effect is LustRecruitEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.hp_threshold <= 0.0 or effect.radius <= 0.0):
		return _record_error("Ability %s%s has invalid Lust recruitment values." % [ability.id, context], report_error)
	if effect is LustTargetSlowEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.slow_percent <= 0.0 or effect.slow_percent >= 100.0):
		return _record_error("Ability %s%s has an invalid Lust target slow." % [ability.id, context], report_error)
	if effect is LustBondEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.lifesteal_percent <= 0.0 or effect.attack_speed_multiplier <= 1.0):
		return _record_error("Ability %s%s has invalid Lust bond values." % [ability.id, context], report_error)
	if effect is LustBasicKnockbackEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.hits_required < 1 or effect.knockback_distance <= 0.0 or effect.stun_duration <= 0.0):
		return _record_error("Ability %s%s has invalid Lust basic attack values." % [ability.id, context], report_error)
	if effect is GluttonyLifestealAuraEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.radius <= 0.0 or effect.lifesteal_percent <= 0.0 or effect.lifesteal_percent > 100.0):
		return _record_error("Ability %s%s has invalid Gluttony lifesteal aura values." % [ability.id, context], report_error)
	if effect is GluttonyRegenerationEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.max_stacks < 1 or effect.max_hp_percent_per_stack <= 0.0):
		return _record_error("Ability %s%s has invalid Gluttony regeneration values." % [ability.id, context], report_error)
	if effect is GluttonyDamageAuraEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.radius <= 0.0 or effect.damage <= 0.0 or effect.interval <= 0.0):
		return _record_error("Ability %s%s has invalid Gluttony damage aura values." % [ability.id, context], report_error)
	if effect is GluttonySiphonEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.CLOSEST_ENEMY or ability.delivery_method != AbilityDefinition.DeliveryMethod.MELEE_HIT or effect.damage <= 0.0):
		return _record_error("Ability %s%s has invalid Gluttony siphon values." % [ability.id, context], report_error)
	if effect is GluttonyDeathExplosionEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.radius <= 0.0 or effect.damage <= 0.0):
		return _record_error("Ability %s%s has invalid Gluttony death explosion values." % [ability.id, context], report_error)
	if effect is GluttonyGreaseEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.CLOSEST_ENEMY or ability.delivery_method != AbilityDefinition.DeliveryMethod.AREA_AROUND_TARGET or effect.miss_percent <= 0.0 or effect.miss_percent > 100.0 or effect.duration <= 0.0):
		return _record_error("Ability %s%s has invalid Gluttony grease values." % [ability.id, context], report_error)
	if effect is DespairTeamProcEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.proc_chance_percent <= 0.0 or effect.proc_chance_percent > 100.0 or effect.total_damage_percent < 100.0):
		return _record_error("Ability %s%s has invalid Despair team proc values." % [ability.id, context], report_error)
	if effect is DespairAttackSlowEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.max_stacks < 1 or effect.attack_speed_reduction_per_stack <= 0.0 or effect.maximum_reduction_percent <= 0.0 or effect.maximum_reduction_percent > 80.0):
		return _record_error("Ability %s%s has invalid Despair attack slow values." % [ability.id, context], report_error)
	if effect is DespairSleepEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.CLOSEST_ENEMY or effect.duration <= 0.0):
		return _record_error("Ability %s%s has invalid Despair sleep values." % [ability.id, context], report_error)
	if effect is DespairSanctuaryEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.health_threshold <= 0.0 or effect.health_threshold > 1.0 or effect.max_hp_heal_percent <= 0.0 or effect.duration <= 0.0 or effect.interval <= 0.0):
		return _record_error("Ability %s%s has invalid Despair sanctuary values." % [ability.id, context], report_error)
	if effect is DespairVinesEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.target_count < 1 or effect.damage <= 0.0 or effect.duration <= 0.0 or effect.interval <= 0.0):
		return _record_error("Ability %s%s has invalid Despair vines values." % [ability.id, context], report_error)
	if effect is DespairGrowthEffect and (ability.kind != AbilityDefinition.AbilityKind.PASSIVE or effect.max_hp_percent_per_second <= 0.0 or effect.damage_percent_per_second <= 0.0 or effect.armor_percent_per_second <= 0.0 or effect.movement_speed_percent_per_second <= 0.0 or effect.attack_speed_percent_per_second <= 0.0 or effect.maximum_bonus_percent <= 0.0 or effect.interval <= 0.0):
		return _record_error("Ability %s%s has invalid Despair growth values." % [ability.id, context], report_error)
	if effect is DespairPressureShieldEffect and (ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or effect.shield_amount <= 0.0 or effect.attack_speed_multiplier <= 0.0 or effect.attack_speed_multiplier >= 1.0 or effect.duration <= 0.0):
		return _record_error("Ability %s%s has invalid Despair pressure shield values." % [ability.id, context], report_error)
	if effect is SummonEffect:
		var summon := effect as SummonEffect
		if ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or ability.delivery_method != AbilityDefinition.DeliveryMethod.INSTANT:
			return _record_error("Summon ability %s%s must be active, self-targeted, and instant." % [ability.id, context], report_error)
		if summon.summoned_unit == null or not definitions.get(summon.summoned_unit.id) is EnemyDefinition or summon.summoned_unit is BossDefinition:
			return _record_error("Ability %s%s has an invalid summoned unit." % [ability.id, context], report_error)
		if summon.max_active_summons < 1:
			return _record_error("Ability %s%s has an invalid active summon limit." % [ability.id, context], report_error)
		if summon.summoner_contribution_percent < 0.0 or summon.summoner_contribution_percent > 100.0:
			return _record_error("Ability %s%s has a summon contribution percentage outside 0..100." % [ability.id, context], report_error)
	if effect is SummonMergeEffect:
		var merge := effect as SummonMergeEffect
		if ability.kind != AbilityDefinition.AbilityKind.ACTIVE or ability.targeting_policy != AbilityDefinition.TargetingPolicy.SELF or ability.delivery_method != AbilityDefinition.DeliveryMethod.INSTANT:
			return _record_error("Summon merge ability %s%s must be active, self-targeted, and instant." % [ability.id, context], report_error)
		if merge.merged_unit == null or not definitions.get(merge.merged_unit.id) is EnemyDefinition or merge.merged_unit is BossDefinition:
			return _record_error("Ability %s%s has an invalid merged summon unit." % [ability.id, context], report_error)
		if merge.stat_multiplier <= 0.0 or merge.attack_speed_bonus_per_summon < 0.0 or merge.duration <= 0.0 or merge.minimum_summons < 2:
			return _record_error("Ability %s%s has invalid summon merge values." % [ability.id, context], report_error)
		if merge.summoner_contribution_percent < 0.0 or merge.summoner_contribution_percent > 100.0:
			return _record_error("Ability %s%s has a merge contribution percentage outside 0..100." % [ability.id, context], report_error)
	return true


func _validate_status(status: StatusDefinition, report_error: bool) -> bool:
	var valid := true
	if status.max_stacks < 1 or status.default_duration < 0.0 or status.periodic_interval < 0.0:
		valid = _record_error("Status %s has invalid duration, interval, or stack values." % status.id, report_error) and valid
	if status.breaks_on_hp_damage and not status.prevents_actions:
		valid = _record_error("Status %s breaks on HP damage without preventing actions." % status.id, report_error) and valid
	if status.grants_negative_status_immunity and status.polarity != StatusDefinition.Polarity.POSITIVE:
		valid = _record_error("Status %s grants negative-status immunity without positive polarity." % status.id, report_error) and valid
	if status.periodic_interval > 0.0 and status.periodic_effects.is_empty():
		valid = _record_error("Status %s has an interval without periodic effects." % status.id, report_error) and valid
	return valid


func _validate_job(job: JobDefinition, report_error: bool) -> bool:
	var valid := true
	if job.stat_modifiers == null:
		valid = _record_error("Job %s has no stat modifiers." % job.id, report_error) and valid
	var seen: Dictionary = {}
	for ability_id in job.innate_ability_ids + job.available_ability_ids:
		if String(ability_id).is_empty() or seen.has(ability_id):
			valid = _record_error("Job %s has an empty or duplicate ability ID." % job.id, report_error) and valid
		elif not definitions.get(ability_id) is AbilityDefinition:
			valid = _record_error("Job %s references unknown ability %s." % [job.id, ability_id], report_error) and valid
		seen[ability_id] = true
	if job.professionalism_thresholds.size() != job.professionalism_ability_ids.size():
		valid = _record_error("Job %s professionalism thresholds and abilities must have equal lengths." % job.id, report_error) and valid
	var previous_threshold := 0
	for threshold in job.professionalism_thresholds:
		if threshold <= previous_threshold:
			valid = _record_error("Job %s professionalism thresholds must be positive and increasing." % job.id, report_error) and valid
		previous_threshold = threshold
	var professionalism_ids: Dictionary = {}
	for ability_id in job.professionalism_ability_ids:
		if String(ability_id).is_empty() or professionalism_ids.has(ability_id):
			valid = _record_error("Job %s has an empty or duplicate professionalism ability ID." % job.id, report_error) and valid
		elif not definitions.get(ability_id) is AbilityDefinition:
			valid = _record_error("Job %s references unknown professionalism ability %s." % [job.id, ability_id], report_error) and valid
		professionalism_ids[ability_id] = true
	return valid


func _validate_enemy(enemy: EnemyDefinition, report_error: bool) -> bool:
	var valid := true
	if enemy.base_stats == null:
		valid = _record_error("Enemy %s has no base stats." % enemy.id, report_error) and valid
	var seen: Dictionary = {}
	for ability_id in enemy.ability_ids:
		if String(ability_id).is_empty() or seen.has(ability_id):
			valid = _record_error("Enemy %s has an empty or duplicate ability ID." % enemy.id, report_error) and valid
		elif not definitions.get(ability_id) is AbilityDefinition:
			valid = _record_error("Enemy %s references unknown ability %s." % [enemy.id, ability_id], report_error) and valid
		seen[ability_id] = true
	return valid


func _validate_run_event(event: RunEventDefinition, report_error: bool) -> bool:
	var valid := true
	if event.weight < 0.0 or event.nodes.is_empty() or String(event.entry_node_id).is_empty():
		valid = _record_error("Run Event %s has invalid weight or an empty graph." % event.id, report_error) and valid
	if not definitions.get(event.theme_hero_id) is HeroDefinition:
		valid = _record_error("Run Event %s references an unknown theme Hero %s." % [event.id, event.theme_hero_id], report_error) and valid
	for condition in event.conditions:
		if not _validate_run_event_condition(event, condition, false, report_error):
			valid = false
	var node_ids: Dictionary = {}
	for node in event.nodes:
		if node == null or String(node.node_id).is_empty() or node_ids.has(node.node_id):
			valid = _record_error("Run Event %s has a null, empty, or duplicate node." % event.id, report_error) and valid
			continue
		node_ids[node.node_id] = true
		if node.choices.is_empty():
			valid = _record_error("Run Event %s node %s has no choices." % [event.id, node.node_id], report_error) and valid
		var choice_ids: Dictionary = {}
		for choice in node.choices:
			if choice == null or String(choice.choice_id).is_empty() or choice.text.is_empty() or choice_ids.has(choice.choice_id):
				valid = _record_error("Run Event %s node %s has an invalid choice." % [event.id, node.node_id], report_error) and valid
				continue
			choice_ids[choice.choice_id] = true
			for condition in choice.conditions:
				if not _validate_run_event_condition(event, condition, true, report_error):
					valid = false
			for effect in choice.effects:
				if not _validate_run_event_effect(event, effect, report_error):
					valid = false
	if not node_ids.has(event.entry_node_id):
		valid = _record_error("Run Event %s entry node is missing." % event.id, report_error) and valid
	for node in event.nodes:
		if node == null:
			continue
		for choice in node.choices:
			if choice != null and not String(choice.next_node_id).is_empty() and not node_ids.has(choice.next_node_id):
				valid = _record_error("Run Event %s choice %s references a missing node." % [event.id, choice.choice_id], report_error) and valid
	for job_id in event.target_allowed_job_ids:
		if not definitions.get(job_id) is JobDefinition:
			valid = _record_error("Run Event %s references unknown target Job %s." % [event.id, job_id], report_error) and valid
	var reachable: Dictionary = {event.entry_node_id: true}
	var frontier: Array[StringName] = [event.entry_node_id]
	while not frontier.is_empty():
		var current_id: StringName = frontier.pop_back()
		var current: RunEventNode = event.get_node_definition(current_id)
		if current == null:
			continue
		for choice in current.choices:
			if choice != null and not String(choice.next_node_id).is_empty() and not reachable.has(choice.next_node_id):
				reachable[choice.next_node_id] = true
				frontier.append(choice.next_node_id)
	if reachable.size() != node_ids.size():
		valid = _record_error("Run Event %s contains unreachable nodes." % event.id, report_error) and valid
	return valid


func _validate_run_event_condition(event: RunEventDefinition, condition: RunEventCondition, choice_condition: bool, report_error: bool) -> bool:
	if condition == null or condition.minimum > condition.maximum:
		return _record_error("Run Event %s contains an invalid condition." % event.id, report_error)
	if condition.condition_type == RunEventCondition.ConditionType.TARGET_VETERANCY_RANGE:
		if not choice_condition or condition.target_index < 0 or condition.target_index >= event.soldier_target_count:
			return _record_error("Run Event %s has an invalid target condition." % event.id, report_error)
	elif condition.condition_type == RunEventCondition.ConditionType.HERO_AVAILABLE and not definitions.get(condition.content_id) is HeroDefinition:
		return _record_error("Run Event %s condition references an unknown Hero." % event.id, report_error)
	elif condition.condition_type == RunEventCondition.ConditionType.JOB_UNLOCKED and not definitions.get(condition.content_id) is JobDefinition:
		return _record_error("Run Event %s condition references an unknown Job." % event.id, report_error)
	elif condition.condition_type == RunEventCondition.ConditionType.HAS_ITEM and not definitions.get(condition.content_id) is ItemDefinition:
		return _record_error("Run Event %s condition references an unknown item." % event.id, report_error)
	return true


func _validate_run_event_effect(event: RunEventDefinition, effect: RunEventEffect, report_error: bool) -> bool:
	if effect == null or String(effect.effect_id).is_empty():
		return _record_error("Run Event %s contains an invalid effect." % event.id, report_error)
	var valid := true
	match effect.effect_type:
		RunEventEffect.EffectType.GRANT_ITEM:
			if not definitions.get(effect.content_id) is ItemDefinition:
				valid = _record_error("Run Event %s references an unknown item." % event.id, report_error) and valid
		RunEventEffect.EffectType.GRANT_HERO_ABILITY:
			var ability := definitions.get(effect.content_id) as AbilityDefinition
			var hero := definitions.get(effect.hero_definition_id) as HeroDefinition
			if ability == null or hero == null or not ability.is_allowed_for_hero(hero.id):
				valid = _record_error("Run Event %s has an invalid Hero ability reward." % event.id, report_error) and valid
		RunEventEffect.EffectType.GRANT_JOB_ABILITY:
			var ability := definitions.get(effect.content_id) as AbilityDefinition
			var job := definitions.get(effect.job_id) as JobDefinition
			if ability == null or job == null or not job.available_ability_ids.has(ability.id):
				valid = _record_error("Run Event %s has an invalid Job ability reward." % event.id, report_error) and valid
		RunEventEffect.EffectType.STAT_MODIFIER:
			if effect.stat not in MODIFIABLE_STATS or effect.modifier_operation not in StatModifier.Operation.values() or effect.battles_remaining == 0 or effect.battles_remaining < -1 or not is_finite(effect.modifier_value):
				valid = _record_error("Run Event %s has an invalid stat modifier." % event.id, report_error) and valid
		RunEventEffect.EffectType.HERO_LEVEL_DELTA:
			if effect.amount == 0 or not definitions.get(effect.hero_definition_id) is HeroDefinition:
				valid = _record_error("Run Event %s has an invalid Hero level effect." % event.id, report_error) and valid
		RunEventEffect.EffectType.SOLDIER_VETERANCY_DELTA:
			if effect.amount == 0 or (not effect.all_soldier_targets and (effect.target_index < 0 or effect.target_index >= event.soldier_target_count)):
				valid = _record_error("Run Event %s has an invalid Soldier Veterancy effect." % event.id, report_error) and valid
		RunEventEffect.EffectType.JOB_CAPACITY_DELTA:
			if effect.amount == 0 or effect.job_id == &"job.militia" or not definitions.get(effect.job_id) is JobDefinition:
				valid = _record_error("Run Event %s has an invalid Job capacity effect." % event.id, report_error) and valid
		RunEventEffect.EffectType.GOLD_DELTA, RunEventEffect.EffectType.HERO_XP_DELTA:
			if effect.amount == 0:
				valid = _record_error("Run Event %s has an empty numeric reward." % event.id, report_error) and valid
		RunEventEffect.EffectType.GRANT_RANDOM_HERO_ITEM:
			pass
	if effect.effect_type == RunEventEffect.EffectType.STAT_MODIFIER:
		if effect.target_scope == RunEventEffect.TargetScope.HERO and not definitions.get(effect.hero_definition_id) is HeroDefinition:
			valid = _record_error("Run Event %s stat effect references an unknown Hero." % event.id, report_error) and valid
		elif effect.target_scope == RunEventEffect.TargetScope.JOB and not definitions.get(effect.job_id) is JobDefinition:
			valid = _record_error("Run Event %s stat effect references an unknown Job." % event.id, report_error) and valid
		elif effect.target_scope == RunEventEffect.TargetScope.SOLDIER_TARGET and not effect.all_soldier_targets and (effect.target_index < 0 or effect.target_index >= event.soldier_target_count):
			valid = _record_error("Run Event %s stat effect references an unavailable Soldier target." % event.id, report_error) and valid
	return valid


func _validate_encounter(encounter: EncounterDefinition, report_error: bool) -> bool:
	var valid := true
	if encounter.min_encounter_index > encounter.max_encounter_index:
		valid = _record_error("Encounter %s has an invalid index range." % encounter.id, report_error) and valid
	if encounter.enemy_ids.is_empty():
		valid = _record_error("Encounter %s has no enemies." % encounter.id, report_error) and valid
	if not ENCOUNTER_DIFFICULTIES.has(encounter.difficulty_hint):
		valid = _record_error("Encounter %s has an invalid difficulty hint." % encounter.id, report_error) and valid
	if not encounter.is_unknown and encounter.key_properties.is_empty():
		valid = _record_error("Known encounter %s must describe its key properties." % encounter.id, report_error) and valid
	if encounter.is_boss and encounter.difficulty_hint != "Boss":
		valid = _record_error("Boss encounter %s must use the Boss difficulty hint." % encounter.id, report_error) and valid
	if encounter.is_boss and encounter.act != 1:
		valid = _record_error("Boss encounter %s is outside the supported Act I Boss route." % encounter.id, report_error) and valid
	for enemy_id in encounter.enemy_ids:
		if not definitions.get(enemy_id) is EnemyDefinition:
			valid = _record_error("Encounter %s references unknown enemy %s." % [encounter.id, enemy_id], report_error) and valid
	if encounter.has_reinforcements():
		if encounter.reinforcement_alive_threshold < 0 or encounter.reinforcement_alive_threshold > 2:
			valid = _record_error("Reinforcement encounter %s has a threshold outside 0..2." % encounter.id, report_error) and valid
		if encounter.enemy_ids.size() <= encounter.reinforcement_alive_threshold:
			valid = _record_error("Reinforcement encounter %s starts at or below its reinforcement threshold." % encounter.id, report_error) and valid
		if encounter.reinforcement_entry_direction not in [EncounterDefinition.ReinforcementEntryDirection.ALL_SIDES, EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE]:
			valid = _record_error("Reinforcement encounter %s has an invalid entry direction." % encounter.id, report_error) and valid
		for enemy_id in encounter.reinforcement_enemy_ids:
			if not definitions.get(enemy_id) is EnemyDefinition:
				valid = _record_error("Reinforcement encounter %s references unknown reinforcement enemy %s." % [encounter.id, enemy_id], report_error) and valid
	if encounter.is_unknown and encounter.is_boss:
		valid = _record_error("Boss encounter %s cannot hide its composition." % encounter.id, report_error) and valid
	return valid


func _validate_encounter_routes(route: RouteDefinition, report_error: bool) -> bool:
	var valid := true
	for definition in definitions.values():
		if not definition is EncounterDefinition:
			continue
		var encounter := definition as EncounterDefinition
		var final_index := route.final_encounter_index(encounter.act)
		if not encounter.is_boss and (encounter.min_encounter_index < 0 or encounter.max_encounter_index > final_index):
			valid = _record_error("Encounter %s falls outside the Demo route." % encounter.id, report_error) and valid
	for act in [1, 2]:
		var final_index := route.final_encounter_index(act)
		for battle_index in range(final_index + 1):
			var known: Array[EncounterDefinition] = []
			var unknown: Array[EncounterDefinition] = []
			for definition in definitions.values():
				if not definition is EncounterDefinition:
					continue
				var encounter := definition as EncounterDefinition
				if encounter.act != act:
					continue
				var is_boss_wave: bool = act == 1 and battle_index == route.act_one_boss_index()
				if encounter.is_boss != is_boss_wave:
					continue
				if not encounter.is_boss and (battle_index < encounter.min_encounter_index or battle_index > encounter.max_encounter_index):
					continue
				if encounter.is_unknown:
					unknown.append(encounter)
				else:
					known.append(encounter)
			if act == 1 and battle_index == 0:
				if not definitions.get(DemoRunFactory.FIRST_ENCOUNTER_ID) is EncounterDefinition:
					valid = _record_error("The fixed tutorial Encounter is missing.", report_error) and valid
				continue
			if known.size() < EncounterGenerator.MIN_CARDS:
				valid = _record_error("Act %d battle %d needs at least two known Encounter Cards." % [act, battle_index + 1], report_error) and valid
			if unknown.size() > 1:
				valid = _record_error("Act %d battle %d has more than one Unknown Encounter." % [act, battle_index + 1], report_error) and valid
			if act == 1 and battle_index == route.act_one_boss_index():
				if not unknown.is_empty():
					valid = _record_error("Final Act I routes cannot be Unknown Encounters.", report_error) and valid
				for encounter in known:
					if not encounter.is_boss:
						valid = _record_error("Every final Act I route must be a Boss Encounter.", report_error) and valid
			else:
				for encounter in known:
					if encounter.is_boss:
						valid = _record_error("Boss encounter %s appears before the end of Act I." % encounter.id, report_error) and valid
			if not unknown.is_empty() and not known.is_empty():
				var highest_known_reward := 0
				for encounter in known:
					highest_known_reward = maxi(highest_known_reward, encounter.gold_reward)
				if unknown[0].gold_reward <= highest_known_reward:
					valid = _record_error("Unknown Encounter must pay more than known routes in its layer.", report_error) and valid
	return valid


func _validate_item(item: ItemDefinition, report_error: bool) -> bool:
	var valid := true
	if item.hero_eligibility not in ItemDefinition.HeroEligibility.values():
		valid = _record_error("Item %s has invalid Hero eligibility." % item.id, report_error) and valid
	for modifier in item.passive_effects:
		if modifier == null or not MODIFIABLE_STATS.has(modifier.stat):
			valid = _record_error("Item %s has an invalid passive stat modifier." % item.id, report_error) and valid
	return valid


func _collect_resource_paths(directory_path: String, paths: Array[String]) -> void:
	var entries := ResourceLoader.list_directory(directory_path)
	if entries.is_empty():
		if not DirAccess.dir_exists_absolute(directory_path):
			_record_error("Content directory does not exist: %s" % directory_path, true)
		return
	for entry in entries:
		if entry.ends_with("/"):
			_collect_resource_paths(directory_path.path_join(entry.trim_suffix("/")), paths)
		elif entry.get_extension() == "tres":
			paths.append(directory_path.path_join(entry))


func _find_forbidden_value(value: Variant, path: String) -> String:
	if value is Node or value is NodePath:
		return path

	if value is Resource:
		for property in value.get_property_list():
			if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				continue
			var property_name: StringName = property.name
			var forbidden_path := _find_forbidden_value(value.get(property_name), "%s.%s" % [path, property_name])
			if not forbidden_path.is_empty():
				return forbidden_path
	elif value is Array:
		for index in value.size():
			var forbidden_path := _find_forbidden_value(value[index], "%s[%d]" % [path, index])
			if not forbidden_path.is_empty():
				return forbidden_path
	elif value is Dictionary:
		for key in value:
			var forbidden_path := _find_forbidden_value(value[key], "%s[%s]" % [path, key])
			if not forbidden_path.is_empty():
				return forbidden_path

	return ""


func _record_error(message: String, report_error: bool) -> bool:
	validation_errors.append(message)
	if report_error:
		push_error(message)
	return false
