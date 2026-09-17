class_name CombatSession
extends Control


signal battle_finished(winner: StringName, duration: float, timed_out: bool)
signal combat_event_emitted(event: CombatEvent)
signal combatant_selected(combatant: Combatant)

const COMBATANT_SCENE := preload("res://combat/combatant.tscn")
const PROJECTILE_SCENE := preload("res://combat/projectile.tscn")
const SEPARATION_DISTANCE := 54.0
const MAX_BATTLE_DURATION := 120.0

var combatants: Array[Combatant] = []
var player_snapshots: Array[CombatUnitSnapshot] = []
var enemy_snapshots: Array[CombatUnitSnapshot] = []
var combat_seed := 0
var elapsed_time := 0.0
var battle_active := false
var last_winner: StringName
var last_battle_timed_out := false
var events: Array[CombatEvent] = []
var statistics := CombatStatistics.new()
var selected_combatant: Combatant
var combat_rng := RandomNumberGenerator.new()


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	if not battle_active:
		return
	elapsed_time += delta
	if elapsed_time >= MAX_BATTLE_DURATION:
		_finish_battle(_get_timeout_winner(), true)


func setup(
	new_player_snapshots: Array[CombatUnitSnapshot],
	new_enemy_snapshots: Array[CombatUnitSnapshot],
	seed: int
) -> void:
	player_snapshots = _duplicate_snapshots(new_player_snapshots)
	enemy_snapshots = _duplicate_snapshots(new_enemy_snapshots)
	combat_seed = seed
	restart_battle()


func restart_battle() -> void:
	_clear_battle()
	events.clear()
	statistics.reset()
	elapsed_time = 0.0
	battle_active = true
	last_winner = &""
	last_battle_timed_out = false
	combat_rng.seed = combat_seed
	var bounds := get_arena_bounds()
	_spawn_team(player_snapshots, bounds, true)
	_spawn_team(enemy_snapshots, bounds, false)
	queue_redraw()


func find_closest_target(requester: Combatant) -> Combatant:
	var closest: Combatant
	var closest_distance := INF
	for candidate in combatants:
		if not candidate.is_alive() or candidate.snapshot.team == requester.snapshot.team:
			continue
		var distance := requester.position.distance_squared_to(candidate.position)
		if distance < closest_distance - 0.01:
			closest = candidate
			closest_distance = distance
		elif is_equal_approx(distance, closest_distance) and is_instance_valid(closest):
			if candidate.snapshot.runtime_id < closest.snapshot.runtime_id:
				closest = candidate
	return closest


func resolve_ability_target(requester: Combatant, ability: AbilityDefinition) -> Combatant:
	match ability.targeting_policy:
		AbilityDefinition.TargetingPolicy.SELF:
			return requester if requester.is_alive() else null
		AbilityDefinition.TargetingPolicy.CLOSEST_ENEMY:
			return find_closest_target(requester)
		AbilityDefinition.TargetingPolicy.LOWEST_HP_ALLY:
			var lowest: Combatant
			var lowest_ratio := INF
			for candidate in combatants:
				if not candidate.is_alive() or candidate.snapshot.team != requester.snapshot.team:
					continue
				var ratio := candidate.current_hp / maxf(candidate.get_effective_stat(&"max_hp"), 1.0)
				if ratio >= 1.0:
					continue
				if ratio < lowest_ratio - 0.0001 or (is_equal_approx(ratio, lowest_ratio) and _runtime_id_before(candidate, lowest)):
					lowest = candidate
					lowest_ratio = ratio
			return lowest
		AbilityDefinition.TargetingPolicy.RANDOM_VALID_ENEMY:
			var valid: Array[Combatant] = []
			for candidate in combatants:
				if candidate.is_alive() and candidate.snapshot.team != requester.snapshot.team:
					valid.append(candidate)
			valid.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
			return valid[combat_rng.randi_range(0, valid.size() - 1)] if not valid.is_empty() else null
	return null


