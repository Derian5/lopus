extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_state_and_snapshot_defaults()
	_test_initial_formation()
	_test_target_preferences()
	_test_melee_attack_range()
	_test_melee_avoidance()
	_test_damage_and_healing_reactions()
	_test_facing_while_retreating()
	_test_projectile_outlives_target()
	if failures == 0:
		print("Combat behavior tests passed.")
		quit()
	else:
		push_error("Combat behavior tests failed: %d" % failures)
		quit(1)


func _test_state_and_snapshot_defaults() -> void:
	var run := DemoRunFactory.create_starting_run(9601)
	var melee_hero := CombatSnapshotBuilder.build_hero(run.heroes[0], run.inventory, registry)
	_check(melee_hero.targeting_mode == &"closest" and not melee_hero.avoids_damage, "Melee units default to nearest targeting without damage avoidance.")
	run.soldiers[0].current_job_id = &"job.archer"
	var ranged_soldier := CombatSnapshotBuilder.build_soldier(run.soldiers[0], null, registry)
	_check(ranged_soldier.avoids_damage, "Ranged units default to damage avoidance.")
	run.soldiers[0].targeting_mode = &"farthest"
	run.soldiers[0].damage_avoidance_override = 0
	var restored := SoldierState.from_dictionary(run.soldiers[0].to_dictionary())
	_check(restored.targeting_mode == &"farthest" and restored.damage_avoidance_override == 0, "Individual Soldier behavior survives serialization.")


func _test_target_preferences() -> void:
	var closest_snapshot := _snapshot("closest", CombatUnitSnapshot.Team.PLAYER)
	var farthest_snapshot := _snapshot("farthest", CombatUnitSnapshot.Team.PLAYER)
	farthest_snapshot.targeting_mode = &"farthest"
	var near_enemy := _snapshot("near", CombatUnitSnapshot.Team.ENEMY)
	var far_enemy := _snapshot("far", CombatUnitSnapshot.Team.ENEMY)
	var session := _session([closest_snapshot, farthest_snapshot], [near_enemy, far_enemy], 9602)
	var closest := session.get_combatant_by_runtime_id("closest")
	var farthest := session.get_combatant_by_runtime_id("farthest")
	var near := session.get_combatant_by_runtime_id("near")
	var far := session.get_combatant_by_runtime_id("far")
	closest.position = Vector2(100.0, 200.0)
	farthest.position = Vector2(100.0, 300.0)
	near.position = Vector2(250.0, 250.0)
	far.position = Vector2(900.0, 250.0)
	_check(session.find_basic_attack_target(closest) == near, "Nearest targeting selects the closest available enemy.")
	_check(session.find_basic_attack_target(farthest) == far, "Farthest targeting selects the farthest enemy on the field even outside attack range.")
	far.position = Vector2(130.0, 300.0)
	farthest.target = far
	farthest._start_attack()
	farthest._update_attack_windup(1.0)
	far.position = Vector2(900.0, 250.0)
	_check(not farthest.prefers_farthest_enemy and session.find_basic_attack_target(farthest) == near, "After its first basic attack, a farthest-targeting unit switches to nearest targeting for the rest of combat.")
	_check(farthest.snapshot.targeting_mode == &"farthest", "The combat-only switch does not overwrite the persisted Management preference.")
	session.free()


