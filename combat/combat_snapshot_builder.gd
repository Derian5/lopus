class_name CombatSnapshotBuilder
extends RefCounted


const MILITIA_BASE_HP := 105.0
const MILITIA_BASE_DAMAGE := 10.0
const MILITIA_BASE_ATTACK_SPEED := 1.0
const MILITIA_BASE_MOVEMENT_SPEED := 108.0
const MILITIA_BASE_ATTACK_RANGE := 46.0
const MILITIA_BASE_ARMOR := 2.0


static func build_player_army(run_state: RunState, registry: Node) -> Array[CombatUnitSnapshot]:
	var result: Array[CombatUnitSnapshot] = []
	var assignment_counts := job_assignment_counts(run_state)
	for hero in run_state.heroes:
		if hero.life_state == HeroState.ALIVE:
			var snapshot := build_hero(hero, run_state.inventory, registry)
			if snapshot != null:
				snapshot.formation_position = FormationService.position_for(run_state, hero.unique_id)
				result.append(snapshot)
	for soldier in run_state.soldiers:
		var job := registry.get_definition(soldier.current_job_id, false) as JobDefinition
		var professionalism_ability_id := professionalism_ability_id(job, int(assignment_counts.get(soldier.current_job_id, 0)))
		var snapshot := build_soldier(soldier, _find_job_build(run_state, soldier.current_job_id), registry, professionalism_ability_id)
		if snapshot != null:
			snapshot.formation_position = FormationService.position_for(run_state, soldier.unique_id)
			result.append(snapshot)
	_apply_gold_army_scaling(result, run_state.gold)
	return result


static func build_hero(hero: HeroState, inventory: InventoryState, registry: Node) -> CombatUnitSnapshot:
	var definition := registry.get_definition(hero.definition_id, false) as HeroDefinition
	if definition == null:
		return null
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = hero.unique_id
	snapshot.definition_id = definition.id
	snapshot.display_name = definition.display_name
	snapshot.team = CombatUnitSnapshot.Team.PLAYER
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	snapshot.attack_type = &"ranged" if definition.tags.has(&"ranged") else &"melee"
	snapshot.targeting_mode = hero.targeting_mode
	snapshot.damage_avoidance_override = hero.damage_avoidance_override
	snapshot.stats = CombatStats.from_stat_block(definition.base_stats)
	snapshot.stats.begin_breakdowns("Base: %s" % definition.display_name)
	var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
	if progression != null:
		var gained_levels := maxf(hero.level - 1, 0)
		_multiply_stat(snapshot.stats, &"max_hp", 1.0 + gained_levels * progression.hero_max_hp_growth_per_level, "Hero Level %d" % hero.level)
		_multiply_stat(snapshot.stats, &"damage", 1.0 + gained_levels * progression.hero_damage_growth_per_level, "Hero Level %d" % hero.level)
		_multiply_stat(snapshot.stats, &"attack_speed", 1.0 + gained_levels * progression.hero_attack_speed_growth_per_level, "Hero Level %d" % hero.level)
		_multiply_stat(snapshot.stats, &"movement_speed", 1.0 + gained_levels * progression.hero_movement_speed_growth_per_level, "Hero Level %d" % hero.level)
		_multiply_stat(snapshot.stats, &"attack_range", 1.0 + gained_levels * progression.hero_attack_range_growth_per_level, "Hero Level %d" % hero.level)
		_multiply_stat(snapshot.stats, &"armor", 1.0 + gained_levels * progression.hero_armor_growth_per_level, "Hero Level %d" % hero.level)
	snapshot.placeholder_color = definition.placeholder_color
	snapshot.abilities = _hero_abilities(hero, definition, registry)
	snapshot.post_combat_xp_bonus_percent = _post_combat_xp_bonus(snapshot.abilities)
	var item_modifier_multiplier := _item_modifier_multiplier(snapshot.abilities)
	var modifiers := _runtime_modifier_entries(hero.stat_modifiers, registry, "Permanent modifier")
	modifiers.append_array(_collect_item_modifier_entries(snapshot, hero.item_ids, inventory, registry, item_modifier_multiplier))
	_apply_modifier_entries(snapshot.stats, modifiers)
	return snapshot


