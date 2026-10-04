extends Node
func _ready() -> void:
 GameManager.cli_mode = true
 GameManager.is_paused = true
 SaveManager.autosave_enabled = false
 SaveManager.save_on_major_event = false
 var ids := ["herald_helmet","herald_gauntlets","herald_sabatons","herald_platelegs","throneguard_helm","throneguard_gauntlets","throneguard_sabatons","throneguard_platelegs","throneguard_cuirass","charmed_gold_ring","sapphire_ring_of_focus","emerald_ring_of_study","topaz_ring_of_the_hawk","ruby_ring_of_fury","diamond_ring_of_warding","riven_signet","reinforced_dhide_body","reinforced_dhide_chaps","reinforced_dhide_coif","umbral_dhide_vambraces"]
 var failures := 0
 for id in ids:
  var source: String = str(DataLoader.get_item(id).get("icon_id", id))
  var texture: Texture2D = AssetRegistry.item_icon(id)
  if texture == null or texture.resource_path != "res://assets/icons/items/%s.png" % source:
   failures += 1
   print("PLACEHOLDER OR INVALID: ",id)
 print("GEAR ICON AUDIT: %d checked, %d placeholders or invalid textures" % [ids.size(),failures])
 get_tree().quit(1 if failures else 0)
