class_name CombatSession
extends Control


const BATTLEGROUND := preload("res://graphics/battleground.png")
## Animated battlefield: a looping video behind everything and a foreground frame in
## front of the units that drifts with the mouse (parallax). Loaded on scene entry,
## never in the Balance Lab.
const BACKDROP_VIDEO_PATH := "res://graphics/battleground/battleground_back.ogv"
const FOREGROUND_PATH := "res://graphics/battleground/battleground_front.png"
## How far (px) each layer drifts when the mouse is at the edge of the arena. The
## foreground moves against the mouse, the backdrop a little with it: depth.
const FOREGROUND_PARALLAX := Vector2(34.0, 18.0)
const BACKDROP_PARALLAX := Vector2(10.0, 5.0)
## Layers are drawn slightly larger than the arena so drifting never shows an edge.
const PARALLAX_OVERSCAN := 1.06
const PARALLAX_SMOOTHING := 5.0
## Above units, projectiles and effects, below health bars (Combatant overhead z 100).
const FOREGROUND_Z := 90
## The foreground is the closest, darkest plane (a silhouette against the lit field).
const FOREGROUND_TINT := Color(0.46, 0.42, 0.4)
const VIGNETTE_Z := 85


signal battle_finished(winner: StringName, duration: float, timed_out: bool)
signal combat_event_emitted(event: CombatEvent)
signal combatant_selected(combatant: Combatant)

const COMBATANT_SCENE := preload("res://combat/combatant.tscn")
const PROJECTILE_SCENE := preload("res://combat/projectile.tscn")
const MAX_BATTLE_DURATION := 120.0
const OVERLAP_RESOLUTION_SPEED := 900.0
const REINFORCEMENT_EDGE_INSET := 48.0
const SUMMON_SPAWN_DISTANCE := 58.0
const MELEE_APPROACH_SLOTS := 12
const TARGET_SWITCH_ADVANTAGE := 32.0
## Preloaded rather than used by class name, so headless runs work before the editor scans new classes.
const VFX := preload("res://combat/vfx/combat_vfx.gd")
const VFX_DIRECTOR := preload("res://combat/vfx/combat_vfx_director.gd")

var combatants: Array[Combatant] = []
var player_snapshots: Array[CombatUnitSnapshot] = []
var enemy_snapshots: Array[CombatUnitSnapshot] = []
var reinforcement_snapshots: Array[CombatUnitSnapshot] = []
var reinforcement_alive_threshold := -1
var reinforcement_entry_direction := EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE
var reinforcements_spawned := false
var combat_seed := 0
var elapsed_time := 0.0
var battle_active := false
var last_winner: StringName
var last_battle_timed_out := false
var events: Array[CombatEvent] = []
var statistics := CombatStatistics.new()
var selected_combatant: Combatant
var combat_rng := RandomNumberGenerator.new()
var summon_serial := 0
var smoke_zones: Array[Dictionary] = []
var active_global_taunts: Array[Dictionary] = []
var active_summon_merges: Dictionary = {}
var initial_player_army_count := 0
var critical_hits := 0
## Set by the aura effects when any unit in this battle gets that aura, so the aura
## lookups (called for every stat query) can skip scanning all units otherwise.
var any_soldier_damage_aura := false
var any_item_slow_aura := false
var any_attack_speed_aura := false
## Visual effects (CombatVfx). The Balance Lab turns them off: they never affect combat.
var vfx_enabled := true
var vfx_director: Node
var backdrop: VideoStreamPlayer
var foreground: TextureRect
var vignette: TextureRect
var parallax_offset := Vector2.ZERO
## Short light flashes of effects (kept apart from the Effects layer).
var light_layer: Node2D


func _ready() -> void:
	resized.connect(queue_redraw)
	resized.connect(_layout_scenery)
	light_layer = Node2D.new()
	light_layer.name = "VfxLights"
	add_child(light_layer)
	vfx_director = VFX_DIRECTOR.new(self)
	add_child(vfx_director)
	_setup_scenery()
	queue_redraw()


func _process(delta: float) -> void:
	_update_parallax(delta)
	if not battle_active:
		return
	_update_smoke_zones(delta)
	_update_global_taunts(delta)
	_update_summon_merges(delta)
	elapsed_time += delta
	if elapsed_time >= MAX_BATTLE_DURATION:
		_finish_battle(_get_timeout_winner(), true)


func _physics_process(delta: float) -> void:
	if battle_active:
		_resolve_combatant_overlaps(delta)


func setup(
	new_player_snapshots: Array[CombatUnitSnapshot],
	new_enemy_snapshots: Array[CombatUnitSnapshot],
	seed: int,
	new_reinforcement_snapshots: Array[CombatUnitSnapshot] = [],
	new_reinforcement_alive_threshold := -1,
	new_reinforcement_entry_direction := EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE
) -> void:
	player_snapshots = _duplicate_snapshots(new_player_snapshots)
	enemy_snapshots = _duplicate_snapshots(new_enemy_snapshots)
	reinforcement_snapshots = _duplicate_snapshots(new_reinforcement_snapshots)
	reinforcement_alive_threshold = new_reinforcement_alive_threshold
	reinforcement_entry_direction = new_reinforcement_entry_direction
	combat_seed = seed
	restart_battle()


func restart_battle() -> void:
	_setup_scenery()
	_clear_battle()
	events.clear()
	statistics.reset()
	elapsed_time = 0.0
	battle_active = true
	last_winner = &""
	last_battle_timed_out = false
	reinforcements_spawned = false
	summon_serial = 0
	any_soldier_damage_aura = false
	any_item_slow_aura = false
	any_attack_speed_aura = false
	combat_rng.seed = combat_seed
	var bounds := get_arena_bounds()
	_spawn_team(player_snapshots, bounds, true)
	_spawn_team(enemy_snapshots, bounds, false)
	critical_hits = 0
	initial_player_army_count = player_army_alive_count()
	_initialize_lust_bonds()
	queue_redraw()


func find_closest_target(requester: Combatant) -> Combatant:
	var closest: Combatant
	var closest_distance := INF
	for candidate in combatants:
		if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team == requester.snapshot.team:
			continue
		var distance := requester.position.distance_squared_to(candidate.position)
		if distance < closest_distance - 0.01:
			closest = candidate
			closest_distance = distance
		elif is_equal_approx(distance, closest_distance) and is_instance_valid(closest):
			if candidate.snapshot.runtime_id < closest.snapshot.runtime_id:
				closest = candidate
	return closest


func find_basic_attack_target(requester: Combatant) -> Combatant:
	if requester._has_forced_basic_target():
		return requester.forced_basic_target
	if requester.snapshot.targeting_mode == &"back_line":
		var hunted := find_back_line_target(requester)
		if is_instance_valid(hunted):
			return _stable_basic_target(requester, hunted, true)
	if requester.prefers_farthest_enemy:
		return find_farthest_target(requester)
	if not requester.targets_farthest_enemy:
		return _stable_basic_target(requester, find_closest_target(requester))
	var farthest: Combatant
	var farthest_distance := -1.0
	for candidate in combatants:
		if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team == requester.snapshot.team:
			continue
		var distance := requester.position.distance_to(candidate.position)
		if distance > requester.basic_attack_reach(candidate):
			continue
		if distance > farthest_distance + 0.01 or (is_equal_approx(distance, farthest_distance) and _runtime_id_before(candidate, farthest)):
			farthest = candidate
			farthest_distance = distance
	return farthest if is_instance_valid(farthest) else find_closest_target(requester)


## Keep a valid basic target unless switching offers a meaningful distance gain.
func _stable_basic_target(requester: Combatant, candidate: Combatant, back_line_only := false) -> Combatant:
	var current := requester.target
	if not is_instance_valid(current) or not current.can_be_targeted_by(requester) or current.snapshot.team == requester.snapshot.team:
		return candidate
	if back_line_only and current.snapshot.attack_type != &"ranged":
		return candidate
	if not is_instance_valid(candidate) or candidate == current:
		return current
	var current_distance := requester.position.distance_to(current.position)
	var candidate_distance := requester.position.distance_to(candidate.position)
	var advantage := maxf(TARGET_SWITCH_ADVANTAGE, current_distance * 0.2)
	return candidate if candidate_distance + advantage < current_distance else current


## Assign deterministic approach sectors without changing the combatant update order
## or drawing any additional random numbers. A claimed sector stays with its fighter.
func melee_approach_position(requester: Combatant, target: Combatant, preferred_slot := -1) -> Dictionary:
	var reach := requester.basic_attack_reach(target)
	var radius := maxf(requester.body_radius + target.body_radius, reach - Combatant.APPROACH_INSET)
	var inset := requester.arena_bounds.grow(-requester.body_radius)
	var away := Vector2.LEFT if requester.position.x < target.position.x else Vector2.RIGHT
	var fallback := (target.position + away * radius).clamp(inset.position, inset.end)
	var best := {"slot": -1, "position": fallback}
	var best_score := INF
	for slot in MELEE_APPROACH_SLOTS:
		# Leave angular margin for the navigation arrival tolerance and crowding.
		var side_slots := MELEE_APPROACH_SLOTS / 2
		var angle := lerpf(-PI / 9.0, PI / 9.0, float(slot % side_slots) / float(side_slots - 1))
		if slot >= side_slots:
			angle += PI
		var point := target.position + Vector2.RIGHT.rotated(angle) * radius
		point = point.clamp(inset.position, inset.end)
		var target_distance := point.distance_to(target.position)
		if target_distance < requester.body_radius + target.body_radius - 0.1 or target_distance > reach + 0.01 or not requester.is_basic_attack_side_position(target, point):
			continue
		var score := requester.position.distance_squared_to(point)
		if slot == preferred_slot:
			score -= 1600.0
		for other in combatants:
			if other == requester or other.snapshot.team != requester.snapshot.team or not other.is_alive():
				continue
			if other.approach_target == target and other.approach_slot_index == slot and other.target == target and other.pending_ability == null:
				score += 1000000.0
			elif other.approach_target == target and other.target == target and other.approach_goal.distance_to(point) < requester.body_radius + other.body_radius + 2.0:
				score += 1000000.0
			var clearance := requester.personal_space_radius() + other.personal_space_radius()
			score += maxf(0.0, clearance * clearance - other.position.distance_squared_to(point)) * 2.0
		if score < best_score:
			best_score = score
			best = {"slot": slot, "position": point}
	return best


