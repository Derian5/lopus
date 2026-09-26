class_name Combatant
extends CharacterBody2D


enum State {
	IDLE,
	ACQUIRE_TARGET,
	MOVE_INTO_RANGE,
	ATTACK_WINDUP,
	ATTACK_RECOVERY,
	DEAD,
}

const HERO_RADIUS := 22.0
const UNIT_RADIUS := 16.0
const BOSS_RADIUS := 29.0
const STUCK_TIMEOUT := 3.0
const RANGED_ATTACK_PAUSE := 0.1

var snapshot: CombatUnitSnapshot
var session
var arena_bounds := Rect2()
var state := State.IDLE
var target: Combatant
var current_hp := 0.0
var body_radius := UNIT_RADIUS
var base_body_radius := UNIT_RADIUS
var state_timer := 0.0
var windup_duration := 0.0
var stuck_time := 0.0
var last_movement_position := Vector2.ZERO
var simulation_active := false
var selected := false
var last_damage_source_id := ""
var last_effect_id: StringName
var ability_cooldowns: Dictionary = {}
var statuses: Array[StatusInstance] = []
var temporary_modifiers: Array[Dictionary] = []
var basic_attack_empowerments: Array[Dictionary] = []
var shields: Array[Dictionary] = []
var pending_ability: AbilityDefinition
var boss_phase := 1
var phase_banner_timer := 0.0
var last_stand_aura_duration := 0.0
var last_stand_remaining := 0.0
var basic_attack_range_bonus := 0.0
var targets_farthest_enemy := false
var melee_teleport_distance := 0.0
var melee_teleport_cooldown := 0.0
var melee_teleport_cooldown_remaining := 0.0
var enemy_attack_speed_aura_radius := 0.0
var enemy_attack_speed_aura_multiplier := 1.0


func setup(unit_snapshot: CombatUnitSnapshot, combat_session, bounds: Rect2) -> void:
	snapshot = unit_snapshot.duplicate_snapshot()
	session = combat_session
	arena_bounds = bounds
	current_hp = snapshot.stats.max_hp
	base_body_radius = BOSS_RADIUS if snapshot.is_boss else (HERO_RADIUS if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else UNIT_RADIUS)
	body_radius = base_body_radius
	var collision_shape := CircleShape2D.new()
	collision_shape.radius = body_radius
	$CollisionShape2D.shape = collision_shape
	# Soft separation is predictable and avoids crowd deadlocks.
	collision_layer = 0
	collision_mask = 0
	last_movement_position = position
	state = State.ACQUIRE_TARGET
	simulation_active = true
	_apply_passive_abilities()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not simulation_active or state == State.DEAD:
		velocity = Vector2.ZERO
		return
	_update_runtime(delta)
	if not is_alive():
		return
	if is_stunned():
		velocity = Vector2.ZERO
		return
	if _try_use_priority_summon():
		return

	match state:
		State.IDLE:
			state = State.ACQUIRE_TARGET
		State.ACQUIRE_TARGET:
			_acquire_target()
		State.MOVE_INTO_RANGE:
			_move_toward_target(delta)
		State.ATTACK_WINDUP:
			_update_attack_windup(delta)
		State.ATTACK_RECOVERY:
			_update_attack_recovery(delta)


func _acquire_target() -> void:
	if _try_use_ability():
		return
	target = session.find_basic_attack_target(self)
	velocity = Vector2.ZERO
	state = State.MOVE_INTO_RANGE if is_instance_valid(target) else State.IDLE


func _move_toward_target(delta: float) -> void:
	if not _has_valid_target():
		state = State.ACQUIRE_TARGET
		return

	var offset := target.position - position
	var distance := offset.length()
	var attack_range := get_effective_stat(&"attack_range")

	var direction := offset.normalized()
	if distance <= attack_range:
		if pending_ability == null and targets_farthest_enemy:
			target = session.find_basic_attack_target(self)
		velocity = Vector2.ZERO
		if pending_ability != null:
			_start_ability_windup()
		else:
			_start_attack()
		return

	var separation: Vector2 = session.get_separation_vector(self)
	var desired_direction: Vector2 = (direction + separation * 0.8).normalized()
	velocity = desired_direction * get_effective_stat(&"movement_speed")
	move_and_slide()
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	_update_stuck_state(delta)


