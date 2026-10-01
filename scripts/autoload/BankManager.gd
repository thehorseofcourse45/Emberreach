extends Node
## BankManager — stacking storage plus search/sort/sell/protect operations.
##
## Capacity model (deliberate, documented design choice):
##   * Storage has a generous base capacity and expansion is cheap for a long time.
##   * Capacity limits how many DISTINCT stacks you keep, never how much of a stack you hold.
##     So a full bank can never make you lose materials you already collected.
##   * An item that arrives when there is no room for a NEW stack goes to the OVERFLOW ledger
##     instead of being deleted. Overflow is persisted and never dropped. The player is told
##     exactly what is waiting and can withdraw it after freeing or buying space.
##   * Rewards (quests, achievements, dungeon clears, shop grants) use add_item_guaranteed,
##     which bypasses the capacity check by design: a reward must never be lost.
##
## Signal batching: bank_changed fires at most once per frame, so a 20-action offline catch-up
## or a 500-item bulk sale does not trigger 500 full list rebuilds.

const BASE_SLOTS: int = 60
const MAX_SLOT_PRICE: float = 5_000_000.0
const FREE_SLOT_AFTER_PURCHASES: int = 118

# item_id -> quantity
var items: Dictionary = {}
## item_id -> quantity received while storage was at capacity. Never discarded.
var overflow: Dictionary = {}
var purchased_slots: int = 0

var _notify_queued: bool = false
var _full_notice_cooldown: float = 0.0
var _last_full_notice: String = ""

func _process(delta: float) -> void:
	if _full_notice_cooldown > 0.0:
		_full_notice_cooldown = maxf(0.0, _full_notice_cooldown - delta)
	if _notify_queued:
		_notify_queued = false
		EventBus.bank_changed.emit()

## Emit any pending bank change immediately (used by tests and by the offline summary).
func flush_notifications() -> void:
	if _notify_queued:
		_notify_queued = false
		EventBus.bank_changed.emit()

func _queue_notify() -> void:
	_notify_queued = true

# ---------------- capacity ----------------

## Capacity comes from the game mode's `bank_limit` in data/game_modes.json when it is non-zero
## (that value becomes the base capacity, so modes can genuinely differ), plus purchased slots
## and flat modifiers. 0 means "no mode override", so the base capacity applies.
## ponytail: the mode limit is a base, not a hard ceiling — buying a slot is allowed to push
## capacity past it. Clamping on every read would make a purchased slot silently vanish.
func get_slot_limit() -> int:
	var mode_limit: int = int((DataLoader.game_modes.get(PlayerData.game_mode, {}) as Dictionary).get("bank_limit", 0))
	var base: int = mode_limit if mode_limit > 0 else BASE_SLOTS
	return maxi(1, base + purchased_slots + int(ModifierManager.get_modifier(ModifierKeys.BANK_SPACE_FLAT)))

func get_used_slots() -> int:
	return items.size()

func get_free_slots() -> int:
	return maxi(0, get_slot_limit() - get_used_slots())

func is_full() -> bool:
	return get_used_slots() >= get_slot_limit()

func is_over_capacity() -> bool:
	return get_used_slots() > get_slot_limit()

func has_overflow() -> bool:
	return not overflow.is_empty()

func overflow_count() -> int:
	var n: int = 0
	for k in overflow.keys():
		n += int(overflow[k])
	return n

## Cost of the NEXT slot. Curve preserved from the original design, clamped at the maximum.
func next_slot_price() -> float:
	var n: int = purchased_slots
	if n >= FREE_SLOT_AFTER_PURCHASES:
		return MAX_SLOT_PRICE
	var denom: float = pow(142015.0, 163.0 / (122.0 + float(n)))
	var cost: float = floor(132728500.0 * float(n + 2) / denom)
	return minf(maxf(cost, 1.0), MAX_SLOT_PRICE)

func can_buy_slot() -> Dictionary:
	var price: float = next_slot_price()
	if PlayerData.gp < price:
		return {"ok": false, "reason": "Not enough GP (%s needed)" % Goals._fmt(price)}
	return {"ok": true, "reason": ""}

