extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")
const SELECTED_PANEL_SCENE := preload("res://ui/combat/selected_unit_panel.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_thresholds()
	_test_replacement_and_projectile()
	_test_impact_aoe_and_burn()
	_test_tooltips()
	_test_management_preview()
	_test_warrior_bloodthirst()
	_test_militia_strength_in_numbers()
	if failures == 0:
		print("Job professionalism tests passed.")
		quit()
	else:
		push_error("Job professionalism tests failed: %d" % failures)
		quit(1)


func _test_content_and_thresholds() -> void:
	var job := registry.get_definition(&"job.archer", false) as JobDefinition
	var tier_1 := registry.get_definition(&"ability.archer_professionalism_fire_arrow_tier_1", false) as AbilityDefinition
	var tier_2 := registry.get_definition(&"ability.archer_professionalism_fire_arrow_tier_2", false) as AbilityDefinition
	_check(job != null and job.available_ability_ids == [tier_1.id, tier_2.id], "Archer offers both skill levels through its Market catalog.")
	_check(tier_1.upgrades_ability_id.is_empty() and tier_2.upgrades_ability_id == tier_1.id and tier_1.price > 0 and tier_2.price > 0, "Fire Arrow II requires a purchased Fire Arrow I.")
	_check(tier_1 != null and tier_2 != null and tier_1.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK and tier_2.activation_mode == AbilityDefinition.ActivationMode.REPLACE_BASIC_ATTACK, "Both professionalism tiers are generic basic-attack replacements.")
	_check(tier_1.cooldown_seconds == 5.0 and tier_2.cooldown_seconds == 5.0 and tier_1.area_radius == 150.0 and tier_2.area_radius == 150.0, "Both fire arrows author the exact cooldown and impact radius.")
	_check((tier_1.effects[0] as DamageEffect).amount == 50.0 and (tier_2.effects[0] as DamageEffect).amount == 100.0, "Fire Arrow impact values are exact.")
	var burn_1 := (tier_1.effects[1] as ApplyStatusEffect).status
	var burn_2 := (tier_2.effects[1] as ApplyStatusEffect).status
	_check(burn_1.id == burn_2.id and burn_1.id == &"status.archer_professionalism_burn" and burn_1.default_duration == 5.0 and burn_1.max_stacks == 1 and burn_1.stack_policy == StatusDefinition.StackPolicy.REFRESH_DURATION, "Fire Arrow burn has one shared refresh-only status ID and five-second duration.")
	_check((burn_1.periodic_effects[0] as DamageEffect).amount == 20.0 and (burn_2.periodic_effects[0] as DamageEffect).amount == 40.0, "Fire Arrow burn tier damage values are exact without changing global Burn.")
	var invalid_job := JobDefinition.new()
	invalid_job.id = &"job.invalid_upgrade_chain"
	invalid_job.stat_modifiers = StatBlock.new()
	invalid_job.available_ability_ids = [tier_2.id]
	_check(not registry._validate_job(invalid_job, false), "Content validation rejects an upgrade whose preceding level is absent from its Job catalog.")

	for count in [0, 2, 3, 5, 6, 8]:
		var run := _run_with_archers(count)
		var build := JobBuildState.new()
		build.job_id = &"job.archer"
		run.job_builds.append(build)
		var snapshots := CombatSnapshotBuilder.build_player_army(run, registry)
		for snapshot in snapshots:
			_check(not snapshot.abilities.has(tier_1) and not snapshot.abilities.has(tier_2), "%d Archers do not unlock skills by assignment count." % count)
		build.set_active_ability(tier_1.id)
		var bought := CombatSnapshotBuilder.build_player_army(run, registry)
		for snapshot in bought:
			if snapshot.job_id == job.id:
				_check(snapshot.abilities.has(tier_1) and not snapshot.abilities.has(tier_2), "Purchased Fire Arrow I applies to every Archer independently of count.")
		build.unlock_ability(tier_2.id)
		build.equip_purchased_ability(tier_2)
		for snapshot in CombatSnapshotBuilder.build_player_army(run, registry):
			if snapshot.job_id == job.id:
				_check(snapshot.abilities.has(tier_2) and not snapshot.abilities.has(tier_1), "A purchased upgrade replaces the previous level rather than stacking it.")


func _test_replacement_and_projectile() -> void:
	var fire_arrow := registry.get_definition(&"ability.archer_professionalism_fire_arrow_tier_1") as AbilityDefinition
	var archer := _snapshot("archer", CombatUnitSnapshot.Team.PLAYER, 500.0, 0.0)
	archer.attack_type = &"ranged"
	archer.targeting_mode = &"farthest"
	archer.stats.attack_range = 500.0
	archer.abilities.append(fire_arrow)
	var forced_target := _snapshot("forced", CombatUnitSnapshot.Team.ENEMY, 1000.0, 0.0)
	var closer_target := _snapshot("closer", CombatUnitSnapshot.Team.ENEMY, 1000.0, 0.0)
	var session := _session([archer], [forced_target, closer_target], 8801)
	var attacker := session.get_combatant_by_runtime_id("archer")
	var forced := session.get_combatant_by_runtime_id("forced")
	var closer := session.get_combatant_by_runtime_id("closer")
	attacker.position = Vector2(100.0, 200.0)
	forced.position = Vector2(450.0, 200.0)
	closer.position = Vector2(250.0, 200.0)
	attacker.forced_basic_target = forced
	attacker.forced_basic_target_remaining = 2.0
	attacker._acquire_target()
	attacker._move_toward_target(0.0)
	_check(attacker.target == forced and attacker.pending_ability == fire_arrow and is_equal_approx(attacker.windup_duration, Combatant.RANGED_ATTACK_PAUSE), "Fire Arrow uses the forced basic target and normal ranged windup.")
	attacker._update_attack_windup(Combatant.RANGED_ATTACK_PAUSE)
	var projectiles := session.get_node("Projectiles")
	var ability_projectile := projectiles.get_child(0) as CombatProjectile
	_check(attacker.ability_cooldowns.get(fire_arrow.id, 0.0) == 5.0, "Fire Arrow cooldown starts when its projectile launches.")
	_check(ability_projectile != null and ability_projectile.visible and ability_projectile.ability == fire_arrow, "Fire Arrow launches an actual visible ability projectile.")
	_check(is_equal_approx(attacker.state_timer, 0.9), "Fire Arrow uses normal attack-speed recovery after its ranged windup.")
	_check(not attacker.prefers_farthest_enemy, "A replacement consumes the one-time farthest basic targeting preference like an ordinary basic attack.")
	var selected_panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(selected_panel)
	selected_panel.show_combatant(attacker)
	var fire_arrow_slot := selected_panel.get_node("%AbilityIcons").get_child(0) as ContentIconButton
	_check(fire_arrow_slot.content_id == fire_arrow.id and fire_arrow_slot.badge_text == "R", "Selected combat unit marks Fire Arrow's icon as a basic replacement.")
	_check(fire_arrow_slot is AbilityCooldownIcon and is_equal_approx((fire_arrow_slot as AbilityCooldownIcon).cooldown_ratio, 1.0), "Selected combat unit renders Fire Arrow's active cooldown as a MOBA-style overlay.")
	(fire_arrow_slot as AbilityCooldownIcon).set_cooldown(2.5, 5.0)
	_check(is_equal_approx((fire_arrow_slot as AbilityCooldownIcon).cooldown_ratio, 0.5) and fire_arrow_slot.get_theme_color("icon_normal_color").is_equal_approx(Color.WHITE), "Cooldown progression reveals the ability icon from top to bottom without globally fading it.")
	selected_panel.free()
	attacker.target = closer
	attacker._start_attack()
	_check(attacker.pending_ability == null, "The next attack remains ordinary while Fire Arrow is cooling down.")
	attacker._update_attack_windup(Combatant.RANGED_ATTACK_PAUSE)
	_check(projectiles.get_child_count() == 2 and (projectiles.get_child(1) as CombatProjectile).ability == null, "A normal basic projectile launches during Fire Arrow cooldown.")
	session.free()


func _test_impact_aoe_and_burn() -> void:
	var fire_arrow := registry.get_definition(&"ability.archer_professionalism_fire_arrow_tier_2") as AbilityDefinition
	var source_snapshot := _snapshot("source", CombatUnitSnapshot.Team.PLAYER, 1000.0, 0.0)
	var ally_snapshot := _snapshot("ally", CombatUnitSnapshot.Team.PLAYER, 1000.0, 100.0)
	var impact_snapshot := _snapshot("impact", CombatUnitSnapshot.Team.ENEMY, 1000.0, 100.0)
	var inside_snapshot := _snapshot("inside", CombatUnitSnapshot.Team.ENEMY, 1000.0, 100.0)
	var boundary_snapshot := _snapshot("boundary", CombatUnitSnapshot.Team.ENEMY, 1000.0, 100.0)
	var outside_snapshot := _snapshot("outside", CombatUnitSnapshot.Team.ENEMY, 1000.0, 100.0)
	var session := _session([source_snapshot, ally_snapshot], [impact_snapshot, inside_snapshot, boundary_snapshot, outside_snapshot], 8802)
	var source := session.get_combatant_by_runtime_id("source")
	var ally := session.get_combatant_by_runtime_id("ally")
	var impact := session.get_combatant_by_runtime_id("impact")
	var inside := session.get_combatant_by_runtime_id("inside")
	var boundary := session.get_combatant_by_runtime_id("boundary")
	var outside := session.get_combatant_by_runtime_id("outside")
	source.position = Vector2(100.0, 300.0)
	impact.position = Vector2(500.0, 300.0)
	inside.position = Vector2(500.0, 151.0)
	boundary.position = Vector2(500.0, 450.0)
	outside.position = Vector2(500.0, 451.0)
	ally.position = Vector2(500.0, 300.0)
	var projectile := CombatProjectile.new()
	session.get_node("Projectiles").add_child(projectile)
	projectile.setup_ability(source, impact, fire_arrow, fire_arrow.presentation_color)
	impact.position += Vector2(20.0, 0.0)
	inside.position += Vector2(20.0, 0.0)
	boundary.position += Vector2(20.0, 0.0)
	outside.position += Vector2(20.0, 0.0)
	ally.position += Vector2(20.0, 0.0)
	projectile.position = impact.position
	projectile._physics_process(0.01)
	_check(is_equal_approx(impact.current_hp, 950.0) and is_equal_approx(inside.current_hp, 950.0) and is_equal_approx(boundary.current_hp, 950.0), "Projectile impact AoE includes moved enemies inside and exactly on radius 150, with armor reducing 100 raw damage to 50.")
	_check(is_equal_approx(outside.current_hp, 1000.0) and is_equal_approx(ally.current_hp, 1000.0), "Projectile impact AoE excludes enemies outside radius and all allies.")
	_check(impact.statuses.size() == 1 and inside.statuses.size() == 1 and boundary.statuses.size() == 1 and outside.statuses.is_empty() and ally.statuses.is_empty(), "Burn applies only to enemy-team units hit by the impact AoE.")

	impact._update_runtime(1.0)
	impact._update_runtime(1.0)
	_check(is_equal_approx(impact.current_hp, 910.0), "Tier 2 burn deals 40 raw armored damage per second.")
	var burn := impact.statuses[0]
	var status_definition := (fire_arrow.effects[1] as ApplyStatusEffect).status
	impact.apply_status(status_definition, source, fire_arrow.id)
	_check(impact.statuses.size() == 1 and is_equal_approx(burn.remaining_duration, 5.0), "Burn refreshes to five seconds without creating a second status or stack.")
	var hp_before_five_ticks := impact.current_hp
	for tick in 5:
		impact._update_runtime(1.0)
	_check(is_equal_approx(impact.current_hp, hp_before_five_ticks - 100.0) and impact.statuses.is_empty(), "Refreshed Tier 2 burn produces exactly five armored ticks and then expires.")
	var attributed_damage := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.DAMAGE_APPLIED and event.source_id == "source" and event.ability_id == fire_arrow.id)
	_check(attributed_damage.size() >= 8, "Fire Arrow impact and periodic damage retain source and ability attribution.")
	session.free()