func _start_attack() -> void:
	state = State.ATTACK_WINDUP
	if snapshot.attack_type == &"ranged" and not snapshot.is_boss:
		windup_duration = RANGED_ATTACK_PAUSE
	else:
		windup_duration = 0.65 if snapshot.is_boss else minf(0.35, 0.25 / maxf(get_effective_stat(&"attack_speed"), 0.01))
	state_timer = windup_duration
	queue_redraw()
	session.record_event(
		CombatEvent.ATTACK_STARTED,
		snapshot.runtime_id,
		target.snapshot.runtime_id,
		&"attack.basic",
		&"attack.basic"
	)


func _start_ability_windup() -> void:
	state = State.ATTACK_WINDUP
	windup_duration = 0.55 if snapshot.is_boss else 0.2
	state_timer = windup_duration
	queue_redraw()


func _update_attack_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	if snapshot.is_boss:
		queue_redraw()
	if not _has_valid_target():
		state = State.ACQUIRE_TARGET
		return

	if snapshot.attack_type == &"melee":
		var allowed_distance := get_effective_stat(&"attack_range") + target.body_radius
		if position.distance_to(target.position) > allowed_distance * 1.25:
			state = State.MOVE_INTO_RANGE
			return

	state_timer -= delta
	if state_timer > 0.0:
		return

	if pending_ability != null:
		var used_ability := pending_ability
		pending_ability = null
		session.deliver_ability(self, target, used_ability)
	elif snapshot.attack_type == &"ranged":
		session.spawn_projectile(self, target, get_effective_stat(&"damage"))
	else:
		var damage_dealt := target.take_damage(get_effective_stat(&"damage"), self, &"attack.basic", &"attack.basic", true)
		apply_basic_attack_lifesteal(damage_dealt)

	state = State.ATTACK_RECOVERY
	var attack_interval := 1.0 / maxf(get_effective_stat(&"attack_speed"), 0.01)
	state_timer = maxf(0.0 if snapshot.attack_type == &"ranged" else 0.05, attack_interval - windup_duration)
	queue_redraw()


