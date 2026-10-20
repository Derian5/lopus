class_name CombatantItemRuntime
extends RefCounted


## Runtime state for Hero item mechanics (and any other unit given the same effects).
## Item AbilityEffects register their configuration here when the battle starts; the
## owning Combatant calls the hooks below from its damage, hit, kill and tick paths.

var owner  # Combatant

# Regeneration (hp_regen stat + temporary bonuses), ticked once per second.
var regen_tick_remaining := 1.0

# On-hit: stack a marker status per target, trigger a status at N stacks.
var stack_triggers: Array[Dictionary] = []
# On-hit: every Nth successful basic attack applies a status.
var nth_hit_statuses: Array[Dictionary] = []
# On-hit: execute non-boss enemies under a health ratio.
var execute_threshold := 0.0
var execute_gold := 0
var execute_gold_cap := 0
var execute_gold_earned := 0
var execute_ability_id: StringName
var execute_effect_id: StringName

# Low-health shield (once per battle).
var low_hp_shields: Array[Dictionary] = []

# Damage redirection from nearby allies.
var redirect_radius := 0.0
var redirect_percent := 0.0
var redirect_heal_percent := 0.0
var redirect_ability_id: StringName
var redirect_effect_id: StringName

# Every N damage taken -> nova (damage, status, self-heal).
var damage_novas: Array[Dictionary] = []

# Pulse heal of the nearest wounded allies.
var pulse_heals: Array[Dictionary] = []

# Soldier damage aura.
var soldier_aura_radius := 0.0
var soldier_aura_percent := 0.0
var veteran_aura_percent := 0.0
var veteran_min_level := 1
var soldier_aura_ability_id: StringName

# Skeletons from nearby enemy deaths.
var death_summons: Array[Dictionary] = []

# Isolation (no allies nearby): damage bonus and damage reduction.
var isolation_radius := 0.0
var isolation_damage_percent := 0.0
var isolation_damage_taken_percent := 0.0
var isolation_ability_id: StringName

# Enemy casts nearby -> stacking buff.
var cast_frenzies: Array[Dictionary] = []

# Rage from damage taken.
var rage_points := 0.0
var rage_damage_per_point := 0.0
var rage_points_required := 0.0
var rage_status: StatusDefinition
var rage_ability_id: StringName

# Enemy slow aura (attack and movement speed).
var slow_aura_radius := 0.0
var slow_aura_percent := 0.0
var slow_aura_ability_id: StringName

# Kill growth that persists for the run.
var kill_growth_max_hp := 0.0
var kill_growth_cap := 0.0
var kill_growth_existing := 0.0
var kill_growth_gained := 0.0
var kill_growth_heal_percent := 0.0
var kill_growth_ability_id: StringName

# Flat Gold after a won battle.
var post_battle_gold := 0

# Once-per-battle effects already used, by ability id.
var used_once: Dictionary = {}

# Charm: the unit temporarily fights for the other team.
var charm_remaining := 0.0
var charm_home_team := -1

# Temporary summons expire.
var lifetime_remaining := -1.0


func setup(combatant) -> void:
	owner = combatant


func has_damage_redirect() -> bool:
	return redirect_radius > 0.0 and redirect_percent > 0.0


# --- ticking -----------------------------------------------------------------

func update(delta: float) -> void:
	if lifetime_remaining > 0.0:
		lifetime_remaining -= delta
		if lifetime_remaining <= 0.0:
			owner.force_die(null, &"summon.expired")
			return
	if charm_remaining > 0.0:
		charm_remaining -= delta
		if charm_remaining <= 0.0:
			end_charm()
	if not owner.is_alive():
		return
	regen_tick_remaining -= delta
	while regen_tick_remaining <= 0.000001:
		regen_tick_remaining += 1.0
		var regen := regeneration_per_second()
		if regen > 0.0 and owner.current_hp < owner.get_effective_stat(&"max_hp"):
			owner.receive_healing(regen, owner, &"stat.hp_regen", &"stat.hp_regen")
	for pulse in pulse_heals:
		pulse.remaining = float(pulse.remaining) - delta
		while float(pulse.remaining) <= 0.000001:
			pulse.remaining = float(pulse.remaining) + float(pulse.interval)
			_pulse_heal(pulse)


func regeneration_per_second() -> float:
	var regen: float = owner.get_effective_stat(&"hp_regen")
	for entry in low_hp_shields:
		if bool(entry.active) and _shield_alive(entry):
			regen += float(entry.regen)
	return regen


func _shield_alive(entry: Dictionary) -> bool:
	for shield in owner.shields:
		if StringName(shield.ability_id) == StringName(entry.ability_id) and float(shield.amount) > 0.0:
			return true
	entry.active = false
	return false


