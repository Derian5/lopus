class_name BossDefinition
extends EnemyDefinition


@export var phase_count := 1
@export var phase_health_thresholds := PackedFloat32Array()
@export_range(1.0, 10.0, 0.05) var phase_damage_multiplier := 1.0
@export_range(1.0, 10.0, 0.05) var phase_attack_speed_multiplier := 1.0
@export var telegraph_color := Color(1.0, 0.25, 0.12, 0.9)
@export var phase_telegraph_text := "PHASE SHIFT"
