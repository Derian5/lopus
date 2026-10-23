extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_melee_strike_follows_locked_target()
	_test_damage_does_not_cancel_strike()
	_test_ranged_unit_does_not_wait_for_navigation()
	_test_ranged_shoot_run_turn_shoot()
	_test_blocked_retreat_does_not_block_shooting()
	_test_rooted_retreat_can_turn_and_shoot()
	_test_heal_approach_clears_retreat()
	_test_late_render_starts_held_attack()
	_test_dead_target_does_not_retarget_strike()
	_test_collision_yields_to_strike()
	if failures == 0:
		print("Committed attack tests passed: guaranteed strikes, planted animation, responsive ranged fire, walking retreats and late-render poses.")
		quit()
	else:
		quit(1)


func _test_melee_strike_follows_locked_target() -> void:
	var session := _session([_unit("fighter")], [_unit("original", true), _unit("taunter", true)])
	var unit := session.get_combatant_by_runtime_id("fighter")
	var original := session.get_combatant_by_runtime_id("original")
	var taunter := session.get_combatant_by_runtime_id("taunter")
	unit.position = Vector2(300, 300)
	original.position = Vector2(370, 300)
	taunter.position = Vector2(350, 350)
	unit.target = original
	unit._move_toward_target(0.0)
	_check(unit.attack_committed, "Entering reach starts a committed basic strike.")
	var position_before := unit.position
	original.position = Vector2(800, 300)
	unit.set_forced_basic_target(taunter, 5.0, &"ability.test_taunt")
	unit._physics_process(0.3)
	_check(original.current_hp == 980.0 and taunter.current_hp == 1000.0, "A fleeing target receives the one locked strike; a new taunt does not redirect it.")
	_check(unit.position == position_before and unit.velocity == Vector2.ZERO and unit.state == Combatant.State.ATTACK_RECOVERY, "The attacker remains planted while its swing completes.")
	unit._update_attack_windup(0.5)
	_check(original.current_hp == 980.0, "Updating a finished windup cannot deal a second strike.")
	unit._physics_process(0.8)
	unit._physics_process(0.01)
	_check(unit.target == taunter, "A forced target takes effect for the following attack.")
	session.free()


func _test_damage_does_not_cancel_strike() -> void:
	var fighter := _unit("fighter")
	fighter.avoids_damage = true
	var session := _session([fighter], [_unit("target", true), _unit("interrupter", true)])
	var unit := session.get_combatant_by_runtime_id("fighter")
	var target := session.get_combatant_by_runtime_id("target")
	var interrupter := session.get_combatant_by_runtime_id("interrupter")
	unit.position = Vector2(300, 300)
	target.position = Vector2(370, 300)
	interrupter.position = Vector2(350, 350)
	unit.target = target
	unit._start_attack()
	var summon := root.get_node("ContentRegistry").get_definition(&"ability.summoner_job_summon") as AbilityDefinition
	_check(not unit._try_activate_ability(summon, true), "A ready priority ability cannot interrupt a committed strike.")
	unit.take_damage(5.0, interrupter, &"attack.basic", &"attack.basic", true)
	_check(unit.attack_committed and unit.committed_attack_target == target, "A melee damage reaction queues retreat without cancelling or replacing the current strike.")
	var after_knockback := unit.position
	unit._physics_process(0.3)
	_check(target.current_hp == 980.0 and unit.position == after_knockback and not unit.melee_retreat_counterattack_pending, "The original strike lands before retreat, without granting a duplicate counterattack.")
	session.free()


func _test_ranged_unit_does_not_wait_for_navigation() -> void:
	var archer := _unit("archer")
	archer.job_id = &"job.archer"
	archer.attack_type = &"ranged"
	archer.stats.attack_range = 300.0
	var session := _session([archer], [_unit("target", true)])
	var unit := session.get_combatant_by_runtime_id("archer")
	var target := session.get_combatant_by_runtime_id("target")
	unit.position = Vector2(300, 300)
	target.position = Vector2(610, 300)
	unit.target = target
	unit.state = Combatant.State.MOVE_INTO_RANGE
	unit.approach_target = target
	unit.approach_reach = unit.basic_attack_reach(target)
	unit.approach_committed = true
	unit.approach_goal = Vector2(100, 200)
	unit._move_toward_target(0.016)
	_check(unit.state == Combatant.State.ATTACK_WINDUP and unit.attack_committed and unit.velocity == Vector2.ZERO, "An in-range ranged unit shoots immediately rather than waiting to reach a stale navigation goal.")
	target.position = Vector2(1000, 300)
	unit._physics_process(0.11)
	_check(session.get_node("Projectiles").get_child_count() == 1, "A committed shot still launches after its target leaves range.")
	session.free()


