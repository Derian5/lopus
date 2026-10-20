class_name CombatUnitSnapshot
extends RefCounted


enum Team {
	PLAYER,
	ENEMY,
}

enum UnitKind {
	HERO,
	SOLDIER,
	ENEMY,
	SUMMON,
}

var runtime_id := ""
var definition_id: StringName
var display_name := ""
var team := Team.PLAYER
var unit_kind := UnitKind.SOLDIER
var job_id: StringName
var veterancy_level := 0
var attack_type: StringName = &"melee"
var targeting_mode: StringName = &"closest"
var damage_avoidance_override := -1
var avoids_damage: bool:
	get:
		return damage_avoidance_override == 1 or (damage_avoidance_override < 0 and attack_type == &"ranged")
	set(value):
		damage_avoidance_override = 1 if value else 0
var stats := CombatStats.new()
var placeholder_color := Color.WHITE
var abilities: Array[AbilityDefinition] = []
var post_combat_xp_bonus_percent := 0.0
var equipped_item_instance_ids: Array[StringName] = []
var equipped_item_definition_ids: Array[StringName] = []
## Run-permanent stat gains already earned, by source ability id ({id: total value}).
var permanent_gains: Dictionary = {}
var summoner_runtime_id := ""
var summoning_ability_id: StringName
var summoning_effect_id: StringName
var summoner_contribution_percent := 100.0
var is_boss := false
var boss_phase_count := 1
var boss_phase_health_thresholds := PackedFloat32Array()
var boss_phase_damage_multiplier := 1.0
var boss_phase_attack_speed_multiplier := 1.0
var boss_telegraph_color := Color(1.0, 0.25, 0.12, 0.9)
var boss_phase_telegraph_text := ""
## Normalized custom starting position; negative = automatic formation.
var formation_position := Vector2(-1.0, -1.0)


func duplicate_snapshot() -> CombatUnitSnapshot:
	var copy := CombatUnitSnapshot.new()
	copy.runtime_id = runtime_id
	copy.definition_id = definition_id
	copy.display_name = display_name
	copy.team = team
	copy.unit_kind = unit_kind
	copy.job_id = job_id
	copy.veterancy_level = veterancy_level
	copy.attack_type = attack_type
	copy.targeting_mode = targeting_mode
	copy.damage_avoidance_override = damage_avoidance_override
	copy.stats = stats.duplicate_stats()
	copy.placeholder_color = placeholder_color
	copy.abilities = abilities.duplicate()
	copy.post_combat_xp_bonus_percent = post_combat_xp_bonus_percent
	copy.equipped_item_instance_ids = equipped_item_instance_ids.duplicate()
	copy.equipped_item_definition_ids = equipped_item_definition_ids.duplicate()
	copy.permanent_gains = permanent_gains.duplicate()
	copy.summoner_runtime_id = summoner_runtime_id
	copy.summoning_ability_id = summoning_ability_id
	copy.summoning_effect_id = summoning_effect_id
	copy.summoner_contribution_percent = summoner_contribution_percent
	copy.is_boss = is_boss
	copy.boss_phase_count = boss_phase_count
	copy.boss_phase_health_thresholds = boss_phase_health_thresholds.duplicate()
	copy.boss_phase_damage_multiplier = boss_phase_damage_multiplier
	copy.boss_phase_attack_speed_multiplier = boss_phase_attack_speed_multiplier
	copy.boss_telegraph_color = boss_telegraph_color
	copy.boss_phase_telegraph_text = boss_phase_telegraph_text
	copy.formation_position = formation_position
	return copy
