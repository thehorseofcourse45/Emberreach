extends Node
var checks := 0
var failures := 0
func ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), 120)
	call_deferred("run")

func run() -> void:
	var count := 0
	var seen := {}
	for d in DataLoader.dungeons.values():
		if not bool(d.get("raid", false)): continue
		count += 1
		var boss: Dictionary = DataLoader.get_monster(str(d.monsters[-1])).duplicate(true)
		var loot: Array = boss.loot_table
		var uniques := []
		for drop in loot:
			if str(drop.item_id).begins_with("raid_reward_"):
				uniques.append(drop)
		ok(uniques.size() == 2, str(d.name) + " has two new rewards")
		for drop in uniques:
			var id := str(drop.item_id)
			var item: Dictionary = DataLoader.get_item(id)
			ok(not item.is_empty() and not seen.has(id), id + " is a unique item")
			seen[id] = true
			ok(float(drop.chance) > 0.0 and float(drop.chance) < 1.0, id + " has a repeatable drop chance")
			var texture := AssetRegistry.item_icon(id)
			ok(texture != null and texture.resource_path.ends_with("/" + id + ".png"), id + " loads its own icon")
			drop.chance = 1.0
			CombatManager._grant_loot({"loot_table": [drop], "name": d.name}, true)
			ok(BankManager.get_count(id) > 0, id + " enters the bank from combat loot")
			ok(EquipmentManager.equip(id), id + " can be equipped")
			for key in item.passive_modifiers:
				ok(ModifierManager.get_modifier(str(key)) >= float(item.passive_modifiers[key]), id + " activates " + str(key))
			ok(EquipmentManager.unequip(int(item.equipment_slot)), id + " can be unequipped")
	ok(count == 15 and seen.size() == 30, "all fifteen raids have two additional rewards")
	print("Raid rewards: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