func _update_attack_recovery(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		velocity = Vector2.ZERO
		state = State.ACQUIRE_TARGET
		return
	if snapshot.attack_type == &"ranged":
		_move_ranged_during_recovery(delta)
	else:
		velocity = Vector2.ZERO


func _move_ranged_during_recovery(delta: float) -> void:
	if not _has_valid_target():
		velocity = Vector2.ZERO
		state = State.ACQUIRE_TARGET
		return
	var offset := target.position - position
	var distance := offset.length()
	var direction := offset.normalized()
	var attack_range := get_effective_stat(&"attack_range")
	var can_retreat := distance < attack_range * 0.55 and _can_retreat_from(direction)
	if can_retreat:
		direction = -direction
	elif distance <= attack_range:
		velocity = Vector2.ZERO
		return
	var separation: Vector2 = session.get_separation_vector(self)
	velocity = (direction + separation * 0.8).normalized() * get_effective_stat(&"movement_speed")
	move_and_slide()
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	_update_stuck_state(delta)


func take_damage(
	raw_damage: float,
	source: Combatant,
	ability_id: StringName = &"attack.basic",
	effect_id: StringName = &"attack.basic",
	is_melee := false
) -> float:
	if not is_targetable():
		return 0.0

	var applied_damage := CombatRules.calculate_damage(raw_damage, get_effective_stat(&"armor"))
	for shield in shields:
		if applied_damage <= 0.0:
			break
		var absorbed := minf(applied_damage, float(shield.amount))
		shield.amount = float(shield.amount) - absorbed
		applied_damage -= absorbed
	shields = shields.filter(func(shield: Dictionary) -> bool: return float(shield.amount) > 0.0)
	applied_damage = minf(applied_damage, current_hp)
	current_hp = maxf(0.0, current_hp - applied_damage)
	last_damage_source_id = source.snapshot.runtime_id if is_instance_valid(source) else ""
	last_effect_id = effect_id
	session.record_event(
		CombatEvent.DAMAGE_APPLIED,
		last_damage_source_id,
		snapshot.runtime_id,
		ability_id,
		effect_id,
		applied_damage
	)
	queue_redraw()
	if applied_damage > 0.0 and is_melee and is_instance_valid(source) and source.snapshot.team != snapshot.team:
		_try_melee_teleport(source)
	if current_hp > 0.0:
		_update_boss_phase()
	if current_hp <= 0.0:
		var duration: float = session.get_last_stand_duration(self)
		if duration > 0.0:
			last_stand_remaining = duration
			target = null
			state = State.ACQUIRE_TARGET
		else:
			_die(source)
	return applied_damage


func receive_healing(
	amount: float,
	source: Combatant,
	ability_id: StringName,
	effect_id: StringName
) -> float:
	if not is_targetable():
		return 0.0
	var missing_health := maxf(0.0, get_effective_stat(&"max_hp") - current_hp)
	var applied_healing := minf(maxf(amount, 0.0), missing_health)
	current_hp += applied_healing
	session.record_event(
		CombatEvent.HEALING_APPLIED,
		source.snapshot.runtime_id if is_instance_valid(source) else "",
		snapshot.runtime_id,
		ability_id,
		effect_id,
		applied_healing
	)
	queue_redraw()
	return applied_healing


func is_alive() -> bool:
	return state != State.DEAD and (current_hp > 0.0 or last_stand_remaining > 0.0)


func is_targetable() -> bool:
	return state != State.DEAD and current_hp > 0.0


func set_simulation_active(value: bool) -> void:
	simulation_active = value
	if not value:
		velocity = Vector2.ZERO


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func get_effective_stat(stat: StringName) -> float:
	var value := float(snapshot.stats.get(stat))
	if stat == &"attack_range":
		value += basic_attack_range_bonus
	for status in statuses:
		for modifier in status.definition.stat_modifiers:
			if StringName(modifier.stat) == stat:
				value = _apply_modifier(value, modifier, status.stacks)
	for entry in temporary_modifiers:
		if StringName(entry.modifier.stat) == stat:
			value = _apply_modifier(value, entry.modifier, 1)
	if snapshot.is_boss and boss_phase > 1:
		if stat == &"damage":
			value *= pow(snapshot.boss_phase_damage_multiplier, boss_phase - 1)
		elif stat == &"attack_speed":
			value *= pow(snapshot.boss_phase_attack_speed_multiplier, boss_phase - 1)
	if stat == &"attack_speed" and session != null:
		value *= session.get_enemy_attack_speed_aura_multiplier(self)
	return maxf(value, 0.0)


func get_damage_multiplier() -> float:
	return get_effective_stat(&"damage") / maxf(snapshot.stats.damage, 0.01)


func add_temporary_modifier(
	modifier: StatModifier,
	duration: float,
	_source,
	_ability_id: StringName,
	_effect_id: StringName
) -> void:
	temporary_modifiers.append({"modifier": modifier, "remaining": duration if duration > 0.0 else -1.0})


func add_basic_attack_empowerment(
	lifesteal_percent: float,
	size_multiplier: float,
	duration: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	basic_attack_empowerments.append({
		"lifesteal_percent": maxf(lifesteal_percent, 0.0),
		"size_multiplier": maxf(size_multiplier, 0.01),
		"remaining": duration if duration > 0.0 else -1.0,
		"ability_id": ability_id,
		"effect_id": effect_id,
	})
	_refresh_body_radius()


func apply_basic_attack_lifesteal(damage_dealt: float) -> float:
	if damage_dealt <= 0.0 or basic_attack_empowerments.is_empty():
		return 0.0
	var percent := 0.0
	for empowerment in basic_attack_empowerments:
		percent += float(empowerment.lifesteal_percent)
	if percent <= 0.0:
		return 0.0
	var attribution: Dictionary = basic_attack_empowerments[0]
	return receive_healing(
		damage_dealt * percent / 100.0,
		self,
		StringName(attribution.ability_id),
		StringName(attribution.effect_id)
	)


func add_shield(
	amount: float,
	duration: float,
	_source,
	_ability_id: StringName,
	_effect_id: StringName
) -> void:
	if amount > 0.0:
		shields.append({"amount": amount, "remaining": duration if duration > 0.0 else -1.0})


func apply_status(definition: StatusDefinition, source: Combatant, ability_id: StringName) -> void:
	for status in statuses:
		if status.definition.id == definition.id:
			status.refresh(source, ability_id)
			session.record_status_applied(source, self, ability_id, definition.id)
			return
	var instance := StatusInstance.new()
	instance.setup(definition, source, ability_id)
	statuses.append(instance)
	session.record_status_applied(source, self, ability_id, definition.id)


func has_negative_status() -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.polarity == StatusDefinition.Polarity.NEGATIVE
	)


func has_status(status_id: StringName) -> bool:
	return statuses.any(func(status: StatusInstance) -> bool:
		return status.definition != null and status.definition.id == status_id
	)


func remove_random_negative_status(_source: Combatant, _ability_id: StringName, _effect_id: StringName) -> bool:
	var candidates: Array[int] = []
	for index in statuses.size():
		if statuses[index].definition != null and statuses[index].definition.polarity == StatusDefinition.Polarity.NEGATIVE:
			candidates.append(index)
	if candidates.is_empty():
		return false
	var selected_index := candidates[session.combat_rng.randi_range(0, candidates.size() - 1)]
	statuses.remove_at(selected_index)
	return true


func is_stunned() -> bool:
	for status in statuses:
		if status.definition.prevents_actions:
			return true
	return false


func get_debug_text() -> String:
	var target_id := "none"
	if is_instance_valid(target):
		target_id = target.snapshot.runtime_id
	var cooldown := state_timer if state == State.ATTACK_RECOVERY else 0.0
	return "ID: %s\nTeam: %s\nState: %s\nTarget: %s\nHP: %.1f / %.1f\nCooldown: %.2f s\nStatuses: %d%s" % [
		snapshot.runtime_id,
		"PLAYER" if snapshot.team == CombatUnitSnapshot.Team.PLAYER else "ENEMY",
		State.keys()[state],
		target_id,
		current_hp,
		get_effective_stat(&"max_hp"),
		cooldown,
		statuses.size(),
		"\nBoss phase: %d / %d" % [boss_phase, snapshot.boss_phase_count] if snapshot.is_boss else "",
	]


func _die(source: Combatant) -> void:
	if state == State.DEAD:
		return
	last_stand_remaining = 0.0
	state = State.DEAD
	simulation_active = false
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	queue_redraw()
	session.record_event(
		CombatEvent.UNIT_DIED,
		source.snapshot.runtime_id if is_instance_valid(source) else last_damage_source_id,
		snapshot.runtime_id,
		&"",
		last_effect_id
	)
	session.notify_combatant_died(self)


func force_die(source: Combatant, effect_id: StringName) -> void:
	last_effect_id = effect_id
	current_hp = 0.0
	_die(source)


func _has_valid_target() -> bool:
	return is_instance_valid(target) and target.is_targetable() and target.snapshot.team != snapshot.team


func _try_use_ability() -> bool:
	for ability in snapshot.abilities:
		if _try_activate_ability(ability, false):
			return true
	return false


func _try_use_priority_summon() -> bool:
	for ability in snapshot.abilities:
		if not _is_summon_ability(ability):
			continue
		if _try_activate_ability(ability, true):
			return true
	return false


func _try_activate_ability(ability: AbilityDefinition, interrupt_current_action: bool) -> bool:
	if ability.kind != AbilityDefinition.AbilityKind.ACTIVE:
		return false
	if float(ability_cooldowns.get(ability.id, 0.0)) > 0.0:
		return false
	var ability_target: Combatant = session.resolve_ability_target(self, ability)
	if not is_instance_valid(ability_target) or not session.can_use_ability(self, ability_target, ability):
		return false
	ability_cooldowns[ability.id] = ability.cooldown_seconds
	if interrupt_current_action:
		pending_ability = null
		target = null
		velocity = Vector2.ZERO
		state_timer = 0.0
		windup_duration = 0.0
		queue_redraw()
	if ability.delivery_method == AbilityDefinition.DeliveryMethod.MELEE_HIT or (snapshot.is_boss and not _is_summon_ability(ability)):
		pending_ability = ability
		target = ability_target
		state = State.MOVE_INTO_RANGE
	else:
		session.deliver_ability(self, ability_target, ability)
		state = State.ACQUIRE_TARGET
	return true


func _is_summon_ability(ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect is SummonEffect:
			return true
	return false


func _apply_passive_abilities() -> void:
	for ability in snapshot.abilities:
		if ability.kind != AbilityDefinition.AbilityKind.PASSIVE:
			continue
		for effect in ability.effects:
			effect.apply(self, self, ability)


func _update_runtime(delta: float) -> void:
	if last_stand_remaining > 0.0:
		last_stand_remaining = maxf(0.0, last_stand_remaining - delta)
		if last_stand_remaining <= 0.0:
			_die(null)
			return
	if melee_teleport_cooldown_remaining > 0.0:
		melee_teleport_cooldown_remaining = maxf(0.0, melee_teleport_cooldown_remaining - delta)
	if phase_banner_timer > 0.0:
		phase_banner_timer = maxf(0.0, phase_banner_timer - delta)
		queue_redraw()
	for ability_id in ability_cooldowns:
		ability_cooldowns[ability_id] = maxf(0.0, float(ability_cooldowns[ability_id]) - delta)
	for index in range(statuses.size() - 1, -1, -1):
		if statuses[index].update(delta, self):
			statuses.remove_at(index)
	for index in range(temporary_modifiers.size() - 1, -1, -1):
		if float(temporary_modifiers[index].remaining) < 0.0:
			continue
		temporary_modifiers[index].remaining = float(temporary_modifiers[index].remaining) - delta
		if float(temporary_modifiers[index].remaining) <= 0.0:
			temporary_modifiers.remove_at(index)
	var body_radius_changed := false
	for index in range(basic_attack_empowerments.size() - 1, -1, -1):
		if float(basic_attack_empowerments[index].remaining) < 0.0:
			continue
		basic_attack_empowerments[index].remaining = float(basic_attack_empowerments[index].remaining) - delta
		if float(basic_attack_empowerments[index].remaining) <= 0.0:
			basic_attack_empowerments.remove_at(index)
			body_radius_changed = true
	if body_radius_changed:
		_refresh_body_radius()
	for index in range(shields.size() - 1, -1, -1):
		if float(shields[index].remaining) < 0.0:
			continue
		shields[index].remaining = float(shields[index].remaining) - delta
		if float(shields[index].remaining) <= 0.0:
			shields.remove_at(index)


func _try_melee_teleport(attacker: Combatant) -> void:
	if melee_teleport_distance <= 0.0 or melee_teleport_cooldown_remaining > 0.0:
		return
	var direction := (position - attacker.position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.LEFT if snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
	var destination := position + direction * melee_teleport_distance
	var inset_bounds := arena_bounds.grow(-body_radius)
	position = Vector2(
		clampf(destination.x, inset_bounds.position.x, inset_bounds.end.x),
		clampf(destination.y, inset_bounds.position.y, inset_bounds.end.y)
	)
	melee_teleport_cooldown_remaining = melee_teleport_cooldown
	pending_ability = null
	target = null
	state = State.ACQUIRE_TARGET


func _refresh_body_radius() -> void:
	var multiplier := 1.0
	for empowerment in basic_attack_empowerments:
		multiplier *= float(empowerment.size_multiplier)
	body_radius = base_body_radius * multiplier
	var collision_shape := $CollisionShape2D.shape as CircleShape2D
	if collision_shape != null:
		collision_shape.radius = body_radius
	var inset_bounds := arena_bounds.grow(-body_radius)
	position = Vector2(
		clampf(position.x, inset_bounds.position.x, inset_bounds.end.x),
		clampf(position.y, inset_bounds.position.y, inset_bounds.end.y)
	)
	queue_redraw()


func _apply_modifier(base_value: float, modifier: StatModifier, stack_count: int) -> float:
	if modifier == null:
		return base_value
	return modifier.apply_to(base_value, stack_count)


func _update_stuck_state(delta: float) -> void:
	if position.distance_squared_to(last_movement_position) < 0.25:
		stuck_time += delta
	else:
		stuck_time = 0.0
		last_movement_position = position

	if stuck_time < STUCK_TIMEOUT:
		return

	stuck_time = 0.0
	target = null
	state = State.ACQUIRE_TARGET


func _can_retreat_from(direction_to_target: Vector2) -> bool:
	var retreat_position := position - direction_to_target * 48.0
	return arena_bounds.grow(-body_radius).has_point(retreat_position)


func _update_boss_phase() -> void:
	if not snapshot.is_boss or boss_phase >= snapshot.boss_phase_count:
		return
	var health_ratio := current_hp / maxf(snapshot.stats.max_hp, 1.0)
	while boss_phase < snapshot.boss_phase_count:
		var threshold_index := boss_phase - 1
		if threshold_index >= snapshot.boss_phase_health_thresholds.size() or health_ratio > snapshot.boss_phase_health_thresholds[threshold_index]:
			break
		boss_phase += 1
		phase_banner_timer = 1.5
		ability_cooldowns.clear()
		session.record_event(
			CombatEvent.BOSS_PHASE_CHANGED,
			snapshot.runtime_id,
			"",
			&"",
			&"boss.phase",
			float(boss_phase)
		)
	queue_redraw()


func _draw() -> void:
	var color := snapshot.placeholder_color
	if state == State.DEAD:
		color = color.darkened(0.65)

	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
		draw_circle(Vector2.ZERO, body_radius, color)
		draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 32, Color.WHITE, 2.0)
	else:
		draw_rect(Rect2(Vector2(-body_radius, -body_radius), Vector2.ONE * body_radius * 2.0), color)
	if snapshot.is_boss:
		draw_arc(Vector2.ZERO, body_radius + 5.0, 0.0, TAU, 40, snapshot.boss_telegraph_color, 3.0)
		for phase_ring in range(1, boss_phase):
			draw_arc(Vector2.ZERO, body_radius + 5.0 + phase_ring * 4.0, 0.0, TAU, 40, snapshot.boss_telegraph_color.lightened(0.2), 2.0)
	if selected:
		draw_arc(Vector2.ZERO, body_radius + 7.0, 0.0, TAU, 32, Color(1.0, 0.86, 0.35), 3.0)

	if state == State.DEAD:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color.WHITE, 3.0)
		draw_line(Vector2(10, -10), Vector2(-10, 10), Color.WHITE, 3.0)
		return
	if snapshot.is_boss and state == State.ATTACK_WINDUP:
		var progress := 1.0 - state_timer / maxf(windup_duration, 0.01)
		draw_arc(Vector2.ZERO, body_radius + 13.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, snapshot.boss_telegraph_color, 5.0)
		var warning := pending_ability.presentation_text if pending_ability != null and not pending_ability.presentation_text.is_empty() else "INCOMING ATTACK"
		draw_string(ThemeDB.fallback_font, Vector2(-body_radius * 2.0, -body_radius - 28.0), warning, HORIZONTAL_ALIGNMENT_CENTER, body_radius * 4.0, 12, snapshot.boss_telegraph_color)
	if snapshot.is_boss and phase_banner_timer > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(-body_radius * 3.0, body_radius + 30.0), snapshot.boss_phase_telegraph_text, HORIZONTAL_ALIGNMENT_CENTER, body_radius * 6.0, 13, snapshot.boss_telegraph_color)

	var health_ratio := current_hp / maxf(get_effective_stat(&"max_hp"), 1.0)
	var bar_rect := Rect2(Vector2(-body_radius, -body_radius - 11.0), Vector2(body_radius * 2.0, 5.0))
	draw_rect(bar_rect, Color(0.08, 0.08, 0.08, 0.9))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * health_ratio, bar_rect.size.y)), Color(0.28, 0.86, 0.38))