func _test_ranged_shoot_run_turn_shoot() -> void:
	var archer := _unit("archer")
	archer.job_id = &"job.archer"
	archer.attack_type = &"ranged"
	archer.stats.attack_range = 300.0
	archer.stats.movement_speed = 120.0
	var session := _session([archer], [_unit("target", true)])
	var unit := session.get_combatant_by_runtime_id("archer")
	var target := session.get_combatant_by_runtime_id("target")
	unit.position = Vector2(500, 300)
	target.position = Vector2(640, 300)
	unit.target = target
	unit._move_toward_target(0.016)
	unit._process(0.0)
	_check(unit.unit_sprite.animation == &"attack" and not unit.unit_sprite.flip_h, "The shot begins stationary and facing the enemy.")
	unit._physics_process(0.1)
	unit._physics_process(0.1)
	_check(unit.position == Vector2(500, 300) and unit.velocity == Vector2.ZERO, "The ranged unit does not slide away while its swing animation is locked.")
	unit._physics_process(0.5)
	unit._process(0.0)
	_check(unit.velocity.x < 0 and unit.unit_sprite.animation == &"move" and unit.unit_sprite.is_playing() and unit.unit_sprite.flip_h, "Retreat uses a playing walk animation and faces away from the enemy.")
	unit._physics_process(0.4)
	unit._physics_process(0.016)
	unit._physics_process(0.016)
	unit._physics_process(0.016)
	unit._process(0.0)
	_check(unit.attack_committed and unit.velocity == Vector2.ZERO and unit.unit_sprite.animation == &"attack" and not unit.unit_sprite.flip_h, "At a safe distance the unit stops, turns back and begins its next shot.")
	session.free()


func _test_blocked_retreat_does_not_block_shooting() -> void:
	var archer := _unit("archer")
	archer.attack_type = &"ranged"
	archer.stats.attack_range = 300.0
	var session := _session([archer], [_unit("target", true)])
	var unit := session.get_combatant_by_runtime_id("archer")
	unit.position = Vector2(500, 300)
	unit.target = session.get_combatant_by_runtime_id("target")
	unit.target.position = Vector2(640, 300)
	unit.state = Combatant.State.ATTACK_RECOVERY
	unit._move_ranged_during_recovery(0.1)
	var blocked_position := unit.position
	for step in 9:
		unit._move_ranged_during_recovery(0.1)
		# Model an immovable crowd cancelling each attempted movement step.
		unit.position = blocked_position
	_check(not unit.ranged_retreat_active, "A retreat with no real progress is abandoned instead of suppressing attacks for seconds.")
	unit.state = Combatant.State.MOVE_INTO_RANGE
	unit._move_toward_target(0.0)
	_check(unit.attack_committed, "An obstructed ranged unit can stop trying to retreat and shoot.")
	session.free()


func _test_rooted_retreat_can_turn_and_shoot() -> void:
	var archer := _unit("archer")
	archer.attack_type = &"ranged"
	archer.stats.attack_range = 300.0
	var session := _session([archer], [_unit("target", true)])
	var unit := session.get_combatant_by_runtime_id("archer")
	unit.position = Vector2(500, 300)
	unit.target = session.get_combatant_by_runtime_id("target")
	unit.target.position = Vector2(640, 300)
	unit._move_ranged_during_recovery(0.1)
	var root_status := StatusDefinition.new()
	root_status.id = &"status.test_rooted_shooter"
	root_status.prevents_movement = true
	root_status.default_duration = 5.0
	unit.apply_status(root_status, unit, &"ability.test_root")
	var before := unit.position
	unit.state = Combatant.State.MOVE_INTO_RANGE
	unit._move_toward_target(0.1)
	_check(unit.attack_committed and unit.position == before, "Rooting a retreating ranged unit prevents running but does not prevent an in-range shot.")
	session.free()


