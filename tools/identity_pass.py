#!/usr/bin/env python3
"""Identity pass: replace Melvor-derived / RuneScape-derived player-facing text in res://data.

Why a script instead of hand edits:
  * 380 items, 29 skills, 29 monsters, 12 regions, 11 dungeons and 24 prayers share naming
    roots (metal tiers, material families). A mapping table is reviewable, repeatable and
    cannot drift between files.
  * STABLE IDENTIFIERS ARE PRESERVED. This script never touches an `id` value, a dictionary
    key, or any numeric field. Saves and the 380 icon files stay valid; only `name`,
    `description` and the new `flavour` fields change.

Run:  python tools/identity_pass.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"

# --------------------------------------------------------------------------------------
# Setting
# --------------------------------------------------------------------------------------
# Emberreach: a frontier settlement on the edge of an ash-choked wilderness. The player
# rebuilds it by gathering, trading, exploring and fighting. Naming roots:
#   * metals  -> Verdigris / Wrought / Crucible / Blighted / Ghoststeel / Skyiron /
#                Starforged / Wyrmsteel
#   * people  -> Cinderkin (ash-touched raiders, replaces the borrowed "golbin")
#   * gods    -> Wardens of Gales / Tides / Stone / Embers

SKILL_NAMES = {
    "attack": "Bladework",
    "strength": "Might",
    "defence": "Warding",
    "hitpoints": "Vitality",
    "ranged": "Marksmanship",
    "magic": "Sorcery",
    "prayer": "Devotion",
    "slayer": "Huntsman",
    "corruption": "Blight",
    "woodcutting": "Timbercraft",
    "fishing": "Angling",
    "mining": "Delving",
    "farming": "Husbandry",
    "firemaking": "Kilncraft",
    "cooking": "Cookery",
    "smithing": "Forgecraft",
    "fletching": "Bowyering",
    "crafting": "Artifice",
    "runecrafting": "Glyphcraft",
    "herblore": "Apothecary",
    "thieving": "Larceny",
    "agility": "Wayfaring",
    "summoning": "Beastbinding",
    "astrology": "Starreading",
    "alt_magic": "Runescribing",
    "township": "Settlement",
    "cartography": "Surveying",
    "archaeology": "Excavation",
    "harvesting": "Prospecting",
}

# Old skill display names, used to rewrite references inside other names (e.g. "Mining Cape").
SKILL_OLD_NAMES = {
    "Attack": "Bladework",
    "Strength": "Might",
    "Defence": "Warding",
    "Hitpoints": "Vitality",
    "Ranged": "Marksmanship",
    "Magic": "Sorcery",
    "Prayer": "Devotion",
    "Slayer": "Huntsman",
    "Corruption": "Blight",
    "Woodcutting": "Timbercraft",
    "Fishing": "Angling",
    "Mining": "Delving",
    "Farming": "Husbandry",
    "Firemaking": "Kilncraft",
    "Cooking": "Cookery",
    "Smithing": "Forgecraft",
    "Fletching": "Bowyering",
    "Crafting": "Artifice",
    "Runecrafting": "Glyphcraft",
    "Herblore": "Apothecary",
    "Thieving": "Larceny",
    "Agility": "Wayfaring",
    "Summoning": "Beastbinding",
    "Astrology": "Starreading",
    "Alt. Magic": "Runescribing",
    "Township": "Settlement",
    "Cartography": "Surveying",
    "Archaeology": "Excavation",
    "Harvesting": "Prospecting",
}

AREA_NAMES = {
    "farmlands": ("Hearthfall Fields", "Reclaimed farmland on Emberreach's doorstep. Windfalls and long grass hide the settlement's first real threats."),
    "golbin_village": ("Cinderkin Warrens", "Tunnels of packed ash and scrap iron, dug by the Cinderkin who took this valley while it burned."),
    "graveyard": ("Ashen Barrows", "Stone cairns sink into grey soil. The names cut into them have been worn smooth by the ashfall."),
    "sandy_shores": ("Sunken Strand", "The tide comes in over a drowned road. Whatever walked it still does."),
    "wet_forest": ("Reedwrack Marsh", "Flooded woodland, thigh-deep and loud at night. Lost shrines keep their foundations here."),
    "bandit_hideout": ("Rook's Hollow", "A terraced camp under a broken viaduct, held by the Sable Rooks who tax the only road inland."),
    "icy_hills": ("Frostbound Reach", "Wind-scoured ridges above the treeline. An observatory of black glass sits at the summit."),
    "castle_of_kings": ("Sunderhold Keep", "The frontier's old seat of power, split down the middle by something that came out of the ground."),
    "dragon_valley": ("Ashwyrm Hollow", "A caldera of warm grey slopes where the old wyrms nest in the cooling rock."),
    "spider_slayer_area": ("Broodweb Fen", "Immigration order territory. Every reed is strung. Something is farming the fen."),
    "abyssal_depths": ("The Umbral Deep", "The dark under the frontier. It is not empty, and it is not patient."),
    "abyssal_rift": ("Riftmouth", "A wound in the rock that breathes. The most dangerous place anyone has mapped."),
}

DUNGEON_NAMES = {
    "chicken_coop": ("The Plucked Roost", "Something has been taking the settlement's fowl for weeks. It is bigger than a fox."),
    "undead_graveyard": ("Barrow of Names", "The barrows of Hearthfall have opened. The dead want their names back."),
    "spider_forest": ("Broodweb Warren", "Reedwrack Fen's heart, and the nest that keeps restocking it."),
    "air_god_dungeon": ("Observatory of Gales", "The summit observatory's instruments still turn. Their keeper never left."),
    "water_god_dungeon": ("Tidal Reliquary", "A drowned shrine that surfaces once a season, and never with the same rooms."),
    "earth_god_dungeon": ("Deepstone Sanctum", "The mine that broke the ridge. It goes further down than any survey admits."),
    "fire_god_dungeon": ("Emberthrone Kiln", "The furnace at the root of the ashfall. It is still burning, and it is fed."),
    "into_the_mist": ("Into the Murk", "Follow the ash upstream. The Murk does not let you arrive where you aimed."),
    "impending_darkness": ("The Long Dusk", "Nightfall that never lifts. Cut a path through it or be part of it."),
    "underwater_city": ("Nhalassar, the Drowned City", "A city that chose the water over the fire. It is still lit below."),
    "throne_of_the_herald": ("Seat of the Herald", "Where the ashfall was decided. Everything you have built is the price of stopping it."),
}

MONSTER_NAMES = {
    "chicken": ("Scrub Fowl", "Half-wild fowl that survived the ashfall by being too aggressive to catch."),
    "cow": ("Longhorn Steer", "Frontier cattle, patient and enormous. The horns are not decorative."),
    "golbin": ("Cinderkin Raider", "Ash-touched scavengers. Quick, poorly armoured, and they never raid alone."),
    "zombie_hand": ("Graveclaw", "A hand that kept working after the rest of it stopped."),
    "skeleton": ("Barrowbones", "Cairn debris, walking. The barrows resent being opened."),
    "spider": ("Fen Spinner", "Reed-height and patient. The web is the warning."),
    "bandit": ("Sable Rook", "Road-thieves in dyed leather. They know the viaduct better than you do."),
    "moss_giant": ("Mossbound Colossus", "Old stone that grew a coat and decided to stand up."),
    "guard": ("Sunderhold Sentry", "Still on duty. The orders are older than the settlement."),
    "rune_knight": ("Glyphbound Knight", "Armour written over with binding script. The script is winning."),
    "green_dragon": ("Verdant Wyrm", "Slept through the ashfall under the moss. Waking up irritable."),
    "golbin_chief": ("Cinderkin Warchief", "Leads the Warrens. Wears the settlement's missing anvil as a shield."),
    "air_elemental": ("Gale Wisp", "A pressure change with intent."),
    "air_god": ("Warden of Gales, Sylphine", "Keeper of the summit instruments. She has been waiting for a student, not a challenger."),
    "water_elemental": ("Tide Wisp", "Water that has been told what to do."),
    "water_god": ("Warden of Tides, Marrowen", "Keeps the reliquary's ledger. Everyone's name is in it."),
    "earth_elemental": ("Stone Wisp", "Rock with an opinion."),
    "earth_god": ("Warden of Stone, Delvhar", "He cut the mine that broke the ridge, and he will not explain why."),
    "fire_elemental": ("Ember Wisp", "A coal that learned to move."),
    "fire_god": ("Warden of Embers, Pyrra", "Tends the kiln. Believes the ashfall was the correct price."),
    "mist_wraith": ("Murk Wraith", "Ash and drowned breath, holding a shape out of habit."),
    "the_mist": ("The Murk Incarnate", "The ashfall given a voice. It repeats what you said, later."),
    "dark_herald": ("Herald of the Long Dusk", "Announces the dark the way weather announces rain."),
    "drowned_sailor": ("Barnacled Deckhand", "Kept working the drowned road. Still on shift."),
    "underwater_king": ("Tidewrack King", "Rules Nhalassar's upper terraces and resents the surface."),
    "abyssal_imp": ("Umbral Imp", "Small, fast, and delighted to be here."),
    "abyssal_fiend": ("Umbral Fiend", "The Deep's outrider. Built out of what it has eaten."),
    "abyssal_lord": ("Umbral Lord", "Commands the Deep's attention, which is a job nobody wants."),
    "the_herald": ("The Herald Ascendant", "The ashfall wearing a crown. It has been waiting at the Seat for you."),
}

PRAYER_NAMES = {
    "thick_skin": "Hearthide",
    "burst_of_strength": "Surge of Might",
    "clarity_of_thought": "Clear Thought",
    "sharp_eye": "Keen Sight",
    "mystic_will": "Arcane Will",
    "ultimate_strength": "Unbound Might",
    "stone_skin": "Quarryhide",
    "rock_skin": "Bedrock Ward",
    "steel_skin": "Ironsheen",
    "protect_from_magic": "Ward Against Sorcery",
    "protect_from_ranged": "Ward Against Arrows",
    "protect_from_melee": "Ward Against Steel",
    "protect_item": "Ward the Satchel",
    "holy_aegis": "Sanctified Aegis",
    "eagle_eye": "Farwatcher",
    "mystic_lore": "Arcane Lore",
    "mystic_might": "Arcane Might",
    "piety": "Devout Focus",
}

ITEM_NAMES = {
    # Logs
    "normal_log": "Emberpine Log", "oak_log": "Ironbark Log", "willow_log": "Silverleaf Log",
    "teak_log": "Reedwood Log", "maple_log": "Amberwood Log", "mahogany_log": "Blackgrain Log",
    "yew_log": "Gravewood Log", "magic_log": "Witchpine Log", "redwood_log": "Bloodwood Log",
    # Fish
    "raw_shrimp": "Raw Marsh Shrimp", "shrimp": "Marsh Shrimp",
    "raw_sardine": "Raw Silverfin", "sardine": "Silverfin",
    "raw_herring": "Raw Reedfish", "herring": "Reedfish",
    "raw_trout": "Raw Speckled Trout", "trout": "Speckled Trout",
    "raw_salmon": "Raw Ember Salmon", "salmon": "Ember Salmon",
    "raw_lobster": "Raw Fen Lobster", "lobster": "Fen Lobster",
    "raw_swordfish": "Raw Bladefin", "swordfish": "Bladefin",
    "raw_crab": "Raw Mudcrab", "crab": "Mudcrab",
    "raw_shark": "Raw Gale Shark", "shark": "Gale Shark",
    "raw_cave_fish": "Raw Cavern Char", "cave_fish": "Cavern Char",
    "raw_manta_ray": "Raw Void Ray", "manta_ray": "Void Ray",
    "raw_whale": "Raw Leviathan", "whale": "Leviathan",
    # Ores, bars, essences
    "mithril_ore": "Ghoststeel Ore", "mithril_bar": "Ghoststeel Bar",
    "adamantite_ore": "Skyiron Ore", "adamantite_bar": "Skyiron Bar",
    "runite_ore": "Starforge Ore", "runite_bar": "Starforge Bar",
    "dragonite_ore": "Wyrmsteel Ore", "dragonite_bar": "Wyrmsteel Bar",
    "rune_essence": "Raw Glyph Essence", "pure_essence": "Refined Glyph Essence",
    # Runes
    "air_rune": "Gale Rune", "water_rune": "Tide Rune", "earth_rune": "Stone Rune",
    "fire_rune": "Ember Rune", "mind_rune": "Waking Rune", "chaos_rune": "Discord Rune",
    "death_rune": "Mourning Rune", "blood_rune": "Vital Rune", "nature_rune": "Verdant Rune",
    "law_rune": "Bond Rune", "cosmic_rune": "Astral Rune",
    # Bones, hides, misc materials
    "big_bones": "Heavy Bones", "dragon_bones": "Wyrm Bones",
    "green_dragonhide": "Verdant Wyrmhide", "blue_dragonhide": "Azure Wyrmhide",
    "red_dragonhide": "Crimson Wyrmhide", "black_dragonhide": "Umbral Wyrmhide",
    "garum_herb": "Emberleaf", "garum_herb_seed": "Emberleaf Seed",
    "sourweed": "Sourthistle", "sourweed_seed": "Sourthistle Seed",
    "mantalyme": "Mirebloom", "mantalyme_seed": "Mirebloom Seed",
    "lemontyle": "Goldpetal", "lemontyle_seed": "Goldpetal Seed",
    "oxilyme": "Fenblossom", "oxilyme_seed": "Fenblossom Seed",
    "golbin_thief_mark": "Cinderkin Mark", "dragon_mark": "Wyrm Mark",
    "shard_air": "Gale Shard", "shard_water": "Tide Shard",
    "shard_earth": "Stone Shard", "shard_fire": "Ember Shard",
    "abyssal_essence": "Umbral Essence",
    "summoning_shard_green": "Verdant Binding Shard", "summoning_shard_crimson": "Crimson Binding Shard",
    "summoning_shard_blue": "Azure Binding Shard", "summoning_shard_silver": "Silver Binding Shard",
    "summoning_shard_black": "Umbral Binding Shard", "summoning_shard_gold": "Gilded Binding Shard",
    # Potions
    "potion_dr_1": "Warded Hide I", "potion_dr_2": "Warded Hide II",
    "potion_dr_3": "Warded Hide III", "potion_dr_4": "Warded Hide IV",
    "potion_mining_1": "True Strike I", "potion_mining_2": "True Strike II",
    "potion_mining_3": "True Strike III", "potion_mining_4": "True Strike IV",
    "potion_skilling_1": "Insight I", "potion_skilling_2": "Insight II",
    "potion_skilling_3": "Insight III", "potion_skilling_4": "Insight IV",
    "potion_firemaking_1": "Banked Coals I", "potion_firemaking_2": "Banked Coals II",
    "potion_firemaking_3": "Banked Coals III", "potion_firemaking_4": "Banked Coals IV",
}

# Metal tier prefixes applied to EQUIPMENT names only (word-initial, including after "Superior").
TIER_PREFIXES = {
    "Bronze": "Verdigris",
    "Iron": "Wrought",
    "Steel": "Crucible",
    "Black": "Blighted",
    "Mithril": "Ghoststeel",
    "Adamant": "Skyiron",
    "Rune": "Starforged",
    "Dragon": "Wyrmsteel",
}

# Words that must never survive in player-facing text.
BANNED = ["golbin", "Golbin", "melvor", "Melvor"]

# --------------------------------------------------------------------------------------


def apply_tier_prefix(name: str) -> str:
    for old, new in TIER_PREFIXES.items():
        if name.startswith(old + " "):
            return new + name[len(old):]
        if name.startswith("Superior " + old + " "):
            return "Superior " + new + name[len("Superior " + old):]
    return name


def apply_skill_words(name: str) -> str:
    for old, new in SKILL_OLD_NAMES.items():
        # Word-boundary replace, longest first so "Alt. Magic" beats "Magic".
        name = re.sub(r"(?<![\w.])" + re.escape(old) + r"(?![\w])", new, name)
    return name


def rename_record(rec: dict, exact: dict, is_equipment: bool) -> list[str]:
    """Mutate a record's player-facing fields in place. Returns a list of change notes."""
    changes: list[str] = []
    if "name" in rec and isinstance(rec["name"], str):
        before = rec["name"]
        after = before
        rec_id = str(rec.get("id", ""))
        if rec_id in exact:
            after = exact[rec_id]
        else:
            after = apply_skill_words(after)
            if is_equipment:
                # Tier prefixes apply to each comma-separated variant too.
                after = ", ".join(apply_tier_prefix(part.strip()) for part in after.split(","))
        if after != before:
            rec["name"] = after
            changes.append(f"{rec_id or before}: {before!r} -> {after!r}")
    for field in ("description", "flavour"):
        if field in rec and isinstance(rec[field], str):
            before = rec[field]
            after = apply_skill_words(before)
            after = after.replace("golbin", "Cinderkin").replace("Golbin", "Cinderkin")
            after = after.replace("Melvor", "Emberreach").replace("melvor", "emberreach")
            if after != before:
                rec[field] = after
                changes.append(f"  {field}: {before!r} -> {after!r}")
    return changes


