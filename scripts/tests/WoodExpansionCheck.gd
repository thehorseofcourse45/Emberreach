extends Node
var checks := 0
var failures := 0

func verify(ok: bool, label: String) -> void:
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
	for ident in ["mosswillow", "frostcedar", "stormwood", "sunheart"]:
		var log_id: String = ident + "_log"
		var tree_id: String = ident + "_tree"
		var burn_id: String = "burn_" + log_id
		var tree: Dictionary = DataLoader.get_action("woodcutting", tree_id)
		var burn: Dictionary = DataLoader.get_action("firemaking", burn_id)
		verify(not tree.is_empty() and not burn.is_empty(), ident + " activities exist")
		PlayerData.set_level("woodcutting", int(tree.level_required) - 1)
		verify(not SkillManager.start_action("woodcutting", tree_id), ident + " cutting level gate")
		PlayerData.set_level("woodcutting", int(tree.level_required))
		verify(SkillManager.start_action("woodcutting", tree_id), ident + " cutting starts")
		var before: int = BankManager.get_count(log_id)
		var xp: float = PlayerData.get_xp("woodcutting")
		SkillManager.tick(SkillManager.current_interval + 0.01)
		verify(BankManager.get_count(log_id) > before, ident + " cutting produces log")
		verify(PlayerData.get_xp("woodcutting") > xp, ident + " cutting grants XP")
		SkillManager.stop_action()
		PlayerData.set_level("firemaking", int(burn.level_required) - 1)
		verify(not SkillManager.start_action("firemaking", burn_id), ident + " burning level gate")
		PlayerData.set_level("firemaking", int(burn.level_required))
		verify(SkillManager.start_action("firemaking", burn_id), ident + " burning starts")
		before = BankManager.get_count(log_id)
		xp = PlayerData.get_xp("firemaking")
		SkillManager.tick(SkillManager.current_interval + 0.01)
		verify(BankManager.get_count(log_id) < before, ident + " burning consumes log")
		verify(PlayerData.get_xp("firemaking") > xp, ident + " burning grants XP")
		SkillManager.stop_action()
		for sid in ["woodcutting", "firemaking"]:
			var action: Dictionary = tree if sid == "woodcutting" else burn
			var expected: String = "res://assets/icons/items/%s.png" % log_id if sid == "woodcutting" else "res://assets/icons/firemaking/%s.png" % burn_id
			var card := Widgets.activity_row(sid, action, false, func(): pass)
			var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
			verify(preview.texture != null and preview.texture.resource_path == expected and preview.texture.get_size() == Vector2(32,32), ident + " " + sid + " preview")
			card.free()
	print("Wood expansion checks: ", checks, " passed: ", checks-failures, " failures: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
