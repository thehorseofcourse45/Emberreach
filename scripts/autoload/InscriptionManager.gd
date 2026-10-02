extends Node
## Finite research and consumable texts; buffs share the existing modifier registry.
var researched: Dictionary = {}
var buffs: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func blocker(action: Dictionary) -> String:
	var research: String = str(action.get("research_unlock", ""))
	if research != "" and researched.has(research):
		return "This recipe has already been researched."
	var required: String = str(action.get("requires_research", ""))
	if required != "" and not researched.has(required):
		return "Research this recipe first."
	return ""

func finish_research(action: Dictionary) -> void:
	var id: String = str(action.get("research_unlock", ""))
	if id != "":
		researched[id] = true
		EventBus.notify("Research complete: " + str(action.name), "success")

func quality_outputs(action: Dictionary) -> Dictionary:
	var prefix: String = str(action.get("quality_product", ""))
	if prefix == "":
		return action.get("output_items", {})
	var odds: Dictionary = quality_odds(str(action.id))
	var roll: float = _rng.randf()
	var quality: String = "illuminated" if roll < float(odds.illuminated) else "faded" if roll > 1.0 - float(odds.faded) else "inked"
	return {prefix + "_" + quality: 1}

func use_text(item_id: String, skill_id: String) -> bool:
	var def: Dictionary = DataLoader.get_item(item_id)
	var effect: String = str(def.get("scribe_effect", ""))
	if effect == "" or not DataLoader.skills.has(skill_id) or not BankManager.has_item(item_id, 1):
		return false
	var amount: float = float(def.get("scribe_amount", 0.0))
	if effect == "xp" and PlayerData.get_level(skill_id) >= PlayerData.get_level_cap(skill_id):
		return false
	if effect == "time" and (not SkillManager.running or SkillManager.node_respawn_timer > 0 or SkillManager.stun_timer > 0):
		return false
	if effect == "mastery" and not buffs.has("scribe_mastery_" + skill_id):
		var glyphs: int = 0
		for id in buffs:
			if str(id).begins_with("scribe_mastery_"):
				glyphs += 1
		if glyphs >= 1 + int(ModifierManager.get_modifier("inscription_glyph_slots")):
			return false
	BankManager.remove_item(item_id, 1)
	var duration: float = 3600.0 * (1.0 + ModifierManager.get_modifier("inscription_duration_percent") / 100.0)
	match effect:
		"xp": PlayerData.add_xp(skill_id, amount)
		"time": SkillManager.tick(maxf(0.001, SkillManager.current_interval - SkillManager.progress + 0.001), false)
		"haste": activate_buff("scribe_haste", {"global_skill_interval_percent": amount}, duration)
		"doubling": activate_buff("scribe_doubling", {"global_doubling_percent": amount}, duration)
		"mastery": activate_buff("scribe_mastery_" + skill_id, {skill_id + "_mastery_xp_percent": amount}, duration)
	EventBus.state_refreshed.emit()
	return true

func activate_buff(id: String, mods: Dictionary, seconds: float) -> void:
	buffs[id] = {"mods": mods.duplicate(true), "remaining": seconds}
	ModifierManager.register("text:" + id, mods, "texts", id.capitalize())

func _process(delta: float) -> void:
	if GameManager.is_paused or OfflineProgression.is_running or SimulationMode.is_silent():
		return
	advance(delta / maxf(Engine.time_scale, 0.01))

func advance(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0:
		return
	for id in buffs.keys():
		buffs[id].remaining = float(buffs[id].remaining) - seconds
		if float(buffs[id].remaining) <= 0:
			buffs.erase(id)
			ModifierManager.unregister("text:" + str(id))

func serialize() -> Dictionary:
	return {"researched": researched.duplicate(true), "buffs": buffs.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	ModifierManager.clear_category("texts")
	researched = data.get("researched", {}).duplicate(true) if typeof(data.get("researched", {})) == TYPE_DICTIONARY else {}
	buffs = {}
	var source: Variant = data.get("buffs", {})
	if typeof(source) != TYPE_DICTIONARY:
		return
	for id in source:
		var value: Variant = source[id]
		if typeof(value) != TYPE_DICTIONARY or typeof(value.get("mods", {})) != TYPE_DICTIONARY:
			continue
		var remaining: float = float(value.get("remaining", 0.0))
		if is_finite(remaining) and remaining > 0:
			activate_buff(str(id), value.mods, minf(remaining, 86400.0))

func quality_odds(action_id: String) -> Dictionary:
	var mastery: int = MasteryManager.get_level("inscription", action_id)
	var illuminated: float = clampf(0.02 + float(mastery - 1) / 250.0 + ModifierManager.get_modifier("inscription_quality_percent") / 100.0, 0, 0.8)
	var faded: float = maxf(0.0, 0.15 - float(mastery - 1) / 660.0)
	return {"illuminated": illuminated, "faded": faded, "inked": 1.0 - illuminated - faded}

func text_preview(item_id: String, skill_id: String) -> String:
	var item: Dictionary = DataLoader.get_item(item_id)
	var effect: String = str(item.get("scribe_effect", ""))
	var key: String = "scribe_mastery_" + skill_id if effect == "mastery" else "scribe_" + effect
	var remaining: float = float(buffs.get(key, {}).get("remaining", 0))
	if effect in ["xp", "time"]: return "%s: %s · instant use; does not replace a buff." % [effect.capitalize(), UIStyle.fmt(float(item.get("scribe_amount", 0)))]
	return "%s: %s; lasts %s.%s" % [effect.capitalize(), UIStyle.fmt(float(item.get("scribe_amount", 0))), UIStyle.fmt_duration(3600.0 * (1.0 + ModifierManager.get_modifier("inscription_duration_percent") / 100.0)), " Replaces " + UIStyle.describe_modifier_table(buffs[key].mods) + " (" + UIStyle.fmt_duration(remaining) + " left)." if remaining > 0 else ""]
