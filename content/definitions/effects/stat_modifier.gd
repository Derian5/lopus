class_name StatModifier
extends Resource


enum Operation {
	ADD,
	MULTIPLY,
}

@export_enum("max_hp", "damage", "attack_speed", "movement_speed", "attack_range", "armor") var stat := "damage"
@export var operation := Operation.ADD
@export var value := 0.0


func apply_to(base_value: float, stack_count := 1) -> float:
	if operation == Operation.MULTIPLY:
		return base_value * pow(value, stack_count)
	return base_value + value * stack_count
