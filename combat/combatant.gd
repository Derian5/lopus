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
const STUCK_TIMEOUT := 3.0

var snapshot: CombatUnitSnapshot
var session
var arena_bounds := Rect2()
var state := State.IDLE
var target: Combatant
var current_hp := 0.0
var body_radius := UNIT_RADIUS
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
var shields: Array[Dictionary] = []
var pending_ability: AbilityDefinition


func setup(unit_snapshot: CombatUnitSnapshot, combat_session, bounds: Rect2) -> void:
	snapshot = unit_snapshot.duplicate_snapshot()
	session = combat_session
	arena_bounds = bounds
	current_hp = snapshot.stats.max_hp
	body_radius = HERO_RADIUS if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else UNIT_RADIUS
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
	target = session.find_closest_target(self)
	velocity = Vector2.ZERO
	state = State.MOVE_INTO_RANGE if is_instance_valid(target) else State.IDLE


func _move_toward_target(delta: float) -> void:
	if not _has_valid_target():
		state = State.ACQUIRE_TARGET
		return

	var offset := target.position - position
	var distance := offset.length()
	var attack_range := get_effective_stat(&"attack_range")
	var preferred_minimum := attack_range * 0.55
	var is_ranged := snapshot.attack_type == &"ranged"

	var direction := offset.normalized()
	var can_retreat := is_ranged and distance < preferred_minimum and _can_retreat_from(direction)
	if distance <= attack_range and not can_retreat:
		velocity = Vector2.ZERO
		if pending_ability != null:
			_start_ability_windup()
		else:
			_start_attack()
		return

	if can_retreat:
		direction = -direction

	var separation: Vector2 = session.get_separation_vector(self)
	var desired_direction: Vector2 = (direction + separation * 0.8).normalized()
	velocity = desired_direction * get_effective_stat(&"movement_speed")
	move_and_slide()
	position.x = clampf(position.x, arena_bounds.position.x + body_radius, arena_bounds.end.x - body_radius)
	position.y = clampf(position.y, arena_bounds.position.y + body_radius, arena_bounds.end.y - body_radius)
	_update_stuck_state(delta)


func _start_attack() -> void:
	state = State.ATTACK_WINDUP
	windup_duration = minf(0.35, 0.25 / maxf(get_effective_stat(&"attack_speed"), 0.01))
	state_timer = windup_duration
	session.record_event(
		CombatEvent.ATTACK_STARTED,
		snapshot.runtime_id,
		target.snapshot.runtime_id,
		&"attack.basic",
		&"attack.basic"
	)


func _start_ability_windup() -> void:
	state = State.ATTACK_WINDUP
	windup_duration = 0.2
	state_timer = windup_duration


func _update_attack_windup(delta: float) -> void:
	velocity = Vector2.ZERO
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
		target.take_damage(get_effective_stat(&"damage"), self)

	state = State.ATTACK_RECOVERY
	var attack_interval := 1.0 / maxf(get_effective_stat(&"attack_speed"), 0.01)
	state_timer = maxf(0.05, attack_interval - windup_duration)


func _update_attack_recovery(delta: float) -> void:
	velocity = Vector2.ZERO
	state_timer -= delta
	if state_timer <= 0.0:
		state = State.ACQUIRE_TARGET


func take_damage(
	raw_damage: float,
	source: Combatant,
	ability_id: StringName = &"attack.basic",
	effect_id: StringName = &"attack.basic"
) -> float:
	if not is_alive():
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
	if current_hp <= 0.0:
		_die(source)
	return applied_damage


func receive_healing(
	amount: float,
	source: Combatant,
	ability_id: StringName,
	effect_id: StringName
) -> float:
	if not is_alive():
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
	for status in statuses:
		for modifier in status.definition.stat_modifiers:
			if StringName(modifier.stat) == stat:
				value = _apply_modifier(value, modifier, status.stacks)
	for entry in temporary_modifiers:
		if StringName(entry.modifier.stat) == stat:
			value = _apply_modifier(value, entry.modifier, 1)
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
	return "ID: %s\nTeam: %s\nState: %s\nTarget: %s\nHP: %.1f / %.1f\nCooldown: %.2f s\nStatuses: %d" % [
		snapshot.runtime_id,
		"PLAYER" if snapshot.team == CombatUnitSnapshot.Team.PLAYER else "ENEMY",
		State.keys()[state],
		target_id,
		current_hp,
		get_effective_stat(&"max_hp"),
		cooldown,
		statuses.size(),
	]


func _die(source: Combatant) -> void:
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


func _has_valid_target() -> bool:
	return is_instance_valid(target) and target.is_alive() and target.snapshot.team != snapshot.team


func _try_use_ability() -> bool:
	for ability in snapshot.abilities:
		if ability.kind != AbilityDefinition.AbilityKind.ACTIVE:
			continue
		if float(ability_cooldowns.get(ability.id, 0.0)) > 0.0:
			continue
		var ability_target: Combatant = session.resolve_ability_target(self, ability)
		if not is_instance_valid(ability_target):
			continue
		ability_cooldowns[ability.id] = ability.cooldown_seconds
		if ability.delivery_method == AbilityDefinition.DeliveryMethod.MELEE_HIT:
			pending_ability = ability
			target = ability_target
			state = State.MOVE_INTO_RANGE
		else:
			session.deliver_ability(self, ability_target, ability)
			state = State.ACQUIRE_TARGET
		return true
	return false


func _apply_passive_abilities() -> void:
	for ability in snapshot.abilities:
		if ability.kind != AbilityDefinition.AbilityKind.PASSIVE:
			continue
		for effect in ability.effects:
			effect.apply(self, self, ability)


func _update_runtime(delta: float) -> void:
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
	for index in range(shields.size() - 1, -1, -1):
		if float(shields[index].remaining) < 0.0:
			continue
		shields[index].remaining = float(shields[index].remaining) - delta
		if float(shields[index].remaining) <= 0.0:
			shields.remove_at(index)


func _apply_modifier(base_value: float, modifier: StatModifier, stack_count: int) -> float:
	if modifier == null:
		return base_value
	if modifier.operation == StatModifier.Operation.MULTIPLY:
		return base_value * pow(modifier.value, stack_count)
	return base_value + modifier.value * stack_count


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


func _draw() -> void:
	var color := snapshot.placeholder_color
	if state == State.DEAD:
		color = color.darkened(0.65)

	if snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO:
		draw_circle(Vector2.ZERO, body_radius, color)
		draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 32, Color.WHITE, 2.0)
	else:
		draw_rect(Rect2(Vector2(-body_radius, -body_radius), Vector2.ONE * body_radius * 2.0), color)
	if selected:
		draw_arc(Vector2.ZERO, body_radius + 7.0, 0.0, TAU, 32, Color(1.0, 0.86, 0.35), 3.0)

	if state == State.DEAD:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color.WHITE, 3.0)
		draw_line(Vector2(10, -10), Vector2(-10, 10), Color.WHITE, 3.0)
		return

	var health_ratio := current_hp / maxf(get_effective_stat(&"max_hp"), 1.0)
	var bar_rect := Rect2(Vector2(-body_radius, -body_radius - 11.0), Vector2(body_radius * 2.0, 5.0))
	draw_rect(bar_rect, Color(0.08, 0.08, 0.08, 0.9))
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * health_ratio, bar_rect.size.y)), Color(0.28, 0.86, 0.38))
