extends SceneTree


func _initialize() -> void:
	var stats := CombatStats.new()
	stats.damage = 10.0
	stats.begin_breakdowns("Base")
	stats.record_change(&"damage", "Bounty Hunter", &"add", 2.0, 10.0, 12.0)
	stats.record_change(&"damage", "Equipment", &"add", 5.0, 12.0, 17.0)
	stats.record_change(&"damage", "Bounty Hunter", &"add", 2.0, 17.0, 19.0)
	stats.record_change(&"damage", "Bounty Hunter", &"add", 8.0, 19.0, 27.0)
	stats.record_change(&"damage", "Damage bonus", &"multiply", 2.0, 27.0, 54.0)
	stats.record_change(&"damage", "Bounty Hunter", &"add", 2.0, 54.0, 56.0)
	stats.damage = 56.0
	var original := stats.breakdown_for(&"damage")
	var text := StatBreakdownFormatter.from_stats(stats, &"damage")
	var expected := "DAMAGE\nBase: 10\nBounty Hunter: +12  ->  22\nEquipment: +5  ->  27\nDamage bonus: x2  ->  54\nBounty Hunter: +2  ->  56\nFINAL: 56"
	if text != expected or stats.breakdown_for(&"damage") != original:
		push_error("Repeated additive sources should combine with correct totals, preserve multiplier boundaries, and leave combat data unchanged.\n%s" % text)
		quit(1)
		return
	print("Stat breakdown formatter tests passed.")
	quit()