func _pulse_heal(pulse: Dictionary) -> void:
	var amount: float = owner.get_effective_stat(&"max_hp") * float(pulse.max_hp_percent) / 100.0
	var wounded: Array = []
	for candidate in owner.session.combatants:
		if candidate.snapshot.team != owner.snapshot.team or not candidate.is_targetable():
			continue
		if candidate.current_hp >= candidate.get_effective_stat(&"max_hp") - 0.01:
			continue
		wounded.append(candidate)
	wounded.sort_custom(func(a, b) -> bool:
		var da: float = a.position.distance_squared_to(owner.position)
		var db: float = b.position.distance_squared_to(owner.position)
		return da < db or (is_equal_approx(da, db) and a.snapshot.runtime_id < b.snapshot.runtime_id)
	)
	for index in mini(int(pulse.targets), wounded.size()):
		wounded[index].receive_healing(amount, owner, StringName(pulse.ability_id), StringName(pulse.effect_id))


# --- basic hits ----------------------------------------------------------------

func on_basic_hit(target, damage_dealt: float) -> void:
	if damage_dealt <= 0.0 or not is_instance_valid(target):
		return
	for entry in stack_triggers:
		if not target.is_alive():
			break
		var cooldowns: Dictionary = entry.cooldowns
		var key: String = target.snapshot.runtime_id
		if float(cooldowns.get(key, -INF)) > owner.session.elapsed_time:
			continue
		var marker: StatusDefinition = entry.stack_status
		target.apply_status(marker, owner, StringName(entry.ability_id))
		if target.status_stacks(marker.id) >= int(entry.stacks_required):
			target.remove_status(marker.id)
			target.apply_status(entry.trigger_status, owner, StringName(entry.ability_id))
			cooldowns[key] = owner.session.elapsed_time + float(entry.per_target_cooldown)
	for entry in nth_hit_statuses:
		entry.count = int(entry.count) + 1
		if int(entry.count) >= int(entry.hits_required) and target.is_alive():
			entry.count = 0
			target.apply_status(entry.status, owner, StringName(entry.ability_id))
	if execute_threshold > 0.0 and target.is_targetable() and not target.snapshot.is_boss and target.snapshot.team != owner.snapshot.team:
		if target.current_hp / maxf(target.get_effective_stat(&"max_hp"), 1.0) < execute_threshold:
			target.force_die(owner, execute_effect_id)
			if execute_gold > 0:
				execute_gold_earned = mini(execute_gold_earned + execute_gold, execute_gold_cap)


# --- damage taken --------------------------------------------------------------

func on_damage_taken(amount: float, source) -> void:
	if amount <= 0.0 or not owner.is_targetable():
		return
	for nova in damage_novas:
		nova.accumulated = float(nova.accumulated) + amount
		while float(nova.accumulated) >= float(nova.threshold) and owner.is_targetable():
			nova.accumulated = float(nova.accumulated) - float(nova.threshold)
			_trigger_nova(nova)
	if rage_points_required > 0.0 and rage_status != null and not owner.has_status(rage_status.id):
		rage_points += amount / maxf(rage_damage_per_point, 0.01)
		if rage_points >= rage_points_required:
			rage_points = 0.0
			owner.apply_status(rage_status, owner, rage_ability_id)
	_check_low_hp_shields()


func _trigger_nova(nova: Dictionary) -> void:
	var ability_id := StringName(nova.ability_id)
	var effect_id := StringName(nova.effect_id)
	owner.session.record_ability_used(owner, owner, ability_id)
	for candidate in owner.session.combatants.duplicate():
		if candidate.snapshot.team == owner.snapshot.team or not candidate.can_receive_effect_from(owner):
			continue
		if candidate.position.distance_to(owner.position) > float(nova.radius):
			continue
		candidate.take_damage(float(nova.damage), owner, ability_id, effect_id, false)
		if candidate.is_alive() and nova.status != null:
			candidate.apply_status(nova.status, owner, ability_id)
	owner.receive_healing(owner.get_effective_stat(&"max_hp") * float(nova.heal_percent) / 100.0, owner, ability_id, effect_id)


func _check_low_hp_shields() -> void:
	var ratio: float = owner.current_hp / maxf(owner.get_effective_stat(&"max_hp"), 1.0)
	for entry in low_hp_shields:
		if bool(entry.used) or ratio > float(entry.threshold):
			continue
		entry.used = true
		entry.active = true
		owner.add_shield(float(entry.shield), float(entry.duration), owner, StringName(entry.ability_id), StringName(entry.effect_id))
		owner.add_runtime_status("Ash Shroud", "Shielded and regenerating +%s HP/s while the shield holds." % StatModifier.format_number(float(entry.regen)), "BUFF", float(entry.duration), StringName(entry.ability_id))
		owner.session.record_ability_used(owner, owner, StringName(entry.ability_id))


# --- kills and deaths ------------------------------------------------------------