static func build_soldier(
	soldier: SoldierState,
	job_build: JobBuildState,
	registry: Node,
	professionalism_ability_id: StringName = &""
) -> CombatUnitSnapshot:
	var job := registry.get_definition(soldier.current_job_id, false) as JobDefinition
	if job == null:
		return null
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = soldier.unique_id
	snapshot.definition_id = job.id
	snapshot.display_name = soldier.display_name(job.display_name)
	snapshot.team = CombatUnitSnapshot.Team.PLAYER
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER
	snapshot.job_id = job.id
	snapshot.veterancy_level = soldier.veterancy_level
	snapshot.attack_type = job.attack_type
	snapshot.targeting_mode = soldier.targeting_mode
	snapshot.damage_avoidance_override = soldier.damage_avoidance_override
	snapshot.stats.max_hp = MILITIA_BASE_HP
	snapshot.stats.damage = MILITIA_BASE_DAMAGE
	snapshot.stats.attack_speed = MILITIA_BASE_ATTACK_SPEED
	snapshot.stats.movement_speed = MILITIA_BASE_MOVEMENT_SPEED
	snapshot.stats.attack_range = MILITIA_BASE_ATTACK_RANGE
	snapshot.stats.armor = MILITIA_BASE_ARMOR
	snapshot.stats.begin_breakdowns("Base: Militia")
	_add_stat_block(snapshot.stats, job.stat_modifiers, "Job: %s" % job.display_name)
	apply_veterancy_growth(snapshot.stats, snapshot.veterancy_level, registry)
	snapshot.placeholder_color = job.placeholder_color
	var modifiers: Array[Dictionary] = []
	if job_build != null:
		modifiers.append_array(_runtime_modifier_entries(job_build.stat_modifiers, registry, "Job build"))
	modifiers.append_array(_runtime_modifier_entries(soldier.stat_modifiers, registry, "Permanent modifier"))
	_apply_modifier_entries(snapshot.stats, modifiers)
	_add_abilities(snapshot, job.innate_ability_ids, registry)
	if job_build != null:
		var ability_ids: Array[StringName] = []
		if job.available_ability_ids.has(job_build.active_ability_id):
			ability_ids.append(job_build.active_ability_id)
		for ability_id in job_build.passive_ability_ids:
			if job.available_ability_ids.has(ability_id):
				ability_ids.append(ability_id)
		_add_abilities(snapshot, ability_ids, registry)
	if not professionalism_ability_id.is_empty():
		_add_abilities(snapshot, [professionalism_ability_id], registry)
	_apply_priest_heal_veterancy(snapshot)
	return snapshot


static func job_assignment_counts(run_state: RunState) -> Dictionary:
	var counts: Dictionary = {}
	for soldier in run_state.soldiers:
		counts[soldier.current_job_id] = int(counts.get(soldier.current_job_id, 0)) + 1
	return counts


static func job_assignment_count(run_state: RunState, job_id: StringName) -> int:
	return int(job_assignment_counts(run_state).get(job_id, 0))


static func professionalism_tier(job: JobDefinition, assignment_count: int) -> int:
	if job == null:
		return -1
	var result := -1
	for index in job.professionalism_thresholds.size():
		if assignment_count < job.professionalism_thresholds[index]:
			break
		result = index
	return result


static func professionalism_ability_id(job: JobDefinition, assignment_count: int) -> StringName:
	var tier := professionalism_tier(job, assignment_count)
	return job.professionalism_ability_ids[tier] if tier >= 0 and tier < job.professionalism_ability_ids.size() else &""


static func build_enemy(definition: EnemyDefinition, runtime_id: String, display_name: String, registry: Node) -> CombatUnitSnapshot:
	if definition == null:
		return null
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = definition.id
	snapshot.display_name = display_name
	snapshot.team = CombatUnitSnapshot.Team.ENEMY
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.ENEMY
	snapshot.attack_type = definition.attack_type
	snapshot.stats = CombatStats.from_stat_block(definition.base_stats)
	snapshot.stats.begin_breakdowns("Base: %s" % definition.display_name)
	snapshot.placeholder_color = definition.placeholder_color
	if definition is BossDefinition:
		var boss := definition as BossDefinition
		snapshot.is_boss = true
		snapshot.boss_phase_count = boss.phase_count
		snapshot.boss_phase_health_thresholds = boss.phase_health_thresholds.duplicate()
		snapshot.boss_phase_damage_multiplier = boss.phase_damage_multiplier
		snapshot.boss_phase_attack_speed_multiplier = boss.phase_attack_speed_multiplier
		snapshot.boss_telegraph_color = boss.telegraph_color
		snapshot.boss_phase_telegraph_text = boss.phase_telegraph_text
	_add_abilities(snapshot, definition.ability_ids, registry)
	return snapshot