func get_ability_definition(ability_id: StringName) -> AbilityDefinition:
	return get_node("/root/ContentRegistry").get_definition(ability_id, false) as AbilityDefinition


func deliver_ability(source: Combatant, target: Combatant, ability: AbilityDefinition) -> void:
	if not battle_active or not is_instance_valid(target) or not target.is_alive():
		return
	record_ability_used(source, target, ability.id)
	if ability.delivery_method == AbilityDefinition.DeliveryMethod.PROJECTILE:
		spawn_ability_projectile(source, target, ability)
		return
	if ability.delivery_method == AbilityDefinition.DeliveryMethod.AREA_AROUND_TARGET:
		for candidate in combatants:
			if candidate.is_alive() and candidate.snapshot.team == target.snapshot.team:
				if candidate.position.distance_to(target.position) <= ability.area_radius:
					_apply_ability_effects(source, candidate, ability)
		return
	_apply_ability_effects(source, target, ability)


func _apply_ability_effects(source: Combatant, target: Combatant, ability: AbilityDefinition) -> void:
	for effect in ability.effects:
		if not target.is_alive():
			break
		effect.apply(source, target, ability)


func get_separation_vector(requester: Combatant) -> Vector2:
	var separation := Vector2.ZERO
	for other in combatants:
		if other == requester or not other.is_alive():
			continue
		var offset := requester.position - other.position
		var distance := offset.length()
		if distance <= 0.001 or distance >= SEPARATION_DISTANCE:
			continue
		separation += offset.normalized() * (SEPARATION_DISTANCE - distance) / SEPARATION_DISTANCE
	return separation.limit_length(1.0)


func spawn_projectile(source: Combatant, target: Combatant, damage: float) -> void:
	if not battle_active:
		return
	var projectile: CombatProjectile = PROJECTILE_SCENE.instantiate()
	$Projectiles.add_child(projectile)
	projectile.setup(source, target, damage, source.snapshot.placeholder_color.lightened(0.2))


func spawn_ability_projectile(source: Combatant, target: Combatant, ability: AbilityDefinition) -> void:
	if not battle_active:
		return
	var projectile: CombatProjectile = PROJECTILE_SCENE.instantiate()
	$Projectiles.add_child(projectile)
	projectile.setup_ability(source, target, ability, ability.presentation_color)


func record_event(
	event_type: StringName,
	source_id := "",
	target_id := "",
	ability_id: StringName = &"",
	effect_id: StringName = &"",
	value := 0.0
) -> CombatEvent:
	var event := CombatEvent.new(
		elapsed_time,
		event_type,
		source_id,
		target_id,
		ability_id,
		effect_id,
		value
	)
	events.append(event)
	statistics.consume(event)
	combat_event_emitted.emit(event)
	return event


func record_ability_used(source: Combatant, target: Combatant, ability_id: StringName) -> void:
	record_event(
		CombatEvent.ABILITY_USED,
		source.snapshot.runtime_id,
		target.snapshot.runtime_id if is_instance_valid(target) else "",
		ability_id
	)


func record_status_applied(
	source: Combatant,
	target: Combatant,
	ability_id: StringName,
	status_id: StringName
) -> void:
	record_event(
		CombatEvent.STATUS_APPLIED,
		source.snapshot.runtime_id,
		target.snapshot.runtime_id,
		ability_id,
		status_id
	)


func notify_combatant_died(_combatant: Combatant) -> void:
	call_deferred("_check_battle_end")


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var nearest: Combatant
	var nearest_distance := INF
	for combatant in combatants:
		var distance := combatant.position.distance_to(event.position)
		if distance <= combatant.body_radius + 10.0 and distance < nearest_distance:
			nearest = combatant
			nearest_distance = distance
	_select_combatant(nearest)


func get_arena_bounds() -> Rect2:
	var margin := Vector2(48.0, 48.0)
	return Rect2(margin, Vector2(maxf(size.x - margin.x * 2.0, 200.0), maxf(size.y - margin.y * 2.0, 200.0)))


