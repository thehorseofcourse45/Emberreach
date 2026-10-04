extends Node
func _ready() -> void:
 GameManager.cli_mode = true
 GameManager.is_paused = true
 SaveManager.autosave_enabled = false
 SaveManager.save_on_major_event = false
 var failures := 0
 var checks := 0
 var specs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/progression_icons_check/assets.json"))
 for s in specs:
  var texture: Texture2D
  match str(s.kind):
   "items": texture = AssetRegistry.item_icon(str(s.id))
   "monsters": texture = AssetRegistry.monster_sprite(str(s.id))
   "areas": texture = AssetRegistry.icon("areas", str(s.id))
  checks += 1
  if texture == null or texture.resource_path != "res://assets/" + str(s.path):
   failures += 1
   print("FAIL authored texture: ",s.id)
  checks += 1
  if texture == null or texture.get_size() != Vector2(int(s.size),int(s.size)):
   failures += 1
   print("FAIL size: ",s.id)
  checks += 1
  if texture == null or texture.get_image().detect_alpha() == Image.ALPHA_NONE:
   failures += 1
   print("FAIL transparency: ",s.id)
 print("PROGRESSION ICONS: %d checks, %d failed" % [checks,failures])
 get_tree().quit(1 if failures else 0)
