class_name RngStreamState
extends RefCounted


var seed := 1
var state := 1
var draw_count := 0


func initialize(new_seed: int) -> void:
	seed = new_seed if new_seed != 0 else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	state = rng.state
	draw_count = 0


func next_u32() -> int:
	var rng := create_rng()
	var value := rng.randi()
	state = rng.state
	draw_count += 1
	return value


func next_seed() -> int:
	return next_u32() | 1


func create_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	rng.state = state
	return rng


func to_dictionary() -> Dictionary:
	return {
		"seed": str(seed),
		"state": str(state),
		"draw_count": draw_count,
	}


static func from_dictionary(data: Dictionary) -> RngStreamState:
	var stream := RngStreamState.new()
	stream.seed = String(data.get("seed", "1")).to_int()
	stream.state = String(data.get("state", "1")).to_int()
	stream.draw_count = maxi(0, int(data.get("draw_count", 0)))
	return stream
