extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_definition_resources()
	_test_job_build_limits()
	await _test_targeting_effects_and_reset()
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
		&"ability.battle_fury", &"ability.whirlwind",
	]
	for ability_id in ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and not ability.effects.is_empty(), "Ability is data-defined with effects: %s" % ability_id)
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