func buy_slot(quantity: int = 1) -> bool:
	var n: int = maxi(1, quantity)
	var total: float = 0.0
	for i in range(n):
		total += _slot_price_for(purchased_slots + i)
	if not PlayerData.spend_gp(total):
		EventBus.notify("Not enough GP — %s needed for %d slot(s)" % [Goals._fmt(total), n], "warn")
		return false
	purchased_slots += n
	_withdraw_overflow_now()
	EventBus.bank_capacity_changed.emit()
	EventBus.notify("Storage expanded by %d (now %d stacks)" % [n, get_slot_limit()], "success")
	return true

func _slot_price_for(index: int) -> float:
	var saved: int = purchased_slots
	purchased_slots = index
	var price: float = next_slot_price()
	purchased_slots = saved
	return price

# ---------------- item ops ----------------

## Add items. Returns the quantity actually stored (0 when a new stack could not be created).
func add_item(item_id: String, quantity: int) -> int:
	if item_id == "" or quantity <= 0:
		return 0
	var stored: int = quantity
	if not items.has(item_id) and is_full():
		# No room for a new stack: hold it in overflow rather than deleting it.
		_add_overflow(item_id, quantity)
		_notice_full(item_id)
		stored = 0
		return stored
	if not items.has(item_id):
		items[item_id] = 0
		PlayerData.discover_item(item_id)
	items[item_id] = maxi(0, int(items[item_id]) + quantity)
	EventBus.item_obtained.emit(item_id, quantity)
	ProgressTracker.record_item_gained(item_id, quantity)
	_queue_notify()
	return stored

## Add items regardless of capacity. Reserved for rewards the player has already earned.
func add_item_guaranteed(item_id: String, quantity: int) -> int:
	if item_id == "" or quantity <= 0:
		return 0
	if not items.has(item_id) and is_full():
		_add_overflow(item_id, quantity)
		return quantity
	return add_item(item_id, quantity)

## Equipment transfers are ownership moves, never fresh lifetime rewards.
func return_item(item_id: String, quantity: int) -> void:
	if quantity <= 0 or DataLoader.get_item(item_id).is_empty(): return
	if not items.has(item_id) and is_full():
		overflow[item_id] = int(overflow.get(item_id, 0)) + quantity
	else:
		items[item_id] = int(items.get(item_id, 0)) + quantity
	_queue_notify()

func _add_overflow(item_id: String, quantity: int) -> void:
	overflow[item_id] = int(overflow.get(item_id, 0)) + quantity
	PlayerData.discover_item(item_id)
	ProgressTracker.record_item_gained(item_id, quantity)
	EventBus.item_obtained.emit(item_id, quantity)
	_queue_notify()

func _notice_full(item_id: String) -> void:
	if _full_notice_cooldown > 0.0 and _last_full_notice == item_id:
		return
	_last_full_notice = item_id
	_full_notice_cooldown = 12.0
	EventBus.notify("Storage is full — %s is waiting in overflow. Expand storage to withdraw it." % DataLoader.get_item(item_id).get("name", item_id), "warn")
	EventBus.bank_capacity_changed.emit()

## Move overflow into the bank wherever there is room. Called after selling or expanding.
func _withdraw_overflow_now() -> void:
	if overflow.is_empty():
		return
	var remaining: Dictionary = {}
	for item_id in overflow.keys():
		var qty: int = int(overflow[item_id])
		if not items.has(item_id) and is_full():
			remaining[item_id] = qty
			continue
		if not items.has(item_id):
			items[item_id] = 0
		items[item_id] = int(items[item_id]) + qty
	overflow = remaining
	if not remaining.is_empty():
		EventBus.notify("Some overflow items still need more storage space.", "info")
	_queue_notify()