## Nearest ranged enemy of the requester (the "back line"), or null if there is none.
func find_back_line_target(requester: Combatant) -> Combatant:
	var best: Combatant
	var best_distance := INF
	for candidate in combatants:
		if candidate.snapshot.team == requester.snapshot.team or candidate.snapshot.attack_type != &"ranged" or not candidate.can_be_targeted_by(requester):
			continue
		var distance := requester.position.distance_squared_to(candidate.position)
		if distance < best_distance - 0.01 or (is_equal_approx(distance, best_distance) and _runtime_id_before(candidate, best)):
			best = candidate
			best_distance = distance
	return best


func find_farthest_target(requester: Combatant) -> Combatant:
	var farthest: Combatant
	var farthest_distance := -1.0
	for candidate in combatants:
		if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team == requester.snapshot.team:
			continue
		var distance := requester.position.distance_squared_to(candidate.position)
		if distance > farthest_distance + 0.01 or (is_equal_approx(distance, farthest_distance) and _runtime_id_before(candidate, farthest)):
			farthest = candidate
			farthest_distance = distance
	return farthest


func find_frenzy_attack_target(requester: Combatant) -> Combatant:
	var candidates: Array[Combatant] = []
	var attack_range := requester.get_effective_stat(&"attack_range")
	for candidate in combatants:
		if candidate == requester:
			continue
		var valid_target := candidate.is_targetable() if candidate.snapshot.team == requester.snapshot.team else candidate.can_be_targeted_by(requester)
		if not valid_target:
			continue
		if requester.position.distance_to(candidate.position) <= attack_range + requester.body_radius + candidate.body_radius:
			candidates.append(candidate)
	candidates.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	return candidates[combat_rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else null


func random_arena_point(requester: Combatant) -> Vector2:
	var bounds := get_arena_bounds().grow(-requester.body_radius)
	return Vector2(
		combat_rng.randf_range(bounds.position.x, bounds.end.x),
		combat_rng.randf_range(bounds.position.y, bounds.end.y)
	)


func resolve_ability_target(requester: Combatant, ability: AbilityDefinition) -> Combatant:
	match ability.targeting_policy:
		AbilityDefinition.TargetingPolicy.SELF:
			return requester if requester.is_alive() else null
		AbilityDefinition.TargetingPolicy.CLOSEST_ENEMY:
			var closest: Combatant
			var closest_distance := INF
			for candidate in combatants:
				if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team == requester.snapshot.team or not _is_within_ability_search_radius(requester, candidate, ability):
					continue
				var distance := requester.position.distance_squared_to(candidate.position)
				if distance < closest_distance - 0.01 or (is_equal_approx(distance, closest_distance) and _runtime_id_before(candidate, closest)):
					closest = candidate
					closest_distance = distance
			return closest
		AbilityDefinition.TargetingPolicy.LOWEST_HP_ALLY:
			var lowest: Combatant
			var lowest_ratio := INF
			for candidate in combatants:
				if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team != requester.snapshot.team or not _is_within_ability_search_radius(requester, candidate, ability):
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
				if candidate.can_be_targeted_by(requester) and candidate.snapshot.team != requester.snapshot.team and _is_within_ability_search_radius(requester, candidate, ability):
					valid.append(candidate)
			valid.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
			return valid[combat_rng.randi_range(0, valid.size() - 1)] if not valid.is_empty() else null
		AbilityDefinition.TargetingPolicy.NEAREST_NEGATIVE_STATUS_ALLY:
			var nearest: Combatant
			var nearest_distance := INF
			for candidate in combatants:
				if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team != requester.snapshot.team or not candidate.has_negative_status() or not _is_within_ability_search_radius(requester, candidate, ability):
					continue
				var distance := requester.position.distance_squared_to(candidate.position)
				if distance < nearest_distance - 0.01 or (is_equal_approx(distance, nearest_distance) and _runtime_id_before(candidate, nearest)):
					nearest = candidate
					nearest_distance = distance
			return nearest
		AbilityDefinition.TargetingPolicy.RANDOM_ENEMY_WITHOUT_STATUS:
			var valid: Array[Combatant] = []
			for candidate in combatants:
				if (
					candidate.can_be_targeted_by(requester)
					and candidate.snapshot.team != requester.snapshot.team
					and not candidate.has_status(ability.excluded_target_status_id)
					and _is_within_ability_search_radius(requester, candidate, ability)
				):
					valid.append(candidate)
			valid.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
			return valid[combat_rng.randi_range(0, valid.size() - 1)] if not valid.is_empty() else null
		AbilityDefinition.TargetingPolicy.LOWEST_CURRENT_HP_ALLY:
			var lowest: Combatant
			var lowest_hp := INF
			for candidate in combatants:
				if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team != requester.snapshot.team or not _is_within_ability_search_radius(requester, candidate, ability):
					continue
				if candidate.current_hp >= candidate.get_effective_stat(&"max_hp"):
					continue
				if candidate.current_hp < lowest_hp - 0.0001 or (is_equal_approx(candidate.current_hp, lowest_hp) and _runtime_id_before(candidate, lowest)):
					lowest = candidate
					lowest_hp = candidate.current_hp
			return lowest
		AbilityDefinition.TargetingPolicy.MOST_TARGETED_ALLY:
			return _most_targeted_ally(requester, ability)
		AbilityDefinition.TargetingPolicy.RANDOM_BACK_LINE_ENEMY:
			var back_line: Array[Combatant] = []
			var any: Array[Combatant] = []
			for candidate in combatants:
				if candidate.can_be_targeted_by(requester) and candidate.snapshot.team != requester.snapshot.team and _is_within_ability_search_radius(requester, candidate, ability):
					any.append(candidate)
					if candidate.snapshot.attack_type == &"ranged":
						back_line.append(candidate)
			var pool := back_line if not back_line.is_empty() else any
			pool.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
			return pool[combat_rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null
		AbilityDefinition.TargetingPolicy.HIGHEST_DAMAGE_ENEMY:
			return _best_enemy(requester, ability, &"damage", true)
		AbilityDefinition.TargetingPolicy.HIGHEST_HP_NON_BOSS_ENEMY:
			return _best_enemy(requester, ability, &"current_hp", false)
	return null


## Enemy with the highest value of a stat (or current HP); ties go to the lower runtime id.
func _best_enemy(requester: Combatant, ability: AbilityDefinition, stat: StringName, allow_boss: bool) -> Combatant:
	var best: Combatant
	var best_value := -INF
	for candidate in combatants:
		if not candidate.can_be_targeted_by(requester) or candidate.snapshot.team == requester.snapshot.team or not _is_within_ability_search_radius(requester, candidate, ability):
			continue
		if not allow_boss and candidate.snapshot.is_boss:
			continue
		if ability.excluded_target_status_id != &"" and candidate.has_status(ability.excluded_target_status_id):
			continue
		var value := candidate.current_hp if stat == &"current_hp" else candidate.get_effective_stat(stat)
		if value > best_value + 0.0001 or (is_equal_approx(value, best_value) and _runtime_id_before(candidate, best)):
			best = candidate
			best_value = value
	return best


# --- item mechanics ------------------------------------------------------------

## Living Heroes and Soldiers of the player's army (summons excluded).
func player_army_alive_count() -> int:
	var count := 0
	for combatant in combatants:
		if combatant.is_alive() and combatant.items.home_team() == CombatUnitSnapshot.Team.PLAYER and combatant.snapshot.unit_kind in [CombatUnitSnapshot.UnitKind.HERO, CombatUnitSnapshot.UnitKind.SOLDIER]:
			count += 1
	return count


## Nearest other living ally that soaks part of the damage for this unit.
func find_damage_redirector(target: Combatant) -> Combatant:
	var best: Combatant
	var best_distance := INF
	for candidate in combatants:
		if candidate == target or not candidate.items.has_damage_redirect() or not candidate.is_targetable():
			continue
		if candidate.snapshot.team != target.snapshot.team:
			continue
		var distance := candidate.position.distance_to(target.position)
		if distance <= candidate.items.redirect_radius and distance < best_distance:
			best = candidate
			best_distance = distance
	return best


## Strongest Soldier damage aura covering this Soldier (auras do not stack).
func get_soldier_damage_aura(target: Combatant) -> Dictionary:
	var result := {"percent": 0.0, "ability_id": &""}
	if not any_soldier_damage_aura:
		return result
	for candidate in combatants:
		var runtime := candidate.items
		if runtime.soldier_aura_radius <= 0.0 or not candidate.is_alive() or candidate.snapshot.team != target.snapshot.team:
			continue
		if candidate.position.distance_to(target.position) > runtime.soldier_aura_radius:
			continue
		var percent := runtime.veteran_aura_percent if target.snapshot.veterancy_level >= runtime.veteran_min_level else runtime.soldier_aura_percent
		if percent > float(result.percent):
			result = {"percent": percent, "ability_id": runtime.soldier_aura_ability_id}
	return result


## Strongest enemy slowing aura on this unit (attack and movement speed).
func get_item_slow_aura(target: Combatant) -> Dictionary:
	var result := {"percent": 0.0, "ability_id": &""}
	if not any_item_slow_aura:
		return result
	for candidate in combatants:
		var runtime := candidate.items
		if runtime.slow_aura_radius <= 0.0 or not candidate.is_alive() or candidate.snapshot.team == target.snapshot.team:
			continue
		if candidate.position.distance_to(target.position) <= runtime.slow_aura_radius and runtime.slow_aura_percent > float(result.percent):
			result = {"percent": runtime.slow_aura_percent, "ability_id": runtime.slow_aura_ability_id}
	return result


func record_critical_hit(_source: Combatant) -> void:
	critical_hits += 1


func _is_within_ability_search_radius(source: Combatant, candidate: Combatant, ability: AbilityDefinition) -> bool:
	return ability.target_search_radius <= 0.0 or source.position.distance_to(candidate.position) <= ability.target_search_radius


func get_ability_definition(ability_id: StringName) -> AbilityDefinition:
	return get_node("/root/ContentRegistry").get_definition(ability_id, false) as AbilityDefinition


func can_use_ability(source: Combatant, target: Combatant, ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect == null or not effect.can_apply(source, target, ability):
			return false
	return true


func deliver_ability(source: Combatant, target: Combatant, ability: AbilityDefinition) -> void:
	if not battle_active or not is_instance_valid(target) or not target.is_alive():
		return
	record_ability_used(source, target, ability.id)
	source.play_ability_animation(target, ability)
	if ability.delivery_method == AbilityDefinition.DeliveryMethod.PROJECTILE:
		spawn_ability_projectile(source, target, ability)
		return
	if ability.delivery_method == AbilityDefinition.DeliveryMethod.AREA_AROUND_TARGET:
		for candidate in combatants:
			if candidate.is_targetable() and candidate.snapshot.team == target.snapshot.team:
				if candidate.position.distance_to(target.position) <= ability.area_radius:
					_apply_ability_effects(source, candidate, ability)
		return
	_apply_ability_effects(source, target, ability)


func _apply_ability_effects(source: Combatant, target: Combatant, ability: AbilityDefinition) -> void:
	if not target.can_receive_effect_from(source):
		return
	for effect in ability.effects:
		if not target.is_alive():
			break
		effect.apply(source, target, ability)


func get_last_stand_duration(target: Combatant) -> float:
	if target.snapshot.unit_kind not in [CombatUnitSnapshot.UnitKind.HERO, CombatUnitSnapshot.UnitKind.SOLDIER]:
		return 0.0
	var duration := 0.0
	for candidate in combatants:
		if candidate.state != Combatant.State.DEAD and candidate.snapshot.team == target.snapshot.team:
			duration = maxf(duration, candidate.last_stand_aura_duration)
	return duration


func get_enemy_attack_speed_aura_multiplier(target: Combatant) -> float:
	var multiplier := 1.0
	if not any_attack_speed_aura:
		return multiplier
	for candidate in combatants:
		if (
			candidate.is_alive()
			and candidate.snapshot.team != target.snapshot.team
			and candidate.enemy_attack_speed_aura_radius > 0.0
			and candidate.position.distance_to(target.position) <= candidate.enemy_attack_speed_aura_radius
		):
			# Auras do not stack: only the strongest slowing aura applies.
			multiplier = minf(multiplier, candidate.enemy_attack_speed_aura_multiplier)
	return multiplier


func get_gluttony_lifesteal_aura(target: Combatant) -> Dictionary:
	var result := {"percent": 0.0, "ability_id": &"", "effect_id": &""}
	for candidate in combatants:
		if (
			candidate.is_alive()
			and candidate.snapshot.team == target.snapshot.team
			and candidate.gluttony_lifesteal_aura_radius > 0.0
			and candidate.position.distance_to(target.position) <= candidate.gluttony_lifesteal_aura_radius
			and candidate.gluttony_lifesteal_percent > float(result.percent)
		):
			result.percent = candidate.gluttony_lifesteal_percent
			result.ability_id = candidate.gluttony_lifesteal_ability_id
			result.effect_id = candidate.gluttony_lifesteal_effect_id
	return result


func get_basic_attack_damage(source: Combatant, raw_damage: float) -> float:
	var strongest_percent := 0.0
	var chance_percent := 0.0
	for candidate in combatants:
		if (
			candidate.is_alive()
			and candidate.snapshot.team == source.snapshot.team
			and candidate.despair_team_proc_total_damage_percent > strongest_percent
		):
			strongest_percent = candidate.despair_team_proc_total_damage_percent
			chance_percent = candidate.despair_team_proc_chance_percent
	if strongest_percent <= 0.0 or combat_rng.randf() >= chance_percent / 100.0:
		return raw_damage
	return raw_damage * strongest_percent / 100.0


func has_despair_sanctuary_target(source: Combatant, health_threshold: float) -> bool:
	return is_instance_valid(_despair_sanctuary_target(source, health_threshold))


func apply_despair_sanctuary(
	source: Combatant,
	health_threshold: float,
	heal_percent: float,
	duration: float,
	interval: float,
	ability_id: StringName,
	effect_id: StringName
) -> Combatant:
	var ally := _despair_sanctuary_target(source, health_threshold)
	if is_instance_valid(ally):
		ally.apply_despair_sanctuary(source, heal_percent, duration, interval, ability_id, effect_id)
	return ally


func _despair_sanctuary_target(source: Combatant, health_threshold: float) -> Combatant:
	var lowest: Combatant
	var lowest_ratio := INF
	for candidate in combatants:
		if candidate == source or candidate.snapshot.team != source.snapshot.team or not candidate.is_targetable() or candidate.despair_sanctuary_remaining > 0.0:
			continue
		var ratio := candidate.current_hp / maxf(candidate.get_effective_stat(&"max_hp"), 1.0)
		if ratio >= health_threshold:
			continue
		if ratio < lowest_ratio - 0.0001 or (is_equal_approx(ratio, lowest_ratio) and _runtime_id_before(candidate, lowest)):
			lowest = candidate
			lowest_ratio = ratio
	return lowest


func has_despair_pressure_target(source: Combatant) -> bool:
	return is_instance_valid(_most_targeted_ally(source))


func apply_despair_pressure_shield(
	source: Combatant,
	shield_amount: float,
	attack_speed_multiplier: float,
	duration: float,
	ability_id: StringName,
	effect_id: StringName
) -> Combatant:
	var ally := _most_targeted_ally(source)
	if not is_instance_valid(ally):
		return null
	ally.shields = ally.shields.filter(func(shield: Dictionary) -> bool: return StringName(shield.get("effect_id", &"")) != effect_id)
	ally.temporary_modifiers = ally.temporary_modifiers.filter(func(entry: Dictionary) -> bool: return StringName(entry.get("effect_id", &"")) != effect_id)
	ally.add_shield(shield_amount, duration, source, ability_id, effect_id)
	var slow := StatModifier.new()
	slow.stat = &"attack_speed"
	slow.operation = StatModifier.Operation.MULTIPLY
	slow.value = attack_speed_multiplier
	ally.add_temporary_modifier(slow, duration, source, ability_id, effect_id)
	return ally


func _most_targeted_ally(source: Combatant, ability: AbilityDefinition = null) -> Combatant:
	var selected: Combatant
	var most_attackers := 0
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team or not candidate.is_targetable() or (ability != null and not _is_within_ability_search_radius(source, candidate, ability)):
			continue
		var attackers := 0
		for enemy in combatants:
			if enemy.snapshot.team != source.snapshot.team and enemy.is_alive() and enemy.target == candidate:
				attackers += 1
		if attackers > most_attackers or (attackers == most_attackers and attackers > 0 and _runtime_id_before(candidate, selected)):
			selected = candidate
			most_attackers = attackers
	return selected


func apply_despair_vines(
	source: Combatant,
	target_count: int,
	damage: float,
	duration: float,
	interval: float,
	ability_id: StringName,
	effect_id: StringName
) -> Array[Combatant]:
	var candidates: Array[Combatant] = []
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team and candidate.can_be_targeted_by(source):
			candidates.append(candidate)
	candidates.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	var selected: Array[Combatant] = []
	for _target_index in mini(target_count, candidates.size()):
		var target: Combatant = candidates.pop_at(combat_rng.randi_range(0, candidates.size() - 1))
		var vines := StatusDefinition.new()
		vines.id = effect_id
		vines.display_name = "Grasping Vines"
		vines.description = "Rooted and takes %.1f armored damage every %.1f seconds." % [damage, interval]
		vines.default_duration = duration
		vines.max_stacks = 1
		vines.stack_policy = StatusDefinition.StackPolicy.REFRESH_DURATION
		vines.periodic_interval = interval
		vines.prevents_movement = true
		vines.polarity = StatusDefinition.Polarity.NEGATIVE
		var tick := DamageEffect.new()
		tick.effect_id = effect_id
		tick.amount = damage
		vines.periodic_effects.append(tick)
		target.apply_status(vines, source, ability_id)
		selected.append(target)
	return selected


func get_lust_target_attack_speed_multiplier(attacker: Combatant) -> float:
	if not attacker.basic_attack_target_active or not is_instance_valid(attacker.target):
		return 1.0
	var lust := attacker.target
	if lust.snapshot.team == attacker.snapshot.team or lust.lust_target_slow_percent <= 0.0 or not lust.is_alive():
		return 1.0
	return 1.0 - clampf(lust.lust_target_slow_percent, 0.0, 99.0) / 100.0


func can_apply_lust_guard(source: Combatant, enemy_radius: float, ally_radius: float) -> bool:
	return has_enemy_in_radius(source, enemy_radius) and is_instance_valid(_lust_guard_ally(source, ally_radius))


func apply_lust_guard(
	source: Combatant,
	enemy_radius: float,
	ally_radius: float,
	armor_bonus: float,
	duration: float,
	ability_id: StringName,
	effect_id: StringName
) -> Combatant:
	if not has_enemy_in_radius(source, enemy_radius):
		return null
	var ally := _lust_guard_ally(source, ally_radius)
	if not is_instance_valid(ally):
		return null
	var armor := StatModifier.new()
	armor.stat = "armor"
	armor.operation = StatModifier.Operation.ADD
	armor.value = armor_bonus
	ally.add_temporary_modifier(armor, duration, source, ability_id, effect_id)
	ally.add_runtime_status("Center of Attention", "Armor +%.0f; all living enemies are taunted." % armor_bonus, "BUFF", duration, ability_id)
	active_global_taunts.append({"source_team": source.snapshot.team, "target": ally, "remaining": duration, "ability_id": ability_id})
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team and candidate.is_targetable():
			candidate.set_forced_basic_target(ally, duration, ability_id)
	return ally


func _update_global_taunts(delta: float) -> void:
	for index in range(active_global_taunts.size() - 1, -1, -1):
		var entry: Dictionary = active_global_taunts[index]
		entry.remaining = float(entry.remaining) - delta
		if float(entry.remaining) <= 0.0 or not is_instance_valid(entry.target) or not entry.target.is_targetable():
			active_global_taunts.remove_at(index)


func _lust_guard_ally(source: Combatant, radius: float) -> Combatant:
	var best: Combatant
	var best_hp := -1.0
	for candidate in combatants:
		if candidate == source or candidate.snapshot.team != source.snapshot.team or not candidate.is_targetable() or candidate.position.distance_to(source.position) > radius:
			continue
		var max_hp := candidate.get_effective_stat(&"max_hp")
		if max_hp > best_hp + 0.0001 or (is_equal_approx(max_hp, best_hp) and _runtime_id_before(candidate, best)):
			best = candidate
			best_hp = max_hp
	return best


func get_lust_allied_death_count(source: Combatant) -> int:
	var count := 0
	for candidate in combatants:
		if candidate != source and candidate.state == Combatant.State.DEAD and candidate.snapshot.team == source.snapshot.team:
			count += 1
	return count


func has_lust_recruit_target(source: Combatant, radius: float, hp_threshold: float) -> bool:
	return is_instance_valid(_lust_recruit_target(source, radius, hp_threshold))


func recruit_lust_target(source: Combatant, radius: float, hp_threshold: float, ability_id: StringName, _effect_id: StringName) -> Combatant:
	var recruited := _lust_recruit_target(source, radius, hp_threshold)
	if not is_instance_valid(recruited):
		return null
	var effective_stats := {}
	for stat in [&"max_hp", &"damage", &"attack_speed", &"movement_speed", &"attack_range", &"armor"]:
		effective_stats[stat] = recruited.get_effective_stat(stat)
	for stat in effective_stats:
		recruited.snapshot.stats.set(stat, effective_stats[stat])
	recruited.snapshot.team = source.snapshot.team
	recruited.statuses.clear()
	recruited.temporary_modifiers.clear()
	recruited.basic_attack_empowerments.clear()
	recruited.shields.clear()
	recruited.clear_combat_action()
	recruited.add_runtime_status("Recruited", "Switched to Lust's team until battle end.", "BUFF", 0.0, ability_id)
	if statistics.unit_stats.has(recruited.snapshot.runtime_id):
		statistics.unit_stats[recruited.snapshot.runtime_id].team = source.snapshot.team
	for candidate in combatants:
		if candidate != recruited and candidate.target == recruited:
			candidate.clear_combat_action()
	recruited.queue_redraw()
	return recruited


func _lust_recruit_target(source: Combatant, radius: float, hp_threshold: float) -> Combatant:
	var nearest: Combatant
	var nearest_distance := INF
	for candidate in combatants:
		if candidate.snapshot.team == source.snapshot.team or not candidate.can_be_targeted_by(source) or candidate.snapshot.is_boss:
			continue
		if candidate.current_hp >= hp_threshold:
			continue
		var distance := source.position.distance_to(candidate.position)
		if distance > radius:
			continue
		if distance < nearest_distance - 0.01 or (is_equal_approx(distance, nearest_distance) and _runtime_id_before(candidate, nearest)):
			nearest = candidate
			nearest_distance = distance
	return nearest


func _initialize_lust_bonds() -> void:
	for source in combatants:
		if not source.lust_bond_pending or not source.is_alive():
			continue
		var strongest: Combatant
		var strongest_damage := -1.0
		for candidate in combatants:
			if candidate == source or candidate.snapshot.team != source.snapshot.team or not candidate.is_alive():
				continue
			var damage := candidate.get_effective_stat(&"damage")
			if damage > strongest_damage + 0.0001 or (is_equal_approx(damage, strongest_damage) and _runtime_id_before(candidate, strongest)):
				strongest = candidate
				strongest_damage = damage
		if is_instance_valid(strongest):
			source.establish_lust_bond(strongest)


func apply_lust_basic_knockback(
	source: Combatant,
	target: Combatant,
	distance: float,
	stun_duration: float,
	ability_id: StringName,
	_effect_id: StringName
) -> void:
	if not is_instance_valid(target) or not target.is_targetable():
		return
	var direction := (target.position - source.position).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT if target.snapshot.runtime_id > source.snapshot.runtime_id else Vector2.LEFT
	target.position += direction * distance
	_clamp_combatant_to_arena(target)
	var stun_template := get_node("/root/ContentRegistry").get_definition(&"status.stun") as StatusDefinition
	if stun_template != null and stun_duration > 0.0:
		var stun := stun_template.duplicate() as StatusDefinition
		stun.default_duration = stun_duration
		target.apply_status(stun, source, ability_id)


func has_sacrifice_target(source: Combatant, radius: float) -> bool:
	return not _sacrifice_targets(source, radius).is_empty()


func sacrifice_random_soldier(
	source: Combatant,
	radius: float,
	stat_gain_percent: float,
	ability_id: StringName,
	effect_id: StringName
) -> Combatant:
	var candidates := _sacrifice_targets(source, radius)
	if candidates.is_empty():
		return null
	var victim: Combatant = candidates[combat_rng.randi_range(0, candidates.size() - 1)]
	var multiplier := maxf(stat_gain_percent, 0.0) / 100.0
	var gained_stats := {
		"max_hp": victim.snapshot.stats.max_hp * multiplier,
		"damage": victim.snapshot.stats.damage * multiplier,
		"armor": victim.snapshot.stats.armor * multiplier,
	}
	source.snapshot.stats.max_hp += float(gained_stats.max_hp)
	source.snapshot.stats.damage += float(gained_stats.damage)
	source.snapshot.stats.armor += float(gained_stats.armor)
	statistics.record_permanent_stat_gain(source.snapshot.runtime_id, victim.snapshot.runtime_id, ability_id, gained_stats)
	victim.force_die(source, effect_id)
	return victim


func _sacrifice_targets(source: Combatant, radius: float) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for candidate in combatants:
		if (
			candidate.is_targetable()
			and candidate.snapshot.team == source.snapshot.team
			and candidate.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SOLDIER
			and candidate.position.distance_to(source.position) <= radius
		):
			result.append(candidate)
	result.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	return result


func has_enemy_target(source: Combatant) -> bool:
	return is_instance_valid(_farthest_enemy(source))


func teleport_to_farthest_enemy(source: Combatant) -> void:
	var enemy := _farthest_enemy(source)
	if not is_instance_valid(enemy):
		return
	var direction := (source.position - enemy.position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT if source.snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
	var distance := source.body_radius + enemy.body_radius + minf(source.get_effective_stat(&"attack_range"), 24.0)
	source.position = enemy.position + direction * distance
	var bounds := get_arena_bounds()
	source.position.x = clampf(source.position.x, bounds.position.x + source.body_radius, bounds.end.x - source.body_radius)
	source.position.y = clampf(source.position.y, bounds.position.y + source.body_radius, bounds.end.y - source.body_radius)
	source.target = enemy


func _farthest_enemy(source: Combatant) -> Combatant:
	var farthest: Combatant
	var farthest_distance := -1.0
	for candidate in combatants:
		if candidate.snapshot.team == source.snapshot.team or not candidate.can_be_targeted_by(source):
			continue
		var distance := source.position.distance_squared_to(candidate.position)
		if distance > farthest_distance + 0.01 or (is_equal_approx(distance, farthest_distance) and _runtime_id_before(candidate, farthest)):
			farthest = candidate
			farthest_distance = distance
	return farthest


func has_enemy_in_radius(source: Combatant, radius: float) -> bool:
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team and candidate.is_targetable() and candidate.position.distance_to(source.position) <= radius:
			return true
	return false


func damage_enemies_in_radius(source: Combatant, radius: float, damage: float, ability_id: StringName, effect_id: StringName, allow_source_lifesteal := true) -> void:
	spawn_area_vfx(source.position, radius, _ability_vfx_color(ability_id))
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team and candidate.is_targetable() and candidate.position.distance_to(source.position) <= radius:
			candidate.take_damage(damage, source, ability_id, effect_id, false, allow_source_lifesteal)


func get_strongest_non_hero_ally_damage(source: Combatant) -> float:
	var strongest: Combatant
	var strongest_damage := 0.0
	for candidate in combatants:
		if candidate == source or not candidate.is_alive() or candidate.snapshot.team != source.snapshot.team:
			continue
		if candidate.snapshot.unit_kind not in [CombatUnitSnapshot.UnitKind.SOLDIER, CombatUnitSnapshot.UnitKind.SUMMON]:
			continue
		var damage := candidate.get_effective_stat(&"damage")
		if damage > strongest_damage + 0.0001 or (is_equal_approx(damage, strongest_damage) and _runtime_id_before(candidate, strongest)):
			strongest = candidate
			strongest_damage = damage
	return strongest_damage


func has_envy_stat_theft_targets(source: Combatant) -> bool:
	return not _envy_theft_enemies(source).is_empty() and not _envy_theft_allies(source).is_empty()


func apply_envy_stat_theft(source: Combatant, steal_percent: float, duration: float, ability_id: StringName, effect_id: StringName) -> void:
	var enemies := _envy_theft_enemies(source)
	var allies := _envy_theft_allies(source)
	if enemies.is_empty() or allies.is_empty():
		return
	var enemy: Combatant = enemies[combat_rng.randi_range(0, enemies.size() - 1)]
	var ally: Combatant = allies[combat_rng.randi_range(0, allies.size() - 1)]
	var ratio := clampf(steal_percent, 0.0, 100.0) / 100.0
	for stat in [&"max_hp", &"damage", &"attack_speed", &"armor"]:
		var amount := enemy.get_effective_stat(stat) * ratio
		var debuff := StatModifier.new()
		debuff.stat = String(stat)
		debuff.operation = StatModifier.Operation.ADD
		debuff.value = -amount
		enemy.add_temporary_modifier(debuff, duration, source, ability_id, effect_id)
		var buff := StatModifier.new()
		buff.stat = String(stat)
		buff.operation = StatModifier.Operation.ADD
		buff.value = amount
		ally.add_temporary_modifier(buff, duration, source, ability_id, effect_id)


func _envy_theft_enemies(source: Combatant) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team and candidate.can_be_targeted_by(source) and not candidate.snapshot.is_boss:
			result.append(candidate)
	result.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	return result


func _envy_theft_allies(source: Combatant) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for candidate in combatants:
		if candidate != source and candidate.snapshot.team == source.snapshot.team and candidate.is_targetable():
			result.append(candidate)
	result.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	return result


func can_create_envy_illusion(source: Combatant, ability_id: StringName, effect_id: StringName, max_active_summons: int) -> bool:
	return is_instance_valid(_strongest_non_boss_enemy(source)) and can_spawn_summon(source, ability_id, effect_id, max_active_summons)


func create_envy_illusion(source: Combatant, stat_percent: float, ability_id: StringName, effect_id: StringName, max_active_summons: int) -> Combatant:
	var original := _strongest_non_boss_enemy(source)
	if not is_instance_valid(original) or not can_spawn_summon(source, ability_id, effect_id, max_active_summons):
		return null
	summon_serial += 1
	var snapshot := original.snapshot.duplicate_snapshot()
	snapshot.runtime_id = "%s-illusion-%04d" % [source.snapshot.runtime_id, summon_serial]
	snapshot.display_name = "%s Illusion" % original.snapshot.display_name
	snapshot.team = source.snapshot.team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
	snapshot.abilities.clear()
	snapshot.is_boss = false
	snapshot.summoner_runtime_id = source.snapshot.runtime_id
	snapshot.summoning_ability_id = ability_id
	snapshot.summoning_effect_id = effect_id
	snapshot.summoner_contribution_percent = 100.0
	var ratio := maxf(stat_percent, 0.0) / 100.0
	for stat in [&"max_hp", &"damage", &"attack_speed", &"attack_range", &"armor"]:
		snapshot.stats.set(stat, original.get_effective_stat(stat) * ratio)
	snapshot.stats.movement_speed = original.get_effective_stat(&"movement_speed")
	var summon := _spawn_combatant(snapshot, _summon_position(source.position, summon_serial, get_arena_bounds()), get_arena_bounds())
	record_event(CombatEvent.UNIT_SUMMONED, source.snapshot.runtime_id, snapshot.runtime_id, ability_id, effect_id, 1.0)
	return summon


func _strongest_non_boss_enemy(source: Combatant) -> Combatant:
	var strongest: Combatant
	var strongest_damage := -1.0
	for candidate in combatants:
		if candidate.snapshot.team == source.snapshot.team or not candidate.can_be_targeted_by(source) or candidate.snapshot.is_boss:
			continue
		var damage := candidate.get_effective_stat(&"damage")
		if damage > strongest_damage + 0.0001 or (is_equal_approx(damage, strongest_damage) and _runtime_id_before(candidate, strongest)):
			strongest = candidate
			strongest_damage = damage
	return strongest


func has_envy_execute_target(source: Combatant, health_threshold: float) -> bool:
	return is_instance_valid(_envy_execute_target(source, health_threshold))


func execute_envy_target(source: Combatant, health_threshold: float, _ability_id: StringName, effect_id: StringName) -> Combatant:
	var victim := _envy_execute_target(source, health_threshold)
	if is_instance_valid(victim):
		victim.force_die(source, effect_id)
	return victim


func _envy_execute_target(source: Combatant, health_threshold: float) -> Combatant:
	var eligible: Array[Combatant] = []
	for candidate in combatants:
		if candidate.snapshot.team == source.snapshot.team or not candidate.can_be_targeted_by(source) or candidate.snapshot.is_boss:
			continue
		if candidate.current_hp / maxf(candidate.get_effective_stat(&"max_hp"), 1.0) <= health_threshold:
			eligible.append(candidate)
	eligible.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		var a_ratio := a.current_hp / maxf(a.get_effective_stat(&"max_hp"), 1.0)
		var b_ratio := b.current_hp / maxf(b.get_effective_stat(&"max_hp"), 1.0)
		return a.snapshot.runtime_id < b.snapshot.runtime_id if is_equal_approx(a_ratio, b_ratio) else a_ratio < b_ratio
	)
	return eligible[0] if not eligible.is_empty() else null


func launch_envy_darts(source: Combatant, damage: float, slow_percent: float, max_targets: int, ability_id: StringName, effect_id: StringName) -> void:
	var candidates: Array[Combatant] = []
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team and candidate.can_be_targeted_by(source):
			candidates.append(candidate)
	candidates.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	for dart_index in mini(max_targets, candidates.size()):
		var selected_index := combat_rng.randi_range(0, candidates.size() - 1)
		var target: Combatant = candidates.pop_at(selected_index)
		var projectile: CombatProjectile = PROJECTILE_SCENE.instantiate()
		$Projectiles.add_child(projectile)
		projectile.setup_envy_dart(source, target, damage, slow_percent, ability_id, effect_id, Color(0.3, 0.95, 0.4))


func trigger_melee_retaliation(
	defender: Combatant,
	attacker: Combatant,
	radius: float,
	damage_multiplier: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	var allies: Array[Combatant] = []
	for candidate in combatants:
		if candidate == defender or candidate.snapshot.team != defender.snapshot.team or not candidate.is_alive():
			continue
		if candidate.position.distance_to(defender.position) <= radius:
			allies.append(candidate)
	allies.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	for ally in allies:
		if not attacker.is_targetable():
			break
		attacker.take_damage(ally.get_effective_stat(&"damage") * damage_multiplier, ally, ability_id, effect_id)


func perform_leap_slam(
	source: Combatant,
	primary_target: Combatant,
	damage: float,
	radius: float,
	knockback_distance: float,
	stun_duration: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	var impact_position := primary_target.position
	var approach_direction := (source.position - impact_position).normalized()
	if approach_direction.is_zero_approx():
		approach_direction = Vector2.LEFT if source.snapshot.team == CombatUnitSnapshot.Team.PLAYER else Vector2.RIGHT
	source.position = impact_position + approach_direction * (source.body_radius + primary_target.body_radius)
	_clamp_combatant_to_arena(source)
	spawn_area_vfx(impact_position, radius, _ability_vfx_color(ability_id))
	primary_target.take_damage(damage, source, ability_id, effect_id, true)
	var stun_template := get_node("/root/ContentRegistry").get_definition(&"status.stun") as StatusDefinition
	for candidate in combatants:
		if candidate == primary_target or candidate.snapshot.team == source.snapshot.team or not candidate.is_targetable():
			continue
		if candidate.position.distance_to(impact_position) > radius:
			continue
		var direction := (candidate.position - impact_position).normalized()
		if direction.is_zero_approx():
			direction = Vector2.RIGHT if candidate.snapshot.runtime_id > primary_target.snapshot.runtime_id else Vector2.LEFT
		candidate.position += direction * knockback_distance
		_clamp_combatant_to_arena(candidate)
		if stun_template != null and stun_duration > 0.0:
			var stun := stun_template.duplicate() as StatusDefinition
			stun.default_duration = stun_duration
			candidate.apply_status(stun, source, ability_id)


func apply_ground_slam(
	source: Combatant,
	impact_position: Vector2,
	damage: float,
	radius: float,
	ability_id: StringName,
	effect_id: StringName
) -> void:
	spawn_area_vfx(impact_position, radius, _ability_vfx_color(ability_id))
	for candidate in combatants:
		if candidate.snapshot.team != source.snapshot.team and candidate.is_targetable() and candidate.position.distance_to(impact_position) <= radius:
			candidate.take_damage(damage, source, ability_id, effect_id, true)


func _clamp_combatant_to_arena(combatant: Combatant) -> void:
	var bounds := get_arena_bounds().grow(-combatant.body_radius)
	combatant.position = Vector2(
		clampf(combatant.position.x, bounds.position.x, bounds.end.x),
		clampf(combatant.position.y, bounds.position.y, bounds.end.y)
	)


func create_smoke_zone(source: Combatant, radius: float, duration: float, dodge_chance: float, ability_id: StringName, effect_id: StringName) -> void:
	smoke_zones.append({
		"position": source.position,
		"team": source.snapshot.team,
		"radius": radius,
		"remaining": duration,
		"dodge_chance": clampf(dodge_chance, 0.0, 1.0),
		"ability_id": ability_id,
		"effect_id": effect_id,
	})
	queue_redraw()


func should_dodge(target: Combatant, is_basic_attack := false) -> bool:
	var dodge_chance := 0.0
	for zone in smoke_zones:
		if int(zone.team) == target.snapshot.team and target.position.distance_to(Vector2(zone.position)) <= float(zone.radius):
			dodge_chance = maxf(dodge_chance, float(zone.dodge_chance))
	if is_basic_attack:
		dodge_chance = maxf(dodge_chance, target.get_gluttony_grease_miss_chance())
		# The Dodge stat stacks with other evasion sources multiplicatively.
		var stat_dodge := target.get_effective_stat(&"dodge") / 100.0
		if stat_dodge > 0.0:
			dodge_chance = 1.0 - (1.0 - dodge_chance) * (1.0 - stat_dodge)
	return dodge_chance > 0.0 and combat_rng.randf() < dodge_chance


func grant_kill_reward(source: Combatant) -> void:
	if source.kill_gold_reward <= 0 and source.kill_permanent_damage <= 0.0:
		return
	statistics.bonus_gold += source.kill_gold_reward
	if source.kill_permanent_damage > 0.0:
		source.snapshot.stats.damage += source.kill_permanent_damage
		statistics.record_permanent_stat_gain(
			source.snapshot.runtime_id,
			source.snapshot.runtime_id,
			source.kill_reward_ability_id,
			{"damage": source.kill_permanent_damage}
		)


func _update_smoke_zones(delta: float) -> void:
	var changed := false
	for index in range(smoke_zones.size() - 1, -1, -1):
		smoke_zones[index].remaining = float(smoke_zones[index].remaining) - delta
		if float(smoke_zones[index].remaining) <= 0.0:
			smoke_zones.remove_at(index)
			changed = true
	if changed:
		queue_redraw()


func get_separation_vector(requester: Combatant) -> Vector2:
	var separation := Vector2.ZERO
	for other in combatants:
		if other == requester:
			continue
		var offset := requester.position - other.position
		var separation_distance := requester.body_radius + other.body_radius
		if other.snapshot.team == requester.snapshot.team:
			separation_distance = requester.personal_space_radius() + other.personal_space_radius()
		# Cheap squared pre-check (with a margin, so the exact test below still decides).
		if offset.length_squared() > separation_distance * separation_distance * 1.0001:
			continue
		if not other.is_alive():
			continue
		var distance := offset.length()
		if distance >= separation_distance:
			continue
		var direction := offset / distance if distance > 0.001 else (Vector2.LEFT if requester.snapshot.runtime_id < other.snapshot.runtime_id else Vector2.RIGHT)
		separation += direction * (separation_distance - distance) / separation_distance
	return separation.limit_length(1.0)


func _resolve_combatant_overlaps(delta: float) -> void:
	var maximum_correction := OVERLAP_RESOLUTION_SPEED * delta
	# Living units only, in the same order as combatants (the pair order matters).
	var living: Array[Combatant] = []
	for combatant in combatants:
		if combatant.is_alive() and not combatant.temporarily_removed:
			living.append(combatant)
	var count := living.size()
	for first_index in count:
		var first := living[first_index]
		for second_index in range(first_index + 1, count):
			var second := living[second_index]
			var offset := second.position - first.position
			var reach := first.body_radius + second.body_radius
			if offset.length_squared() > reach * reach * 1.0001:
				continue
			var distance := offset.length()
			var required_distance := first.body_radius + second.body_radius
			if distance >= required_distance:
				continue
			var direction := offset / distance if distance > 0.001 else (Vector2.RIGHT if first.snapshot.runtime_id < second.snapshot.runtime_id else Vector2.LEFT)
			var correction := direction * minf((required_distance - distance) * 0.5, maximum_correction)
			var first_locked := first.is_attack_motion_locked()
			var second_locked := second.is_attack_motion_locked()
			if first_locked and not second_locked:
				second.position += correction * 2.0
			elif second_locked and not first_locked:
				first.position -= correction * 2.0
			else:
				first.position -= correction
				second.position += correction
	var bounds := get_arena_bounds()
	for combatant in combatants:
		if combatant.is_alive() and not combatant.temporarily_removed:
			combatant.position.x = clampf(combatant.position.x, bounds.position.x + combatant.body_radius, bounds.end.x - combatant.body_radius)
			combatant.position.y = clampf(combatant.position.y, bounds.position.y + combatant.body_radius, bounds.end.y - combatant.body_radius)


func spawn_projectile(source: Combatant, target: Combatant, damage: float) -> void:
	if not battle_active:
		return
	var projectile: CombatProjectile = PROJECTILE_SCENE.instantiate()
	$Projectiles.add_child(projectile)
	projectile.setup(source, target, damage, source.snapshot.placeholder_color.lightened(0.2))


## Melee basic hit: a spark spray turned along the blow. Heroes, bosses and big enemies
## hit with the heavy impact; Heroes in the colour of their sin.
func spawn_hit_vfx(source: Combatant, impact_position: Vector2, direction: Vector2) -> AnimatedSprite2D:
	if not battle_active or not vfx_enabled or not is_instance_valid(source):
		return null
	var is_hero := source.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO
	var heavy := is_hero or source.snapshot.is_boss or source.snapshot.definition_id in VFX.HEAVY_HITTERS
	var effect_id := &"hit_heavy" if heavy else &"hit_slash"
	var scale := 0.82 if source.snapshot.is_boss else (0.6 if heavy else 0.46)
	var tint: Color = VFX.HERO_COLORS.get(source.snapshot.definition_id, Color.WHITE)
	if source.snapshot.team == CombatUnitSnapshot.Team.ENEMY and not heavy:
		tint = Color(1.0, 0.82, 0.74)
	var angle := direction.angle() if not direction.is_zero_approx() else 0.0
	if not heavy and source.snapshot.job_id in VFX.SPEAR_JOBS:
		# Spear thrust: a flurry of sparks off the point, lighting the ground around it.
		var spark_at := impact_position + Vector2(0.0, -16.0)
		VFX.flash_light(light_layer, spark_at, Color(1.0, 0.72, 0.38), 1.1, 0.55, 0.16)
		VFX.spark_lights(light_layer, spark_at, direction, Color(1.0, 0.66, 0.3), 3)
		return VFX.spawn($Effects, &"spear_sparks", spark_at, 0.5, Color.WHITE, angle, VFX.IMPACT_Z, true)
	if heavy:
		VFX.flash_light(light_layer, impact_position, Color(1.0, 0.78, 0.5) * tint, 0.9, 1.3, 0.2)
	return VFX.spawn($Effects, effect_id, impact_position + Vector2(0.0, -16.0), scale, tint, angle, VFX.IMPACT_Z, not heavy)


## Where a shot lands: a burst in the colour of the shot (arrows spark instead).
func spawn_projectile_hit_vfx(projectile_effect: StringName, impact_position: Vector2, direction: Vector2, tint := Color.WHITE) -> void:
	if not vfx_enabled:
		return
	var at := impact_position + Vector2(0.0, -16.0)
	if projectile_effect == &"arrow":
		VFX.spawn($Effects, &"hit_slash", at, 0.4, Color(1.0, 0.92, 0.8), direction.angle(), VFX.IMPACT_Z, true)
		return
	var color: Color = VFX.PROJECTILE_COLORS.get(projectile_effect, Color.WHITE) * tint
	if projectile_effect == &"venom_bolt":
		# A crossbow bolt: a piercing hit plus a splash of poison.
		VFX.spawn($Effects, &"hit_slash", at, 0.48, Color(0.85, 1.0, 0.75), direction.angle(), VFX.IMPACT_Z)
		VFX.spawn($Effects, &"magic_burst", at, 0.42, color, 0.0, VFX.IMPACT_Z, true)
		return
	# Magic shots land with a big burst and a flash of light; Hero spells also shake the ground.
	VFX.spawn($Effects, &"magic_burst", at, 0.72, color, 0.0, VFX.IMPACT_Z)
	VFX.flash_light(light_layer, at, color, 1.8, 2.4, 0.4)
	if projectile_effect in [&"arcane_lance", &"gloom_orb"]:
		VFX.spawn($Effects, &"slam_ring", impact_position, 0.32, color, 0.0, VFX.GROUND_Z + 1, true)


## Area abilities: an isometric shockwave as wide as the ability radius.
func spawn_area_vfx(impact_position: Vector2, radius: float, tint := Color.WHITE) -> void:
	if not vfx_enabled or radius <= 0.0:
		return
	# The rings of the atlas are ~230 px wide at scale 1: dust under the units, light above.
	var scale := clampf(radius * 2.0 / 230.0, 0.35, 2.5)
	VFX.spawn($Effects, &"slam_dust", impact_position, scale, Color.WHITE, 0.0, VFX.GROUND_Z)
	VFX.spawn($Effects, &"slam_ring", impact_position, scale, tint, 0.0, VFX.GROUND_Z + 1)
	VFX.flash_light(light_layer, impact_position, Color(1.0, 0.8, 0.55) * tint, 1.4, 2.0 * scale + 1.0, 0.45)


## Footstep dust, kicked up behind a walking unit (low priority).
func spawn_dust_vfx(combatant: Combatant) -> void:
	if not vfx_enabled:
		return
	var scale := 0.9 if combatant.snapshot.is_boss else (0.62 if combatant.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else 0.5)
	var behind := -signf(combatant.velocity.x) * combatant.body_radius * 0.5
	VFX.spawn($Effects, &"walk_dust", combatant.feet_position() + Vector2(behind, -15.0 * scale), scale, Color.WHITE, 0.0, VFX.GROUND_Z, true)


func spawn_ability_projectile(source: Combatant, target: Combatant, ability: AbilityDefinition) -> void:
	if not battle_active:
		return
	var projectile: CombatProjectile = PROJECTILE_SCENE.instantiate()
	$Projectiles.add_child(projectile)
	projectile.setup_ability(source, target, ability, ability.presentation_color)


func apply_projectile_impact(source: Combatant, target: Combatant, ability: AbilityDefinition, impact_position: Vector2) -> void:
	if ability.area_radius <= 0.0:
		_apply_ability_effects(source, target, ability)
		return
	spawn_area_vfx(impact_position, ability.area_radius, _ability_vfx_color(ability.id))
	for candidate in combatants:
		if (
			candidate.is_targetable()
			and candidate.snapshot.team != source.snapshot.team
			and candidate.position.distance_to(impact_position) <= ability.area_radius
		):
			_apply_ability_effects(source, candidate, ability)


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
	if not is_instance_valid(source):
		return
	var ability := get_ability_definition(ability_id)
	for candidate in combatants:
		if not candidate.items.cast_frenzies.is_empty() and candidate.is_alive() and candidate.snapshot.team != source.snapshot.team:
			candidate.items.on_enemy_ability_used(source, ability)


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


func notify_combatant_died(combatant: Combatant, source: Combatant = null) -> void:
	if combatant.snapshot.unit_kind != CombatUnitSnapshot.UnitKind.SUMMON or combatant.items.lifetime_remaining < 0.0:
		for candidate in combatants:
			if not candidate.items.death_summons.is_empty() and candidate.is_alive() and candidate.snapshot.team != combatant.snapshot.team:
				candidate.items.on_enemy_died_nearby(combatant)
	for owner_id in active_summon_merges.keys():
		var merge: Dictionary = active_summon_merges[owner_id]
		if merge.merged == combatant:
			_finish_summon_merge(String(owner_id), true, source)
			break
	var partner := combatant.lust_bond_partner
	if is_instance_valid(partner) and partner.is_alive():
		var killer := source
		if not is_instance_valid(killer) and not combatant.last_damage_source_id.is_empty():
			killer = get_combatant_by_runtime_id(combatant.last_damage_source_id)
		partner.force_die(killer, combatant.lust_bond_effect_id)
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


## Share of the arena height above the walkable ground: the painted battlefield shows
## ruins and sky there, so units (their body centre, feet about 60 px lower) never go up.
const WALKABLE_TOP_FRACTION := 0.21


func get_arena_bounds() -> Rect2:
	var margin := Vector2(48.0, 48.0)
	var top := maxf(margin.y, size.y * WALKABLE_TOP_FRACTION)
	return Rect2(Vector2(margin.x, top), Vector2(maxf(size.x - margin.x * 2.0, 200.0), maxf(size.y - top - margin.y, 200.0)))


func _ability_vfx_color(ability_id: StringName) -> Color:
	var ability := get_ability_definition(ability_id) if not String(ability_id).is_empty() else null
	return ability.presentation_color.lerp(Color.WHITE, 0.35) if ability != null else Color.WHITE


func get_combatant_by_runtime_id(runtime_id: String) -> Combatant:
	for combatant in combatants:
		if combatant.snapshot.runtime_id == runtime_id:
			return combatant
	return null


func select_combatant_by_runtime_id(runtime_id: String) -> void:
	_select_combatant(get_combatant_by_runtime_id(runtime_id))


## Use the same formation as the preview, including Heroes behind melee Soldiers
## and any positions chosen manually on the Battlefield tab.
func _spawn_team(snapshots: Array[CombatUnitSnapshot], bounds: Rect2, player_team: bool) -> void:
	var positions := FormationService.spawn_positions(snapshots, bounds, player_team)
	for index in snapshots.size():
		_spawn_combatant(snapshots[index], positions[index], bounds, true)


func _spawn_combatant(snapshot: CombatUnitSnapshot, spawn_position: Vector2, bounds: Rect2, initial_battle_spawn := false) -> Combatant:
	var combatant: Combatant = COMBATANT_SCENE.instantiate()
	$Units.add_child(combatant)
	combatant.position = spawn_position
	statistics.register_unit(snapshot)
	var walk_delay_frames := _initial_walk_delay_frames(snapshot.runtime_id) if initial_battle_spawn else 0
	combatant.setup(snapshot, self, bounds, walk_delay_frames)
	combatants.append(combatant)
	for taunt in active_global_taunts:
		if snapshot.team != int(taunt.source_team) and is_instance_valid(taunt.target) and taunt.target.is_targetable():
			combatant.set_forced_basic_target(taunt.target, float(taunt.remaining), StringName(taunt.ability_id))
	return combatant


func _initial_walk_delay_frames(runtime_id: String) -> int:
	var delay_hash := ("%d:%s" % [combat_seed, runtime_id]).hash()
	return 1 + (delay_hash & 0x7fffffff) % 9


func can_spawn_summon(
	source: Combatant,
	ability_id: StringName,
	effect_id: StringName,
	max_active_summons: int
) -> bool:
	if not battle_active or not is_instance_valid(source) or not source.is_alive() or max_active_summons < 1 or active_summon_merges.has(source.snapshot.runtime_id):
		return false
	var active_count := 0
	for combatant in combatants:
		if (
			combatant.is_alive()
			and combatant.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON
			and combatant.snapshot.summoner_runtime_id == source.snapshot.runtime_id
			and combatant.snapshot.summoning_ability_id == ability_id
			and combatant.snapshot.summoning_effect_id == effect_id
		):
			active_count += 1
	return active_count < max_active_summons


func spawn_summon(
	source: Combatant,
	definition: EnemyDefinition,
	ability_id: StringName,
	effect_id: StringName,
	max_active_summons: int,
	summoner_contribution_percent: float,
	at_position := Vector2.INF
) -> Combatant:
	if definition == null or not can_spawn_summon(source, ability_id, effect_id, max_active_summons):
		return null
	summon_serial += 1
	var runtime_id := "%s-summon-%04d" % [source.snapshot.runtime_id, summon_serial]
	var snapshot := CombatSnapshotBuilder.build_enemy(
		definition,
		runtime_id,
		definition.display_name,
		get_node("/root/ContentRegistry")
	)
	if snapshot == null:
		return null
	snapshot.team = source.snapshot.team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
	snapshot.veterancy_level = source.snapshot.veterancy_level
	snapshot.summoner_runtime_id = source.snapshot.runtime_id
	snapshot.summoning_ability_id = ability_id
	snapshot.summoning_effect_id = effect_id
	snapshot.summoner_contribution_percent = clampf(summoner_contribution_percent, 0.0, 100.0)
	CombatSnapshotBuilder.apply_veterancy_growth(snapshot.stats, snapshot.veterancy_level, get_node("/root/ContentRegistry"))
	var bounds := get_arena_bounds()
	var spawn_position := _summon_position(source.position if at_position == Vector2.INF else at_position, summon_serial, bounds)
	var summon := _spawn_combatant(snapshot, spawn_position, bounds)
	record_event(CombatEvent.UNIT_SUMMONED, source.snapshot.runtime_id, runtime_id, ability_id, effect_id, 1.0)
	return summon


func can_merge_owned_summons(source: Combatant, minimum_summons: int) -> bool:
	return (
		battle_active
		and is_instance_valid(source)
		and source.is_alive()
		and not active_summon_merges.has(source.snapshot.runtime_id)
		and _owned_living_summons(source.snapshot.runtime_id).size() >= minimum_summons
	)


func merge_owned_summons(
	source: Combatant,
	definition: EnemyDefinition,
	stat_multiplier: float,
	attack_speed_bonus_per_summon: float,
	duration: float,
	minimum_summons: int,
	summoner_contribution_percent: float,
	ability_id: StringName,
	effect_id: StringName
) -> Combatant:
	if definition == null or not can_merge_owned_summons(source, minimum_summons):
		return null
	var components := _owned_living_summons(source.snapshot.runtime_id)
	var center := Vector2.ZERO
	var total_max_hp := 0.0
	var total_current_hp := 0.0
	var total_damage := 0.0
	var total_armor := 0.0
	for component in components:
		center += component.position
		total_max_hp += component.get_effective_stat(&"max_hp")
		total_current_hp += component.current_hp
		total_damage += component.get_effective_stat(&"damage")
		total_armor += component.get_effective_stat(&"armor")
	center /= components.size()
	var reference: Combatant = components[0]
	var multiplier := maxf(stat_multiplier, 0.0)
	summon_serial += 1
	var snapshot := CombatSnapshotBuilder.build_enemy(
		definition,
		"%s-merged-%04d" % [source.snapshot.runtime_id, summon_serial],
		definition.display_name,
		get_node("/root/ContentRegistry")
	)
	if snapshot == null:
		return null
	snapshot.team = source.snapshot.team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
	snapshot.veterancy_level = source.snapshot.veterancy_level
	snapshot.attack_type = reference.snapshot.attack_type
	snapshot.summoner_runtime_id = source.snapshot.runtime_id
	snapshot.summoning_ability_id = ability_id
	snapshot.summoning_effect_id = effect_id
	snapshot.summoner_contribution_percent = clampf(summoner_contribution_percent, 0.0, 100.0)
	snapshot.stats.max_hp = total_max_hp * multiplier
	snapshot.stats.damage = total_damage * multiplier
	snapshot.stats.armor = total_armor * multiplier
	snapshot.stats.attack_speed = reference.snapshot.stats.attack_speed * (1.0 + attack_speed_bonus_per_summon * components.size())
	snapshot.stats.attack_range = reference.snapshot.stats.attack_range
	snapshot.stats.movement_speed = reference.snapshot.stats.movement_speed
	for component in components:
		component.set_temporarily_removed(true)
	var merged := _spawn_combatant(snapshot, center, get_arena_bounds())
	merged.current_hp = minf(total_current_hp * multiplier, merged.get_effective_stat(&"max_hp"))
	active_summon_merges[source.snapshot.runtime_id] = {
		"merged": merged,
		"components": components,
		"remaining": duration,
		"effect_id": effect_id,
	}
	record_event(CombatEvent.UNIT_SUMMONED, source.snapshot.runtime_id, snapshot.runtime_id, ability_id, effect_id, components.size())
	return merged


func _owned_living_summons(owner_runtime_id: String) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for combatant in combatants:
		if combatant.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SUMMON and combatant.snapshot.summoner_runtime_id == owner_runtime_id and combatant.is_alive():
			result.append(combatant)
	result.sort_custom(func(a: Combatant, b: Combatant) -> bool: return a.snapshot.runtime_id < b.snapshot.runtime_id)
	return result


func _update_summon_merges(delta: float) -> void:
	for owner_id in active_summon_merges.keys():
		var merge: Dictionary = active_summon_merges[owner_id]
		merge.remaining = float(merge.remaining) - delta
		active_summon_merges[owner_id] = merge
		if float(merge.remaining) <= 0.0:
			_finish_summon_merge(String(owner_id), false)


func _finish_summon_merge(owner_runtime_id: String, merged_died: bool, killer: Combatant = null) -> void:
	if not active_summon_merges.has(owner_runtime_id):
		return
	var merge: Dictionary = active_summon_merges[owner_runtime_id]
	active_summon_merges.erase(owner_runtime_id)
	var merged: Combatant = merge.merged
	var components: Array = merge.components
	var split_position := merged.position if is_instance_valid(merged) else Vector2.ZERO
	var health_ratio := 0.0
	if is_instance_valid(merged) and not merged_died:
		health_ratio = clampf(merged.current_hp / maxf(merged.get_effective_stat(&"max_hp"), 1.0), 0.0, 1.0)
	for index in components.size():
		var component := components[index] as Combatant
		if not is_instance_valid(component):
			continue
		component.set_temporarily_removed(false)
		component.position = _summon_position(split_position, index + 1, get_arena_bounds())
		if merged_died:
			component.force_die(killer, StringName(merge.effect_id))
		else:
			component.current_hp = component.get_effective_stat(&"max_hp") * health_ratio
			component.queue_redraw()
	if is_instance_valid(merged) and not merged_died:
		merged.set_temporarily_removed(true)
		combatants.erase(merged)
		if selected_combatant == merged:
			_select_combatant(null)
		merged.queue_free()


func _summon_position(source_position: Vector2, serial: int, bounds: Rect2) -> Vector2:
	var angle := TAU * float((serial - 1) % 8) / 8.0
	var desired := source_position + Vector2.from_angle(angle) * SUMMON_SPAWN_DISTANCE
	var inset_bounds := bounds.grow(-Combatant.UNIT_RADIUS)
	return Vector2(
		clampf(desired.x, inset_bounds.position.x, inset_bounds.end.x),
		clampf(desired.y, inset_bounds.position.y, inset_bounds.end.y)
	)


func _spawn_reinforcements(bounds: Rect2) -> void:
	for index in reinforcement_snapshots.size():
		_spawn_combatant(reinforcement_snapshots[index], _reinforcement_position(index, reinforcement_snapshots.size(), bounds), bounds)
	record_event(CombatEvent.REINFORCEMENTS_SPAWNED, "", "", &"", &"", reinforcement_snapshots.size())


func _reinforcement_position(index: int, count: int, bounds: Rect2) -> Vector2:
	if reinforcement_entry_direction == EncounterDefinition.ReinforcementEntryDirection.RIGHT_SIDE:
		var ratio := float(index + 1) / float(count + 1)
		return Vector2(bounds.end.x - REINFORCEMENT_EDGE_INSET, lerpf(bounds.position.y, bounds.end.y, ratio))
	var side := index % 4
	var side_slot := index / 4
	var side_count := ceili(float(count - side) / 4.0)
	var ratio := float(side_slot + 1) / float(side_count + 1)
	match side:
		0:
			return Vector2(bounds.end.x - REINFORCEMENT_EDGE_INSET, lerpf(bounds.position.y, bounds.end.y, ratio))
		1:
			return Vector2(lerpf(bounds.position.x, bounds.end.x, ratio), bounds.end.y - REINFORCEMENT_EDGE_INSET)
		2:
			return Vector2(bounds.position.x + REINFORCEMENT_EDGE_INSET, lerpf(bounds.position.y, bounds.end.y, ratio))
		_:
			return Vector2(lerpf(bounds.position.x, bounds.end.x, ratio), bounds.position.y + REINFORCEMENT_EDGE_INSET)


func _check_battle_end() -> void:
	if not battle_active:
		return
	var player_alive := false
	var enemy_alive_count := 0
	for combatant in combatants:
		if not combatant.is_alive():
			continue
		if combatant.items.home_team() == CombatUnitSnapshot.Team.PLAYER:
			player_alive = true
		else:
			enemy_alive_count += 1

	if (
		player_alive
		and not reinforcements_spawned
		and not reinforcement_snapshots.is_empty()
		and enemy_alive_count <= reinforcement_alive_threshold
	):
		reinforcements_spawned = true
		_spawn_reinforcements(get_arena_bounds())
		return
	if player_alive and enemy_alive_count > 0:
		return
	var winner: StringName = &"player" if player_alive else &"enemy"
	_finish_battle(winner, false)


func _finish_battle(winner: StringName, timed_out: bool) -> void:
	if not battle_active:
		return
	# Zero-HP last-stand units cannot escape their delayed death when combat stops.
	for combatant in combatants:
		if combatant.is_alive() and combatant.current_hp <= 0.0:
			combatant.force_die(null, combatant.last_effect_id)
	battle_active = false
	last_winner = winner
	last_battle_timed_out = timed_out
	if winner == &"player":
		for combatant in combatants:
			if combatant.items.home_team() == CombatUnitSnapshot.Team.PLAYER:
				statistics.bonus_gold += combatant.items.total_post_battle_gold()
	for combatant in combatants:
		combatant.set_simulation_active(false)
	for projectile in $Projectiles.get_children():
		projectile.queue_free()
	for effect in $Effects.get_children():
		effect.queue_free()
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
	smoke_zones.clear()
	active_global_taunts.clear()
	active_summon_merges.clear()
	selected_combatant = null
	combatants.clear()
	if vfx_director != null:
		vfx_director.clear()
	if light_layer != null:
		for light in light_layer.get_children():
			light.free()
	for unit in $Units.get_children():
		unit.free()
	for projectile in $Projectiles.get_children():
		projectile.free()
	for effect in $Effects.get_children():
		effect.free()


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
	# With the animated backdrop the video (drawn behind this node) is the ground.
	if backdrop == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.125, 0.11, 0.09))
		_draw_battleground(Rect2(Vector2.ZERO, size))
	var bounds := get_arena_bounds()
	draw_rect(bounds, Color(0.12, 0.08, 0.04, 0.08), true)
	draw_rect(bounds, Color(0.37, 0.31, 0.22), false, 2.0)
	for zone in smoke_zones:
		draw_circle(Vector2(zone.position), float(zone.radius), Color(0.28, 0.3, 0.34, 0.24))
		draw_arc(Vector2(zone.position), float(zone.radius), 0.0, TAU, 64, Color(0.62, 0.66, 0.72, 0.45), 2.0)
	draw_dashed_line(
		Vector2(bounds.get_center().x, bounds.position.y),
		Vector2(bounds.get_center().x, bounds.end.y),
		Color(0.55, 0.48, 0.36, 0.45),
		2.0,
		16.0
	)


func _draw_battleground(target_rect: Rect2) -> void:
	var texture_size := BATTLEGROUND.get_size()
	if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0 or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var source_rect := Rect2(Vector2.ZERO, texture_size)
	var target_aspect := target_rect.size.x / target_rect.size.y
	var texture_aspect := texture_size.x / texture_size.y
	if texture_aspect > target_aspect:
		source_rect.size.x = texture_size.y * target_aspect
		source_rect.position.x = (texture_size.x - source_rect.size.x) * 0.5
	else:
		source_rect.size.y = texture_size.x / target_aspect
		source_rect.position.y = (texture_size.y - source_rect.size.y) * 0.5
	draw_texture_rect_region(BATTLEGROUND, target_rect, source_rect)


# --- animated battlefield ---------------------------------------------------------

func _setup_scenery() -> void:
	if not vfx_enabled or backdrop != null:
		return
	var video := load(BACKDROP_VIDEO_PATH) as VideoStream if ResourceLoader.exists(BACKDROP_VIDEO_PATH) else null
	if video != null:
		backdrop = VideoStreamPlayer.new()
		backdrop.name = "Backdrop"
		backdrop.stream = video
		backdrop.expand = true
		backdrop.volume_db = -80.0
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Drawn behind this node's own drawing (arena frame, smoke zones).
		backdrop.show_behind_parent = true
		if "loop" in backdrop:
			backdrop.set("loop", true)
		backdrop.finished.connect(backdrop.play)
		add_child(backdrop)
		move_child(backdrop, 0)
		backdrop.play()
	var front := load(FOREGROUND_PATH) as Texture2D if ResourceLoader.exists(FOREGROUND_PATH) else null
	if front != null:
		foreground = TextureRect.new()
		foreground.name = "Foreground"
		foreground.texture = front
		foreground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		foreground.stretch_mode = TextureRect.STRETCH_SCALE
		foreground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foreground.z_index = FOREGROUND_Z
		foreground.modulate = FOREGROUND_TINT
		add_child(foreground)
	vignette = TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = VFX.get_vignette_texture()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.z_index = VIGNETTE_Z
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	vignette.material = unshaded
	add_child(vignette)
	_layout_scenery()
	queue_redraw()


## Both layers cover the arena (cropping like the old battleground) with a little
## overscan, shifted by the current parallax offset.
func _layout_scenery() -> void:
	if backdrop != null:
		var video_texture := backdrop.get_video_texture()
		var video_size := Vector2(video_texture.get_size()) if video_texture != null and video_texture.get_width() > 0 else Vector2(1888.0, 1072.0)
		# The backdrop drifts the other way and less: it is far away.
		var back_offset := -parallax_offset / FOREGROUND_PARALLAX * BACKDROP_PARALLAX
		_cover(backdrop, video_size, back_offset)
	if foreground != null:
		_cover(foreground, foreground.texture.get_size(), parallax_offset)
	if vignette != null:
		vignette.position = Vector2.ZERO
		vignette.size = size


func _cover(layer: Control, content_size: Vector2, offset: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or content_size.x <= 0.0 or content_size.y <= 0.0:
		return
	var scale := maxf(size.x / content_size.x, size.y / content_size.y) * PARALLAX_OVERSCAN
	var drawn := content_size * scale
	layer.size = drawn
	layer.position = (size - drawn) * 0.5 + offset


## Mouse position over the arena, -1..1 on both axes, eases the layers toward it.
func _update_parallax(delta: float) -> void:
	if foreground == null and backdrop == null:
		return
	var target := Vector2.ZERO
	if size.x > 0.0 and size.y > 0.0:
		var mouse := get_local_mouse_position() / size * 2.0 - Vector2.ONE
		mouse = mouse.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
		target = -mouse * FOREGROUND_PARALLAX
	parallax_offset = parallax_offset.lerp(target, clampf(delta * PARALLAX_SMOOTHING, 0.0, 1.0))
	_layout_scenery()
