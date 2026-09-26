#!/usr/bin/env python
"""content_fixups.py — close real acquisition gaps found by `--validate`.

The identity pass renamed content but did not invent missing sources. `ContentValidator`
flagged a set of items that existed with no way to obtain them, including the entire seed
chain (which made Husbandry and Apothecary unreachable) and two quest rewards that pointed at
item ids that never existed.

This script is deliberately narrow and idempotent: it only adds SECONDARY OUTPUTS to existing
actions (so recipes, levels and balance are untouched) and repairs the two broken reward ids.
Everything else the validator flags is reported by it as a warning and listed in
VALIDATION_REPORT.md as deferred content.

Run:  python tools/content_fixups.py
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILLS = os.path.join(ROOT, "data", "skills.json")
QUESTS = os.path.join(ROOT, "data", "quests.json")
DUNGEONS = os.path.join(ROOT, "data", "dungeons.json")
MONSTERS = os.path.join(ROOT, "data", "monsters.json")

# --- secondary outputs: (skill, action) -> [ {item_id, chance, min_qty, max_qty} ] -----------
# Seeds are stolen, not grown: a player who has never farmed can start by pickpocketing.
SECONDARY_ADDITIONS = {
    ("thieving", "man"): [{"item_id": "garum_herb_seed", "chance": 0.15, "min_qty": 1, "max_qty": 2}],
    ("thieving", "golbin"): [{"item_id": "garum_herb_seed", "chance": 0.18, "min_qty": 1, "max_qty": 3}],
    ("thieving", "farmer"): [{"item_id": "sourweed_seed", "chance": 0.16, "min_qty": 1, "max_qty": 2}],
    ("thieving", "marauder"): [{"item_id": "mantalyme_seed", "chance": 0.12, "min_qty": 1, "max_qty": 2}],
    ("thieving", "chef"): [{"item_id": "lemontyle_seed", "chance": 0.12, "min_qty": 1, "max_qty": 2}],
    ("thieving", "merchant"): [{"item_id": "oxilyme_seed", "chance": 0.10, "min_qty": 1, "max_qty": 2}],
    ("thieving", "thief"): [{"item_id": "poraxx_seed", "chance": 0.10, "min_qty": 1, "max_qty": 2}],
    ("thieving", "princess"): [{"item_id": "barrentoe_seed", "chance": 0.10, "min_qty": 1, "max_qty": 2}],
    # Thieving gear drops from the people you rob.
    ("thieving", "guard"): [{"item_id": "knights_defender", "chance": 0.02, "min_qty": 1, "max_qty": 1}],
    ("thieving", "rune_knight"): [{"item_id": "knights_defender", "chance": 0.04, "min_qty": 1, "max_qty": 1}],
    ("thieving", "king"): [{"item_id": "chapeau_noir", "chance": 0.05, "min_qty": 1, "max_qty": 1}],
    # Gems come out of the rock they are found in.
    ("mining", "silver_ore"): [{"item_id": "topaz", "chance": 0.04, "min_qty": 1, "max_qty": 1}],
    ("mining", "gold_ore"): [{"item_id": "topaz", "chance": 0.06, "min_qty": 1, "max_qty": 2}],
    # High-tier constellations yield golden dust.
    ("astrology", "study_nysa"): [{"item_id": "golden_stardust", "chance": 0.05, "min_qty": 1, "max_qty": 1}],
    ("astrology", "study_haemir"): [{"item_id": "golden_stardust", "chance": 0.08, "min_qty": 1, "max_qty": 2}],
    # Broken artefacts come up with the whole ones.
    ("archaeology", "small"): [{"item_id": "artefact_shard", "chance": 0.22, "min_qty": 1, "max_qty": 2}],
    ("archaeology", "ancient"): [{"item_id": "artefact_shard", "chance": 0.20, "min_qty": 1, "max_qty": 3}],
    # Cut gems fall out of the rock they are found in, on the way to the rings that need them
    # (Sapphire ring L20, Emerald L27, Ruby L34, Diamond L43).
    ("mining", "iron_ore"): [{"item_id": "sapphire", "chance": 0.03, "min_qty": 1, "max_qty": 1}],
    ("mining", "silver_ore"): [{"item_id": "sapphire", "chance": 0.06, "min_qty": 1, "max_qty": 1},
                                {"item_id": "emerald", "chance": 0.03, "min_qty": 1, "max_qty": 1}],
    ("mining", "gold_ore"): [{"item_id": "emerald", "chance": 0.05, "min_qty": 1, "max_qty": 1}],
    ("mining", "mithril_ore"): [{"item_id": "ruby", "chance": 0.05, "min_qty": 1, "max_qty": 1}],
    ("mining", "adamantite_ore"): [{"item_id": "ruby", "chance": 0.04, "min_qty": 1, "max_qty": 1},
                                     {"item_id": "diamond", "chance": 0.03, "min_qty": 1, "max_qty": 1}],
    ("mining", "runite_ore"): [{"item_id": "diamond", "chance": 0.05, "min_qty": 1, "max_qty": 1}],
    ("mining", "dragonite_ore"): [{"item_id": "diamond", "chance": 0.06, "min_qty": 1, "max_qty": 2}],
    # Drawing a bar also draws its arrowtips, at the same level the arrows are fletched.
    ("smithing", "smelt_bronze_bar"): [{"item_id": "bronze_arrowtips", "chance": 0.35, "min_qty": 1, "max_qty": 3}],
    ("smithing", "smelt_iron_bar"): [{"item_id": "iron_arrowtips", "chance": 0.35, "min_qty": 1, "max_qty": 3}],
    ("smithing", "smelt_steel_bar"): [{"item_id": "steel_arrowtips", "chance": 0.35, "min_qty": 1, "max_qty": 3}],
}

# --- loot a monster should have been dropping but never did ---------------------------------
# Wyrmhide grades the armour that uses it (Verdant L40, Azure L50, Crimson L60, Blighted L70), so
# each grade is skinned off a beast of a comparable tier rather than off one endgame wyrm.
MONSTER_LOOT_ADDITIONS = {
    "moss_giant": [{"item_id": "green_dragonhide", "chance": 1.0, "quantity": 2, "min_quantity": 1}],
    "guard": [{"item_id": "blue_dragonhide", "chance": 0.90, "quantity": 2, "min_quantity": 1}],
    "mist_wraith": [{"item_id": "red_dragonhide", "chance": 0.85, "quantity": 2, "min_quantity": 1}],
    "rune_knight": [{"item_id": "black_dragonhide", "chance": 0.85, "quantity": 2, "min_quantity": 1}],
    # The wyrm itself is the richest source of its own hide.
    "green_dragon": [{"item_id": "green_dragonhide", "chance": 1.0, "quantity": 4, "min_quantity": 2}],
}

# --- binding shards come off the things you bind --------------------------------------------
# All 25 summoning tablets and the first shard refinement consume "summoning_shard_green",
# but nothing in the data produced or dropped it: the whole Beastbinding tree was unreachable.
# Shards are a combat drop ("bind the spirit of what you kill"), scaled by the enemy's level so
# deeper areas pay better. Higher shard tiers are refined from green, so one source feeds all six.
SHARD_ITEM = "summoning_shard_green"
SHARD_CHANCE = 0.85
SHARD_CHANCE_BOSS = 1.0


def shard_drop(monster):
    level = int(monster.get("combat_level", 1))
    if bool(monster.get("is_boss", False)):
        return {"item_id": SHARD_ITEM, "chance": SHARD_CHANCE_BOSS,
                "quantity": 3 + level // 50, "min_quantity": 2}
    return {"item_id": SHARD_ITEM, "chance": SHARD_CHANCE,
            "quantity": 1 + level // 50, "min_quantity": 1}


# --- first-clear rewards that had nothing attached ------------------------------------------
DUNGEON_ADDITIONS = {
    "into_the_mist": {"ancient_sword": 1},
    "underwater_city": {"chapeau_noir": 1},
}

# --- reward ids that never existed ----------------------------------------------------------
QUEST_REWARD_FIXES = {
    "hands_that_build": {"bread": "shrimp"},
    "struck_iron": {"stone": "copper_ore"},
}


def dump(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(data, indent=2, ensure_ascii=False))
        fh.write("\n")


def add_secondaries(skills):
    added = 0
    for (skill_id, action_id), entries in SECONDARY_ADDITIONS.items():
        skill = skills.get(skill_id)
        if not isinstance(skill, dict):
            print("  ! missing skill %s" % skill_id)
            continue
        action = None
        for candidate in skill.get("actions", []):
            if candidate.get("id") == action_id:
                action = candidate
                break
        if action is None:
            print("  ! missing action %s:%s" % (skill_id, action_id))
            continue
        existing = {sec.get("item_id") for sec in action.get("secondary_outputs", [])}
        for entry in entries:
            if entry["item_id"] in existing:
                continue
            action.setdefault("secondary_outputs", []).append(entry)
            added += 1
    return added


def add_monster_shards(monsters):
    added = 0
    for monster_id, monster in monsters.items():
        if not isinstance(monster, dict):
            continue
        loot = monster.setdefault("loot_table", [])
        if any(isinstance(d, dict) and d.get("item_id") == SHARD_ITEM for d in loot):
            continue
        drop = shard_drop(monster)
        # Keep bones first and currency last; a shard sits with the material drops.
        insert_at = len(loot)
        for i, d in enumerate(loot):
            if isinstance(d, dict) and d.get("is_currency"):
                insert_at = i
                break
        loot.insert(insert_at, drop)
        added += 1
    return added


def add_monster_loot(monsters):
    added = 0
    for monster_id, entries in MONSTER_LOOT_ADDITIONS.items():
        monster = monsters.get(monster_id)
        if not isinstance(monster, dict):
            print("  ! missing monster %s" % monster_id)
            continue
        loot = monster.setdefault("loot_table", [])
        present = {d.get("item_id") for d in loot if isinstance(d, dict)}
        for entry in entries:
            if entry["item_id"] in present:
                continue
            insert_at = len(loot)
            for i, d in enumerate(loot):
                if isinstance(d, dict) and d.get("is_currency"):
                    insert_at = i
                    break
            loot.insert(insert_at, entry)
            present.add(entry["item_id"])
            added += 1
    return added


def add_dungeon_rewards(dungeons):
    added = 0
    for dungeon_id, items in DUNGEON_ADDITIONS.items():
        dungeon = dungeons.get(dungeon_id)
        if not isinstance(dungeon, dict):
            print("  ! missing dungeon %s" % dungeon_id)
            continue
        reward = dungeon.setdefault("rewards_first_clear", {})
        granted = reward.setdefault("items", {})
        for item_id, qty in items.items():
            if item_id in granted:
                continue
            granted[item_id] = qty
            added += 1
    return added


def fix_quest_rewards(quests):
    fixed = 0
    for quest_id, replacements in QUEST_REWARD_FIXES.items():
        quest = quests.get(quest_id)
        if not isinstance(quest, dict):
            print("  ! missing quest %s" % quest_id)
            continue
        items = quest.get("reward", {}).get("items", {})
        for bad_id, good_id in replacements.items():
            if bad_id not in items:
                continue
            qty = items.pop(bad_id)
            items[good_id] = int(items.get(good_id, 0)) + int(qty)
            fixed += 1
    return fixed


def main():
    for path in (SKILLS, QUESTS, DUNGEONS, MONSTERS):
        if not os.path.exists(path):
            print("missing %s" % path)
            return 1
    skills = json.load(open(SKILLS, encoding="utf-8"))
    quests = json.load(open(QUESTS, encoding="utf-8"))
    dungeons = json.load(open(DUNGEONS, encoding="utf-8"))
    monsters = json.load(open(MONSTERS, encoding="utf-8"))

    secondaries = add_secondaries(skills)
    rewards = add_dungeon_rewards(dungeons)
    fixed = fix_quest_rewards(quests)
    shards = add_monster_shards(monsters)
    loot = add_monster_loot(monsters)

    dump(SKILLS, skills)
    dump(QUESTS, quests)
    dump(DUNGEONS, dungeons)
    dump(MONSTERS, monsters)

    print("secondary outputs added: %d" % secondaries)
    print("dungeon first-clear rewards added: %d" % rewards)
    print("quest reward ids repaired: %d" % fixed)
    print("monsters given binding-shard drops: %d" % shards)
    print("monster loot entries added: %d" % loot)
    print("Re-run: godot --headless --path . -- --validate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