func withdraw_overflow(item_id: String = "") -> int:
	var moved: int = 0
	if item_id == "":
		_withdraw_overflow_now()
		return overflow_count()
	if overflow.has(item_id):
		var want: int = int(overflow[item_id])
		if not items.has(item_id) and is_full():
			return 0
		overflow.erase(item_id)
		if not items.has(item_id):
			items[item_id] = 0
		items[item_id] = int(items[item_id]) + want
		moved = want
		_queue_notify()
	return moved

func remove_item(item_id: String, quantity: int) -> bool:
	if item_id == "" or quantity <= 0:
		return false
	if not items.has(item_id) or int(items[item_id]) < quantity:
		return false
	items[item_id] = int(items[item_id]) - quantity
	if int(items[item_id]) <= 0:
		items.erase(item_id)
	EventBus.item_lost.emit(item_id, quantity)
	# Freeing a stack may make room for waiting overflow — never lose it.
	if not overflow.is_empty():
		_withdraw_overflow_now()
	_queue_notify()
	return true

func get_count(item_id: String) -> int:
	return int(items.get(item_id, 0))

## Total owned including overflow — used by dependency explanations so they match reality.
func get_total_owned(item_id: String) -> int:
	return get_count(item_id) + int(overflow.get(item_id, 0))

func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_count(item_id) >= quantity

func can_afford(cost: Dictionary) -> bool:
	for item_id in cost.keys():
		if get_count(str(item_id)) < int(cost[item_id]):
			return false
	return true

## Consume a material bundle atomically: either every entry is removed or none is.
## Returns {ok, reason}. This is what makes "materials are consumed atomically" real.
func consume_bundle(cost: Dictionary) -> Dictionary:
	for item_id in cost.keys():
		var need: int = int(cost[item_id])
		if need <= 0:
			return {"ok": false, "reason": "invalid cost entry '%s'" % item_id}
		if get_count(str(item_id)) < need:
			return {"ok": false, "reason": "missing %s ×%d" % [
				DataLoader.get_item(str(item_id)).get("name", item_id), need - get_count(str(item_id))]}
	# All entries verified — now apply. remove_item cannot fail at this point.
	for item_id in cost.keys():
		remove_item(str(item_id), int(cost[item_id]))
	return {"ok": true, "reason": ""}

# ---------------- protection & selling ----------------

func set_protected(item_id: String, protected: bool = true) -> void:
	if item_id == "":
		return
	if protected:
		PlayerData.protected_items[item_id] = true
	else:
		PlayerData.protected_items.erase(item_id)
	_queue_notify()

func is_protected(item_id: String) -> bool:
	return PlayerData.protected_items.has(item_id)

func toggle_protected(item_id: String) -> bool:
	var now: bool = not is_protected(item_id)
	set_protected(item_id, now)
	return now

# ---------------- favourites ----------------

## Favourites are an organisation aid, not a safety rail. They pin an item to the top of the bank
## and can be filtered for, but they never block a sale: that is what protection is for, and the two
## are independent so a player can bookmark a high-value item without defending it by accident.
func set_favorite(item_id: String, favorite: bool = true) -> void:
	if item_id == "":
		return
	if favorite:
		PlayerData.favorite_items[item_id] = true
	else:
		PlayerData.favorite_items.erase(item_id)
	_queue_notify()

func is_favorite(item_id: String) -> bool:
	return PlayerData.favorite_items.has(item_id)

func toggle_favorite(item_id: String) -> bool:
	var now: bool = not is_favorite(item_id)
	set_favorite(item_id, now)
	return now

func favorite_count() -> int:
	return PlayerData.favorite_items.size()

## Preview an exact transaction before committing to it.
func sell_preview(item_id: String, quantity: int) -> Dictionary:
	var have: int = get_count(item_id)
	var qty: int = have if quantity < 0 else clampi(quantity, 0, have)
	var unit: int = int(DataLoader.get_item(item_id).get("sell_price", 0))
	var mult: float = 1.0 + ModifierManager.get_modifier("global_gp_percent") / 100.0
	return {
		"item_id": item_id,
		"name": DataLoader.get_item(item_id).get("name", item_id),
		"quantity": qty,
		"unit_price": unit,
		"multiplier": mult,
		"gp_gained": float(unit) * float(qty) * mult,
		"remaining": have - qty,
		"protected": is_protected(item_id),
		"equipped": EquipmentManager.is_equipped(item_id),
	}

