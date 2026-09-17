class_name StatModifier
extends Resource


enum Operation {
	ADD,
	MULTIPLY,
}

@export_enum("max_hp", "damage", "attack_speed", "movement_speed", "attack_range", "armor") var stat := "damage"
@export var operation := Operation.ADD
@export var value := 0.0