func _test_tooltips() -> void:
	var job_text := ContentButton.describe_content(&"job.archer")
	var ability_text := ContentButton.describe_content(&"ability.archer_professionalism_fire_arrow_tier_1")
	_check(job_text.contains("MARKET SKILLS") and job_text.contains("Level 1: Fire Arrow I") and job_text.contains("Level 2: Fire Arrow II") and not job_text.contains("PROFESSIONALISM"), "Job tooltip lists purchasable levels instead of assignment thresholds.")
	_check(ability_text.contains("EMPOWERED ATTACK") and ability_text.contains("radius.png[/img] [b]150[/b]") and ability_text.contains("50[/b] damage"), "Ability tooltip identifies empowered attacks, radius and damage from data.")


func _test_management_preview() -> void:
	var run := DemoRunFactory.create_starting_run(8803)
	run.unlocked_job_ids.append(&"job.archer")
	run.job_capacities["job.archer"] = 3
	for index in 3:
		run.soldiers[index].current_job_id = &"job.archer"
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	screen._select_unit("soldier", 0)
	var ability_rows := screen.get_node("%AbilityRows")
	var has_fire_arrow_icon := ability_rows.get_children().any(func(slot: Node) -> bool: return slot is ContentIconButton and slot.content_id == &"ability.archer_professionalism_fire_arrow_tier_1")
	_check(ability_rows.get_child_count() >= HeroState.MAX_ABILITY_SLOTS and has_fire_arrow_icon, "Management shows unpurchased skills and reserves four icon slots.")
	var preview := ability_rows.get_children().filter(func(slot: Node) -> bool: return slot is ContentIconButton and slot.content_id == &"ability.archer_professionalism_fire_arrow_tier_1")[0] as ContentIconButton
	_check(preview.locked and preview.badge_text == "NOT BOUGHT" and preview.tooltip_override.contains("NOT PURCHASED"), "Unpurchased skills explain that they must be bought in the Market.")
	var archer_heading := screen.get_node("%Roster").get_children().filter(func(row: Node) -> bool: return row is ManagementDropSlot and row.target_payload.get("job_id", &"") == &"job.archer")
	_check(not archer_heading.is_empty() and not archer_heading[0].text.contains("PROFESSIONALISM") and not archer_heading[0].text.contains("NEXT"), "Management Job rows omit professionalism tier and threshold text.")
	screen.free()


