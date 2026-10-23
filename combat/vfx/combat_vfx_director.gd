class_name CombatVfxDirector
extends Node

## Preloaded rather than used by class name, so headless runs work before the editor scans new classes.
const VFX := preload("res://combat/vfx/combat_vfx.gd")


## Turns combat events into effects: ability casts, ability hits, healing, deaths and
## summons. Basic hits, shots, area slams and footstep dust are spawned directly by
## CombatSession / Combatant / CombatProjectile through the same CombatVfx helpers.
## Presentation only; does nothing while CombatSession.vfx_enabled is false.

## Per-unit cooldowns keep periodic ticks (poison, regeneration) from flooding the screen.
const CAST_COOLDOWN := 0.3
const ABILITY_HIT_COOLDOWN := 0.3
const HEAL_COOLDOWN := 0.7
const BURN_TICK_COOLDOWN := 0.4
const PLAYER_SOUL := Color(0.78, 0.86, 1.0)
const ENEMY_SOUL := Color(1.0, 0.68, 0.6)
const SUMMON_COLOR := Color(0.55, 0.95, 0.9)
const BLESSING_COLOR := Color(1.0, 0.82, 0.45)

var session: CombatSession
var last_shown := {}
var last_bleed_pulse := {}
var blood_event_serial := 0


func _init(combat_session: CombatSession) -> void:
	session = combat_session
	name = "VfxDirector"


func _ready() -> void:
	session.combat_event_emitted.connect(_on_event)


func clear() -> void:
	last_shown.clear()
	last_bleed_pulse.clear()
	blood_event_serial = 0


func _on_event(event: CombatEvent) -> void:
	if not session.vfx_enabled:
		return
	match event.event_type:
		CombatEvent.ABILITY_USED:
			_on_ability_used(event)
		CombatEvent.DAMAGE_APPLIED:
			_on_damage(event)
		CombatEvent.HEALING_APPLIED:
			_on_healing(event)
		CombatEvent.STATUS_APPLIED:
			_on_status(event)
		CombatEvent.UNIT_DIED:
			_on_death(event)
		CombatEvent.UNIT_SUMMONED:
			_on_summon(event)
		CombatEvent.VETERANCY_GAINED:
			_on_veterancy(event)


func _on_ability_used(event: CombatEvent) -> void:
	var source := session.get_combatant_by_runtime_id(event.source_id)
	if source == null:
		return
	var major := source.snapshot.is_boss or source.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO
	# Soldiers cast often: their sigil is smaller and shows less often.
	if not _ready_again("cast:" + event.source_id, CAST_COOLDOWN if major else CAST_COOLDOWN * 3.0):
		return
	var tint := _ability_color(event.ability_id)
	var scale := 0.72 if source.snapshot.is_boss else (0.52 if major else 0.36)
	var ability := session.get_ability_definition(event.ability_id)
	var style := VFX.ability_style(ability)
	if style == &"blink":
		return  # Teleport helpers place paired departure/arrival visuals.
	# The rune circle is drawn 30 px below the atlas centre: put it on the unit's feet.
	if major:
		VFX.flash_light(session.light_layer, source.position, tint, 1.1, 2.0, 0.6)
	if style in [&"arcane", &"summon"]:
		VFX.spawn(_layer(), &"cast_sigil", source.feet_position() + Vector2(0.0, -30.0 * scale), scale, tint, 0.0, VFX.GROUND_Z + 1)
	else:
		VFX.spawn_spell(_layer(), &"boon" if style == &"fire" else style, source.feet_position(), tint, 46.0 if major else 28.0, 0.5)


