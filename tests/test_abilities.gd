extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_definition_resources()
	_test_job_build_limits()
	await _test_targeting_effects_and_reset()
	await _test_summoning()
	await _test_summoner_veterancy_inheritance()
	if failures == 0:
		print("Stage 5 ability and status tests passed.")
		quit()
	else:
		push_error("Stage 5 ability and status tests failed: %d" % failures)
		quit(1)


func _test_definition_resources() -> void:
	var registry = root.get_node("ContentRegistry")
	var ability_ids := [
		&"ability.fire_bolt", &"ability.mending_light", &"ability.stunning_blow",
		&"ability.frost_dart", &"ability.guardian_shield", &"ability.fortify",
		&"ability.battle_fury", &"ability.whirlwind", &"ability.hero_summon",
		&"ability.summoner_job_summon", &"ability.enemy_summon",
		&"ability.pride_last_stand", &"ability.pride_farthest_attack", &"ability.pride_cleanse",
		&"ability.pride_sacrifice", &"ability.pride_melee_teleport", &"ability.pride_attack_speed_aura",
	]
	for ability_id in ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and not ability.effects.is_empty(), "Ability is data-defined with effects: %s" % ability_id)
	var universal := 0
	var single_hero := 0
	var shared := 0
	for ability_id in ability_ids:
		var ability := registry.get_definition(ability_id) as AbilityDefinition
		if not ability.available_to_heroes:
			continue
		if ability.allowed_hero_ids.is_empty():
			universal += 1
		elif ability.allowed_hero_ids.size() == 1:
			single_hero += 1
		else:
			shared += 1
	_check(universal == 0 and single_hero == 12 and shared == 2, "Demo abilities include twelve focused skills and two explicitly shared skills.")
	var fire := registry.get_definition(&"ability.fire_bolt") as AbilityDefinition
	_check(fire.effects.size() == 2, "One ability contains multiple ordered effects.")
	_check(fire.effects[0] is DamageEffect and fire.effects[1] is ApplyStatusEffect, "Effect order is preserved by the Resource.")
	var deliveries: Array[int] = []
	for ability_id in ability_ids:
		deliveries.append((registry.get_definition(ability_id) as AbilityDefinition).delivery_method)
	for method in AbilityDefinition.DeliveryMethod.values():
		_check(deliveries.has(method), "Demo abilities cover delivery method %s." % AbilityDefinition.DeliveryMethod.keys()[method])


func _test_job_build_limits() -> void:
	var build := JobBuildState.new()
	build.set_active_ability(&"ability.fire_bolt")
	_check(build.add_passive_ability(&"passive.one"), "First passive slot is accepted.")
	_check(build.add_passive_ability(&"passive.two"), "Second passive slot is accepted.")
	_check(build.add_passive_ability(&"passive.three"), "Third passive slot is accepted.")
	_check(not build.add_passive_ability(&"passive.four"), "A fourth passive slot is rejected.")
	_check(build.is_valid() and build.active_ability_id == &"ability.fire_bolt", "Job build has one active and at most three passives.")