func _test_initial_formation() -> void:
	var player_ranged_a := _snapshot("player-ranged-a", CombatUnitSnapshot.Team.PLAYER)
	player_ranged_a.attack_type = &"ranged"
	var player_melee_a := _snapshot("player-melee-a", CombatUnitSnapshot.Team.PLAYER)
	var player_ranged_b := _snapshot("player-ranged-b", CombatUnitSnapshot.Team.PLAYER)
	player_ranged_b.attack_type = &"ranged"
	var player_melee_b := _snapshot("player-melee-b", CombatUnitSnapshot.Team.PLAYER)
	var enemy_ranged_a := _snapshot("enemy-ranged-a", CombatUnitSnapshot.Team.ENEMY)
	enemy_ranged_a.attack_type = &"ranged"
	var enemy_melee_a := _snapshot("enemy-melee-a", CombatUnitSnapshot.Team.ENEMY)
	var enemy_ranged_b := _snapshot("enemy-ranged-b", CombatUnitSnapshot.Team.ENEMY)
	enemy_ranged_b.attack_type = &"ranged"
	var enemy_melee_b := _snapshot("enemy-melee-b", CombatUnitSnapshot.Team.ENEMY)
	var session := _session(
		[player_ranged_a, player_melee_a, player_ranged_b, player_melee_b],
		[enemy_ranged_a, enemy_melee_a, enemy_ranged_b, enemy_melee_b],
		9604
	)
	var player_ranged_x := [session.get_combatant_by_runtime_id("player-ranged-a").position.x, session.get_combatant_by_runtime_id("player-ranged-b").position.x]
	var player_melee_x := [session.get_combatant_by_runtime_id("player-melee-a").position.x, session.get_combatant_by_runtime_id("player-melee-b").position.x]
	var enemy_ranged_x := [session.get_combatant_by_runtime_id("enemy-ranged-a").position.x, session.get_combatant_by_runtime_id("enemy-ranged-b").position.x]
	var enemy_melee_x := [session.get_combatant_by_runtime_id("enemy-melee-a").position.x, session.get_combatant_by_runtime_id("enemy-melee-b").position.x]
	_check(player_ranged_x.max() < player_melee_x.min(), "Every allied ranged unit starts behind every allied melee unit.")
	_check(enemy_ranged_x.min() > enemy_melee_x.max(), "Every enemy ranged unit starts behind every enemy melee unit.")
	session.free()


func _test_melee_attack_range() -> void:
	var attacker_snapshot := _snapshot("range-attacker", CombatUnitSnapshot.Team.PLAYER)
	attacker_snapshot.stats.attack_range = 50.0
	var target_snapshot := _snapshot("range-target", CombatUnitSnapshot.Team.ENEMY)
	var session := _session([attacker_snapshot], [target_snapshot], 9605)
	var attacker := session.get_combatant_by_runtime_id("range-attacker")
	var target := session.get_combatant_by_runtime_id("range-target")
	attacker.position = Vector2(300.0, 300.0)
	target.position = Vector2(420.0, 300.0)
	attacker.target = target
	attacker.state = Combatant.State.MOVE_INTO_RANGE
	attacker._move_toward_target(0.0)
	_check(attacker.state == Combatant.State.MOVE_INTO_RANGE, "A melee unit stays out of attack windup beyond its authored reach.")

	attacker.position = Vector2(300.0, 300.0)
	attacker.snapshot.stats.attack_range = 100.0
	attacker.state = Combatant.State.MOVE_INTO_RANGE
	attacker._move_toward_target(0.0)
	_check(attacker.state == Combatant.State.ATTACK_WINDUP, "Increasing melee attack range lets the unit begin attacking from farther away.")

	var exact_reach := attacker.basic_attack_reach(target)
	var hp_before := target.current_hp
	target.position = attacker.position + Vector2(exact_reach + 0.02, 0.0)
	attacker._update_attack_windup(attacker.windup_duration)
	_check(attacker.state == Combatant.State.MOVE_INTO_RANGE and target.current_hp == hp_before, "A melee target just beyond exact reach takes no damage after windup.")
	target.position = attacker.position + Vector2(exact_reach, 0.0)
	attacker.target = target
	attacker._start_attack()
	attacker._update_attack_windup(attacker.windup_duration)
	_check(target.current_hp < hp_before, "A melee target at exact authored reach is hit.")
	session.free()