func _on_damage(event: CombatEvent) -> void:
	if event.value <= 0.0:
		return
	var target := session.get_combatant_by_runtime_id(event.target_id)
	if target == null:
		return
	var ability := session.get_ability_definition(event.ability_id)
	var periodic := _periodic_status(event, target)
	if periodic != null:
		var periodic_style := VFX.status_style(periodic.definition, ability)
		if periodic_style == &"fire" and _ready_again("burn:" + event.target_id, BURN_TICK_COOLDOWN):
			# The flames on the body flare up with each burn tick.
			session.spawn_fire_tick(target)
		if periodic_style == &"bleed":
			var key := event.target_id + ":" + String(periodic.definition.id)
			# Stacks deal damage as separate events at the same simulation time.
			# Show one stronger pulse, rather than three identical overlapping sprays.
			if float(last_bleed_pulse.get(key, -INF)) != event.timestamp:
				last_bleed_pulse[key] = event.timestamp
				_spawn_blood(event, target, true, periodic.stacks)
		return
	_spawn_blood(event, target)
	if event.ability_id == &"attack.basic" or event.ability_id.is_empty() or not _ready_again("hit:" + event.target_id, ABILITY_HIT_COOLDOWN):
		return
	# Flying shots already have an impact; persistent damage has its own attached
	# visual. Do not turn every burn/poison tick into another white explosion.
	if ability != null and ability.delivery_method == AbilityDefinition.DeliveryMethod.PROJECTILE:
		return
	var tint := _ability_color(event.ability_id)
	VFX.spawn_spell(_layer(), VFX.ability_style(ability), target.feet_position(), tint, 30.0, 0.45)


func _periodic_status(event: CombatEvent, target: Combatant) -> StatusInstance:
	for status in target.statuses:
		if status.source_ability_id != event.ability_id:
			continue
		for effect in status.definition.periodic_effects:
			if effect.effect_id == event.effect_id:
				return status
	return null


func _spawn_blood(event: CombatEvent, target: Combatant, bleed_tick := false, stacks := 1) -> void:
	if not VFX.bleeds(target):
		return
	var source := session.get_combatant_by_runtime_id(event.source_id)
	var direction := (target.position - source.position).normalized() if source != null else Vector2.RIGHT
	if direction.is_zero_approx():
		direction = Vector2.LEFT if target.snapshot.runtime_id.hash() % 2 == 0 else Vector2.RIGHT
	var height := maxf(target.health_bar_offset / 0.65, 48.0)
	var ratio := event.value / maxf(target.snapshot.stats.max_hp, 1.0)
	var severity := clampf(0.7 + sqrt(maxf(ratio, 0.0)) * 1.8, 0.7, 1.5)
	if bleed_tick:
		severity = 0.8 + minf(stacks, 5) * 0.14
	blood_event_serial += 1
	var variation := (event.source_id + ":" + event.target_id + ":" + str(blood_event_serial)).hash()
	VFX.spawn_blood(_layer(), target.feet_position() - Vector2(0, height * 0.55), target.feet_position(), direction, height, severity, bleed_tick, variation)


func _on_status(event: CombatEvent) -> void:
	var target := session.get_combatant_by_runtime_id(event.target_id)
	if target == null:
		return
	if target.status_vfx != null:
		target.status_vfx.refresh()
	if not _ready_again("status:" + event.target_id, 0.45):
		return
	var ability := session.get_ability_definition(event.ability_id)
	for status in target.statuses:
		if status.definition.id != event.effect_id:
			continue
		var style := VFX.status_style(status.definition, ability)
		if not style.is_empty() and style not in [&"fire", &"bleed", &"poison", &"shadow"]:
			VFX.spawn_spell(_layer(), style, target.feet_position(), _ability_color(event.ability_id), 32.0, 0.6)
		break


func _on_healing(event: CombatEvent) -> void:
	if event.value < 1.0:
		return
	var target := session.get_combatant_by_runtime_id(event.target_id)
	if target == null or not target.is_alive() or not _ready_again("heal:" + event.target_id, HEAL_COOLDOWN):
		return
	VFX.flash_light(session.light_layer, target.position, Color(0.5, 1.0, 0.55), 0.7, 1.3, 0.5)
	VFX.spawn(_layer(), &"heal_sparkle", target.position + Vector2(0.0, -24.0), 0.58, Color.WHITE, 0.0, VFX.IMPACT_Z, true)


