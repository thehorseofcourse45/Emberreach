extends Node
func _ready() -> void:
	var elite: Texture2D = AssetRegistry.icon("obstacles", "elite_pillar_of_expertise")
	var regular: Texture2D = AssetRegistry.icon("obstacles", "pillar_of_skilling")
	var ok := elite != null and regular != null and elite.get_size() == Vector2(32, 32) and elite.resource_path == "res://assets/icons/obstacles/elite_pillar_of_expertise.png" and hash(elite.get_image().get_data()) != hash(regular.get_image().get_data())
	print("OBSTACLE ART: ", "1/1 checks" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
