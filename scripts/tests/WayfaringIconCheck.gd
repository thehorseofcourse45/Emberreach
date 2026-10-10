extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var checks := 0
	var failures := 0
	var seen: Array[String] = []
	for action in DataLoader.get_skill_actions("agility"):
		var source: String = str(action.get("icon_obstacle", ""))
		var expected: String = "res://assets/icons/obstacles/%s.png" % source
		checks += 1
		if source == "" or seen.has(source) or not ResourceLoader.exists(expected):
			failures += 1
			print("FAIL: unique existing artwork ", action.id)
		seen.append(source)
		for level in [1,120]:
			PlayerData.set_level("agility", level)
			var card := Widgets.activity_row("agility", action, false, func(): pass)
			var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
			checks += 1
			if preview.texture == null or preview.texture.resource_path != expected:
				failures += 1
				print("FAIL: row preview ", action.id, " level ", level)
			card.free()
	print("Wayfaring icon checks: ", checks, " passed: ", checks-failures, " failures: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
