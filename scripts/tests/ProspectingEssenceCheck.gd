extends Node

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true
	call_deferred("run")

func run() -> void:
	PlayerData.initialize_new_game()
	BankManager.deserialize({"purchased_slots": 1000})
	ModifierManager._sources.clear()
	ModifierManager._mark_dirty()
	MasteryManager.deserialize({})
	SimulationMode.begin()
	SkillManager.seed_rng(9876)
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ProspectingEssences.json"))
	var types := {}
	for action in DataLoader.get_skill_actions("harvesting"):
		for item in action.get("output_items", {}):
			types[item] = true
	check(types.size() == 12, "twelve Prospecting essence types")
	for spec in specs:
		var id: String = str(spec[0])+"_essence"
		var action_id := "refine_"+id
		check(not DataLoader.get_item(id).is_empty(), id+" defined")
		var recipe: Dictionary = DataLoader.get_action("enchanting", action_id)
		check(not recipe.is_empty(), action_id+" defined")
		if recipe.is_empty():
			continue
		for vein in spec[8]:
			var data: Dictionary = DataLoader.get_action("harvesting", str(vein))
			var old_id: String = "umbral_essence" if str(vein)=="crownstone_seam" else ("prismatic_essence" if str(vein) in ["ember_seam", "voidtouched"] else "harvested_essence")
			check(int(data.output_items.get(old_id, 0)) == 1, str(vein)+" preserves legacy output")
			check(str(data.output_items.keys()[0]) == id, str(vein)+" previews specialist essence")
			PlayerData.set_level("harvesting", 120)
			check(SkillManager.start_action("harvesting", str(vein)), str(vein)+" starts")
			var result: Dictionary = SkillManager.perform_action()
			check(bool(result.get("success", false)), str(vein)+" completes")
			check(int(result.get("items", {}).get(id, 0)) >= 1, str(vein)+" yields specialist essence")
			check(int(result.get("items", {}).get(old_id, 0)) >= 1, str(vein)+" yields legacy essence")
			check(float(result.get("xp", 0)) > 0.0, str(vein)+" earns XP")
			SkillManager.stop_action()
		BankManager.items.clear()
		PlayerData.set_level("enchanting", 120)
		check(not SkillManager.can_perform("enchanting", action_id), action_id+" rejects missing materials")
		for item in recipe.input_items:
			BankManager.add_item_guaranteed(str(item), int(recipe.input_items[item]))
		PlayerData.set_level("enchanting", int(recipe.level_required)-1)
		check(not SkillManager.can_perform("enchanting", action_id), action_id+" level locked")
		PlayerData.set_level("enchanting", 120)
		check(SkillManager.start_action("enchanting", action_id), action_id+" starts")
		var result: Dictionary = SkillManager.perform_action()
		check(bool(result.get("success", false)), action_id+" completes")
		for item in recipe.input_items:
			check(BankManager.get_count(str(item)) == 0, action_id+" consumes "+str(item))
		check(BankManager.get_count(str(spec[6])) == int(spec[7]), action_id+" pays enchantment material")
		check(float(result.get("xp", 0)) > 0 and MasteryManager.get_xp("enchanting", action_id) > 0, action_id+" earns XP and mastery")
		SkillManager.stop_action()
		check(not Goals.sources_for_item(id).is_empty(), id+" acquisition hint")
		if not "--without-art" in OS.get_cmdline_user_args():
			var texture: Texture2D = AssetRegistry.item_icon(id)
			check(texture != null and texture.resource_path != "" and texture.get_size()==Vector2(32,32), id+" authored icon")
	SimulationMode.end()
	print("Prospecting essences: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
