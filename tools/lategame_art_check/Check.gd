extends Node
func _ready() -> void:
 GameManager.cli_mode = true
 GameManager.is_paused = true
 SaveManager.autosave_enabled = false
 SaveManager.save_on_major_event = false
 var failures := 0
 var checks := 0
 var specs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/lategame_art_check/specs.json"))
 for s in specs:
  var texture: Texture2D = AssetRegistry.item_icon(str(s.id))
  checks += 1
  if texture == null or texture.resource_path != "res://assets/"+str(s.path):
   failures += 1
   print("FAIL authored icon: ",s.id)
  checks += 1
  if texture == null or texture.get_size() != Vector2(32,32): failures += 1
  checks += 1
  if texture == null or texture.get_image().detect_alpha() == Image.ALPHA_NONE: failures += 1
 print("LATE-GAME ART: %d checks, %d failed" % [checks,failures])
 get_tree().quit(1 if failures else 0)
