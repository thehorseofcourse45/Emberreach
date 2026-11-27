extends RefCounted
## Describes the same data and constants consumed by live and simulated combat.
static func passive(id: String) -> String:
	match id:
		"armored": return "Armored: reduces each landed hit by up to half."
		"regeneration": return "Regeneration: heals 2% of maximum HP after each of its attacks."
		"lifedrain": return "Lifedrain: heals 30% of damage dealt by its hits."
		"leech": return "Leech: heals 25% of damage dealt by its hits."
		"thorns": return "Thorns: reflects 10% of damage taken while it survives."
		"enrage": return "Enrage: hits 50% harder at or below 25% HP."
		"rage": return "Rage: damage increases as its HP falls."
		"veil": return "Veil: gains 15 evasion rating."
		"venomous": return "Venomous: damaging hits have a 25% chance to poison."
	return id.capitalize()

static func phase_effects(effects: Dictionary) -> String:
	var parts: Array[String] = []
	if effects.has("attack_speed_multiplier"):
		parts.append("attacks %.0f%% faster" % ((float(effects.attack_speed_multiplier) - 1.0) * 100.0))
	if effects.has("max_hit_multiplier"):
		parts.append("maximum hit increases %.0f%%" % ((float(effects.max_hit_multiplier) - 1.0) * 100.0))
	if effects.has("attack_type"): parts.append("switches to " + str(effects.attack_type) + " attacks")
	for id in effects.get("add_passives", []): parts.append("gains " + passive(str(id)).trim_suffix("."))
	var status: Dictionary = effects.get("apply_status", {})
	if not status.is_empty():
		var description := "applies %s for %.1f seconds" % [str(status.get("id", "status")), float(status.get("duration", 3.0))]
		if float(status.get("damage_per_tick", 0.0)) > 0.0: description += " (%.1f damage per tick)" % float(status.damage_per_tick)
		parts.append(description)
	return "; ".join(parts)

static func describe(monster: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var weak: Array = monster.get("weak_to", [])
	var resist: Array = monster.get("resists", [])
	if not weak.is_empty(): lines.append("Weak to %s: +25%% damage from that style." % ", ".join(weak))
	if not resist.is_empty(): lines.append("Resists %s: -25%% damage from that style." % ", ".join(resist))
	for id in monster.get("passives", []): lines.append(passive(str(id)))
	if not bool(monster.get("can_be_stunned", true)): lines.append("Immune to stun.")
	if bool(monster.get("is_immune_to_effects", false)): lines.append("Immune to player-applied status effects.")
	for id in monster.get("special_attacks", []):
		var special: Dictionary = DataLoader.get_special_attack(str(id))
		if special.is_empty(): continue
		var text: String = "Special: %s (up to %.0f%% chance per landed attack" % [str(special.get("name", id)), float(special.get("trigger_chance", 10.0))]
		text += "; specials are checked in order). %.2fx damage" % float(special.get("damage_multiplier", 1.0))
		if str(special.get("applies_status", "")) != "": text += "; may apply " + str(special.applies_status) + " for %.1fs" % float(special.get("status_duration", 3.0))
		lines.append(text + ".")
	for phase in monster.get("phases", []):
		if not phase is Dictionary: continue
		var changes := phase_effects(phase.get("effects", {}))
		if changes != "": lines.append("At %d%% HP — %s: %s." % [int(phase.get("at_hp_percent", 0)), str(phase.get("name", "Phase")), changes])
	return lines