static func _find_job_build(run_state: RunState, job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	return null


static func apply_veterancy_growth(stats: CombatStats, veterancy_level: int, registry: Node) -> void:
	var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
	if progression == null or veterancy_level <= 0:
		return
	var level := float(veterancy_level)
	var source := "Veterancy %d" % veterancy_level
	_multiply_stat(stats, &"max_hp", 1.0 + level * progression.veterancy_max_hp_growth_per_level, source)
	_multiply_stat(stats, &"damage", 1.0 + level * progression.veterancy_damage_growth_per_level, source)
	_multiply_stat(stats, &"attack_speed", 1.0 + level * progression.veterancy_attack_speed_growth_per_level, source)
	_multiply_stat(stats, &"movement_speed", 1.0 + level * progression.veterancy_movement_speed_growth_per_level, source)
	_multiply_stat(stats, &"attack_range", 1.0 + level * progression.veterancy_attack_range_growth_per_level, source)
	_multiply_stat(stats, &"armor", 1.0 + level * progression.veterancy_armor_growth_per_level, source)


static func _add_abilities(snapshot: CombatUnitSnapshot, ability_ids: Array[StringName], registry: Node) -> void:
	for ability_id in ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		if ability != null and not snapshot.abilities.has(ability):
			snapshot.abilities.append(ability)


static func _apply_priest_heal_veterancy(snapshot: CombatUnitSnapshot) -> void:
	if snapshot.veterancy_level <= 0:
		return
	for index in snapshot.abilities.size():
		var ability := snapshot.abilities[index]
		var has_veterancy_scaling := ability.effects.any(func(effect: AbilityEffect) -> bool:
			return effect is HealEffect and effect.veterancy_bonus_percent_per_level > 0.0
		)
		if not has_veterancy_scaling:
			continue
		var scaled_ability := ability.duplicate(true) as AbilityDefinition
		for effect in scaled_ability.effects:
			if effect is HealEffect and effect.veterancy_bonus_percent_per_level > 0.0:
				effect.amount *= 1.0 + snapshot.veterancy_level * effect.veterancy_bonus_percent_per_level / 100.0
		snapshot.abilities[index] = scaled_ability


static func _collect_item_modifier_entries(
	snapshot: CombatUnitSnapshot,
	item_ids: Array[StringName],
	inventory: InventoryState,
	registry: Node,
	modifier_multiplier := 1.0
) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	if inventory == null:
		return modifiers
	for instance_id in item_ids:
		var definition_id := inventory.get_definition_id(instance_id)
		var item := registry.get_definition(definition_id, false) as ItemDefinition
		if item == null:
			continue
		snapshot.equipped_item_instance_ids.append(instance_id)
		snapshot.equipped_item_definition_ids.append(definition_id)
		for authored_modifier in item.passive_effects:
			if authored_modifier == null:
				continue
			if is_equal_approx(modifier_multiplier, 1.0):
				modifiers.append({"modifier": authored_modifier, "source": "Item: %s" % item.display_name})
				continue
			var modifier := authored_modifier.duplicate() as StatModifier
			if modifier.operation == StatModifier.Operation.MULTIPLY:
				modifier.value = 1.0 + (modifier.value - 1.0) * modifier_multiplier
			else:
				modifier.value *= modifier_multiplier
			modifiers.append({"modifier": modifier, "source": "Item: %s (ability-scaled)" % item.display_name})
	return modifiers


static func _hero_abilities(hero: HeroState, definition: HeroDefinition, registry: Node) -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	for ability_id in hero.ability_ids:
		if not hero.owned_ability_ids.has(ability_id):
			continue
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		if ability != null and ability.is_allowed_for_hero(definition.id):
			result.append(ability.for_hero_level(hero.ability_level(ability.id)))
			if result.size() >= HeroState.MAX_ABILITY_SLOTS:
				break
	return result


static func _item_modifier_multiplier(abilities: Array[AbilityDefinition]) -> float:
	var multiplier := 1.0
	for ability in abilities:
		for effect in ability.effects:
			if effect is ItemStatScalingEffect:
				multiplier = maxf(multiplier, 1.0 + effect.bonus_percent / 100.0)
	return multiplier


static func _post_combat_xp_bonus(abilities: Array[AbilityDefinition]) -> float:
	var result := 0.0
	for ability in abilities:
		for effect in ability.effects:
			if effect is EnvyPostCombatXpEffect:
				result = maxf(result, effect.bonus_percent)
	return result


static func _apply_gold_army_scaling(snapshots: Array[CombatUnitSnapshot], gold: int) -> void:
	var percent_per_gold := 0.0
	for snapshot in snapshots:
		if snapshot.unit_kind != CombatUnitSnapshot.UnitKind.HERO:
			continue
		for ability in snapshot.abilities:
			for effect in ability.effects:
				if effect is GoldArmyScalingEffect:
					percent_per_gold = maxf(percent_per_gold, effect.percent_per_gold)
	if percent_per_gold <= 0.0:
		return
	var multiplier := 1.0 + maxi(gold, 0) * percent_per_gold / 100.0
	for snapshot in snapshots:
		var source := "Ability: Gold scaling (%d Gold)" % maxi(gold, 0)
		_multiply_stat(snapshot.stats, &"max_hp", multiplier, source)
		_multiply_stat(snapshot.stats, &"damage", multiplier, source)
		_multiply_stat(snapshot.stats, &"attack_speed", multiplier, source)
		_multiply_stat(snapshot.stats, &"attack_range", multiplier, source)
		_multiply_stat(snapshot.stats, &"armor", multiplier, source)


static func _runtime_modifier_entries(runtime_modifiers: Array[RuntimeStatModifier], registry: Node, fallback: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for modifier in runtime_modifiers:
		if modifier != null:
			result.append({"modifier": modifier.to_stat_modifier(), "source": _source_name(modifier.source_id, registry, fallback)})
	return result


static func _source_name(source_id: StringName, registry: Node, fallback: String) -> String:
	if not String(source_id).is_empty():
		var definition := registry.get_definition(source_id, false) as ContentDefinition
		if definition != null:
			return definition.display_name
		return String(source_id).get_slice(".", String(source_id).get_slice_count(".") - 1).replace("_", " ").capitalize()
	return fallback


static func _add_stat_block(stats: CombatStats, block: StatBlock, source: String) -> void:
	if block == null:
		return
	for stat in CombatStats.STAT_NAMES:
		var amount := float(block.get(stat))
		var before := float(stats.get(stat))
		stats.set(stat, before + amount)
		stats.record_change(stat, source, &"add", amount, before, float(stats.get(stat)))
	_clamp_stats(stats)


static func _multiply_stat(stats: CombatStats, stat: StringName, multiplier: float, source: String) -> void:
	var before := float(stats.get(stat))
	stats.set(stat, before * multiplier)
	stats.record_change(stat, source, &"multiply", multiplier, before, float(stats.get(stat)))


static func _apply_modifier_entries(stats: CombatStats, entries: Array[Dictionary]) -> void:
	for operation in [StatModifier.Operation.ADD, StatModifier.Operation.MULTIPLY]:
		for entry in entries:
			var modifier := entry.modifier as StatModifier
			if modifier == null or modifier.operation != operation or StringName(modifier.stat) not in CombatStats.STAT_NAMES:
				continue
			var stat := StringName(modifier.stat)
			var before := float(stats.get(stat))
			var after := modifier.apply_to(before)
			stats.set(stat, after)
			stats.record_change(stat, String(entry.source), &"add" if operation == StatModifier.Operation.ADD else &"multiply", modifier.value, before, after)
	_clamp_stats(stats)


static func _clamp_stats(stats: CombatStats) -> void:
	var before: Dictionary = {}
	for stat in CombatStats.STAT_NAMES:
		before[stat] = float(stats.get(stat))
	stats._clamp_values()
	for stat in CombatStats.STAT_NAMES:
		stats.record_change(stat, "Stat limit", &"set", float(stats.get(stat)), float(before[stat]), float(stats.get(stat)))