## Sell items for GP. Refuses protected items and equipped items by default.
func sell_item(item_id: String, quantity: int, allow_protected: bool = false) -> bool:
	if quantity <= 0:
		return false
	if is_protected(item_id) and not allow_protected:
		EventBus.notify("%s is protected — unprotect it first." % DataLoader.get_item(item_id).get("name", item_id), "warn")
		return false
	var have: int = get_count(item_id)
	if have < quantity:
		return false
	var unit: int = int(DataLoader.get_item(item_id).get("sell_price", 0))
	var total: float = float(unit) * float(quantity) * (1.0 + ModifierManager.get_modifier("global_gp_percent") / 100.0)
	if not remove_item(item_id, quantity):
		return false
	ProgressTracker.record_item_sold(item_id, quantity)
	PlayerData.add_gp(total)
	return true

func sell_all(item_id: String, allow_protected: bool = false) -> bool:
	return sell_item(item_id, get_count(item_id), allow_protected)

## Sell every unprotected item matching a filter. Returns {items, gp}.
func sell_many(entries: Array) -> Dictionary:
	var sold_items: int = 0
	var gp: float = 0.0
	for entry in entries:
		var item_id: String = str(entry)
		if item_id == "" or is_protected(item_id):
			continue
		var before: float = PlayerData.gp
		if sell_item(item_id, get_count(item_id)):
			sold_items += 1
			gp += PlayerData.gp - before
	return {"items": sold_items, "gp": gp}

## Bury bones for Prayer Points.
func bury_bone(item_id: String, quantity: int = 1) -> bool:
	var data: Dictionary = DataLoader.get_item(item_id)
	if data.get("item_type", "") != "bone":
		return false
	if quantity <= 0:
		return false
	var points: float = float(data.get("prayer_points", 1)) + ModifierManager.get_modifier(ModifierKeys.BLESSED_BONE_OFFERING_FLAT, 0.0)
	var buried: int = 0
	for _i in range(quantity):
		if not remove_item(item_id, 1):
			break
		PlayerData.add_prayer_points(points)
		buried += 1
	return buried > 0

## Open crates and nests, and hatch eggs, from Storage. A container is only ever spent when
## what it holds has really been handed over, so an opened crate can never silently vanish.
## Returns {ok, opened, items, pet, reason}.
func open_container(item_id: String, quantity: int = 1) -> Dictionary:
	var def: Dictionary = DataLoader.get_item(item_id)
	var granted: Dictionary = def.get("container_items", {}) as Dictionary
	var pet_id: String = str(def.get("container_pet", ""))
	var name: String = str(def.get("name", item_id))
	if quantity <= 0 or (granted.is_empty() and pet_id == ""):
		return {"ok": false, "opened": 0, "items": {}, "pet": "", "reason": "%s is not a container" % name}
	if pet_id != "" and PetManager.is_unlocked(pet_id):
		return {"ok": false, "opened": 0, "items": {}, "pet": "",
			"reason": "%s has already hatched" % name}
	var opened: int = mini(quantity, get_count(item_id))
	if opened <= 0:
		return {"ok": false, "opened": 0, "items": {}, "pet": "", "reason": "No %s in Storage" % name}
	# An egg is a one-off unlock, so hatching one leaves the rest of the stack alone.
	if pet_id != "":
		opened = 1
	var totals: Dictionary = {}
	for grant in granted.keys():
		totals[str(grant)] = int(granted[grant]) * opened
	if not remove_item(item_id, opened):
		return {"ok": false, "opened": 0, "items": {}, "pet": "", "reason": "No %s in Storage" % name}
	for grant in totals.keys():
		add_item_guaranteed(str(grant), int(totals[grant]))
	if pet_id != "":
		PetManager.unlock(pet_id)
	var parts: Array[String] = []
	for grant in totals.keys():
		parts.append("%s x%s" % [DataLoader.get_item(str(grant)).get("name", grant), int(totals[grant])])
	var summary: String = ", ".join(parts)
	EventBus.notify("Opened %s x%d%s" % [name, opened, "" if summary == "" else ": " + summary], "success")
	EventBus.state_refreshed.emit()
	return {"ok": true, "opened": opened, "items": totals, "pet": pet_id, "reason": ""}