func _test_targeting_effects_and_reset() -> void:
	var registry = root.get_node("ContentRegistry")
	var players := CombatDemoFactory.create_player_army(1, 1)
	players[0].abilities.clear()
	players[1].abilities.clear()
	var enemies := CombatDemoFactory.create_enemy_army(2, 0)
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, 4242)
	await process_frame
	var hero := _unit(session, "player-hero-00")
	var ally := _unit(session, "player-soldier-00")
	var enemy_a := _unit(session, "enemy-00")
	var enemy_b := _unit(session, "enemy-01")
	hero.position = Vector2(100, 100)
	ally.position = Vector2(120, 100)
	enemy_a.position = Vector2(300, 100)
	enemy_b.position = Vector2(500, 100)
	ally.current_hp = 30.0

	var heal := registry.get_definition(&"ability.mending_light") as AbilityDefinition
	var fire := registry.get_definition(&"ability.fire_bolt") as AbilityDefinition
	var shield := registry.get_definition(&"ability.guardian_shield") as AbilityDefinition
	var random_ability := registry.get_definition(&"ability.frost_dart") as AbilityDefinition
	_check(session.resolve_ability_target(hero, heal) == ally, "Lowest HP ally targeting uses health ratio.")
	_check(session.resolve_ability_target(hero, fire) == enemy_a, "Closest enemy targeting uses distance.")
	_check(session.resolve_ability_target(hero, shield) == hero, "Self targeting returns the caster.")
	var random_sequence: Array[String] = []
	for index in 5:
		random_sequence.append(session.resolve_ability_target(hero, random_ability).snapshot.runtime_id)

	session.deliver_ability(hero, ally, heal)
	_check(ally.current_hp > 30.0, "HealEffect restores health.")
	var fire_hp := enemy_a.current_hp
	session._apply_ability_effects(hero, enemy_a, fire)
	_check(enemy_a.current_hp < fire_hp and enemy_a.statuses.size() == 1, "Multiple damage and status effects execute in order.")
	var burn: StatusDefinition = registry.get_definition(&"status.burn")
	enemy_a.apply_status(burn, hero, fire.id)
	_check(enemy_a.statuses[0].stacks == 2, "Add Stacks increments up to the status limit.")
	var stun: StatusDefinition = registry.get_definition(&"status.stun")
	enemy_a.apply_status(stun, hero, &"ability.stunning_blow")
	var stun_duration := enemy_a.statuses[1].remaining_duration
	enemy_a.statuses[1].remaining_duration = 0.1
	enemy_a.apply_status(stun, hero, &"ability.stunning_blow")
	_check(is_equal_approx(enemy_a.statuses[1].remaining_duration, stun_duration), "Refresh Duration restores duration without adding stacks.")
	session.deliver_ability(hero, hero, shield)
	_check(not hero.shields.is_empty() and hero.get_effective_stat(&"armor") > hero.snapshot.stats.armor, "ShieldEffect and StatModifierEffect both apply.")

	var damage_events := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.DAMAGE_APPLIED and event.ability_id == fire.id)
	var healing_events := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.HEALING_APPLIED and event.ability_id == heal.id)
	_check(not damage_events.is_empty() and damage_events[0].effect_id == &"effect.fire_bolt_damage", "Damage event attributes ability and effect.")
	_check(not healing_events.is_empty() and healing_events[0].effect_id == &"effect.mending_light_heal", "Healing event attributes ability and effect.")
	_check(session.statistics.ability_stats.has(String(fire.id)) and session.statistics.ability_stats.has(String(heal.id)), "CombatStatistics aggregates both abilities.")

	hero.snapshot.abilities = [shield, fire]
	hero.ability_cooldowns.clear()
	hero._acquire_target()
	var uses := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.ABILITY_USED)
	_check(not uses.is_empty() and uses[-1].ability_id == shield.id, "AI uses the first available ability in ordered priority.")
	hero.ability_cooldowns[shield.id] = 5.0
	hero.statuses.append(StatusInstance.new())
	session.restart_battle()
	await process_frame
	var restarted_hero := _unit(session, "player-hero-00")
	_check(restarted_hero.ability_cooldowns.is_empty() and restarted_hero.statuses.is_empty(), "Restart creates clean cooldown and status runtime state.")
	var repeated_sequence: Array[String] = []
	for index in 5:
		repeated_sequence.append(session.resolve_ability_target(restarted_hero, random_ability).snapshot.runtime_id)
	_check(repeated_sequence == random_sequence, "Random valid enemy targeting repeats from the combat seed.")
	session.free()


