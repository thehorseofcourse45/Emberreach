extends Node
var checks := 0
var failures := 0
func check(v: bool, msg: String) -> void:
	checks += 1
	if not v:
		failures += 1
		print("FAIL: ", msg)
func find_button(node: Node, label: String) -> Button:
	if node is Button and str(node.text) == label: return node
	for child in node.get_children():
		var found := find_button(child, label)
		if found != null: return found
	return null
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	call_deferred("run")
func run() -> void:
	var low := "chicken_coop"
	var high := "cinder_bastion_depths"
	check(PlayerData.dungeon_mastery_eligible(low), "regular dungeon eligible")
	check(PlayerData.dungeon_mastery_eligible(high), "high regular dungeon eligible")
	check(not PlayerData.dungeon_mastery_eligible("infernal_crucible"), "raid excluded")
	check(not PlayerData.dungeon_mastery_eligible("worldheart_citadel"), "stronghold excluded")
	check(PlayerData.dungeon_mastery_repeat_reward(low).is_empty(), "early dungeon has no catalyst per clear")
	check(int(PlayerData.dungeon_mastery_repeat_reward(high).get("enchant_catalyst", 0)) > 0, "high dungeon grants catalyst")
	check(not PlayerData.claim_dungeon_mastery(low, 0), "unearned milestone cannot be claimed")
	PlayerData.completion_log.dungeons[low] = true
	check(PlayerData.dungeon_mastery_clears(low) == 1, "legacy completion counts as one")
	var before: int = BankManager.get_total_owned("silver_bar")
	check(PlayerData.claim_dungeon_mastery(low, 0), "legacy milestone claim succeeds")
	check(BankManager.get_total_owned("silver_bar") == before + 1, "milestone pays reward")
	check(not PlayerData.claim_dungeon_mastery(low, 0), "milestone cannot be claimed twice")
	var saved: Dictionary = PlayerData.serialize()
	PlayerData.deserialize(saved)
	check(PlayerData.dungeon_mastery_claimed(low, 0), "claim survives save round trip")
	check(not PlayerData.claim_dungeon_mastery(low, 0), "reload cannot duplicate reward")
	var old: Dictionary = PlayerData.serialize()
	old.stats.erase("dungeon_mastery_claimed")
	old.stats.dungeons_cleared.erase(high)
	old.completion_log.dungeons[high] = true
	PlayerData.deserialize(old)
	check(PlayerData.dungeon_mastery_clears(high) == 1, "old save recovers first-clear progress")
	check(not PlayerData.dungeon_mastery_claimed(high, 0), "old save can claim its milestone")
	var qty: int = int(PlayerData.dungeon_mastery_repeat_reward(high).enchant_catalyst)
	var prior: int = BankManager.get_total_owned("enchant_catalyst")
	SimulationMode.begin()
	CombatManager.context = {"type": "dungeon", "id": high, "monsters": [], "index": 0}
	CombatManager._complete_combat()
	check(PlayerData.dungeon_mastery_clears(high) == 2, "new clear adds to legacy first clear")
	check(BankManager.get_total_owned("enchant_catalyst") >= prior + qty, "offline-style clear grants catalyst")
	check(int(SimulationMode.get_table(SimulationMode.BUCKET_ITEMS_PRODUCED).get("enchant_catalyst", 0)) >= qty, "offline summary records catalyst")
	SimulationMode.end()
	PlayerData.stats.dungeons_cleared[high] = 25
	for i in range(PlayerData.DUNGEON_MASTERY_THRESHOLDS.size()):
		var reward: Dictionary = PlayerData.dungeon_mastery_reward(high, i)
		var old_count: int = BankManager.get_total_owned(str(reward.item_id))
		check(PlayerData.claim_dungeon_mastery(high, i), "earned milestone %d claims" % i)
		check(BankManager.get_total_owned(str(reward.item_id)) == old_count + int(reward.quantity), "milestone %d pays exactly" % i)
		check(not PlayerData.claim_dungeon_mastery(high, i), "milestone %d is idempotent" % i)
	var sources: Array = Goals.sources_for_item("enchant_catalyst")
	var found := false
	for source in sources:
		if str(source.get("kind", "")) == "dungeon_mastery": found = true
	check(found, "catalyst source lists dungeon mastery")
	PlayerData.stats.dungeons_cleared[low] = 5
	check(PlayerData.claim_dungeon_mastery(low, 0), "first milestone is claimed before UI test")
	var panel = load("res://scripts/ui/panels/CombatPanel.gd").new()
	add_child(panel)
	panel.focus_route({"area_id": low})
	var button := find_button(panel, "Claim")
	check(button != null, "dungeon screen offers earned milestone")
	if button != null:
		button.pressed.emit()
		check(PlayerData.dungeon_mastery_claimed(low, 1), "claim button awards correct milestone")
	panel.queue_free()
	await get_tree().process_frame
	print("DUNGEON MASTERY: ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
