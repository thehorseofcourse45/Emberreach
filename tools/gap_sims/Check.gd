extends Node
## Gap sims: best-in-slot loadouts at a few levels, every style, against every open-area monster
## from Saltmarch up. Prints one CSV row per (level, style, monster). Read-only on the data.

const LEVELS: Array = [90, 105, 120]
const STYLES: Array = ["melee", "ranged", "magic"]
const AREAS: Array = ["saltmarch_basin", "castle_of_kings", "dragon_valley", "sundered_reaches",
	"drowned_reach", "heralds_march", "abyssal_depths", "abyssal_rift"]
const TRIALS: int = 400
const COMBAT_SKILLS: Array = ["attack", "strength", "defence", "hitpoints", "ranged", "magic", "prayer", "slayer"]

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("run")

func _num(stats: Dictionary, k: String) -> float:
	return float(stats.get(k, 0))

## How much an item helps one style. Offence counts double; defence counts a little everywhere.
func _score(item: Dictionary, style: String) -> float:
	var s: Dictionary = item.get("equipment_stats", {})
	var d: float = (_num(s, "melee_defence") + _num(s, "ranged_defence") + _num(s, "magic_defence")) * 0.3 + _num(s, "damage_reduction") * 3.0
	match style:
		"melee":
			return maxf(maxf(_num(s, "stab"), _num(s, "slash")), _num(s, "crush")) + 2.0 * _num(s, "melee_strength") + d \
				- (50.0 if _num(s, "ranged_attack") + _num(s, "magic_attack") > 0.0 else 0.0)
		"ranged":
			return _num(s, "ranged_attack") + 2.0 * _num(s, "ranged_strength") + d
		_:
			return _num(s, "magic_attack") + 3.0 * _num(s, "magic_damage_percent") + 2.0 * _num(s, "spell_max_hit") + d

func _is_weapon_for(item: Dictionary, style: String) -> bool:
	var s: Dictionary = item.get("equipment_stats", {})
	match style:
		"ranged": return _num(s, "ranged_attack") > 0.0 or item.has("ammo_tier_max")
		"magic": return _num(s, "magic_attack") > 0.0 or item.has("spell_max_hit") or s.has("spell_max_hit")
		_: return maxf(maxf(_num(s, "stab"), _num(s, "slash")), _num(s, "crush")) > 0.0 and _num(s, "ranged_attack") <= 0.0 and _num(s, "magic_attack") <= 0.0

func _loadout(level: int, style: String) -> Dictionary:
	GameManager.start_new_game("standard")
	for sk in COMBAT_SKILLS:
		PlayerData.set_level(sk, level)
	var best: Dictionary = {}   # slot -> [score, id]
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.items[id]
		var slot: int = int(it.get("equipment_slot", -1))
		if slot < 0 or slot > 9 or str(it.get("item_type", "")) != "equipment":
			continue
		if not EquipmentManager._meets_requirements(it):
			continue
		if slot == ItemData.EquipmentSlot.WEAPON and not _is_weapon_for(it, style):
			continue
		var sc: float = _score(it, style)
		if not best.has(slot) or sc > float(best[slot][0]):
			best[slot] = [sc, str(id)]
	var weapon: String = str(best.get(ItemData.EquipmentSlot.WEAPON, [0, ""])[1])
	var two_handed: bool = bool(DataLoader.get_item(weapon).get("is_two_handed", false))
	for slot in best.keys():
		if slot == ItemData.EquipmentSlot.WEAPON or (two_handed and slot == ItemData.EquipmentSlot.SHIELD):
			continue
		BankManager.add_item_guaranteed(str(best[slot][1]), 1)
		EquipmentManager.equip(str(best[slot][1]))
	BankManager.add_item_guaranteed(weapon, 1)
	EquipmentManager.equip(weapon)
	for arrow in ["bronze_arrow", "iron_arrow", "steel_arrow", "mithril_arrow", "adamantite_arrow", "runite_arrow", "dragonite_arrow", "herald_arrow"]:
		if DataLoader.items.has(arrow):
			BankManager.add_item_guaranteed(arrow, 100000)
	for rune_id in DataLoader.items.keys():
		if str(DataLoader.items[rune_id].get("item_type", "")) == "rune":
			BankManager.add_item_guaranteed(str(rune_id), 100000)
	for food in ["shark", "manta_ray", "whale", "dreadfin", "abyssal_eel", "celestial_marlin"]:
		if DataLoader.items.has(food):
			BankManager.add_item_guaranteed(food, 100000)
	CombatManager.attack_style = style
	var gear: Array = []
	for slot in [ItemData.EquipmentSlot.WEAPON, ItemData.EquipmentSlot.SHIELD, 0, 1, 2]:
		gear.append(EquipmentManager.get_equipped(slot))
	return {"weapon": weapon, "gear": gear, "ammo": EquipmentManager.active_ammo() if style == "ranged" else ""}

func _melee_style(weapon: String) -> String:
	var s: Dictionary = DataLoader.get_item(weapon).get("equipment_stats", {})
	var best: String = "slash"
	for k in ["stab", "slash", "crush"]:
		if _num(s, k) > _num(s, best):
			best = k
	return best

func run() -> void:
	print("SIMROW,level,style,area,monster,mlevel,mstyle,deaths%,kills_h,food_h,avg_fight_s,max_hit,accuracy,dr,weapon,ammo")
	for level in LEVELS:
		for style in STYLES:
			var lo: Dictionary = _loadout(int(level), str(style))
			var ms: String = _melee_style(str(lo.weapon)) if style == "melee" else "slash"
			var base: Dictionary = CombatSimulatorManager.build_snapshot("area", "dragon_valley", str(style), ms, false)
			print("LOADOUT,%d,%s,%s,%s" % [level, style, ",".join(lo.gear), lo.ammo])
			for area_id in AREAS:
				var snap_area: Dictionary = CombatSimulatorManager.build_snapshot("area", str(area_id), str(style), ms, false)
				for m in (snap_area.monsters as Array):
					var snap: Dictionary = snap_area.duplicate(true)
					snap.monsters = [m]
					snap.auto_eat_tier = 3
					var r: Dictionary = CombatSimulator.simulate(snap, TRIALS, 1234)
					var mon: Dictionary = DataLoader.get_monster(str(m.id))
					print("SIMROW,%d,%s,%s,%s,%d,%s,%.1f,%.0f,%.0f,%.1f,%s,%s,%s,%s,%s" % [level, style, area_id, m.id,
						int(mon.get("combat_level", 0)), str(m.attack_type),
						100.0 * float(r.get("death_chance", 0.0)), float(r.get("kills_per_hour", 0.0)),
						float(r.get("food_per_hour", 0.0)), float(r.get("average_fight_seconds", 0.0)),
						str(snap.player.max_hit), str(snap.player.accuracy), str(snap.player.damage_reduction),
						lo.weapon, lo.ammo])
	get_tree().quit(0)
