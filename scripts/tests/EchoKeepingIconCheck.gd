extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var checks := 0
	var failures := 0
	for action in DataLoader.get_skill_actions("echo_keeping"):
		var path := "res://assets/icons/echo_keeping/%s.png" % action.id
		var card := Widgets.activity_row("echo_keeping", action, false, func(): pass)
		var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
		checks += 1
		if preview.texture == null or preview.texture.resource_path != path or preview.texture.get_size() != Vector2(32, 32):
			failures += 1
			print("FAIL: ", action.id)
		card.free()
	if checks != 20:
		failures += 1
	print("Echo Keeping icon checks: ", checks, " passed: ", checks - failures, " failures: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