func _test_melee_avoidance() -> void:
	var avoiding_snapshot := _snapshot("avoiding", CombatUnitSnapshot.Team.PLAYER)
	avoiding_snapshot.avoids_damage = true
	var steady_snapshot := _snapshot("steady", CombatUnitSnapshot.Team.PLAYER)
	var attacker_snapshot := _snapshot("attacker", CombatUnitSnapshot.Team.ENEMY)
	attacker_snapshot.stats.damage = 5.0
	var session := _session([avoiding_snapshot, steady_snapshot], [attacker_snapshot], 9603)
	var avoiding := session.get_combatant_by_runtime_id("avoiding")
	var steady := session.get_combatant_by_runtime_id("steady")
	var attacker := session.get_combatant_by_runtime_id("attacker")
	avoiding.position = Vector2(300.0, 250.0)
	steady.position = Vector2(300.0, 400.0)
	attacker.position = Vector2(330.0, 250.0)
	var attacker_hp := attacker.current_hp
	avoiding.take_damage(5.0, attacker, &"attack.basic", &"attack.basic", true)
	var configured_retreat_duration := avoiding.melee_retreat_remaining
	_check(configured_retreat_duration > 0.0 and avoiding.melee_retreat_counterattack_pending, "An avoiding melee unit starts its configured retreat with a ready counterattack.")
	avoiding._update_melee_retreat(0.1)
	avoiding._update_melee_retreat(1.0)
	_check(attacker.current_hp < attacker_hp, "The retreating melee unit attacks its melee attacker once when its attack is ready.")
	var retreat_position := avoiding.position
	avoiding._update_melee_retreat(0.4)
	_check(avoiding.position.x < retreat_position.x, "After counterattacking, the melee unit continues moving away from its attacker.")
	avoiding.take_damage(5.0, attacker, &"attack.basic", &"attack.basic", true)
	_check(avoiding.melee_retreat_remaining == configured_retreat_duration, "Another melee hit restarts the retreat timer.")
	steady.take_damage(5.0, attacker, &"attack.basic", &"attack.basic", true)
	_check(steady.melee_retreat_remaining == 0.0, "A melee unit with avoidance disabled does not retreat.")
	session.free()


func _test_damage_and_healing_reactions() -> void:
	var ally_snapshot := _snapshot("ally", CombatUnitSnapshot.Team.PLAYER)
	var enemy_snapshot := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY)
	var session := _session([ally_snapshot], [enemy_snapshot], 9604)
	var ally := session.get_combatant_by_runtime_id("ally")
	var enemy := session.get_combatant_by_runtime_id("enemy")
	ally.position = Vector2(300.0, 300.0)
	enemy.position = Vector2(200.0, 300.0)
	ally.add_shield(100.0, 5.0, ally, &"ability.test_shield", &"effect.test_shield")
	var ally_hp := ally.current_hp
	ally.take_damage(20.0, enemy)
	_check(ally.current_hp == ally_hp and ally.shields[0].amount == 80.0, "Shield damage remains absorbed without reducing HP.")
	_check(ally.flash_remaining == 0.1 and ally.flash_color == Color.WHITE and ally.position.is_equal_approx(Vector2(300.0 + ally.damage_knockback_for(20.0), 300.0)), "Shield damage flashes fully white and knocks back by the hit's share of Max HP.")
	ally._physics_process(0.1)
	_check(ally.flash_remaining == 0.0, "The default damage flash expires after 0.1 seconds even when simulation is inactive.")

	ally.position = Vector2(500.0, 300.0)
	enemy.position = Vector2(600.0, 300.0)
	enemy.damage_flash_color = Color.MAGENTA
	enemy.damage_flash_duration = 0.2
	enemy.damage_knockback_distance = 15.0
	var enemy_dealt := enemy.take_damage(20.0, ally)
	_check(enemy.flash_remaining == 0.2 and enemy.flash_color == Color.MAGENTA and enemy.position.is_equal_approx(Vector2(600.0 + enemy.damage_knockback_for(enemy_dealt), 300.0)), "Enemy damage reactions use configurable flash color, duration, and knockback distance.")
	var max_hp := enemy.get_effective_stat(&"max_hp")
	_check(
		is_equal_approx(enemy.damage_knockback_for(max_hp * enemy.damage_knockback_reference_percent / 100.0), enemy.damage_knockback_distance)
		and is_equal_approx(enemy.damage_knockback_for(max_hp * 0.02), enemy.damage_knockback_distance * 2.0 / enemy.damage_knockback_reference_percent)
		and enemy.damage_knockback_for(max_hp * 0.02) < enemy.damage_knockback_for(max_hp * 0.08)
		and is_equal_approx(enemy.damage_knockback_for(max_hp * 5.0), enemy.damage_knockback_max_distance),
		"Damage knockback scales with the hit's share of Max HP and is capped."
	)
	enemy.position = Vector2(600.0, 300.0)
	enemy.take_damage(0.01, ally)
	_check(enemy.position == Vector2(600.0, 300.0), "Chip damage too small to matter does not move the unit.")

	ally.current_hp = 400.0
	var healing_position := ally.position
	ally.receive_healing(20.0, ally, &"ability.test_heal", &"effect.test_heal")
	_check(ally.flash_remaining == 0.1 and ally.flash_color == Color(1.0, 0.9, 0.2, 1.0), "Effective healing flashes the healed unit yellow for 0.1 seconds.")
	_check(ally.position == healing_position, "Healing never applies damage knockback.")
	session.free()