func _test_warrior_bloodthirst() -> void:
	var warrior_job := registry.get_definition(&"job.warrior") as JobDefinition
	_check(warrior_job.available_ability_ids.size() == 2, "Warrior has two purchasable skill levels.")
	var tier_1 := registry.get_definition(&"ability.warrior_professionalism_bloodthirst_tier_1") as AbilityDefinition
	var tier_2 := registry.get_definition(&"ability.warrior_professionalism_bloodthirst_tier_2") as AbilityDefinition
	var warrior_a := _snapshot("warrior-a", CombatUnitSnapshot.Team.PLAYER, 400.0, 0.0)
	warrior_a.job_id = &"job.warrior"
	warrior_a.abilities = [tier_2]
	var warrior_b := _snapshot("warrior-b", CombatUnitSnapshot.Team.PLAYER, 400.0, 0.0)
	warrior_b.job_id = &"job.warrior"
	warrior_b.abilities = [tier_2]
	var ogre := _snapshot("ogre", CombatUnitSnapshot.Team.ENEMY, 5000.0, 60.0)
	var session := _session([warrior_a, warrior_b], [ogre], 7301)
	var unit_a := session.get_combatant_by_runtime_id("warrior-a")
	var unit_b := session.get_combatant_by_runtime_id("warrior-b")
	var target := session.get_combatant_by_runtime_id("ogre")
	unit_a.current_hp = 100.0
	var healed := unit_a.apply_basic_attack_lifesteal(40.0)
	_check(is_equal_approx(healed, 20.0) and is_equal_approx(unit_a.current_hp, 120.0), "Bloodthirst heals for 50% of basic attack damage.")
	for hit in 7:
		unit_a.record_successful_basic_hit(target, 10.0)
	for hit in 7:
		unit_b.record_successful_basic_hit(target, 10.0)
	var sunder := target.statuses.filter(func(status: StatusInstance) -> bool: return status.definition.id == &"status.warrior_sundered_armor")
	_check(sunder.size() == 1 and sunder[0].stacks == 10, "Sundered Armor stacks from every Warrior share one 10-stack cap on a target.")
	_check(is_equal_approx(target.get_effective_stat(&"armor"), 10.0), "Ten Sundered Armor stacks remove 50 armor.")
	_check(tier_1.effects.size() == 1 and tier_1.effects[0] is BasicAttackLifestealEffect, "Bloodthirst I only grants lifesteal.")
	session.free()