func on_kill(victim) -> void:
	if kill_growth_max_hp <= 0.0 or victim.snapshot.team == owner.snapshot.team:
		return
	var room := maxf(0.0, kill_growth_cap - kill_growth_existing - kill_growth_gained)
	var gain := minf(kill_growth_max_hp, room)
	if gain > 0.0:
		kill_growth_gained += gain
		owner.snapshot.stats.max_hp += gain
		owner.current_hp += gain
		owner.session.statistics.record_permanent_stat_gain(owner.snapshot.runtime_id, victim.snapshot.runtime_id, kill_growth_ability_id, {"max_hp": gain})
	owner.receive_healing(owner.get_effective_stat(&"max_hp") * kill_growth_heal_percent / 100.0, owner, kill_growth_ability_id, kill_growth_ability_id)


func on_enemy_died_nearby(victim) -> void:
	for entry in death_summons:
		if victim.position.distance_to(owner.position) > float(entry.radius):
			continue
		if owner.session.combat_rng.randf() * 100.0 >= float(entry.chance):
			continue
		var summon = owner.session.spawn_summon(owner, entry.unit, StringName(entry.ability_id), StringName(entry.effect_id), int(entry.max_active), 100.0, victim.position)
		if summon != null:
			summon.items.lifetime_remaining = float(entry.lifetime)


func on_enemy_ability_used(caster, ability: AbilityDefinition) -> void:
	if ability == null or ability.kind != AbilityDefinition.AbilityKind.ACTIVE:
		return
	for entry in cast_frenzies:
		if caster.position.distance_to(owner.position) <= float(entry.radius):
			owner.apply_status(entry.status, owner, StringName(entry.ability_id))


# --- stat contributions --------------------------------------------------------

func is_isolated() -> bool:
	if isolation_radius <= 0.0:
		return false
	for candidate in owner.session.combatants:
		if candidate != owner and candidate.is_alive() and candidate.snapshot.team == owner.snapshot.team:
			if candidate.position.distance_to(owner.position) <= isolation_radius:
				return false
	return true


func modify_stat(stat: StringName, value: float, entries) -> float:
	if owner.session == null:
		return value
	if (stat == &"damage" or stat == &"damage_taken") and isolation_radius > 0.0 and is_isolated():
		var before := value
		if stat == &"damage":
			value *= 1.0 + isolation_damage_percent / 100.0
			if entries != null:
				owner._record_stat_step(entries, owner._ability_source_name(isolation_ability_id, "Isolation"), &"multiply", 1.0 + isolation_damage_percent / 100.0, before, value)
		else:
			value += isolation_damage_taken_percent
			if entries != null:
				owner._record_stat_step(entries, owner._ability_source_name(isolation_ability_id, "Isolation"), &"add", isolation_damage_taken_percent, before, value)
	if stat == &"damage" and owner.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.SOLDIER:
		var aura: Dictionary = owner.session.get_soldier_damage_aura(owner)
		var percent := float(aura.get("percent", 0.0))
		if percent > 0.0:
			var before := value
			value *= 1.0 + percent / 100.0
			if entries != null:
				owner._record_stat_step(entries, owner._ability_source_name(StringName(aura.get("ability_id", &"")), "Banner aura"), &"multiply", 1.0 + percent / 100.0, before, value)
	if stat == &"attack_speed" or stat == &"movement_speed":
		var slow: Dictionary = owner.session.get_item_slow_aura(owner)
		var slow_percent := float(slow.get("percent", 0.0))
		if slow_percent > 0.0:
			var before := value
			value *= 1.0 - slow_percent / 100.0
			if entries != null:
				owner._record_stat_step(entries, owner._ability_source_name(StringName(slow.get("ability_id", &"")), "Slowing aura"), &"multiply", 1.0 - slow_percent / 100.0, before, value)
	return value


# --- charm ---------------------------------------------------------------------

func start_charm(new_team: int, duration: float, ability_id: StringName) -> void:
	if charm_remaining <= 0.0:
		charm_home_team = owner.snapshot.team
	charm_remaining = maxf(charm_remaining, duration)
	owner.snapshot.team = new_team
	owner.clear_combat_action()
	owner.add_runtime_status("Charmed", "Fights for the other side.", "DEBUFF", duration, ability_id)
	for candidate in owner.session.combatants:
		if candidate != owner and candidate.target == owner:
			candidate.clear_combat_action()
	owner.queue_redraw()


func end_charm() -> void:
	charm_remaining = 0.0
	if charm_home_team < 0:
		return
	owner.snapshot.team = charm_home_team
	charm_home_team = -1
	owner.clear_combat_action()
	if owner.session != null:
		for candidate in owner.session.combatants:
			if candidate != owner and candidate.target == owner:
				candidate.clear_combat_action()
		owner.session.call_deferred("_check_battle_end")
	owner.queue_redraw()


## Team the unit belongs to for victory checks (charmed units still count for home).
func home_team() -> int:
	return charm_home_team if charm_remaining > 0.0 and charm_home_team >= 0 else owner.snapshot.team


func total_post_battle_gold() -> int:
	return post_battle_gold + execute_gold_earned
