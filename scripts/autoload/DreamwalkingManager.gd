extends Node
## Offline hours are allocated once by OfflineProgression; no online XP source.
var dreamscape: String = "meadow"
var share: float = 0.0
var next_essence_bonus: float = 0.0
var essence_fraction: float = 0.0
var events: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func dream(id: String) -> Dictionary:
	for def in DataLoader.new_skill_systems.get("dreams", []):
		if str(def.id) == id:
			return def
	return {}

func select(id: String, fraction: float) -> bool:
	var def: Dictionary = dream(id)
	if def.is_empty() or PlayerData.get_level("dreamwalking") < int(def.level) or not is_finite(fraction):
		return false
	dreamscape = id
	share = clampf(fraction, 0.0, 1.0)
	return true

func allocated_share() -> float:
	var def: Dictionary = dream(dreamscape)
	return share if not def.is_empty() and PlayerData.get_level("dreamwalking") >= int(def.level) else 0.0

func prepare_draught(item_id: String) -> bool:
	if item_id != "potion_dreamwalking" or not BankManager.has_item(item_id, 1):
		return false
	BankManager.remove_item(item_id, 1)
	next_essence_bonus = 15.0
	EventBus.notify("Lucid Draught prepared for your next offline dream.", "success")
	return true

func advance_offline(seconds: float, advance_buffs: bool = false) -> Dictionary:
	var result: Dictionary = {"seconds": 0.0, "essence": 0, "nightmare_loss": 0, "events": 0}
	var def: Dictionary = dream(dreamscape)
	if not is_finite(seconds) or seconds <= 0.0 or def.is_empty() or PlayerData.get_level("dreamwalking") < int(def.level):
		return result
	seconds = minf(seconds, OfflineProgression.MAX_CAP_HOURS * 3600.0)
	result.seconds = seconds
	var mastery: int = MasteryManager.get_level("dreamwalking", dreamscape)
	var depth_cap: float = 12.0 * (1.0 + ModifierManager.get_modifier("dreamwalking_depth_percent") / 100.0) + float(mastery - 1) / 99.0
	var total_xp: float = 0.0
	var essence: float = essence_fraction
	var elapsed: float = 0.0
	while elapsed < seconds:
		var slice: float = minf(3600.0, seconds - elapsed)
		if advance_buffs:
			for buff in InscriptionManager.buffs.values():
				slice = minf(slice, maxf(0.001, float(buff.remaining)))
		var depth: float = 1.0 + minf(depth_cap, maxf(0.0, (elapsed + slice * 0.5) / 3600.0 - 1.0)) / 12.0
		total_xp += float(def.xp_hour) * slice / 3600.0 * depth * ModifierManager.get_skill_xp_multiplier("dreamwalking")
		essence += float(def.essence_hour) * slice / 3600.0 * depth * (1.0 + float(mastery - 1) / 500.0 + (ModifierManager.get_modifier("dreamwalking_essence_percent") + next_essence_bonus) / 100.0)
		elapsed += slice
		if advance_buffs:
			OfflineProgression._advance_passive_clocks(slice)
	var gain: int = floori(essence)
	essence_fraction = essence - gain
	if seconds >= 21600.0 and ModifierManager.get_modifier("dreamwalking_nightmare_immunity") <= 0.0 and _rng.randf() < maxf(0.01, 0.10 - float(mastery - 1) / 1200.0):
		result.nightmare_loss = floori(gain * 0.1)
		gain -= int(result.nightmare_loss)
	BankManager.add_item_guaranteed("dream_essence", gain)
	SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, "dream_essence", gain)
	PlayerData.add_xp("dreamwalking", total_xp)
	MasteryManager.add_mastery_xp("dreamwalking", dreamscape, seconds, ModifierManager.get_mastery_xp_bonus("dreamwalking"))
	SummoningManager.on_action("dreamwalking", seconds / 60.0)
	PetManager.roll_for_skill("dreamwalking", seconds)
	next_essence_bonus = 0.0
	if seconds >= 3600.0 and events.size() < 10 and (_rng.randf() < 0.35 or ModifierManager.get_modifier("dreamwalking_event_guarantee") > 0.0):
		var shadow: bool = _rng.randf() < 0.5
		events.append({"kind": "shadow" if shadow else "garden", "text": "A shadow offers you lucidity in exchange for a tenth of your Dream Essence." if shadow else "A sleeping gardener offers a basket of fertile dreamsoil."})
		result.events = 1
	result.essence = gain
	return result

