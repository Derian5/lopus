class_name CombatResult
extends RefCounted


var result_id := ""
var winner: StringName
var duration := 0.0
var timed_out := false
var encounter_id: StringName
var gold_reward := 0
var bonus_gold_reward := 0
var unit_statistics: Array[Dictionary] = []
var top_damage: Dictionary = {}
var top_healing: Dictionary = {}
var application_summary: Dictionary = {}
var permanent_stat_gains: Array[Dictionary] = []


static func from_statistics(
	new_result_id: String,
	statistics: CombatStatistics,
	encounter: EncounterDefinition,
	battle_timed_out: bool,
	progression: ProgressionDefinition
) -> CombatResult:
	var result := CombatResult.new()
	result.result_id = new_result_id
	result.winner = statistics.winner
	result.duration = statistics.duration
	result.timed_out = battle_timed_out
	if encounter != null:
		result.encounter_id = encounter.id
		result.bonus_gold_reward = statistics.bonus_gold if result.winner == &"player" else 0
		result.gold_reward = (encounter.gold_reward + result.bonus_gold_reward) if result.winner == &"player" else 0
	for data: Dictionary in statistics.unit_stats.values():
		var result_data := data.duplicate(true)
		result_data["contribution"] = progression.contribution_breakdown(result_data)
		result.unit_statistics.append(result_data)
	result.unit_statistics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.runtime_id) < String(b.runtime_id)
	)
	result.top_damage = statistics.get_top_unit(&"damage_dealt", CombatUnitSnapshot.Team.PLAYER)
	result.top_healing = statistics.get_top_unit(&"effective_healing", CombatUnitSnapshot.Team.PLAYER)
	result.permanent_stat_gains = statistics.permanent_stat_gains.duplicate(true)
	return result


func get_unit_statistics(runtime_id: String) -> Dictionary:
	for data in unit_statistics:
		if String(data.runtime_id) == runtime_id:
			return data
	return {}


func get_player_deaths() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for data in unit_statistics:
		if (
			int(data.team) == CombatUnitSnapshot.Team.PLAYER
			and int(data.unit_kind) in [CombatUnitSnapshot.UnitKind.HERO, CombatUnitSnapshot.UnitKind.SOLDIER]
			and int(data.deaths) > 0
		):
			result.append(data)
	return result
