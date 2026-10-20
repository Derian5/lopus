extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const JOBS: Array[StringName] = [&"job.archer", &"job.priest", &"job.summoner", &"job.warrior", &"job.shieldbearer"]
const SUMMONS: Array[StringName] = [&"enemy.summoned_brawler", &"enemy.summoned_shooter", &"enemy.summoned_amalgam"]
var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_frame_sequences_and_anchors()
	_test_visual_size_consistency()
	_test_priest_cast()
	_test_summoner_cast()
	if failures == 0:
		print("Allied animation tests passed: five Jobs, three summons, grounded frames, healing and summoning casts.")
		quit()
	else:
		quit(1)


func _test_frame_sequences_and_anchors() -> void:
	var army: Array[CombatUnitSnapshot] = []
	for job in JOBS:
		army.append(_soldier(job))
	for id in SUMMONS:
		var snapshot := CombatSnapshotBuilder.build_enemy(registry.get_definition(id) as EnemyDefinition, String(id), String(id), registry)
		snapshot.team = CombatUnitSnapshot.Team.PLAYER
		snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
		army.append(snapshot)
	var session := _session(army)
	for snapshot in army:
		var unit := session.get_combatant_by_runtime_id(snapshot.runtime_id)
		var sprite := unit.unit_sprite
		_check(sprite.visible and sprite.material == null, "%s uses transparent artwork without erasing green details." % snapshot.runtime_id)
		var animations: Array[StringName] = [&"move", &"attack", &"death"]
		if snapshot.job_id in [&"job.priest", &"job.summoner"]:
			animations.append(&"skill")
		for animation in animations:
			_check(sprite.sprite_frames.has_animation(animation) and sprite.sprite_frames.get_frame_count(animation) == 16, "%s has the complete %s animation." % [snapshot.runtime_id, animation])
			_check(sprite.sprite_frames.get_animation_loop(animation) == (animation == &"move"), "Only walking loops: %s / %s." % [snapshot.runtime_id, animation])
			sprite.animation = animation
			for frame in 16:
				sprite.frame = frame
				for face_left in [false, true]:
					sprite.flip_h = face_left
					unit._update_unit_sprite_offset()
					_check(unit.body_anchor_offset().is_equal_approx(unit.unit_sprite_ground_offset), "%s / %s / %d keeps its authored ground anchor in either facing." % [snapshot.runtime_id, animation, frame])
		unit.target = session.get_combatant_by_runtime_id("enemy")
		unit._start_attack()
		unit._process(0.0)
		var sprite_duration := float(sprite.sprite_frames.get_frame_count(&"attack")) / (sprite.sprite_frames.get_animation_speed(&"attack") * sprite.speed_scale)
		_check(is_equal_approx(sprite_duration, unit.attack_animation_duration / Combatant.ANIMATION_SPEED), "%s plays all attack frames within its attack cycle (ANIMATION_SPEED faster)." % snapshot.runtime_id)
		unit.state = Combatant.State.DEAD
		unit._process(0.0)
		_check(sprite.animation == &"death" and sprite.is_playing(), "%s starts its death animation." % snapshot.runtime_id)
	_check(is_equal_approx(session.get_combatant_by_runtime_id("enemy.summoned_amalgam").unit_sprite_base_scale, session.get_combatant_by_runtime_id("enemy.summoned_brawler").unit_sprite_base_scale), "All summoned variants share the same 64px visual scale.")
	session.free()


func _test_visual_size_consistency() -> void:
	var army: Array[CombatUnitSnapshot] = [_soldier(&"job.militia")]
	for job in JOBS:
		army.append(_soldier(job))
	for id in Combatant.UNIT_ANIMATION_CONFIGS:
		if not String(id).begins_with("hero."):
			continue
		var hero := HeroState.new()
		hero.unique_id = String(id)
		hero.definition_id = id
		army.append(CombatSnapshotBuilder.build_hero(hero, InventoryState.new(), registry))
	var summon_ids := SUMMONS.duplicate()
	summon_ids.append(&"enemy.summoned_skeleton")
	for id in summon_ids:
		var summon := CombatSnapshotBuilder.build_enemy(registry.get_definition(id) as EnemyDefinition, String(id), String(id), registry)
		summon.team = CombatUnitSnapshot.Team.PLAYER
		summon.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
		army.append(summon)
	var session := _session(army)
	for snapshot in army:
		var unit := session.get_combatant_by_runtime_id(snapshot.runtime_id)
		var is_summon := snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON
		_check(is_equal_approx(unit.body_radius, 20.16), "Visual resizing does not alter combat collision radii.")
		if not unit.unit_sprite.visible:
			_check(is_summon and is_equal_approx(unit.visual_radius * 2.0, 64.0), "Summons without art also receive 64px placeholder visuals.")
			continue
		var heights: Array[float] = []
		for frame in unit.unit_sprite.sprite_frames.get_frame_count(&"move"):
			var texture := unit.unit_sprite.sprite_frames.get_frame_texture(&"move", frame)
			heights.append(_visible_height(texture, unit.unit_sprite_uses_chroma_key) * unit.unit_sprite_base_scale)
		heights.sort()
		var median := heights[heights.size() / 2]
		var expected := 64.0 if is_summon else (156.0 if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else 128.0)
		_check(absf(median - expected) < 2.0, "%s visible height is %.1f px, expected approximately %.0f." % [snapshot.runtime_id, median, expected])
		_check(is_equal_approx(unit.body_anchor_offset().y, expected * (52.0 / 96.0)), "Normalized sprites retain their size-adjusted ground anchor.")
	_check(is_equal_approx(session.get_combatant_by_runtime_id("enemy").visual_radius * 2.0, 128.0), "Enemies without animated artwork also use a 128px visible body.")
	session.free()


