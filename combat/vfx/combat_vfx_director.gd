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
const PLAYER_SOUL := Color(0.78, 0.86, 1.0)
const ENEMY_SOUL := Color(1.0, 0.68, 0.6)
const SUMMON_COLOR := Color(0.55, 0.95, 0.9)

var session: CombatSession
var last_shown := {}


func _init(combat_session: CombatSession) -> void:
	session = combat_session
	name = "VfxDirector"


func _ready() -> void:
	session.combat_event_emitted.connect(_on_event)


func clear() -> void:
	last_shown.clear()


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
		CombatEvent.UNIT_DIED:
			_on_death(event)
		CombatEvent.UNIT_SUMMONED:
			_on_summon(event)


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
	# The rune circle is drawn 30 px below the atlas centre: put it on the unit's feet.
	if major:
		VFX.flash_light(session.light_layer, source.position, tint, 1.1, 2.0, 0.6)
	VFX.spawn(_layer(), &"cast_sigil", source.feet_position() + Vector2(0.0, -30.0 * scale), scale, tint, 0.0, VFX.GROUND_Z + 1)


func _on_damage(event: CombatEvent) -> void:
	if event.value <= 0.0 or String(event.ability_id).is_empty() or event.ability_id == &"attack.basic":
		return
	var target := session.get_combatant_by_runtime_id(event.target_id)
	if target == null or not _ready_again("hit:" + event.target_id, ABILITY_HIT_COOLDOWN):
		return
	VFX.spawn(_layer(), &"magic_burst", target.position + Vector2(0.0, -16.0), 0.42, _ability_color(event.ability_id), 0.0, VFX.IMPACT_Z, true)


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


func _on_summon(event: CombatEvent) -> void:
	var summon := session.get_combatant_by_runtime_id(event.target_id)
	if summon == null:
		return
	var tint := _ability_color(event.ability_id, SUMMON_COLOR)
	var scale := 0.62 if event.value > 1.0 else 0.46
	VFX.flash_light(session.light_layer, summon.position, tint, 1.2, 1.8, 0.6)
	VFX.spawn(_layer(), &"summon_portal", summon.feet_position() + Vector2(0.0, -22.0 * scale), scale, tint, 0.0, VFX.GROUND_Z + 1)


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
