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
	for hero in run_state.heroes:
		if hero.life_state == HeroState.ALIVE:
			var snapshot := build_hero(hero, registry)
			if snapshot != null:
				result.append(snapshot)
	for soldier in run_state.soldiers:
		var snapshot := build_soldier(soldier, _find_job_build(run_state, soldier.current_job_id), registry)
		if snapshot != null:
			result.append(snapshot)
	return result


static func build_hero(hero: HeroState, registry: Node) -> CombatUnitSnapshot:
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
	snapshot.stats = CombatStats.from_stat_block(definition.base_stats)
	var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
	if progression != null:
		snapshot.stats.multiply(1.0 + maxf(hero.level - 1, 0) * progression.hero_stat_growth_per_level)
	snapshot.placeholder_color = definition.placeholder_color
	_apply_items(snapshot.stats, hero.item_ids, &"hero", &"", registry)
	var ordered_ids := hero.ability_priority if not hero.ability_priority.is_empty() else hero.ability_ids
	_add_abilities(snapshot, ordered_ids.slice(0, HeroState.MAX_ABILITY_SLOTS), registry)
	return snapshot


static func build_soldier(
	soldier: SoldierState,
	job_build: JobBuildState,
	registry: Node
) -> CombatUnitSnapshot:
	var job := registry.get_definition(soldier.current_job_id, false) as JobDefinition
	if job == null:
		return null
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = soldier.unique_id
	snapshot.definition_id = job.id
	snapshot.display_name = soldier.generated_name
	snapshot.team = CombatUnitSnapshot.Team.PLAYER
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER
	snapshot.job_id = job.id
	snapshot.attack_type = job.attack_type
	snapshot.stats.max_hp = MILITIA_BASE_HP
	snapshot.stats.damage = MILITIA_BASE_DAMAGE
	snapshot.stats.attack_speed = MILITIA_BASE_ATTACK_SPEED
	snapshot.stats.movement_speed = MILITIA_BASE_MOVEMENT_SPEED
	snapshot.stats.attack_range = MILITIA_BASE_ATTACK_RANGE
	snapshot.stats.armor = MILITIA_BASE_ARMOR
	snapshot.stats.add_stat_block(job.stat_modifiers)
	var progression := registry.get_definition(&"progression.demo", false) as ProgressionDefinition
	if progression != null:
		snapshot.stats.multiply(1.0 + soldier.veterancy_level * progression.veterancy_stat_growth_per_level)
	snapshot.placeholder_color = job.placeholder_color
	_apply_items(snapshot.stats, soldier.item_ids, &"soldier", job.id, registry)
	if job_build != null:
		var ability_ids: Array[StringName] = []
		if job.available_ability_ids.has(job_build.active_ability_id):
			ability_ids.append(job_build.active_ability_id)
		for ability_id in job_build.passive_ability_ids:
			if job.available_ability_ids.has(ability_id):
				ability_ids.append(ability_id)
		_add_abilities(snapshot, ability_ids, registry)
	return snapshot


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
	snapshot.placeholder_color = definition.placeholder_color
	_add_abilities(snapshot, definition.ability_ids, registry)
	return snapshot


static func _find_job_build(run_state: RunState, job_id: StringName) -> JobBuildState:
	for build in run_state.job_builds:
		if build.job_id == job_id:
			return build
	return null


static func _add_abilities(snapshot: CombatUnitSnapshot, ability_ids: Array[StringName], registry: Node) -> void:
	for ability_id in ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		if ability != null and not snapshot.abilities.has(ability):
			snapshot.abilities.append(ability)


static func _apply_items(
	stats: CombatStats,
	item_ids: Array[StringName],
	target_type: StringName,
	job_id: StringName,
	registry: Node
) -> void:
	for item_id in item_ids:
		var item := registry.get_definition(item_id, false) as ItemDefinition
		if item == null or item.allowed_target_type != target_type:
			continue
		if not item.allowed_job_ids.is_empty() and not item.allowed_job_ids.has(job_id):
			continue
		stats.add_stat_block(item.stat_modifiers)