func resolve_event(index: int, accept: bool) -> bool:
	if index < 0 or index >= events.size():
		return false
	var event: Dictionary = events[index]
	events.remove_at(index)
	if str(event.kind) == "shadow" and accept:
		var paid: int = floori(BankManager.get_count("dream_essence") * 0.1)
		if paid > 0:
			BankManager.remove_item("dream_essence", paid)
		PlayerData.add_xp("dreamwalking", 500.0)
	elif str(event.kind) == "garden" and accept:
		BankManager.add_item_guaranteed("ranch_manure", 5)
	else:
		BankManager.add_item_guaranteed("dream_essence", 10)
	EventBus.state_refreshed.emit()
	return true

func buy(id: String) -> bool:
	for offer in DataLoader.new_skill_systems.get("bazaar", []):
		if str(offer.id) != id:
			continue
		if not BankManager.has_item("dream_essence", int(offer.cost)):
			return false
		BankManager.remove_item("dream_essence", int(offer.cost))
		if offer.has("mods"):
			InscriptionManager.activate_buff("dream_" + id, offer.mods, float(offer.seconds))
		for item_id in (offer.get("items", {}) as Dictionary):
			BankManager.add_item_guaranteed(str(item_id), int(offer.items[item_id]))
		for _tick in range(int(offer.get("town_ticks", 0))):
			TownshipManager.produce_tick()
		EventBus.state_refreshed.emit()
		return true
	return false

func serialize() -> Dictionary:
	return {"dreamscape": dreamscape, "share": share, "next_essence_bonus": next_essence_bonus, "essence_fraction": essence_fraction, "events": events.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	dreamscape = str(data.get("dreamscape", "meadow"))
	if dream(dreamscape).is_empty():
		dreamscape = "meadow"
	var fraction: float = float(data.get("share", 0.0))
	share = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0
	next_essence_bonus = clampf(float(data.get("next_essence_bonus", 0.0)), 0.0, 15.0)
	essence_fraction = clampf(float(data.get("essence_fraction", 0.0)), 0.0, 0.999999)
	events = data.get("events", []).duplicate(true).slice(0, 10) if typeof(data.get("events", [])) == TYPE_ARRAY else []

func preview(offline_seconds: float) -> Dictionary:
	var def: Dictionary = dream(dreamscape)
	var seconds: float = maxf(0.0, minf(offline_seconds, OfflineProgression.MAX_CAP_HOURS * 3600.0)) * allocated_share()
	var mastery: int = MasteryManager.get_level("dreamwalking", dreamscape)
	var cap: float = 12.0 * (1.0 + ModifierManager.get_modifier("dreamwalking_depth_percent") / 100.0) + float(mastery - 1) / 99.0
	var elapsed: float = 0.0
	var weighted: float = 0.0
	while elapsed < seconds:
		var slice: float = minf(3600.0, seconds - elapsed)
		weighted += slice / 3600.0 * (1.0 + minf(cap, maxf(0.0, (elapsed + slice * 0.5) / 3600.0 - 1)) / 12.0)
		elapsed += slice
	var expected: float = float(def.get("essence_hour", 0)) * weighted * (1.0 + float(mastery - 1) / 500.0 + (ModifierManager.get_modifier("dreamwalking_essence_percent") + next_essence_bonus) / 100.0)
	if seconds >= 21600 and ModifierManager.get_modifier("dreamwalking_nightmare_immunity") <= 0: expected *= 1.0 - maxf(0.01, 0.1 - float(mastery - 1) / 1200.0) * 0.1
	return {"seconds": seconds, "xp": float(def.get("xp_hour", 0)) * weighted * ModifierManager.get_skill_xp_multiplier("dreamwalking"), "essence": expected}
