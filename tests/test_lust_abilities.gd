extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const SELECTED_PANEL_SCENE := preload("res://ui/combat/selected_unit_panel.tscn")
const LUST_ID := &"hero.glass_arcanist"
const ABILITY_IDS: Array[StringName] = [
	&"ability.lust_guardian_desire",
	&"ability.lust_fallen_devotion",
	&"ability.lust_recruit",
	&"ability.lust_beguiling_presence",
	&"ability.lust_fatal_bond",
	&"ability.lust_heartbreaker",
]

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_rewards()
	_test_melee_attack()
	_test_guard_and_taunt()
	_test_death_scaling()
	_test_recruitment()
	_test_target_slow()
	_test_fatal_bond()
	_test_heartbreaker()
	if failures == 0:
		print("Lust ability tests passed.")
		quit()
	else:
		push_error("Lust ability tests failed: %d" % failures)
		quit(1)


func _test_content_and_rewards() -> void:
	var lust_definition := registry.get_definition(LUST_ID, false) as HeroDefinition
	_check(lust_definition != null and lust_definition.tags.has(&"melee") and not lust_definition.tags.has(&"ranged") and lust_definition.base_stats.damage == 12.0 and lust_definition.base_stats.attack_speed == 1.2 and lust_definition.base_stats.attack_range == 300.0, "Lust uses her authored melee base stats.")
	for ability_id in ABILITY_IDS:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and ability.allowed_hero_ids == [LUST_ID] and ability.hero_levels.size() == 4, "%s is a four-level Lust-exclusive ability." % ability_id)
	var expected_guard := [20.0, 40.0, 80.0, 160.0]
	var expected_scaling := [6.0, 12.0, 24.0, 48.0]
	var expected_recruit := [100.0, 200.0, 400.0, 800.0]
	var expected_slow := [20.0, 35.0, 50.0, 65.0]
	var expected_lifesteal := [20.0, 30.0, 40.0, 50.0]
	var expected_speed := [1.4, 1.8, 2.2, 2.6]
	var expected_hits := [6, 5, 4, 3]
	var expected_stun := [0.6, 0.8, 1.0, 1.2]
	for index in 4:
		var level := index + 1
		_check((_ability(&"ability.lust_guardian_desire", level).effects[0] as LustGuardTauntEffect).armor_bonus == expected_guard[index], "Guardian Desire Level %d armor is exact." % level)
		_check((_ability(&"ability.lust_fallen_devotion", level).effects[0] as LustDeathScalingEffect).percent_per_death == expected_scaling[index], "Fallen Devotion Level %d scaling is exact." % level)
		_check((_ability(&"ability.lust_recruit", level).effects[0] as LustRecruitEffect).hp_threshold == expected_recruit[index], "Irresistible Offer Level %d threshold is exact." % level)
		_check((_ability(&"ability.lust_beguiling_presence", level).effects[0] as LustTargetSlowEffect).slow_percent == expected_slow[index], "Beguiling Presence Level %d slow is exact." % level)
		var level_bond := _ability(&"ability.lust_fatal_bond", level).effects[0] as LustBondEffect
		_check(level_bond.lifesteal_percent == expected_lifesteal[index] and level_bond.attack_speed_multiplier == expected_speed[index], "Fatal Bond Level %d values are exact." % level)
		var level_breaker := _ability(&"ability.lust_heartbreaker", level).effects[0] as LustBasicKnockbackEffect
		_check(level_breaker.hits_required == expected_hits[index] and level_breaker.stun_duration == expected_stun[index], "Heartbreaker Level %d values are exact." % level)
	var guard := _ability(&"ability.lust_guardian_desire", 4)
	var scaling := _ability(&"ability.lust_fallen_devotion", 4).effects[0] as LustDeathScalingEffect
	var recruit := _ability(&"ability.lust_recruit", 4)
	var slow := _ability(&"ability.lust_beguiling_presence", 4).effects[0] as LustTargetSlowEffect
	var bond := _ability(&"ability.lust_fatal_bond", 4).effects[0] as LustBondEffect
	var breaker := _ability(&"ability.lust_heartbreaker", 4).effects[0] as LustBasicKnockbackEffect
	_check(guard.cooldown_seconds == 10.0 and (guard.effects[0] as LustGuardTauntEffect).armor_bonus == 160.0, "Guardian Desire has the approved cooldown and armor tiers.")
	_check(scaling.percent_per_death == 48.0 and recruit.cooldown_seconds == 15.0 and (recruit.effects[0] as LustRecruitEffect).hp_threshold == 800.0, "Death scaling and recruitment reach their approved Level 4 values.")
	_check(slow.slow_percent == 65.0 and bond.lifesteal_percent == 50.0 and bond.attack_speed_multiplier == 2.6, "Presence and bond reach their approved Level 4 values.")
	_check(breaker.hits_required == 3 and breaker.knockback_distance == 80.0 and breaker.stun_duration == 1.2, "Heartbreaker reaches its approved Level 4 cadence and control values.")
	var run := DemoRunFactory.create_starting_run(9700, [LUST_ID, &"hero.test_vanguard", &"hero.army_support"])
	var lust: HeroState
	var other: HeroState
	for hero in run.heroes:
		if hero.definition_id == LUST_ID:
			lust = hero
		elif other == null:
			other = hero
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var candidates := HeroAbilityRewardService._candidates(lust, registry, route)
	var other_candidates := HeroAbilityRewardService._candidates(other, registry, route)
	_check(candidates.size() == 6 and candidates.all(func(data: Dictionary) -> bool: return ABILITY_IDS.has(data.ability_id)), "Hero rewards expose all six Lust abilities to Lust.")
	_check(not other_candidates.any(func(data: Dictionary) -> bool: return ABILITY_IDS.has(data.ability_id)), "Hero rewards do not expose Lust abilities to other Heroes.")