func _spawn_team(snapshots: Array[CombatUnitSnapshot], bounds: Rect2, player_team: bool) -> void:
	var row_spacing := minf(72.0, bounds.size.y / 7.0)
	var column_spacing := 72.0
	var rows := 6
	for index in snapshots.size():
		var row := index % rows
		var column := index / rows
		var combatant: Combatant = COMBATANT_SCENE.instantiate()
		$Units.add_child(combatant)
		var x := bounds.position.x + 125.0 + column * column_spacing
		if not player_team:
			x = bounds.end.x - 125.0 - column * column_spacing
		var used_rows := mini(rows, snapshots.size())
		var y_offset := (row - (used_rows - 1) * 0.5) * row_spacing
		combatant.position = Vector2(x, bounds.get_center().y + y_offset)
		statistics.register_unit(snapshots[index])
		combatant.setup(snapshots[index], self, bounds)
		combatants.append(combatant)


func _check_battle_end() -> void:
	if not battle_active:
		return
	var player_alive := false
	var enemy_alive := false
	for combatant in combatants:
		if not combatant.is_alive():
			continue
		if combatant.snapshot.team == CombatUnitSnapshot.Team.PLAYER:
			player_alive = true
		else:
			enemy_alive = true

	if player_alive and enemy_alive:
		return
	var winner: StringName = &"player" if player_alive else &"enemy"
	_finish_battle(winner, false)


func _finish_battle(winner: StringName, timed_out: bool) -> void:
	if not battle_active:
		return
	battle_active = false
	last_winner = winner
	last_battle_timed_out = timed_out
	for combatant in combatants:
		combatant.set_simulation_active(false)
	for projectile in $Projectiles.get_children():
		projectile.queue_free()
	record_event(CombatEvent.BATTLE_FINISHED, String(winner), "", &"", &"", elapsed_time)
	battle_finished.emit(winner, elapsed_time, timed_out)


func _get_timeout_winner() -> StringName:
	var player_health := 0.0
	var enemy_health := 0.0
	for combatant in combatants:
		if not combatant.is_alive():
			continue
		if combatant.snapshot.team == CombatUnitSnapshot.Team.PLAYER:
			player_health += combatant.current_hp
		else:
			enemy_health += combatant.current_hp
	return &"player" if player_health > enemy_health else &"enemy"


func _clear_battle() -> void:
	battle_active = false
	selected_combatant = null
	combatants.clear()
	for unit in $Units.get_children():
		unit.free()
	for projectile in $Projectiles.get_children():
		projectile.free()


func _select_combatant(combatant: Combatant) -> void:
	if is_instance_valid(selected_combatant):
		selected_combatant.set_selected(false)
	selected_combatant = combatant
	if is_instance_valid(selected_combatant):
		selected_combatant.set_selected(true)
	combatant_selected.emit(selected_combatant)


func _duplicate_snapshots(source: Array[CombatUnitSnapshot]) -> Array[CombatUnitSnapshot]:
	var result: Array[CombatUnitSnapshot] = []
	for snapshot in source:
		result.append(snapshot.duplicate_snapshot())
	return result


func _runtime_id_before(candidate: Combatant, current: Combatant) -> bool:
	return not is_instance_valid(current) or candidate.snapshot.runtime_id < current.snapshot.runtime_id


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.125, 0.11, 0.09))
	var bounds := get_arena_bounds()
	draw_rect(bounds, Color(0.17, 0.145, 0.11), true)
	draw_rect(bounds, Color(0.37, 0.31, 0.22), false, 2.0)
	draw_dashed_line(
		Vector2(bounds.get_center().x, bounds.position.y),
		Vector2(bounds.get_center().x, bounds.end.y),
		Color(0.55, 0.48, 0.36, 0.45),
		2.0,
		16.0
	)