func _test_summoning() -> void:
	var registry = root.get_node("ContentRegistry")
	var players := CombatDemoFactory.create_player_army(1, 0)
	var enemies := CombatDemoFactory.create_enemy_army(1, 0)
	var summon_ability := registry.get_definition(&"ability.hero_summon") as AbilityDefinition
	players[0].abilities.clear()
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, 5151)
	await process_frame
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var hero := _unit(session, "player-hero-00")
	var enemy := _unit(session, "enemy-00")
	hero.snapshot.abilities = [summon_ability]
	var original_position := hero.position
	hero.ability_cooldowns.clear()
	hero._acquire_target()
	var summons := _living_summons(session, hero.snapshot.runtime_id)
	_check(summons.size() == 1, "Summon creates exactly one temporary unit per cast.")
	var first: Combatant = summons[0]
	first.set_simulation_active(false)
	_check(
		first.snapshot.definition_id == &"enemy.summoned_shooter"
		and first.snapshot.team == CombatUnitSnapshot.Team.PLAYER
		and first.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON,
		"Summon uses the configured unit template and inherits the caster team."
	)
	_check(first.position.distance_to(original_position) <= CombatSession.SUMMON_SPAWN_DISTANCE + 0.1, "Summoned unit appears near its caster.")
	hero.ability_cooldowns.clear()
	hero._acquire_target()
	summons = _living_summons(session, hero.snapshot.runtime_id)
	_check(summons.size() == 2, "Repeated casts fill the configured simultaneous-live limit.")
	for summon in summons:
		summon.set_simulation_active(false)
	hero.ability_cooldowns.clear()
	_check(not hero._try_use_ability() and not hero.ability_cooldowns.has(summon_ability.id), "A full summon limit prevents casting without consuming cooldown.")
	var first_runtime_id := first.snapshot.runtime_id
	first.take_damage(10000.0, enemy)
	hero.ability_cooldowns.clear()
	hero._acquire_target()
	summons = _living_summons(session, hero.snapshot.runtime_id)
	_check(summons.size() == 2 and not summons.any(func(unit: Combatant) -> bool: return unit.snapshot.runtime_id == first_runtime_id), "A dead summon releases its live-limit slot.")
	_check(session.statistics.get_event_count(CombatEvent.UNIT_SUMMONED) == 3, "Each successful summon emits one combat event.")
	session.restart_battle()
	_check(_living_summons(session, "player-hero-00").is_empty() and session.summon_serial == 0, "Restart removes runtime summons and resets summon IDs.")
	hero = _unit(session, "player-hero-00")
	enemy = _unit(session, "enemy-00")
	var priority_summon := summon_ability.duplicate(true) as AbilityDefinition
	priority_summon.id = &"ability.test_priority_summon"
	(priority_summon.effects[0] as SummonEffect).max_active_summons = 3
	(priority_summon.effects[0] as SummonEffect).summoner_contribution_percent = 35.0
	hero.snapshot.abilities = [priority_summon]
	hero.target = enemy
	hero.state = Combatant.State.MOVE_INTO_RANGE
	hero.ability_cooldowns.clear()
	hero._physics_process(0.01)
	_check(_living_summons(session, hero.snapshot.runtime_id).size() == 1 and hero.state == Combatant.State.ACQUIRE_TARGET, "A ready summon immediately interrupts movement.")
	_check(is_equal_approx(_living_summons(session, hero.snapshot.runtime_id)[0].snapshot.summoner_contribution_percent, 35.0), "Summoned unit retains its designer-configured owner contribution percentage.")
	hero.target = enemy
	hero.state = Combatant.State.ATTACK_WINDUP
	hero.state_timer = 10.0
	hero.ability_cooldowns.clear()
	hero._physics_process(0.01)
	_check(_living_summons(session, hero.snapshot.runtime_id).size() == 2 and hero.state == Combatant.State.ACQUIRE_TARGET and is_zero_approx(hero.state_timer), "A ready summon immediately interrupts attack windup.")
	hero.target = enemy
	hero.state = Combatant.State.ATTACK_RECOVERY
	hero.state_timer = 10.0
	hero.ability_cooldowns.clear()
	hero._physics_process(0.01)
	_check(_living_summons(session, hero.snapshot.runtime_id).size() == 3 and hero.state == Combatant.State.ACQUIRE_TARGET and is_zero_approx(hero.state_timer), "A ready summon immediately interrupts attack recovery or ranged retreat.")
	hero.target = enemy
	hero.state = Combatant.State.MOVE_INTO_RANGE
	hero.ability_cooldowns.clear()
	hero._physics_process(0.01)
	_check(_living_summons(session, hero.snapshot.runtime_id).size() == 3 and hero.state == Combatant.State.MOVE_INTO_RANGE and not hero.ability_cooldowns.has(priority_summon.id), "A full summon limit neither consumes cooldown nor interrupts movement.")
	session.free()


func _living_summons(session: CombatSession, summoner_runtime_id: String) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for combatant in session.combatants:
		if combatant.is_alive() and combatant.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON and combatant.snapshot.summoner_runtime_id == summoner_runtime_id:
			result.append(combatant)
	return result


func _test_summoner_veterancy_inheritance() -> void:
	var registry = root.get_node("ContentRegistry")
	var run := DemoRunFactory.create_starting_run(5152)
	var soldier := run.soldiers[0]
	soldier.current_job_id = &"job.summoner"
	soldier.veterancy_level = 2
	var summoner_snapshot := CombatSnapshotBuilder.build_soldier(soldier, null, run.inventory, registry)
	var players: Array[CombatUnitSnapshot] = [summoner_snapshot]
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, CombatDemoFactory.create_enemy_army(1, 0), 5152)
	await process_frame
	var summons := _living_summons(session, summoner_snapshot.runtime_id)
	if summons.is_empty():
		var summoner := _unit(session, summoner_snapshot.runtime_id)
		summoner._physics_process(0.01)
		summons = _living_summons(session, summoner_snapshot.runtime_id)
	_check(summons.size() == 1, "Summoner Job uses its innate summon ability without a configurable Job build.")
	if not summons.is_empty():
		var summon := summons[0]
		var definition := registry.get_definition(summon.snapshot.definition_id) as EnemyDefinition
		var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
		var expected_hp := definition.base_stats.max_hp * (1.0 + soldier.veterancy_level * progression.veterancy_max_hp_growth_per_level)
		var expected_damage := definition.base_stats.damage * (1.0 + soldier.veterancy_level * progression.veterancy_damage_growth_per_level)
		_check(summoner_snapshot.veterancy_level == soldier.veterancy_level and summon.snapshot.veterancy_level == soldier.veterancy_level, "Summoned creature inherits its Soldier Summoner's veterancy level.")
		_check(is_equal_approx(summon.snapshot.stats.max_hp, expected_hp) and is_equal_approx(summon.snapshot.stats.damage, expected_damage), "Inherited veterancy applies the configured HP and damage growth to the summoned creature.")
	session.free()


func _unit(session: CombatSession, runtime_id: String) -> Combatant:
	for combatant in session.combatants:
		if combatant.snapshot.runtime_id == runtime_id:
			return combatant
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