# ---------------- queries (bank UI) ----------------

func search(query: String) -> Array:
	var q: String = query.to_lower().strip_edges()
	var out: Array = []
	for item_id in items.keys():
		var data: Dictionary = DataLoader.get_item(item_id)
		var disp: String = data.get("name", item_id)
		if q == "" or disp.to_lower().contains(q) or item_id.to_lower().contains(q):
			out.append(_row(item_id, int(items[item_id]), data))
	return out

func _row(item_id: String, quantity: int, data: Dictionary) -> Dictionary:
	return {
		"item_id": item_id,
		"quantity": quantity,
		"data": data,
		"protected": is_protected(item_id),
		"favorite": is_favorite(item_id),
		"equipped": EquipmentManager.is_equipped(item_id),
		"tracked": Goals.is_pinned("item", item_id),
		"in_overflow": int(overflow.get(item_id, 0)),
		"category": str(data.get("item_type", "misc")),
		"unit_value": int(data.get("sell_price", 0)),
	}

enum SortMode { NAME, QUANTITY, VALUE, TYPE }

func sorted_list(query: String = "", mode: SortMode = SortMode.NAME, ascending: bool = true,
		category_filter: String = "", favorites_only: bool = false) -> Array:
	var list: Array = search(query)
	if category_filter != "" and category_filter != "all":
		list = list.filter(func(r): return str(r["category"]) == category_filter)
	if favorites_only:
		list = list.filter(func(r): return bool(r["favorite"]))
	# Favourites lead in every sort order, including descending: the point of pinning an item is
	# that it stays findable when the bank is long, not that it obeys the sort direction.
	list.sort_custom(func(a, b):
		var fa: bool = bool(a["favorite"])
		var fb: bool = bool(b["favorite"])
		if fa != fb:
			return fa
		var va: Variant
		var vb: Variant
		match mode:
			SortMode.QUANTITY:
				va = a["quantity"]; vb = b["quantity"]
			SortMode.VALUE:
				va = int(a["data"].get("sell_price", 0)); vb = int(b["data"].get("sell_price", 0))
			SortMode.TYPE:
				va = a["data"].get("item_type", ""); vb = b["data"].get("item_type", "")
			_:
				va = a["data"].get("name", a["item_id"]); vb = b["data"].get("name", b["item_id"])
		if va == vb:
			return str(a["item_id"]) < str(b["item_id"])
		return (va < vb) if ascending else (va > vb))
	return list

func category_counts() -> Dictionary:
	var out: Dictionary = {}
	for item_id in items.keys():
		var c: String = str(DataLoader.get_item(item_id).get("item_type", "misc"))
		out[c] = int(out.get(c, 0)) + 1
	return out

# ---------------- persistence ----------------

func serialize() -> Dictionary:
	return {"items": items, "purchased_slots": purchased_slots, "overflow": overflow}

func deserialize(d: Dictionary) -> void:
	items = _sanitize_ledger(d.get("items", {}))
	overflow = _sanitize_ledger(d.get("overflow", {}))
	purchased_slots = maxi(0, int(d.get("purchased_slots", 0)))
	_queue_notify()

## Guarantee non-negative integer quantities and drop unknown ids, so a hand-edited or
## partially-corrupted ledger cannot produce a negative or fractional stack.
func _sanitize_ledger(source: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(source) != TYPE_DICTIONARY:
		return out
	for item_id in (source as Dictionary).keys():
		if not DataLoader.items.has(str(item_id)):
			continue
		var qty: int = int((source as Dictionary)[item_id])
		if qty > 0:
			out[str(item_id)] = qty
	return out
