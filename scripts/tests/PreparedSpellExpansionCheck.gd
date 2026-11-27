extends Node
var failures := 0
var checks := 0
const IDS := ["briar_hex", "frostglass_prism", "thunderbrand", "astral_cinder"]

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)

func has_text(node: Node, needle: String) -> bool:
	if node is Label and needle in (node as Label).text:
		return true
	for child in node.get_children():
		if has_text(child, needle):
			return true
	return false

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var panel := preload("res://scripts/ui/panels/NewSkillSystems.gd").new()
	add_child(panel)
	panel.set_skill("spellweaving")
	check(has_text(panel, "Patterns learned"), "learning progress shown")
	check(has_text(panel, "Next patterns"), "unlearned patterns discoverable")
	panel.free()
	PlayerData.set_level("spellweaving", 120)
	PlayerData.set_level("magic", 120)
	EquipmentManager.slots[ItemData.EquipmentSlot.WEAPON] = "fire_staff"
	for id in IDS:
		var a: Dictionary = DataLoader.get_action("spellweaving", id)
		check(not a.is_empty(), id + " exists")
		check(not ArcaneSkills.learned(a), id + " starts unlearned")
		for item in a.input_items:
			BankManager.add_item_guaranteed(item, int(a.input_items[item]) * 2)
		check(SkillManager.start_action("spellweaving", id, 1), id + " starts")
		SkillManager.tick(SkillManager.current_interval + 0.01)
		check(ArcaneSkills.learned(a), id + " learned by weaving")
		SkillManager.stop_action()
		PlayerData.settings.spellweaving_pattern = id
		check(ArcaneSkills.can_cast(a), id + " can be prepared")
		var special := ArcaneSkills.special("magic")
		check(not special.is_empty() and str(special.get("applies_status", "")) in ["poison", "slow", "stun", "burn"], id + " has combat effect")
		var texture := AssetRegistry.icon("spellweaving", id)
		check(texture.resource_path == "res://assets/icons/spellweaving/%s.png" % id and texture.get_size() == Vector2(32, 32), id + " has icon")
	var saved := PlayerData.serialize().duplicate(true)
	PlayerData.deserialize(saved)
	for id in IDS:
		check(ArcaneSkills.learned(DataLoader.get_action("spellweaving", id)), id + " persists")
	print("PREPARED SPELL EXPANSION: ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
