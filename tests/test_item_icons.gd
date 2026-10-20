extends SceneTree


var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var paths := {}
	var item_count := 0
	var ability_count := 0
	for definition in registry.definitions.values():
		if not definition is ItemDefinition:
			continue
		var item := definition as ItemDefinition
		item_count += 1
		_check(item.icon != null, "%s has an icon." % item.id)
		if item.icon == null:
			continue
		var slug := String(item.id).trim_prefix("item.")
		var expected := "res://graphics/ui/item_icons/warcraft/%s.png" % slug
		_check(item.icon.resource_path == expected, "%s references its own approved art." % item.id)
		_check(not paths.has(expected), "%s has a unique icon resource." % item.id)
		paths[expected] = true
		_check(item.icon.get_size() == Vector2(128, 128), "%s imports at 128x128." % item.id)
		var source := Image.load_from_file("res://graphics/generated/runware/source/items_wc3/item_%s_source.png" % slug)
		_check(source != null and source.get_size() == Vector2i(128, 128), "%s preserves its source art." % item.id)
		var slot := ContentIconButton.new()
		root.add_child(slot)
		slot.configure(item, &"item")
		_check(slot.icon == item.icon and slot.content_id == item.id, "%s renders the assigned art in shared equipment controls." % item.id)
		slot.free()
		for ability_id in item.ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition
			_check(ability != null, "%s exists." % ability_id)
			if ability == null:
				continue
			ability_count += 1
			_check(ability.icon == item.icon and ability.presentation_icon == item.icon, "%s inherits the owning item's icon." % ability_id)
	_check(item_count == 42 and paths.size() == 42, "All 42 items have individual icons.")
	_check(ability_count == 24, "All 24 item abilities inherit their item's art.")
	if failures == 0:
		print("Item icon tests passed: 42 items, 24 abilities, 128x128 sources and shared UI controls.")
		quit()
	else:
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
