extends Node
const Wards = preload("res://scripts/core/RuneWards.gd")
const SPELLS = ["purify_essence", "charcoal_weaving", "verdant_compost", "azure_hide", "prismatic_distillation", "herald_awakening", "ward_of_tides", "ward_of_embers", "ward_of_growth", "ward_of_craft", "ward_of_precision", "ward_of_devotion", "enchant_tidetender_amulet", "enchant_artisan_amulet", "enchant_stormfocus_amulet", "enchant_dawnscribe_amulet"]
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	for ident in SPELLS:
		InscriptionManager.deserialize({})
		var a: Dictionary = DataLoader.get_action("alt_magic", ident)
		check(not a.is_empty(), ident + " exists")
		PlayerData.set_level("alt_magic", int(a.level_required)-1)
		check(not SkillManager.start_action("alt_magic", ident), ident + " level gate")
		PlayerData.set_level("alt_magic", int(a.level_required))
		for material in a.input_items:
			BankManager.add_item_guaranteed(material, int(a.input_items[material])*20)
		var first: String = str(a.input_items.keys()[0])
		var before: int = BankManager.get_count(first)
		var xp: float = PlayerData.get_xp("alt_magic")
		var output: String = str(a.output_items.keys()[0]) if not a.output_items.is_empty() else ""
		var stock: int = BankManager.get_count(output) if output != "" else 0
		check(SkillManager.start_action("alt_magic",ident,1), ident + " starts")
		SkillManager.tick(SkillManager.current_interval+.01)
		check(BankManager.get_count(first)<before and PlayerData.get_xp("alt_magic")>xp, ident + " consumes materials and grants XP")
		if output != "":
			check(BankManager.get_count(output)>stock, ident + " creates output")
		else:
			check(Wards.remaining(a)>0, ident + " charges ward")
			var saved: Dictionary = InscriptionManager.serialize()
			InscriptionManager.deserialize({})
			InscriptionManager.deserialize(saved)
			check(Wards.remaining(a)>0, ident + " survives save round trip")
			InscriptionManager.advance(Wards.max_seconds(a)+1)
			check(Wards.remaining(a)==0, ident + " expires")
		SkillManager.stop_action()
		if ident.begins_with("enchant_"):
			var item: Dictionary = DataLoader.get_item(output)
			var mod: String = str(item.passive_modifiers.keys()[0])
			var base: float = ModifierManager.get_modifier(mod)
			check(EquipmentManager.equip(output), output + " equips")
			check(ModifierManager.get_modifier(mod)>base, output + " equipped bonus applies")
			EquipmentManager.unequip(6)
			var card := Widgets.activity_row("alt_magic", a, false, func(): pass)
			var image: TextureRect = card.get_child(0).get_child(0).get_child(0)
			check(image.texture != null and image.texture.resource_path=="res://assets/icons/items/%s.png" % output, output + " authored icon loads")
			card.free()
		if a.get("conversion", false):
			var previous: int = BankManager.get_count(output)
			SkillManager.start_action("alt_magic",ident,2)
			SkillManager.simulate_elapsed(SkillManager.current_interval*2+.1)
			check(BankManager.get_count(output)>previous, ident + " offline production")
			SkillManager.stop_action()
	InscriptionManager.deserialize({})
	var suite = preload("res://scripts/tests/TestRunner.gd").new()
	suite.call("_test_runescribing")
	check(int(suite.get("_failed"))==0, "existing Runescribing invariants and ward engine")
	suite = null
	print("Runescribing expansion: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures==0 else 1)