func _on_death(event: CombatEvent) -> void:
	var unit := session.get_combatant_by_runtime_id(event.target_id)
	if unit == null:
		return
	var scale := 1.0 if unit.snapshot.is_boss else (0.7 if unit.snapshot.unit_kind == CombatUnitSnapshot.UnitKind.HERO else 0.56)
	var tint := PLAYER_SOUL if unit.items.home_team() == CombatUnitSnapshot.Team.PLAYER else ENEMY_SOUL
	var feet := unit.feet_position()
	# Smoke puff centre is 37 px and the soul's ground ring 60 px below their atlas centres.
	VFX.spawn(_layer(), &"death_smoke", feet - Vector2(0.0, 37.0 * scale + 10.0), scale, Color.WHITE, 0.0, VFX.IMPACT_Z - 3)
	VFX.flash_light(session.light_layer, feet - Vector2(0.0, 40.0), tint, 0.8, 1.6, 0.7)
	VFX.spawn(_layer(), &"death_soul", feet - Vector2(0.0, 60.0 * scale), scale, tint, 0.0, VFX.IMPACT_Z - 2)
	# A pool of blood spreads under the body and stays for the rest of the battle.
	session.spawn_blood_pool(unit)


func _on_summon(event: CombatEvent) -> void:
	var summon := session.get_combatant_by_runtime_id(event.target_id)
	if summon == null:
		return
	var tint := _ability_color(event.ability_id, SUMMON_COLOR)
	var scale := 0.62 if event.value > 1.0 else 0.46
	VFX.flash_light(session.light_layer, summon.position, tint, 1.2, 1.8, 0.6)
	VFX.spawn(_layer(), &"summon_portal", summon.feet_position() + Vector2(0.0, -22.0 * scale), scale, tint, 0.0, VFX.GROUND_Z + 1)


## Veterancy rank up: a shaft of golden light from above, a spark shower and a
## burst at the feet (atlas veterancy_blessing: the feet sit 112.5 px below the
## cell centre), with warm lights.
func _on_veterancy(event: CombatEvent) -> void:
	var unit := session.get_combatant_by_runtime_id(event.target_id)
	if unit == null:
		return
	var scale := 0.85
	var feet := unit.feet_position()
	VFX.spawn(_layer(), &"veterancy_blessing", feet - Vector2(0.0, 112.5 * scale), scale, Color.WHITE, 0.0, VFX.IMPACT_Z + 2)
	VFX.flash_light(session.light_layer, feet - Vector2(0.0, 120.0), BLESSING_COLOR, 1.0, 1.6, 0.5)
	# The light shaft reaches the ground about 0.24 s in: flare and sparks there.
	var tween := session.light_layer.create_tween()
	tween.tween_interval(0.24)
	tween.tween_callback(Callable(VFX, "flash_light").bind(session.light_layer, feet - Vector2(0.0, 20.0), BLESSING_COLOR, 1.6, 2.2, 0.9))
	tween.tween_callback(Callable(VFX, "spark_lights").bind(session.light_layer, feet - Vector2(0.0, 10.0), Vector2.UP, BLESSING_COLOR, 6))


func _ability_color(ability_id: StringName, fallback := Color(0.85, 0.85, 1.0)) -> Color:
	var ability := session.get_ability_definition(ability_id) if not String(ability_id).is_empty() else null
	if ability == null or ability.presentation_color.a <= 0.0:
		return fallback
	# Effects are authored white; lighten dark ability colours so they stay readable.
	return ability.presentation_color.lerp(Color.WHITE, 0.25)


func _ready_again(key: String, cooldown: float) -> bool:
	var now := session.elapsed_time
	if last_shown.has(key) and now - float(last_shown[key]) < cooldown:
		return false
	last_shown[key] = now
	return true


func _layer() -> Node:
	return session.get_node("Effects")
