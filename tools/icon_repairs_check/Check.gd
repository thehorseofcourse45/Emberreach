extends Node
const Sidebar = preload("res://scripts/ui/SidebarNav.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  print("ICON FIX FAIL: ",message)
func _ready() -> void:
 GameManager.cli_mode = true
 GameManager.is_paused = true
 SaveManager.autosave_enabled = false
 SaveManager.save_on_major_event = false
 var specs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/icon_repairs_check/specs.json"))
 for s in specs:
  for path in s.paths:
   var p: String = str(path)
   var id: String = p.get_file().get_basename()
   var texture: Texture2D = AssetRegistry.item_icon(id) if p.begins_with("icons/items/") else AssetRegistry.icon("farming" if p.begins_with("icons/farming/") else "navigation",id)
   check(texture != null and texture.resource_path == "res://assets/"+p,"authored texture "+p)
   check(texture != null and texture.get_size() == Vector2(32,32),"dimensions "+p)
   check(texture != null and texture.get_image().detect_alpha() != Image.ALPHA_NONE,"transparency "+p)
 for sid in ["farming","cooking","herblore"]:
  check(AssetRegistry.skill_icon(sid).resource_path == "res://assets/icons/skills/%s.png" % sid,"skill icon "+sid)
  for action in DataLoader.get_skill_actions(sid):
   var row: Control = Widgets.activity_row(sid,action,false,func(_id): pass)
   var preview: TextureRect = row.get_child(0).get_child(0).get_child(0)
   check(preview.texture != null and preview.texture.resource_path.begins_with("res://assets/"),"activity icon "+str(action.id))
   row.free()
 check(Sidebar._icon_kind_for(Screens.PRESTIGE)=="navigation","Ascendancy icon kind")
 check(Sidebar._icon_id_for(Screens.PRESTIGE)=="prestige","Ascendancy icon ID")
 print("ICON REPAIRS: %d checks, %d failed" % [checks,failures])
 get_tree().quit(1 if failures else 0)
