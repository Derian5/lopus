class_name CombatDemoFactory
extends RefCounted


const HERO_COLORS: Array[Color] = [
	Color(0.95, 0.72, 0.24),
	Color(0.65, 0.38, 0.9),
	Color(0.24, 0.78, 0.68),
]
const PROTOTYPE_HERO_ABILITY_IDS: Array[StringName] = []


static func create_player_army(hero_count := 3, soldier_count := 9) -> Array[CombatUnitSnapshot]:
	var result: Array[CombatUnitSnapshot] = []
	var hero_definition := _get_registry().get_definition(&"hero.test_vanguard") as HeroDefinition
	for index in hero_count:
		var snapshot := CombatUnitSnapshot.new()
		snapshot.runtime_id = "player-hero-%02d" % index
		snapshot.definition_id = hero_definition.id
		snapshot.display_name = "%s %d" % [hero_definition.display_name, index + 1]
		snapshot.team = CombatUnitSnapshot.Team.PLAYER
		snapshot.unit_kind = CombatUnitSnapshot.UnitKind.HERO
		snapshot.attack_type = &"ranged" if index == 2 else &"melee"
		snapshot.stats = CombatStats.from_stat_block(hero_definition.base_stats)
		if snapshot.attack_type == &"ranged":
			snapshot.stats.attack_range = 320.0
			snapshot.stats.damage = 18.0
		snapshot.placeholder_color = HERO_COLORS[index % HERO_COLORS.size()]
		for ability_id in PROTOTYPE_HERO_ABILITY_IDS:
			var ability := _get_registry().get_definition(ability_id) as AbilityDefinition
			if ability != null:
				snapshot.abilities.append(ability)
		snapshot.abilities.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool:
			return a.priority > b.priority
		)
		result.append(snapshot)

	for index in soldier_count:
		var snapshot := CombatUnitSnapshot.new()
		snapshot.runtime_id = "player-soldier-%02d" % index
		snapshot.definition_id = &"job.militia"
		snapshot.display_name = "Militia %d" % (index + 1)
		snapshot.team = CombatUnitSnapshot.Team.PLAYER
		snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER
		snapshot.job_id = &"job.militia"
		snapshot.attack_type = &"melee"
		snapshot.stats.max_hp = 105.0
		snapshot.stats.damage = 10.0
		snapshot.stats.attack_speed = 1.0
		snapshot.stats.movement_speed = 108.0
		snapshot.stats.attack_range = 46.0
		snapshot.stats.armor = 2.0
		snapshot.placeholder_color = Color(0.24, 0.52, 0.9)
		result.append(snapshot)

	return result


static func create_enemy_army(melee_count := 8, ranged_count := 4) -> Array[CombatUnitSnapshot]:
	var result: Array[CombatUnitSnapshot] = []
	var registry = _get_registry()
	var melee_definition := registry.get_definition(&"enemy.raider") as EnemyDefinition
	var ranged_definition := registry.get_definition(&"enemy.crossbowman") as EnemyDefinition

	for index in melee_count:
		result.append(_create_enemy_snapshot(melee_definition, index, &"melee"))
	for index in ranged_count:
		result.append(_create_enemy_snapshot(ranged_definition, melee_count + index, &"ranged"))

	return result


static func create_enemy_army_from_encounter(encounter: EncounterDefinition, route_power := 1.0, battle_number := 0) -> Array[CombatUnitSnapshot]:
	if encounter == null:
		return []
	return _create_enemy_army_from_ids(encounter.enemy_ids, "enemy", encounter, route_power, battle_number)


static func create_reinforcement_army_from_encounter(encounter: EncounterDefinition, route_power := 1.0, battle_number := 0) -> Array[CombatUnitSnapshot]:
	if encounter == null:
		return []
	return _create_enemy_army_from_ids(encounter.reinforcement_enemy_ids, "enemy-reinforcement", encounter, route_power, battle_number)


static func _create_enemy_army_from_ids(enemy_ids: Array[StringName], runtime_prefix: String, encounter: EncounterDefinition = null, route_power := 1.0, battle_number := 0) -> Array[CombatUnitSnapshot]:
	var result: Array[CombatUnitSnapshot] = []
	var registry := _get_registry()
	for index in enemy_ids.size():
		var definition := registry.get_definition(enemy_ids[index]) as EnemyDefinition
		var snapshot := CombatSnapshotBuilder.build_enemy(
			definition,
			"%s-%02d" % [runtime_prefix, index],
			"%s %d" % [definition.display_name, index + 1],
			registry
		)
		var route_source := "Act threat (battle %d)" % battle_number if battle_number > 0 else "Act threat"
		apply_enemy_power(snapshot.stats, route_power, route_source)
		if encounter != null:
			apply_enemy_power(snapshot.stats, encounter.enemy_power, "Encounter strength: %s" % encounter.display_name)
		result.append(snapshot)
	return result


static func _create_enemy_snapshot(
	definition: EnemyDefinition,
	index: int,
	attack_type: StringName
) -> CombatUnitSnapshot:
	# The explicit attack type keeps the stress-test factory flexible while the
	# shared builder remains the normal definition-driven path.
	var snapshot := CombatSnapshotBuilder.build_enemy(
		definition,
		"enemy-%02d" % index,
		"%s %d" % [definition.display_name, index + 1],
		_get_registry()
	)
	snapshot.attack_type = attack_type
	return snapshot


static func _get_registry() -> Node:
	return Engine.get_main_loop().root.get_node("ContentRegistry")


## Route-level enemy power for the run's current battle (1.0 without a run or route curve).
static func route_enemy_power(run_state: RunState) -> float:
	if run_state == null:
		return 1.0
	var route := _get_registry().get_definition(RunState.ROUTE_DEFINITION_ID, false) as RouteDefinition
	return route.enemy_power_for(run_state.current_act, run_state.encounter_index) if route != null else 1.0


## Enemy power grows damage faster than health so late battles get deadlier
## instead of longer (the 120-second limit awards stalled fights by remaining HP).
static func enemy_hp_multiplier(power: float) -> float:
	return pow(maxf(power, 0.01), 0.85)


static func enemy_damage_multiplier(power: float) -> float:
	return pow(maxf(power, 0.01), 1.15)


## Scales Max HP and Damage by an enemy power and records both steps in the stat
## breakdown so the inspector explains why the same enemy differs between battles.
## Power splits multiplicatively: (a*b)^k == a^k * b^k, so layers can be applied one by one.
static func apply_enemy_power(stats: CombatStats, power: float, source: String) -> void:
	if is_equal_approx(power, 1.0):
		return
	var hp_multiplier := enemy_hp_multiplier(power)
	var before := stats.max_hp
	stats.max_hp *= hp_multiplier
	stats.record_change(&"max_hp", source, &"multiply", hp_multiplier, before, stats.max_hp)
	var damage_multiplier := enemy_damage_multiplier(power)
	before = stats.damage
	stats.damage *= damage_multiplier
	stats.record_change(&"damage", source, &"multiply", damage_multiplier, before, stats.damage)