def walk(container, exact: dict, is_equipment: bool, changes: list[str]) -> None:
    """Recursively rename every dictionary that has a 'name' field."""
    if isinstance(container, dict):
        if "name" in container and isinstance(container["name"], str):
            changes.extend(rename_record(container, exact, is_equipment))
        for value in container.values():
            walk(value, exact, is_equipment, changes)
    elif isinstance(container, list):
        for value in container:
            walk(value, exact, is_equipment, changes)


def process(filename: str, exact: dict, is_equipment_all: bool, changes: list[str]) -> None:
    path = DATA / filename
    data = json.loads(path.read_text(encoding="utf-8"))
    comment = data.pop("_comment", None)
    walk(data, exact, is_equipment_all, changes)
    if comment is not None:
        data = {"_comment": comment, **data}
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def scan_banned(changes: list[str]) -> None:
    """Report any surviving banned words so nothing slips through."""
    leftovers = []
    for path in sorted(DATA.glob("*.json")):
        text = path.read_text(encoding="utf-8")
        for word in BANNED:
            if word in text:
                for m in re.finditer(r'.{0,60}' + re.escape(word) + r'.{0,60}', text):
                    leftovers.append(f"{path.name}: ...{m.group(0)}...")
    if leftovers:
        print("REMAINING banned text:")
        for line in leftovers[:40]:
            print("  " + line.replace("\n", " "))
    else:
        print("No banned text remains in res://data.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.dry_run:
        print("Dry run: set the mapping tables above; nothing is written.")
        return 0

    changes: list[str] = []

    # 1. Skills: ids and every level_requirement reference stay untouched; only names change.
    process("skills.json", {}, False, changes)
    skills_path = DATA / "skills.json"
    skills = json.loads(skills_path.read_text(encoding="utf-8"))
    for skill_id, new_name in SKILL_NAMES.items():
        if skill_id in skills and isinstance(skills[skill_id], dict):
            old = skills[skill_id].get("name")
            if old != new_name:
                skills[skill_id]["name"] = new_name
                changes.append(f"skill {skill_id}: {old!r} -> {new_name!r}")
    skills_path.write_text(json.dumps(skills, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # 2. Regions & dungeons get names plus flavour text.
    for filename, mapping in (("areas.json", AREA_NAMES), ("dungeons.json", DUNGEON_NAMES)):
        path = DATA / filename
        data = json.loads(path.read_text(encoding="utf-8"))
        for key, (new_name, flavour) in mapping.items():
            if key in data and isinstance(data[key], dict):
                old = data[key].get("name")
                data[key]["name"] = new_name
                if "flavour" not in data[key]:
                    data[key]["flavour"] = flavour
                changes.append(f"{filename} {key}: {old!r} -> {new_name!r}")
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # Keep a stable key order for monsters: rebuild with the original key order.
    monsters_path = DATA / "monsters.json"
    monsters = json.loads(monsters_path.read_text(encoding="utf-8"))
    ordered = {}
    for key, rec in monsters.items():
        if isinstance(rec, dict) and key in MONSTER_NAMES:
            new_name, flavour = MONSTER_NAMES[key]
            old = rec.get("name")
            rec["name"] = new_name
            if "flavour" not in rec:
                rec["flavour"] = flavour
            if old != new_name:
                changes.append(f"monster {key}: {old!r} -> {new_name!r}")
        ordered[key] = rec
    monsters_path.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # 3. Prayers.
    prayers_path = DATA / "prayers.json"
    prayers = json.loads(prayers_path.read_text(encoding="utf-8"))
    for prayer_id, new_name in PRAYER_NAMES.items():
        if prayer_id in prayers and isinstance(prayers[prayer_id], dict):
            old = prayers[prayer_id].get("name")
            prayers[prayer_id]["name"] = new_name
            if old != new_name:
                changes.append(f"prayer {prayer_id}: {old!r} -> {new_name!r}")
    prayers_path.write_text(json.dumps(prayers, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # 4. Items: exact overrides plus tiered equipment prefixes and skill-word references.
    items_path = DATA / "items.json"
    items = json.loads(items_path.read_text(encoding="utf-8"))
    for item_id, rec in items.items():
        if not isinstance(rec, dict):
            continue
        is_equipment = str(rec.get("item_type", "")) == "equipment"
        changes.extend(rename_record(rec, ITEM_NAMES, is_equipment))
    items_path.write_text(json.dumps(items, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # 5. Everything else (obstacles, familiars, pets, constellations, shop, township,
    #    harvesting veins, cartography, archaeology, slayer tasks).
    for filename in ("obstacles.json", "familiars.json", "pets.json", "constellations.json",
                     "shop.json", "shop_township.json", "slayer_tasks.json",
                     "harvesting_veins.json", "cartography_hexes.json",
                     "archaeology_sites.json", "raid_shop.json", "special_attacks.json"):
        process(filename, {}, False, changes)

    print(f"{len(changes)} player-facing strings renamed.")
    for line in changes[:25]:
        print("  " + line)
    if len(changes) > 25:
        print(f"  ... and {len(changes) - 25} more")
    scan_banned(changes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