func _test_melee_attack() -> void:
	var hero := HeroState.new()
	hero.unique_id = "lust-melee"
	hero.definition_id = LUST_ID
	var lust_snapshot := CombatSnapshotBuilder.build_hero(hero, InventoryState.new(), registry)
	var enemy := _snapshot("melee-target", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([lust_snapshot], [enemy], 9710)
	var lust_unit := _unit(session, "lust-melee")
	var target := _unit(session, "melee-target")
	lust_unit.position = Vector2(300.0, 300.0)
	target.position = Vector2(380.0, 300.0)
	lust_unit.target = target
	var hp_before := target.current_hp
	lust_unit._start_attack()
	lust_unit._update_attack_windup(lust_unit.windup_duration)
	var projectiles := session.get_node("Projectiles")
	_check(lust_snapshot.attack_type == &"melee" and lust_snapshot.stats.damage == 12.0 and lust_snapshot.stats.attack_speed == 1.2 and lust_snapshot.stats.attack_range == 300.0, "Lust's combat snapshot uses her authored melee base stats.")
	_check(projectiles.get_child_count() == 0 and target.current_hp < hp_before, "Lust's basic attack deals direct melee damage without launching a projectile.")
	session.free()


func _test_guard_and_taunt() -> void:
	var lust := _snapshot("lust", LUST_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 200.0, 10.0)
	var ally_a := _snapshot("ally-a", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 400.0, 10.0)
	var ally_b := _snapshot("ally-b", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 400.0, 10.0)
	var enemy_a := _snapshot("enemy-a", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	var enemy_b := _snapshot("enemy-b", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	var session := _session([lust, ally_a, ally_b], [enemy_a, enemy_b], 9701)
	var lust_unit := _unit(session, "lust")
	var a := _unit(session, "ally-a")
	var b := _unit(session, "ally-b")
	var first_enemy := _unit(session, "enemy-a")
	var second_enemy := _unit(session, "enemy-b")
	lust_unit.position = Vector2(300, 300)
	a.position = Vector2(320, 300)
	b.position = Vector2(330, 300)
	first_enemy.position = Vector2(440, 300)
	second_enemy.position = Vector2(1000, 500)
	var ability := _ability(&"ability.lust_guardian_desire", 2)
	_check(session.can_use_ability(lust_unit, lust_unit, ability), "Guardian Desire can cast when an enemy is within 150 and another ally is within 250.")
	session.deliver_ability(lust_unit, lust_unit, ability)
	_check(is_equal_approx(a.get_effective_stat(&"armor"), 40.0) and is_zero_approx(b.get_effective_stat(&"armor")), "Equal-max-HP guard targets use stable runtime-ID order and never target Lust.")
	_check(first_enemy.forced_basic_target == a and second_enemy.forced_basic_target == a and session.find_basic_attack_target(second_enemy) == a, "The taunt globally overrides every living enemy's basic target.")
	var active_panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(active_panel)
	active_panel.show_combatant(a)
	_check(active_panel.status_summary_text().contains("Center of Attention") and active_panel.status_summary_text().contains("Armor +40"), "The guarded ally's status indicators expose armor and global taunt metadata.")
	active_panel.show_combatant(first_enemy)
	_check(active_panel.status_summary_text().contains("Taunted") and active_panel.status_summary_text().contains("ally-a"), "Enemy status indicators expose the forced taunt target and duration.")
	active_panel.free()
	a.force_die(first_enemy, &"effect.test")
	first_enemy._update_runtime(0.01)
	_check(first_enemy.forced_basic_target == null, "Taunt clears gracefully when its target dies.")
	second_enemy._update_runtime(5.1)
	b._update_runtime(5.1)
	_check(second_enemy.forced_basic_target == null and is_zero_approx(b.get_effective_stat(&"armor")), "Taunt and guard runtime state expire after five seconds.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(first_enemy)
	_check(not panel.status_summary_text().contains("Taunted"), "Expired taunt is removed from the status indicators.")
	panel.free()
	var no_enemy_session := _session([lust, ally_a], [enemy_a], 9702)
	var no_enemy_lust := _unit(no_enemy_session, "lust")
	_unit(no_enemy_session, "enemy-a").position = Vector2(1000, 500)
	_check(not no_enemy_session.can_use_ability(no_enemy_lust, no_enemy_lust, ability), "Guardian Desire cannot cast without an enemy within 150.")
	no_enemy_session.free()
	session.free()


func _test_death_scaling() -> void:
	var lust := _snapshot("lust", LUST_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 20.0)
	lust.stats.armor = 10.0
	lust.abilities = [_ability(&"ability.lust_fallen_devotion", 2)]
	var ally_a := _snapshot("ally-a", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 100.0, 10.0)
	var ally_b := _snapshot("ally-b", &"enemy.summoned_brawler", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SUMMON, 100.0, 10.0)
	var enemy := _snapshot("enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([lust, ally_a, ally_b], [enemy], 9703)
	var lust_unit := _unit(session, "lust")
	_unit(session, "ally-a").force_die(_unit(session, "enemy"), &"effect.test")
	_unit(session, "ally-b").force_die(_unit(session, "enemy"), &"effect.test")
	_check(is_equal_approx(lust_unit.get_effective_stat(&"max_hp"), 124.0) and is_equal_approx(lust_unit.get_effective_stat(&"damage"), 24.8), "Two allied deaths at Level 2 apply one additive x1.24 aggregate multiplier.")
	_check(is_equal_approx(lust_unit.get_effective_stat(&"attack_speed"), 1.0) and is_equal_approx(lust_unit.get_effective_stat(&"armor"), 12.4), "Death scaling affects armor but never attack speed.")
	lust_unit.current_hp = 500.0
	lust_unit._clamp_current_hp_to_max()
	_check(is_equal_approx(lust_unit.current_hp, 124.0), "Current HP remains safely clamped when effective max HP is evaluated.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(lust_unit)
	_check(panel.status_summary_text().contains("2 allied deaths") and panel.status_summary_text().contains("HP/Damage/Armor +24%"), "Status indicators expose Lust's active death count and affected stats.")
	panel.free()
	session.free()


func _test_recruitment() -> void:
	var lust := _snapshot("lust", LUST_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 200.0, 10.0)
	lust.abilities = [_ability(&"ability.lust_fallen_devotion", 1)]
	var near_b := _snapshot("enemy-b", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 25.0)
	var near_a := _snapshot("enemy-a", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 20.0)
	near_a.abilities = [_ability(&"ability.enemy_summon", 1)]
	var boss := _snapshot("boss", &"enemy.iron_warden", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 100.0)
	boss.is_boss = true
	var far := _snapshot("far", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	var session := _session([lust], [near_b, near_a, boss, far], 9704)
	var lust_unit := _unit(session, "lust")
	lust_unit.position = Vector2(300, 300)
	for id in ["enemy-a", "enemy-b", "boss"]:
		_unit(session, id).position = Vector2(400, 300)
		_unit(session, id).current_hp = 99.0
	_unit(session, "far").position = Vector2(700, 300)
	_unit(session, "far").current_hp = 1.0
	var chosen := _unit(session, "enemy-a")
	var modifier := StatModifier.new()
	modifier.stat = "damage"
	modifier.operation = StatModifier.Operation.MULTIPLY
	modifier.value = 1.5
	chosen.add_temporary_modifier(modifier, 10.0, lust_unit, &"ability.test", &"effect.test")
	var ability := _ability(&"ability.lust_recruit", 1)
	session.deliver_ability(lust_unit, lust_unit, ability)
	_check(chosen.snapshot.team == CombatUnitSnapshot.Team.PLAYER and chosen.current_hp == 99.0 and chosen.get_effective_stat(&"damage") == 30.0, "Recruitment chooses nearest/runtime-ID deterministically and retains current HP and effective stats.")
	_check(chosen.snapshot.abilities.size() == 1 and chosen.snapshot.attack_type == near_a.attack_type and chosen.target == null, "Recruitment retains attack type and abilities while clearing stale actions.")
	_check(_unit(session, "enemy-b").snapshot.team == CombatUnitSnapshot.Team.ENEMY and _unit(session, "boss").snapshot.team == CombatUnitSnapshot.Team.ENEMY and _unit(session, "far").snapshot.team == CombatUnitSnapshot.Team.ENEMY, "Recruitment excludes boss, out-of-radius, and non-selected enemies.")
	_check(int(session.statistics.unit_stats["enemy-a"].team) == CombatUnitSnapshot.Team.PLAYER, "Combat statistics immediately use the recruited unit's current team.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(chosen)
	_check(panel.status_summary_text().contains("Recruited") and panel.status_summary_text().contains("permanent"), "Recruited is exposed as a permanent combat status indicator.")
	panel.free()
	chosen.force_die(_unit(session, "enemy-b"), &"effect.test")
	_check(session.get_lust_allied_death_count(lust_unit) == 1 and is_equal_approx(lust_unit.get_effective_stat(&"damage"), 10.6), "A recruited unit's later death counts as an allied death based on its current team.")
	var exact := _unit(session, "enemy-b")
	exact.current_hp = 100.0
	_check(not (ability.effects[0] as LustRecruitEffect).can_apply(lust_unit, lust_unit, ability), "Recruitment HP comparison is strict when remaining candidates are at or above threshold, bosses, or outside radius.")
	session.free()


func _test_target_slow() -> void:
	var lust := _snapshot("lust", LUST_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 200.0, 10.0)
	lust.abilities = [_ability(&"ability.lust_beguiling_presence", 2)]
	var ally := _snapshot("ally", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 200.0, 10.0)
	var enemy := _snapshot("enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 200.0, 10.0)
	enemy.stats.attack_speed = 2.0
	var session := _session([lust, ally], [enemy], 9705)
	var lust_unit := _unit(session, "lust")
	var enemy_unit := _unit(session, "enemy")
	enemy_unit.target = lust_unit
	enemy_unit.basic_attack_target_active = true
	_check(is_equal_approx(enemy_unit.get_effective_stat(&"attack_speed"), 1.3), "An enemy currently targeting Lust attacks 35% slower.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(enemy_unit)
	_check(panel.status_summary_text().contains("Beguiling Presence") and panel.status_summary_text().contains("-35%"), "The target-conditional slow appears in the enemy status indicators.")
	enemy_unit.target = _unit(session, "ally")
	_check(is_equal_approx(enemy_unit.get_effective_stat(&"attack_speed"), 2.0), "The attack-speed debuff disappears immediately when the enemy changes target.")
	panel.free()
	session.free()


func _test_fatal_bond() -> void:
	var lust := _snapshot("lust", LUST_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 200.0, 10.0)
	lust.abilities = [_ability(&"ability.lust_fatal_bond", 2)]
	var strongest_b := _snapshot("strong-b", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 200.0, 30.0)
	var strongest_a := _snapshot("strong-a", &"hero.control_savant", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 200.0, 30.0)
	var enemy := _snapshot("enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	var session := _session([lust, strongest_b, strongest_a], [enemy], 9706)
	var lust_unit := _unit(session, "lust")
	var partner := _unit(session, "strong-a")
	_check(lust_unit.lust_bond_partner == partner and partner.lust_bond_partner == lust_unit, "Fatal Bond includes Heroes and uses highest damage with stable runtime-ID tie break.")
	_check(is_equal_approx(lust_unit.get_effective_stat(&"attack_speed"), 1.8) and is_equal_approx(partner.get_effective_stat(&"attack_speed"), 1.8), "Both bond members gain the Level 2 x1.8 attack-speed multiplier.")
	partner.current_hp = 100.0
	var damage_dealt := _unit(session, "enemy").take_damage(50.0, partner, &"ability.test", &"effect.periodic")
	_check(is_equal_approx(damage_dealt, 50.0) and is_equal_approx(partner.current_hp, 115.0), "Bond lifesteal heals from non-basic ability or periodic damage.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(partner)
	_check(panel.status_summary_text().contains("Fatal Bond with lust") and panel.status_summary_text().contains("30% all-damage lifesteal"), "Both bond members expose partner and bonuses through status indicators.")
	panel.free()
	lust_unit.force_die(_unit(session, "enemy"), &"effect.test")
	_check(not lust_unit.is_alive() and not partner.is_alive(), "Death of either bond member force-kills the other exactly once without recursion.")
	_check(int(session.statistics.unit_stats["lust"].deaths) == 1 and int(session.statistics.unit_stats["strong-a"].deaths) == 1, "Mutual bond death records each death once.")
	session.free()
	var alone := _snapshot("alone", LUST_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 10.0)
	alone.abilities = [_ability(&"ability.lust_fatal_bond", 1)]
	var alone_session := _session([alone], [enemy], 9707)
	_check(_unit(alone_session, "alone").lust_bond_partner == null, "Fatal Bond remains inactive when Lust has no ally.")
	alone_session.free()


func _test_heartbreaker() -> void:
	var lust := _snapshot("lust", LUST_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 200.0, 10.0)
	lust.abilities = [_ability(&"ability.lust_heartbreaker", 4)]
	var enemy := _snapshot("enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([lust], [enemy], 9708)
	var lust_unit := _unit(session, "lust")
	var enemy_unit := _unit(session, "enemy")
	lust_unit.position = Vector2(300, 300)
	enemy_unit.position = Vector2(400, 300)
	var expected_x := 400.0
	var ability_hit := enemy_unit.take_damage(10.0, lust_unit, &"ability.test", &"effect.test")
	expected_x += _hit_knockback(enemy_unit, ability_hit)
	_check(lust_unit.lust_basic_hit_count == 0, "Ability damage does not increment Heartbreaker.")
	for hit in 2:
		var dealt := enemy_unit.take_damage(10.0, lust_unit)
		expected_x += _hit_knockback(enemy_unit, dealt)
		lust_unit.record_successful_basic_hit(enemy_unit, dealt)
	_check(lust_unit.lust_basic_hit_count == 2 and is_equal_approx(enemy_unit.position.x, expected_x), "Heartbreaker counts only successful basic hits while every damaging hit applies global knockback.")
	var dealt := enemy_unit.take_damage(10.0, lust_unit)
	expected_x += _hit_knockback(enemy_unit, dealt)
	lust_unit.record_successful_basic_hit(enemy_unit, dealt)
	_check(lust_unit.lust_basic_hit_count == 0 and is_equal_approx(enemy_unit.position.x, expected_x + 80.0), "The third Level 4 basic hit adds Heartbreaker's 80-unit knockback after the damage-scaled hit reaction and resets the counter.")
	_check(enemy_unit.has_status(&"status.stun") and is_equal_approx(enemy_unit.statuses[-1].remaining_duration, 1.2), "Heartbreaker applies the approved Level 4 stun through the existing status system.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(enemy_unit)
	_check(panel.status_summary_text().contains("Stun") and panel.status_summary_text().contains("1.2 s"), "Heartbreaker stun appears in the status indicators with duration.")
	_check(panel.get_node("%StatusIcons").visible and panel.get_node("%StatusIcons").get_child_count() == 1 and panel.get_node("%StatusIcons").get_child(0) is StatusEffectIcon, "An active stun renders as a circular status indicator above the stat row.")
	panel.free()
	session.free()


func _ability(ability_id: StringName, level: int) -> AbilityDefinition:
	return (registry.get_definition(ability_id) as AbilityDefinition).for_hero_level(level)


func _snapshot(runtime_id: String, definition_id: StringName, team: int, kind: int, hp: float, damage: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = definition_id
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = kind
	snapshot.stats.max_hp = hp
	snapshot.stats.damage = damage
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 100.0
	snapshot.stats.armor = 0.0
	return snapshot


func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot], seed: int) -> CombatSession:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, seed)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	return session


func _unit(session: CombatSession, runtime_id: String) -> Combatant:
	return session.get_combatant_by_runtime_id(runtime_id)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _hit_knockback(unit: Combatant, damage: float) -> float:
	var distance := unit.damage_knockback_for(damage)
	return distance if distance >= 0.5 else 0.0