func _visible_height(texture: Texture2D, chroma_key: bool) -> float:
	# Measure actual opaque content, independently of its stored reference height.
	var image := texture.get_image().duplicate() as Image
	var original_height := image.get_height()
	image.resize(512, 512, Image.INTERPOLATE_NEAREST)
	var top := 512
	var bottom := -1
	for y in 512:
		for x in 512:
			var color := image.get_pixel(x, y)
			if color.a >= 0.5 and (not chroma_key or color.g - maxf(color.r, color.b) < 0.08):
				top = mini(top, y)
				bottom = maxi(bottom, y)
				break
	return float(maxi(0, bottom - top + 1)) * original_height / 512.0


func _test_priest_cast() -> void:
	var session := _session([_soldier(&"job.priest"), _soldier(&"job.warrior")])
	var priest := session.get_combatant_by_runtime_id("job.priest")
	var ally := session.get_combatant_by_runtime_id("job.warrior")
	priest.position = Vector2(400, 300)
	ally.position = Vector2(300, 300)
	ally.current_hp = 10.0
	var heal := priest.snapshot.abilities.filter(func(a: AbilityDefinition) -> bool: return a.id == &"ability.priest_heal")[0] as AbilityDefinition
	var amount := (heal.effects[0] as HealEffect).amount
	_check(priest._try_activate_ability(heal, false), "Priest activates its actual Heal ability.")
	_check(is_equal_approx(ally.current_hp, minf(10.0 + amount, ally.snapshot.stats.max_hp)) and is_equal_approx(float(priest.ability_cooldowns[heal.id]), priest.cooldown_for(heal)), "The cast animation does not delay healing or alter cooldowns.")
	priest.state = Combatant.State.ATTACK_RECOVERY
	priest.velocity = Vector2.ZERO
	priest._process(0.1)
	_check(priest.unit_sprite.animation == &"skill" and priest.unit_sprite.is_playing() and priest.unit_sprite.flip_h, "A stationary Heal animation survives AI state changes and faces the healed ally.")
	priest.velocity = Vector2.RIGHT * 50.0
	priest._process(0.0)
	_check(priest.unit_sprite.animation == &"move" and not priest.unit_sprite.flip_h, "A moving caster walks instead of sliding in a stale casting pose.")
	priest.state = Combatant.State.IDLE
	priest.velocity = Vector2.ZERO
	priest._process(1.0)
	_check(priest.unit_sprite.animation == &"move" and not priest.unit_sprite.is_playing(), "After the complete Heal animation the Priest returns to its resting pose.")
	session.free()


func _test_summoner_cast() -> void:
	var session := _session([_soldier(&"job.summoner")])
	var summoner := session.get_combatant_by_runtime_id("job.summoner")
	var summon := registry.get_definition(&"ability.summoner_job_summon") as AbilityDefinition
	var before := session.combatants.size()
	_check(summoner._try_activate_ability(summon, true), "Summoner activates its actual innate summon.")
	_check(session.combatants.size() == before + 1 and is_equal_approx(float(summoner.ability_cooldowns[summon.id]), summoner.cooldown_for(summon)), "Summoning occurs at the original time and starts the original cooldown.")
	summoner._process(0.1)
	_check(summoner.unit_sprite.animation == &"skill" and summoner.unit_sprite.is_playing(), "Summoner plays skill frames instead of immediately returning to idle.")
	var creature := session.combatants[-1]
	_check(creature.snapshot.definition_id == &"enemy.summoned_brawler" and creature.unit_sprite.visible and creature.unit_sprite.sprite_frames.get_frame_count(&"death") == 16, "A real spawned creature receives its new animated body.")
	summoner.force_die(null, &"effect.test")
	summoner._process(0.0)
	_check(summoner.skill_animation_remaining == 0.0 and summoner.unit_sprite.animation == &"death", "Death immediately overrides a spell animation.")
	session.free()


func _soldier(job: StringName) -> CombatUnitSnapshot:
	var soldier := SoldierState.new()
	soldier.unique_id = String(job)
	soldier.current_job_id = job
	return CombatSnapshotBuilder.build_soldier(soldier, null, registry)


func _session(army: Array[CombatUnitSnapshot]) -> CombatSession:
	var enemy := CombatUnitSnapshot.new()
	enemy.runtime_id = "enemy"
	enemy.team = CombatUnitSnapshot.Team.ENEMY
	enemy.stats.max_hp = 10000.0
	var session: CombatSession = SESSION_SCENE.instantiate()
	root.add_child(session)
	session.setup(army, [enemy], 73021)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	return session


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