func _test_militia_strength_in_numbers() -> void:
	var militia_job := registry.get_definition(&"job.militia") as JobDefinition
	_check(militia_job.innate_ability_ids.has(&"ability.militia_strength_in_numbers"), "Militia has Strength in Numbers as an innate ability.")
	var ability := registry.get_definition(&"ability.militia_strength_in_numbers") as AbilityDefinition
	var players: Array[CombatUnitSnapshot] = []
	for index in 7:
		var snapshot := _snapshot("militia-%d" % index, CombatUnitSnapshot.Team.PLAYER, 150.0, 4.0)
		snapshot.job_id = &"job.militia"
		snapshot.abilities = [ability]
		players.append(snapshot)
	var session := _session(players, [_snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 100.0, 0.0)], 7302)
	var units: Array[Combatant] = []
	for index in 7:
		var unit := session.get_combatant_by_runtime_id("militia-%d" % index)
		unit.position = Vector2(2000.0 + index * 400.0, 300.0)
		units.append(unit)
	_check(is_equal_approx(units[0].get_effective_stat(&"armor"), 4.0), "A lone Militia gets no Strength in Numbers bonus.")
	units[1].position = units[0].position + Vector2(100.0, 0.0)
	units[2].position = units[0].position + Vector2(0.0, 150.0)
	_check(is_equal_approx(units[0].get_effective_stat(&"armor"), 10.0), "Each other Militia within range adds 3 armor.")
	for index in range(3, 7):
		units[index].position = units[0].position + Vector2(-50.0 - index, 0.0)
	_check(is_equal_approx(units[0].get_effective_stat(&"armor"), 19.0), "Strength in Numbers caps at five other Militia (+15 armor).")
	session.free()


func _run_with_archers(count: int) -> RunState:
	var run := RunState.new()
	for index in count:
		var soldier := SoldierState.new()
		soldier.unique_id = "archer-%d" % index
		soldier.generated_name = "Archer %d" % index
		soldier.current_job_id = &"job.archer"
		run.soldiers.append(soldier)
	var militia := SoldierState.new()
	militia.unique_id = "militia"
	militia.generated_name = "Militia"
	run.soldiers.append(militia)
	return run


func _snapshot(runtime_id: String, team: int, max_hp: float, armor: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER if team == CombatUnitSnapshot.Team.PLAYER else CombatUnitSnapshot.UnitKind.ENEMY
	snapshot.stats.max_hp = max_hp
	snapshot.stats.damage = 10.0
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 100.0
	snapshot.stats.armor = armor
	return snapshot


func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot], seed: int) -> CombatSession:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 700.0)
	root.add_child(session)
	session.setup(players, enemies, seed)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	return session


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
