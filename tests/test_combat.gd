extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const COMBAT_SCENE := preload("res://combat/combat.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 20.0
	_test_damage_formula()
	_test_player_unit_animations()
	_test_hero_unit_animations()
	_test_ranged_attack_rhythm()
	_test_pride_projectile_visual()
	_test_hero_attack_effects()
	_test_reinforcement_waves()
	await _test_reinforcement_encounter_integration()

	Engine.time_scale = 1.0
	if failures == 0:
		print("Combat tests passed.")
		quit()
	else:
		push_error("Combat tests failed: %d" % failures)
		quit(1)


func _test_damage_formula() -> void:
	_check(is_equal_approx(CombatRules.calculate_damage(100.0, 0.0), 100.0), "Zero armor preserves damage.")
	_check(is_equal_approx(CombatRules.calculate_damage(100.0, 100.0), 50.0), "100 armor halves damage.")
	_check(is_equal_approx(CombatRules.calculate_damage(-10.0, 0.0), 0.0), "Negative raw damage is clamped.")
	_check(is_equal_approx(Combatant.UNIT_RADIUS, 20.16) and is_equal_approx(Combatant.HERO_RADIUS, 20.16) and is_equal_approx(Combatant.BOSS_RADIUS, 31.92), "Soldier, Hero, and boss collision radii are 30 percent smaller than their visual radii.")
	_check(is_equal_approx(Combatant.UNIT_VISUAL_RADIUS, 28.8) and is_equal_approx(Combatant.HERO_VISUAL_RADIUS, 28.8) and is_equal_approx(Combatant.BOSS_VISUAL_RADIUS, 45.6), "Procedural unit visuals are increased independently by 20 percent.")


func _test_player_unit_animations() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	_check(CombatSession.BATTLEGROUND.resource_path == "res://graphics/battleground.png", "Combat renders the authored battlefield beneath its arena markings and simulation.")
	var jobs: Array[StringName] = [&"job.militia", &"job.archer", &"job.priest", &"job.summoner"]
	var players: Array[CombatUnitSnapshot] = []
	for job_id in jobs:
		var soldier := _unit_snapshot("%s-animation" % job_id, CombatUnitSnapshot.Team.PLAYER, &"melee")
		soldier.job_id = job_id
		players.append(soldier)
	var enemy := _unit_snapshot("animation-target", CombatUnitSnapshot.Team.ENEMY, &"melee")
	session.setup(players, [enemy], 1203)
	var startup_delays: Dictionary = {}
	for player in players:
		var animated_unit := session.get_combatant_by_runtime_id(player.runtime_id)
		startup_delays[player.runtime_id] = animated_unit.initial_walk_delay_frames
		_check(animated_unit.initial_walk_delay_frames >= 1 and animated_unit.initial_walk_delay_frames <= 9 and animated_unit.initial_walk_delay_remaining > 0.0, "Initial walking waits for one to nine animation frames.")
	var unique_delays: Dictionary = {}
	for delay in startup_delays.values():
		unique_delays[delay] = true
	_check(unique_delays.size() > 1, "Initial walking delays vary across the starting formation.")
	var first_player := session.get_combatant_by_runtime_id(players[0].runtime_id)
	var second_player := session.get_combatant_by_runtime_id(players[1].runtime_id)
	first_player.position = Vector2(300.0, 300.0)
	second_player.position = Vector2(335.0, 300.0)
	session.get_combatant_by_runtime_id(players[2].runtime_id).position = Vector2(800.0, 100.0)
	session.get_combatant_by_runtime_id(players[3].runtime_id).position = Vector2(800.0, 500.0)
	session.get_combatant_by_runtime_id(enemy.runtime_id).position = Vector2(1050.0, 300.0)
	_check(session.get_separation_vector(first_player).x < 0.0 and session.get_separation_vector(second_player).x > 0.0, "Soft separation uses the enlarged collision radii instead of a fixed crowding distance.")
	first_player.state = Combatant.State.ATTACK_WINDUP
	second_player.state = Combatant.State.ATTACK_WINDUP
	var distance_before_resolution := first_player.position.distance_to(second_player.position)
	session._physics_process(0.1)
	_check(first_player.position.distance_to(second_player.position) > distance_before_resolution, "Overlapping units are physically separated even while both are attacking.")
	for index in jobs.size():
		var job_id := jobs[index]
		var unit := session.get_combatant_by_runtime_id(players[index].runtime_id)
		var sprite := unit.get_node("UnitSprite") as AnimatedSprite2D
		var expected_move_frames := 16 if job_id == &"job.militia" else 8
		var expected_attack_frames := 16 if job_id == &"job.militia" else (6 if job_id == &"job.summoner" else 8)
		_check(sprite.visible and sprite.sprite_frames.get_frame_count(&"move") == expected_move_frames and sprite.sprite_frames.get_frame_count(&"attack") == expected_attack_frames, "%s uses the complete movement and attack animations." % job_id)
		if job_id == &"job.militia":
			_check(sprite.sprite_frames.get_frame_count(&"death") == 16, "Militia uses the complete death animation.")
		unit.state = Combatant.State.ATTACK_WINDUP
		unit.velocity = Vector2.ZERO
		unit._process(0.0)
		_check(sprite.animation == &"attack" and sprite.is_playing(), "%s plays its attack animation during attack windup." % job_id)
		unit.state = Combatant.State.MOVE_INTO_RANGE
		unit.velocity = Vector2.LEFT * 100.0
		unit.initial_walk_delay_remaining = 0.0
		unit._process(0.0)
		_check(sprite.animation == &"move" and sprite.is_playing() and sprite.flip_h, "%s movement animates and faces its travel direction." % job_id)
	var delayed_unit := session.get_combatant_by_runtime_id(players[0].runtime_id)
	var delayed_sprite := delayed_unit.get_node("UnitSprite") as AnimatedSprite2D
	delayed_unit.state = Combatant.State.MOVE_INTO_RANGE
	delayed_unit.velocity = Vector2.RIGHT * 100.0
	delayed_unit.initial_walk_delay_remaining = 0.1
	delayed_sprite.animation = &"move"
	delayed_sprite.frame = 0
	delayed_sprite.pause()
	delayed_unit._process(0.05)
	_check(not delayed_sprite.is_playing(), "The initial walk animation remains paused while its frame delay is active.")
	delayed_unit._process(0.05)
	_check(delayed_sprite.is_playing(), "The walk animation starts when its one-shot frame delay expires.")
	delayed_unit.state = Combatant.State.ATTACK_WINDUP
	delayed_unit._process(0.0)
	delayed_unit.state = Combatant.State.MOVE_INTO_RANGE
	delayed_unit._process(0.0)
	_check(delayed_sprite.animation == &"move" and delayed_sprite.is_playing(), "Returning to movement does not rearm the opening delay.")
	var late_spawn := _unit_snapshot("late-animation", CombatUnitSnapshot.Team.PLAYER, &"melee")
	late_spawn.job_id = &"job.militia"
	var summoned := session._spawn_combatant(late_spawn, Vector2(200.0, 200.0), session.get_arena_bounds())
	_check(summoned.initial_walk_delay_frames == 0 and is_zero_approx(summoned.initial_walk_delay_remaining), "Units spawned after battle start do not receive the opening walk delay.")
	var unit := session.get_combatant_by_runtime_id(players[0].runtime_id)
	var sprite := unit.get_node("UnitSprite") as AnimatedSprite2D
	var move_frame := sprite.sprite_frames.get_frame_texture(&"move", 0)
	_check(move_frame.resource_path.ends_with("/militia/walk/frame_0000.png") and sprite.scale.is_equal_approx(Vector2.ONE * 0.2688), "Militia uses the new frame sequence at combat scale.")
	_check(is_equal_approx(unit.health_bar_offset, 72.0), "Militia raises its health bar above the animated sprite.")
	unit._trigger_flash(Color.WHITE, 0.1, Combatant.DAMAGE_FLASH_PRIORITY)
	unit._process(0.0)
	_check(is_equal_approx(float((sprite.material as ShaderMaterial).get_shader_parameter("flash_amount")), 1.0), "Militia chroma-key rendering preserves its damage flash.")
	sprite.animation = &"move"
	sprite.frame = 0
	sprite.flip_h = false
	unit._update_unit_sprite_offset()
	_check(sprite.position.length() > 1.0, "Militia frames compensate their green-screen canvas around the visual center.")
	var right_facing_position := sprite.position
	sprite.flip_h = true
	unit._update_unit_sprite_offset()
	_check(is_equal_approx(sprite.position.x, -right_facing_position.x) and is_equal_approx(sprite.position.y, right_facing_position.y), "Militia mirrors its frame offset when facing left without jumping away from its combat origin.")
	unit.state = Combatant.State.DEAD
	unit._process(0.0)
	_check(sprite.animation == &"death" and sprite.is_playing(), "Militia plays its death animation after dying.")
	var temporary_armor := StatModifier.new()
	temporary_armor.stat = "armor"
	temporary_armor.operation = StatModifier.Operation.ADD
	temporary_armor.value = 7.0
	unit.add_temporary_modifier(temporary_armor, 5.0, unit, &"", &"effect.test")
	var armor_tooltip := StatBreakdownFormatter.from_combatant(unit, &"armor")
	_check(armor_tooltip.contains("Temporary modifier") and armor_tooltip.contains("+7") and armor_tooltip.contains("FINAL:"), "Combat stat hover explains active temporary modifiers and the final value.")
	session.restart_battle()
	for player in players:
		var restarted := session.get_combatant_by_runtime_id(player.runtime_id)
		_check(restarted.initial_walk_delay_frames == int(startup_delays[player.runtime_id]), "Restarting with the same combat seed reproduces each opening walk delay.")
	session.free()


func _test_hero_unit_animations() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	var hero_ids: Array[StringName] = [
		&"hero.test_vanguard",
		&"hero.ashen_duelist",
		&"hero.army_support",
		&"hero.glass_arcanist",
		&"hero.thorn_warden",
		&"hero.iron_oracle",
		&"hero.control_savant",
	]
	var heroes: Array[CombatUnitSnapshot] = []
	for hero_id in hero_ids:
		var hero := _unit_snapshot("%s-animation" % hero_id, CombatUnitSnapshot.Team.PLAYER, &"melee")
		hero.unit_kind = CombatUnitSnapshot.UnitKind.HERO
		hero.definition_id = hero_id
		hero.stats.attack_speed = 2.0
		heroes.append(hero)
	var enemy := _unit_snapshot("hero-animation-target", CombatUnitSnapshot.Team.ENEMY, &"melee")
	session.setup(heroes, [enemy], 1204)
	for hero in heroes:
		var unit := session.get_combatant_by_runtime_id(hero.runtime_id)
		var sprite := unit.get_node("UnitSprite") as AnimatedSprite2D
		_check(sprite.visible and sprite.sprite_frames.get_frame_count(&"move") == 16 and sprite.sprite_frames.get_frame_count(&"attack") == 16 and sprite.sprite_frames.get_frame_count(&"death") == 16, "%s uses all authored Hero animation frames." % hero.definition_id)
		_check(sprite.material is ShaderMaterial and is_equal_approx(unit.health_bar_offset, 78.0), "%s uses chroma-key rendering with its health bar above the sprite." % hero.definition_id)
		sprite.animation = &"move"
		sprite.frame = 0
		sprite.scale = Vector2.ONE * unit.unit_sprite_base_scale * float(unit.unit_sprite_animation_scales.get(&"move", 1.0))
		unit._update_unit_sprite_offset()
		var walk_anchor := unit.body_anchor_offset()
		var walk_stable := true
		for frame in sprite.sprite_frames.get_frame_count(&"move"):
			sprite.frame = frame
			unit._update_unit_sprite_offset()
			walk_stable = walk_stable and unit.body_anchor_offset().distance_to(walk_anchor) < 0.5
		_check(walk_stable, "%s keeps its body planted on every walk frame." % hero.definition_id)
		sprite.animation = &"attack"
		sprite.scale = Vector2.ONE * unit.unit_sprite_base_scale * float(unit.unit_sprite_animation_scales.get(&"attack", 1.0))
		var attack_stable := true
		for frame in sprite.sprite_frames.get_frame_count(&"attack"):
			sprite.frame = frame
			unit._update_unit_sprite_offset()
			attack_stable = attack_stable and unit.body_anchor_offset().distance_to(walk_anchor) < 0.5
		_check(attack_stable, "%s keeps a stable screen-space anchor throughout its attack animation and when switching from walking." % hero.definition_id)

	var wrath := session.get_combatant_by_runtime_id("hero.ashen_duelist-animation")
	var wrath_sprite := wrath.get_node("UnitSprite") as AnimatedSprite2D
	wrath_sprite.animation = &"move"
	wrath_sprite.frame = 0
	wrath._update_unit_sprite_offset()
	var wrath_start_x := wrath_sprite.position.x
	wrath_sprite.frame = 15
	wrath._update_unit_sprite_offset()
	_check(wrath_sprite.position.x < wrath_start_x - 40.0, "Wrath walk frames compensate the character moving across the source canvas.")

	var greed := session.get_combatant_by_runtime_id("hero.test_vanguard-animation")
	var greed_sprite := greed.get_node("UnitSprite") as AnimatedSprite2D
	greed.state = Combatant.State.ATTACK_WINDUP
	greed.windup_duration = 0.2
	greed.sprite_was_attacking = false
	greed.sprite_was_attack_recovery = false
	greed._process(0.0)
	_check(greed_sprite.animation == &"attack" and greed_sprite.get_playing_speed() > 0.0, "Greed plays the dagger attack forward during windup.")
	greed.state = Combatant.State.ATTACK_RECOVERY
	greed.state_timer = 0.4
	greed._process(0.0)
	_check(greed_sprite.animation == &"attack" and greed_sprite.get_playing_speed() < 0.0, "Greed reverses the dagger animation during recovery.")

	var lust := session.get_combatant_by_runtime_id("hero.glass_arcanist-animation")
	var lust_sprite := lust.get_node("UnitSprite") as AnimatedSprite2D
	lust.state = Combatant.State.MOVE_INTO_RANGE
	lust.velocity = Vector2.RIGHT
	lust.initial_walk_delay_remaining = 0.0
	lust._process(0.0)
	var lust_walk_scale := lust_sprite.scale.x
	lust.state = Combatant.State.ATTACK_WINDUP
	lust.windup_duration = 0.125
	lust.attack_animation_duration = 0.5
	lust._process(0.0)
	_check(lust_sprite.animation == &"attack" and lust_sprite.scale.x > lust_walk_scale * 3.5, "Lust attack compensates its smaller updated source canvas with animation-specific scale and centering.")
	var lust_attack_duration := float(lust_sprite.sprite_frames.get_frame_count(&"attack")) / (lust_sprite.sprite_frames.get_animation_speed(&"attack") * lust_sprite.speed_scale)
	_check(is_equal_approx(lust_attack_duration, 0.5), "Hero attack playback fits the full authored animation into the actual attack cycle.")
	var gluttony := session.get_combatant_by_runtime_id("hero.thorn_warden-animation")
	var gluttony_sprite := gluttony.get_node("UnitSprite") as AnimatedSprite2D
	gluttony.state = Combatant.State.MOVE_INTO_RANGE
	gluttony.velocity = Vector2.RIGHT
	gluttony.initial_walk_delay_remaining = 0.0
	gluttony._process(0.0)
	var gluttony_walk_scale := gluttony_sprite.scale.x
	gluttony.state = Combatant.State.ATTACK_WINDUP
	gluttony.attack_animation_duration = 0.5
	gluttony._process(0.0)
	var gluttony_attack_texture := gluttony_sprite.sprite_frames.get_frame_texture(&"attack", 0)
	_check(gluttony_sprite.scale.x >= gluttony_walk_scale * 2.0 and gluttony_attack_texture is AtlasTexture, "Gluttony's updated attack is enlarged consistently and crops its black canvas bars.")
	session.free()


func _test_ranged_attack_rhythm() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	var ranged := _unit_snapshot("ranged-test", CombatUnitSnapshot.Team.PLAYER, &"ranged")
	ranged.stats.attack_speed = 2.0
	ranged.stats.attack_range = 300.0
	ranged.stats.movement_speed = 120.0
	var melee := _unit_snapshot("melee-test", CombatUnitSnapshot.Team.ENEMY, &"melee")
	session.setup([ranged], [melee], 1234)
	var attacker := session.combatants[0]
	var target := session.combatants[1]
	attacker.position = Vector2(500.0, 300.0)
	target.position = Vector2(650.0, 300.0)
	target.set_simulation_active(false)
	attacker.target = target
	attacker.state = Combatant.State.MOVE_INTO_RANGE
	attacker._move_toward_target(0.016)
	_check(attacker.state == Combatant.State.ATTACK_WINDUP and is_equal_approx(attacker.windup_duration, 0.1), "Ranged units stop for exactly 0.1 seconds when an attack is ready.")
	attacker._update_attack_windup(0.1)
	_check(attacker.state == Combatant.State.ATTACK_RECOVERY and is_equal_approx(attacker.state_timer, 0.4), "Ranged recovery preserves the attack-speed interval after the 0.1 second pause.")
	_check(session.get_node("Projectiles").get_child_count() == 1, "A ranged attack creates a visible projectile.")
	var projectile := session.get_node("Projectiles").get_child(0) as CombatProjectile
	_check(projectile.visible and projectile.z_index > attacker.z_index and projectile.color.a > 0.0, "Projectiles render above combatants with an opaque authored color.")
	var projectile_start := projectile.position
	projectile._physics_process(0.016)
	_check(projectile.position != projectile_start, "The visible projectile advances toward its target before impact.")
	attacker._update_attack_recovery(0.05)
	_check(attacker.velocity.dot(target.position - attacker.position) < 0.0, "A ranged unit resumes retreating while its attack recovers.")
	session.free()


func _test_pride_projectile_visual() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	var pride := _unit_snapshot("pride-projectile", CombatUnitSnapshot.Team.PLAYER, &"ranged")
	pride.definition_id = &"hero.control_savant"
	pride.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	var enemy := _unit_snapshot("pride-projectile-target", CombatUnitSnapshot.Team.ENEMY, &"melee")
	session.setup([pride], [enemy], 1205)
	var attacker := session.get_combatant_by_runtime_id(pride.runtime_id)
	var target := session.get_combatant_by_runtime_id(enemy.runtime_id)
	attacker.position = Vector2(400.0, 300.0)
	target.position = Vector2(700.0, 300.0)
	var sprite := attacker.get_node("UnitSprite") as AnimatedSprite2D
	sprite.animation = &"attack"
	sprite.frame = 1
	sprite.flip_h = false
	attacker._update_unit_sprite_offset()
	var expected_origin := attacker.basic_projectile_origin(target)
	session.spawn_projectile(attacker, target, pride.stats.damage)
	var projectile := session.get_node("Projectiles").get_child(0) as CombatProjectile
	_check(projectile.uses_pride_visual and projectile.position.is_equal_approx(expected_origin), "Pride's basic projectile launches from the visible staff tip.")
	_check(projectile.pride_effect.visible and projectile.pride_effect.sprite_frames.get_frame_count(&"fly") == 8 and projectile.pride_effect.is_playing(), "Pride's basic projectile uses the complete animated Effector atlas.")
	_check(projectile.pride_cast_sparks.visible and projectile.pride_cast_sparks.sprite_frames.get_frame_count(&"burst") == 8 and not projectile.pride_cast_sparks.sprite_frames.get_animation_loop(&"burst"), "Pride's projectile launch plays one non-looping radial spark burst.")
	_check(is_equal_approx(projectile.pride_cast_sparks.sprite_frames.get_animation_speed(&"burst"), 16.67), "Pride's enlarged launch flash remains visible for about half a second.")
	_check(projectile.pride_cast_sparks.global_position.is_equal_approx(expected_origin), "Pride's launch sparks remain centered on the staff tip.")
	_check(is_equal_approx(projectile.pride_effect.rotation, (target.position - projectile.position).angle()), "Pride's projectile visual points along its flight direction.")
	projectile._physics_process(0.016)
	_check(projectile.position != expected_origin and projectile.pride_cast_sparks.global_position.is_equal_approx(expected_origin), "Pride's launch sparks stay at the cast point while the bolt travels onward.")
	target.position = Vector2(100.0, 300.0)
	var left_origin := attacker.basic_projectile_origin(target)
	_check(left_origin.x < attacker.position.x and is_equal_approx(left_origin.y, expected_origin.y), "Pride's staff-tip projectile origin mirrors cleanly when attacking left.")
	session.free()


func _test_hero_attack_effects() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	var hero_ids: Array[StringName] = [
		&"hero.ashen_duelist",
		&"hero.test_vanguard",
		&"hero.glass_arcanist",
		&"hero.thorn_warden",
		&"hero.army_support",
		&"hero.iron_oracle",
		&"hero.control_savant",
	]
	var ranged_ids: Array[StringName] = [&"hero.army_support", &"hero.iron_oracle", &"hero.control_savant"]
	var heroes: Array[CombatUnitSnapshot] = []
	for hero_id in hero_ids:
		var hero := _unit_snapshot("%s-vfx" % hero_id, CombatUnitSnapshot.Team.PLAYER, &"ranged" if hero_id in ranged_ids else &"melee")
		hero.definition_id = hero_id
		hero.unit_kind = CombatUnitSnapshot.UnitKind.HERO
		heroes.append(hero)
	var enemy := _unit_snapshot("hero-vfx-target", CombatUnitSnapshot.Team.ENEMY, &"melee")
	session.setup(heroes, [enemy], 1206)
	var target := session.get_combatant_by_runtime_id(enemy.runtime_id)
	target.position = Vector2(760.0, 300.0)
	for index in hero_ids.size():
		var source := session.get_combatant_by_runtime_id(heroes[index].runtime_id)
		source.position = Vector2(300.0, 120.0 + index * 45.0)
		var effect := session.spawn_hero_attack_impact(source, target.position, Vector2.RIGHT)
		_check(effect != null and effect.is_playing() and effect.sprite_frames.get_frame_count(&"impact") == 8, "%s basic attacks use their complete themed impact atlas." % hero_ids[index])
	_check(session.get_node("Effects").get_child_count() == hero_ids.size(), "Every Hero has a distinct attack impact on the dedicated effects layer.")
	var wrath := session.get_combatant_by_runtime_id("hero.ashen_duelist-vfx")
	target.position = wrath.position + Vector2(20.0, 0.0)
	wrath.target = target
	wrath.state = Combatant.State.ATTACK_WINDUP
	wrath.windup_duration = 0.1
	wrath.state_timer = 0.0
	var effect_count_before_melee := session.get_node("Effects").get_child_count()
	wrath._update_attack_windup(0.0)
	_check(session.get_node("Effects").get_child_count() == effect_count_before_melee + 1, "A Hero melee hit automatically spawns its themed impact.")
	var first_ranged_projectile: CombatProjectile
	for hero_id in ranged_ids:
		var source := session.get_combatant_by_runtime_id("%s-vfx" % hero_id)
		var expected_origin := source.basic_projectile_origin(target)
		session.spawn_projectile(source, target, source.get_effective_stat(&"damage"))
		var projectile := session.get_node("Projectiles").get_child(-1) as CombatProjectile
		if first_ranged_projectile == null:
			first_ranged_projectile = projectile
		_check(projectile.uses_hero_visual and projectile.pride_effect.visible and projectile.pride_effect.sprite_frames.get_frame_count(&"fly") == 8, "%s uses its own animated basic projectile." % hero_id)
		_check(projectile.position.is_equal_approx(expected_origin) and projectile.position != source.position, "%s launches its projectile from the authored weapon tip." % hero_id)
	var effect_count_before_ranged := session.get_node("Effects").get_child_count()
	first_ranged_projectile.position = target.position
	first_ranged_projectile._physics_process(0.01)
	_check(session.get_node("Effects").get_child_count() == effect_count_before_ranged + 1, "A Hero ranged basic hit automatically spawns its themed impact.")
	session.free()


func _test_reinforcement_waves() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	var player := _unit_snapshot("reinforcement-player", CombatUnitSnapshot.Team.PLAYER, &"melee")
	var initial := _unit_snapshot("reinforcement-initial", CombatUnitSnapshot.Team.ENEMY, &"melee")
	var reinforcements: Array[CombatUnitSnapshot] = []
	for index in 4:
		reinforcements.append(_unit_snapshot("reinforcement-%d" % index, CombatUnitSnapshot.Team.ENEMY, &"melee"))
	session.setup(
		[player],
		[initial],
		4321,
		reinforcements,
		0,
		EncounterDefinition.ReinforcementEntryDirection.ALL_SIDES
	)
	var player_unit := session.get_combatant_by_runtime_id(player.runtime_id)
	player_unit.set_simulation_active(false)
	_check(not session.statistics.unit_stats.has("reinforcement-0"), "Pending reinforcements are absent from combat statistics.")
	session.get_combatant_by_runtime_id(initial.runtime_id).take_damage(20000.0, player_unit)
	session._check_battle_end()
	_check(session.battle_active and session.reinforcements_spawned, "Threshold zero spawns reinforcements before the initial enemy group can end the battle.")
	_check(session.statistics.get_event_count(CombatEvent.REINFORCEMENTS_SPAWNED) == 1, "A reinforcement group emits exactly one spawn event.")
	_check(session.statistics.get_event_count(CombatEvent.BATTLE_FINISHED) == 0, "The first enemy group does not emit a premature battle finish.")
	var bounds := session.get_arena_bounds()
	var entered_sides: Dictionary = {}
	for index in 4:
		var reinforcement := session.get_combatant_by_runtime_id("reinforcement-%d" % index)
		reinforcement.set_simulation_active(false)
		if is_equal_approx(reinforcement.position.x, bounds.end.x - CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["right"] = true
		if is_equal_approx(reinforcement.position.y, bounds.end.y - CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["bottom"] = true
		if is_equal_approx(reinforcement.position.x, bounds.position.x + CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["left"] = true
		if is_equal_approx(reinforcement.position.y, bounds.position.y + CombatSession.REINFORCEMENT_EDGE_INSET):
			entered_sides["top"] = true
	_check(entered_sides.size() == 4, "All-sides reinforcements are distributed across every arena edge.")
	for index in 4:
		session.get_combatant_by_runtime_id("reinforcement-%d" % index).take_damage(20000.0, player_unit)
	session._check_battle_end()
	_check(not session.battle_active and session.last_winner == &"player", "The battle ends only after the reinforcement group is defeated.")
	_check(session.statistics.get_event_count(CombatEvent.BATTLE_FINISHED) == 1, "The complete reinforcement battle emits one finish event.")
	session.restart_battle()
	_check(not session.reinforcements_spawned and session.combatants.size() == 2, "Restart removes reinforcements and rearms their trigger.")
	session.free()

	var right_session: CombatSession = SESSION_SCENE.instantiate()
	right_session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	right_session.size = Vector2(1200.0, 600.0)
	root.add_child(right_session)
	var initial_group: Array[CombatUnitSnapshot] = []
	for index in 3:
		initial_group.append(_unit_snapshot("right-initial-%d" % index, CombatUnitSnapshot.Team.ENEMY, &"melee"))
	var right_reinforcements: Array[CombatUnitSnapshot] = [
		_unit_snapshot("right-reinforcement-0", CombatUnitSnapshot.Team.ENEMY, &"melee"),
		_unit_snapshot("right-reinforcement-1", CombatUnitSnapshot.Team.ENEMY, &"melee"),
	]
	right_session.setup(
		[player],
		initial_group,
		4322,
		right_reinforcements,
		2,
		EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE
	)
	var right_player := right_session.get_combatant_by_runtime_id(player.runtime_id)
	right_player.set_simulation_active(false)
	right_session.get_combatant_by_runtime_id("right-initial-0").take_damage(20000.0, right_player)
	right_session._check_battle_end()
	var right_x := right_session.get_arena_bounds().end.x - CombatSession.REINFORCEMENT_EDGE_INSET
	_check(right_session.reinforcements_spawned, "Threshold two spawns reinforcements when two initial enemies remain.")
	_check(
		is_equal_approx(right_session.get_combatant_by_runtime_id("right-reinforcement-0").position.x, right_x)
		and is_equal_approx(right_session.get_combatant_by_runtime_id("right-reinforcement-1").position.x, right_x),
		"Right-side reinforcements enter only from the right arena edge."
	)
	right_session.free()


func _test_reinforcement_encounter_integration() -> void:
	var run := DemoRunFactory.create_starting_run(4330)
	run.current_act = 1
	run.encounter_index = 1
	run.available_encounter_ids = [&"encounter.reinforced_assault"]
	EncounterService.select_encounter(run, &"encounter.reinforced_assault")
	run.run_phase = &"combat"
	var combat = COMBAT_SCENE.instantiate()
	combat.setup_run(run, 4330)
	root.add_child(combat)
	await process_frame
	await process_frame
	var definition := root.get_node("ContentRegistry").get_definition(&"encounter.reinforced_assault") as EncounterDefinition
	_check(combat.current_encounter == definition and definition.has_reinforcements(), "Combat recognizes reinforcement settings on a standard Encounter definition.")
	_check(
		combat.combat_session.reinforcement_snapshots.size() == definition.reinforcement_enemy_ids.size()
		and combat.combat_session.reinforcement_alive_threshold == definition.reinforcement_alive_threshold
		and combat.combat_session.reinforcement_entry_direction == definition.reinforcement_entry_direction,
		"Combat passes reinforcement content settings into the runtime session."
	)
	combat.free()


func _unit_snapshot(runtime_id: String, team: CombatUnitSnapshot.Team, attack_type: StringName) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.attack_type = attack_type
	snapshot.stats.max_hp = 10000.0
	snapshot.stats.damage = 1.0
	return snapshot


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