func _test_heal_approach_clears_retreat() -> void:
	var priest := _unit("priest")
	priest.attack_type = &"ranged"
	var session := _session([priest, _unit("ally")], [_unit("enemy", true)])
	var unit := session.get_combatant_by_runtime_id("priest")
	var ally := session.get_combatant_by_runtime_id("ally")
	unit.position = Vector2(500, 300)
	ally.position = Vector2(900, 300)
	ally.current_hp = 40.0
	unit.target = session.get_combatant_by_runtime_id("enemy")
	unit.target.position = Vector2(640, 300)
	unit.ranged_retreat_active = true
	unit.ranged_retreat_destination = Vector2(300, 300)
	var heal := root.get_node("ContentRegistry").get_definition(&"ability.priest_heal") as AbilityDefinition
	_check(unit._try_activate_ability(heal, false) and not unit.ranged_retreat_active, "A priority Heal does not inherit the previous retreat plan.")
	unit._move_toward_target(0.1)
	_check(unit.target == ally and is_equal_approx(unit.position.x, 510.0), "A caster approaches its ally once per step rather than treating the ally as a retreat threat.")
	session.free()


func _test_late_render_starts_held_attack() -> void:
	var pride := _unit("pride")
	pride.definition_id = &"hero.control_savant"
	pride.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	pride.attack_type = &"ranged"
	pride.stats.attack_range = 300.0
	var session := _session([pride], [_unit("target", true)])
	var unit := session.get_combatant_by_runtime_id("pride")
	unit.position = Vector2(300, 300)
	unit.target = session.get_combatant_by_runtime_id("target")
	unit.target.position = Vector2(600, 300)
	unit._start_attack()
	unit._physics_process(0.15)
	unit._process(0.0)
	_check(unit.state == Combatant.State.ATTACK_RECOVERY and unit.unit_sprite.animation == &"attack" and unit.unit_sprite.frame == unit.attack_hold_frames.y, "Pride shows its release pose even when rendering misses the brief windup.")
	session.free()


func _test_dead_target_does_not_retarget_strike() -> void:
	var session := _session([_unit("fighter")], [_unit("target", true), _unit("other", true)])
	var unit := session.get_combatant_by_runtime_id("fighter")
	var target := session.get_combatant_by_runtime_id("target")
	unit.position = Vector2(300, 300)
	target.position = Vector2(370, 300)
	unit.target = target
	unit._start_attack()
	target.force_die(null, &"effect.test")
	unit._physics_process(0.3)
	_check(not unit.attack_committed and unit.state == Combatant.State.ATTACK_RECOVERY and session.get_combatant_by_runtime_id("other").current_hp == 1000.0, "A dead locked target consumes the strike without redirecting it to another victim.")
	unit.force_die(null, &"effect.test")
	_check(not unit.attack_committed and unit.attack_motion_lock_remaining == 0.0, "Death clears all attack commitments and movement locks.")
	session.free()


func _test_collision_yields_to_strike() -> void:
	var session := _session([_unit("fighter"), _unit("moving-ally")], [_unit("target", true)])
	var unit := session.get_combatant_by_runtime_id("fighter")
	var ally := session.get_combatant_by_runtime_id("moving-ally")
	var target := session.get_combatant_by_runtime_id("target")
	unit.position = Vector2(300, 300)
	ally.position = Vector2(330, 300)
	target.position = Vector2(370, 330)
	unit.target = target
	unit._start_attack()
	session._physics_process(0.1)
	_check(unit.position == Vector2(300, 300) and ally.position.x > 330.0, "Moving neighbours yield to a planted attacker instead of dragging its swing across the ground.")
	session.free()


func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot]) -> CombatSession:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.vfx_enabled = false
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200, 700)
	root.add_child(session)
	session.setup(players, enemies, 77101)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_physics_process(false)
		unit.set_process(false)
		unit.set_simulation_active(false)
	for unit in players:
		session.get_combatant_by_runtime_id(unit.runtime_id).set_simulation_active(true)
	return session


func _unit(id: String, enemy := false) -> CombatUnitSnapshot:
	var unit := CombatUnitSnapshot.new()
	unit.runtime_id = id
	unit.display_name = id
	unit.team = CombatUnitSnapshot.Team.ENEMY if enemy else CombatUnitSnapshot.Team.PLAYER
	unit.stats.max_hp = 1000.0
	unit.stats.damage = 20.0
	unit.stats.attack_range = 50.0
	unit.stats.movement_speed = 100.0
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
