extends SceneTree

func _init() -> void:
	var path: String = "res://scripts/tests/TestRunner.gd"
	var script: Resource = load(path)
	print("loaded %s -> %s" % [path, "ok" if script != null else "null"])
	if script != null:
		var probe: Object = script.new()
		print("instantiated: ", probe != null)
	quit()
