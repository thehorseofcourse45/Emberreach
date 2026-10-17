extends Node
var checks := 0
var failures := 0
var hashes: Dictionary={}
func ok(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: ",message)
func noop() -> void:
	pass
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	var actions: Array=DataLoader.get_skill_actions("inscription")
	ok(actions.size()==49,"all 49 Scribing activities checked")
	for action in actions:
		var id: String=str(action.output_items.keys()[0])
		var texture: Texture2D=AssetRegistry.item_icon(id)
		ok(texture.resource_path.ends_with(id+".png"),"real item icon: "+id)
		ok(texture.get_size()==Vector2(32,32),"32x32 icon: "+id)
		var image: Image=texture.get_image()
		ok(image.get_pixel(0,0).a==0 and image.get_pixel(31,31).a==0,"transparent corners: "+id)
		var hash: String=image.get_data().hex_encode().sha256_text()
		ok(not hashes.has(hash),"unique activity artwork: "+str(action.id))
		hashes[hash]=true
		var row: Control=Widgets.activity_row("inscription",action,false,noop)
		add_child(row)
		var previews: Array=row.find_children("*","TextureRect",true,false)
		ok(not previews.is_empty() and previews[0].texture==texture,"activity preview uses item artwork: "+str(action.id))
		row.free()
	print("Scribing icons: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