func _test_facing_while_retreating() -> void:
	var archer_snapshot := _snapshot("archer", CombatUnitSnapshot.Team.PLAYER)
	archer_snapshot.attack_type = &"ranged"
	var brute_snapshot := _snapshot("brute", CombatUnitSnapshot.Team.ENEMY)
	var session := _session([archer_snapshot], [brute_snapshot], 9605)
	var archer := session.get_combatant_by_runtime_id("archer")
	var brute := session.get_combatant_by_runtime_id("brute")
	var sprite := archer.get_node("UnitSprite") as AnimatedSprite2D
	archer.position = Vector2(400.0, 300.0)
	brute.position = Vector2(460.0, 300.0)
	archer.target = brute
	archer.state = Combatant.State.ATTACK_RECOVERY
	archer.velocity = Vector2(-120.0, 0.0)
	sprite.flip_h = true
	archer._update_sprite_facing(true)
	_check(not sprite.flip_h, "A ranged unit kiting away during attack recovery keeps facing its target.")
	brute.position = Vector2(403.0, 360.0)
	archer.velocity = Vector2(120.0, 0.0)
	archer._update_sprite_facing(true)
	_check(not sprite.flip_h, "An enemy almost straight above or below does not flip the sprite back and forth.")
	archer.state = Combatant.State.MOVE_INTO_RANGE
	archer.melee_retreat_remaining = 0.2
	archer.melee_retreat_source = brute
	brute.position = Vector2(340.0, 300.0)
	archer.velocity = Vector2(120.0, 0.0)
	archer._update_sprite_facing(false)
	_check(sprite.flip_h, "A unit backing away from a melee attacker keeps facing the attacker.")
	archer.melee_retreat_remaining = 0.0
	archer.target = null
	archer._update_sprite_facing(false)
	_check(not sprite.flip_h, "Free movement still faces the walking direction.")
	session.free()


func _test_projectile_outlives_target() -> void:
	var archer_snapshot := _snapshot("archer", CombatUnitSnapshot.Team.PLAYER)
	archer_snapshot.attack_type = &"ranged"
	var session := _session([archer_snapshot], [_snapshot("victim", CombatUnitSnapshot.Team.ENEMY), _snapshot("other", CombatUnitSnapshot.Team.ENEMY)], 9606)
	var archer := session.get_combatant_by_runtime_id("archer")
	var victim := session.get_combatant_by_runtime_id("victim")
	archer.position = Vector2(200.0, 300.0)
	victim.position = Vector2(700.0, 300.0)
	session.spawn_projectile(archer, victim, 10.0)
	var projectile := session.get_node("Projectiles").get_child(-1) as CombatProjectile
	projectile._physics_process(0.1)
	var victim_position := victim.position
	victim.take_damage(100000.0, archer)
	_check(not victim.is_alive(), "The projectile's target dies before impact.")
	var before := projectile.position
	projectile._physics_process(0.1)
	_check(is_instance_valid(projectile) and not projectile.is_queued_for_deletion() and projectile.position.x > before.x, "A projectile keeps flying after its target dies.")
	for step in 30:
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			break
		projectile._physics_process(0.05)
	_check(not is_instance_valid(projectile) or projectile.is_queued_for_deletion(), "The projectile disappears once it reaches where its target fell.")
	_check(before.distance_to(victim_position) > 100.0, "The projectile was still far from its target when the target died.")
	session.free()


func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot], seed: int) -> CombatSession:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, seed)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	return session


func _snapshot(runtime_id: String, team: int) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.HERO if team == CombatUnitSnapshot.Team.PLAYER else CombatUnitSnapshot.UnitKind.ENEMY
	snapshot.attack_type = &"melee"
	snapshot.stats.max_hp = 500.0
	snapshot.stats.damage = 20.0
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 50.0
	snapshot.stats.armor = 0.0
	return snapshot


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
