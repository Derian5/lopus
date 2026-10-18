class_name DespairTeamProcEffect
extends AbilityEffect


@export_range(0.0, 100.0, 0.1) var proc_chance_percent := 15.0
@export_range(100.0, 100000.0, 1.0, "or_greater") var total_damage_percent := 150.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_despair_team_proc(proc_chance_percent, total_damage_percent, ability.id, effect_id)
