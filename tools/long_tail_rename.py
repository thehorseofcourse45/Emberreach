#!/usr/bin/env python3
"""Long-tail identity pass: rename the remaining Melvor-derived display names in res://data.

Companion to tools/identity_pass.py, which renamed the visible spine (logs, ores, bars,
gear tiers, areas, dungeons). This pass covers what that one missed:

  * verbatim Melvor items (Chapeau Noir, Knight's Defender, the five slayer-area keys,
    Ring of Power, Cape of Completion, the township boxes, the Dragon tool trio)
  * skill action names that still use pre-rename words (tree species, herbs, fish,
    staves, d'hide, the fishing/fletching/crafting actions)
  * the 15 base-game constellations (Melvor's roster)
  * prayers that kept their RuneScape/Melvor wording
  * the pet roster, the familiar roster, and the placeholder "Obstacle N-M" names
  * shop upgrades lifted verbatim (Multi-Tree, the four god upgrades)

Like the original pass: STABLE IDENTIFIERS ARE PRESERVED. No `id` value, dictionary key
or numeric field is ever touched — only `name` values and prose that quotes them. Saves,
icon files and routes keep working.

Run:  python tools/long_tail_rename.py [--dry-run]
Idempotent: a second run reports 0 changes.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"

# --------------------------------------------------------------------------------------
# Record renames: file -> [(old name, new name)], matched as the exact  "name": "old"
# --------------------------------------------------------------------------------------

ITEM_RENAMES: list[tuple[str, str]] = [
    # Verbatim Melvor items
    ("Chapeau Noir", "Duskbrim"),
    ("Knight's Defender", "Sentinel's Defender"),
    ("Blazing Lantern", "Cinder Lantern"),
    ("Magical Ring", "Hexward Ring"),
    ("Desert Hat", "Dustveil Hat"),
    ("Mirror Shield", "Lookingglass Ward"),
    ("Climbing Boots", "Craghooks"),
    ("Ring of Power", "Signet of Force"),
    ("Cape of Completion", "Frontier Laurel"),
    ("Food Box", "Larder Crate"),
    ("Wood Box", "Timber Crate"),
    ("Bar Box", "Ingot Crate"),
    ("Herb Box", "Apothecary Crate"),
    # Wood tier: bows still named after the old log species
    ("Oak Shortbow", "Ironbark Shortbow"), ("Oak Longbow", "Ironbark Longbow"),
    ("Willow Shortbow", "Silverleaf Shortbow"), ("Willow Longbow", "Silverleaf Longbow"),
    ("Yew Shortbow", "Gravewood Shortbow"), ("Yew Longbow", "Gravewood Longbow"),
    ("Magic Shortbow", "Witchpine Shortbow"), ("Magic Longbow", "Witchpine Longbow"),
    ("Redwood Shortbow", "Bloodwood Shortbow"), ("Redwood Longbow", "Bloodwood Longbow"),
    # D'hide long tail: only the black set kept the old abbreviation
    ("Blighted D'hide Body", "Blighted Wyrmhide Body"),
    ("Blighted D'hide Chaps", "Blighted Wyrmhide Chaps"),
    ("Blighted D'hide Vambraces", "Blighted Wyrmhide Vambraces"),
    ("Blighted D'hide Coif", "Blighted Wyrmhide Coif"),
    # Herbs that kept their Melvor names
    ("Poraxx Herb", "Ashcap Herb"), ("Poraxx Seed", "Ashcap Seed"),
    ("Barrentoe Herb", "Gravemoss Herb"), ("Barrentoe Seed", "Gravemoss Seed"),
]

# Familiars: renamed roster -> mark/tablet item names and tablet actions follow.
FAMILIAR_RENAMES: dict[str, str] = {
    "ent": "Oldroot", "mole": "Ashmole", "octopus": "Tidegrasp", "pig": "Sootsow",
    "crow": "Cindercrow", "leprechaun": "Glimmerkin", "monkey": "Riftmonkey",
    "salamander": "Cinderling", "bear": "Ashbear", "devil": "Ashfiend",
    "eagle": "Galecrest", "owl": "Duskwing", "beaver": "Muddam", "fox": "Ashfox",
    "occultist": "Ashcaller", "wolf": "Dustwolf", "minotaur": "Sunderhorn",
    "centaur": "Windhoof", "witch": "Hexweaver", "cyclops": "Stonegaze",
    "yak": "Rimeyak", "unicorn": "Starfoil", "dragon": "Ashwyrm", "tortoise": "Mossback",
}
# dragon's mark is already partially renamed — its current name is "Wyrm Mark", which
# must be aligned with the roster (map holds the CURRENT name, keyed by id).
FAMILIAR_MARK_OVERRIDES: dict[str, str] = {"dragon": "Wyrm Mark"}


def familiar_item_renames() -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for old, new in FAMILIAR_RENAMES.items():
        cap = old.replace("_", " ").title()
        out.append((FAMILIAR_MARK_OVERRIDES.get(old, f"{cap} Mark"), f"{new} Mark"))
        out.append((f"{cap} Tablet", f"{new} Tablet"))
    return out


def familiar_action_renames() -> list[tuple[str, str]]:
    return [(f"{old.replace('_', ' ').title()} Tablet", f"{new} Tablet")
            for old, new in FAMILIAR_RENAMES.items()]


SKILL_RENAMES: list[tuple[str, str]] = [
    # Woodcutting trees (synced to the renamed logs)
    ("Normal Tree", "Emberpine Tree"), ("Oak Tree", "Ironbark Tree"),
    ("Willow Tree", "Silverleaf Tree"), ("Teak Tree", "Reedwood Tree"),
    ("Maple Tree", "Amberwood Tree"), ("Mahogany Tree", "Blackgrain Tree"),
    ("Yew Tree", "Gravewood Tree"), ("Sorcery Tree", "Witchpine Tree"),
    ("Redwood Tree", "Bloodwood Tree"),
    # Fishing actions that never picked up the item rename
    ("Crab", "Mudcrab"), ("Cave Fish", "Cavern Char"),
    ("Manta Ray", "Void Ray"), ("Whale", "Leviathan"),
    # Fletching
    ("Normal Shortbow", "Emberpine Shortbow"), ("Normal Longbow", "Emberpine Longbow"),
    ("Oak Shortbow", "Ironbark Shortbow"), ("Oak Longbow", "Ironbark Longbow"),
    ("Willow Shortbow", "Silverleaf Shortbow"), ("Willow Longbow", "Silverleaf Longbow"),
    ("Yew Shortbow", "Gravewood Shortbow"), ("Yew Longbow", "Gravewood Longbow"),
    ("Magic Shortbow", "Witchpine Shortbow"), ("Magic Longbow", "Witchpine Longbow"),
    ("Redwood Shortbow", "Bloodwood Shortbow"), ("Redwood Longbow", "Bloodwood Longbow"),
    # Crafting d'hide actions
    ("Green D'hide Body", "Verdant Wyrmhide Body"),
    ("Green D'hide Chaps", "Verdant Wyrmhide Chaps"),
    ("Green D'hide Vambraces", "Verdant Wyrmhide Vambraces"),
    ("Green D'hide Coif", "Verdant Wyrmhide Coif"),
    ("Blue D'hide Body", "Azure Wyrmhide Body"),
    ("Blue D'hide Chaps", "Azure Wyrmhide Chaps"),
    ("Blue D'hide Vambraces", "Azure Wyrmhide Vambraces"),
    ("Blue D'hide Coif", "Azure Wyrmhide Coif"),
    ("Red D'hide Body", "Crimson Wyrmhide Body"),
    ("Red D'hide Chaps", "Crimson Wyrmhide Chaps"),
    ("Red D'hide Vambraces", "Crimson Wyrmhide Vambraces"),
    ("Red D'hide Coif", "Crimson Wyrmhide Coif"),
    ("Reinforced D'hide Body", "Blighted Wyrmhide Body"),
    ("Reinforced D'hide Chaps", "Blighted Wyrmhide Chaps"),
    ("Reinforced D'hide Coif", "Blighted Wyrmhide Coif"),
    ("Umbral D'hide Vambraces", "Blighted Wyrmhide Vambraces"),
    # Runecrafting staves
    ("Air Staff", "Gale Staff"), ("Water Staff", "Tide Staff"),
    ("Earth Staff", "Stone Staff"), ("Fire Staff", "Ember Staff"),
    # Farming herbs
    ("Garum", "Emberleaf"), ("Sourweed", "Sourthistle"), ("Mantalyme", "Mirebloom"),
    ("Lemontyle", "Goldpetal"), ("Oxilyme", "Fenblossom"), ("Poraxx", "Ashcap"),
    ("Barrentoe", "Gravemoss"), ("Duskroot", "Hushroot"),
    # Alt. Magic (Melvor's "Superheat Item" verbatim)
    ("Superheat Item", "Superheat Iron"),
    # Summoning tablets (follow the renamed roster)
    *familiar_action_renames(),
]

CONSTELLATION_RENAMES: dict[str, str] = {  # Melvor's 15 base-game constellations
    "deedree": "Vespera", "iridan": "Irielle", "ameria": "Aurelia", "terra": "Loamara",
    "vale": "Vaelith", "syllia": "Serith", "arachi": "Keshari", "ko": "Orrin",
    "tellus": "Petrava", "qimican": "Qimara", "roshaniya": "Rosanyr",
    "ashtar": "Emberine", "variel": "Varrel", "nysa": "Nyssara", "haemir": "Haemros",
    # orison / vex / halcyon are already original
}

PRAYER_RENAMES: list[tuple[str, str]] = [
    ("Clear Thought", "Steady Mind"),
    ("Battleheart", "Ironwill"),
    ("Annihilation", "Ruinfall"),
    ("Rigour", "Steady Aim"),
    ("Augury", "Portent"),
    ("Redemption", "Second Wind"),
    ("Smite", "Wrathfall"),
]

PET_RENAMES: dict[str, str] = {
    "pyro": "Emberpaw", "beavis": "Barkbite", "leonardo": "Tinshield", "mark": "Bindle",
    "sam": "Quickpaw", "erran": "Trailfoot", "harold": "Longdusk", "saki": "Slink",
    "rocky": "Flint", "bubbles": "Ripple", "cook": "Simmer", "tomato": "Turnip",
    "sprinkles": "Fennel", "bob": "Bobbin", "smith": "Anvil", "fletch": "Quill",
    "rune": "Glyph", "astro": "Twinkle", "cart": "Compass", "dig": "Trowel",
    "harvest": "Bramble", "alt": "Wisp", "town": "Hearth", "atk": "Redblade",
    "str": "Boulder", "hp": "Redcap", "rng": "Longshot", "mag": "Glimmer",
    "pray": "Vigil", "slay": "Tracker",
}

OBSTACLE_RENAMES: list[tuple[str, str]] = [
    ("Obstacle 1-1", "Hedgerow Hop"), ("Obstacle 1-2", "Ditch Vault"), ("Obstacle 1-3", "Stacked Crates"),
    ("Obstacle 2-1", "Lean-To Scramble"), ("Obstacle 2-2", "Rope Ladder"), ("Obstacle 2-3", "Stockade Wall"),
    ("Obstacle 3-1", "Hayrick Leap"), ("Obstacle 3-2", "Fence Run"), ("Obstacle 3-3", "Grain Silo Climb"),
    ("Obstacle 4-1", "Cartwheel Beam"), ("Obstacle 4-2", "Market Awning"), ("Obstacle 4-3", "Cobblestone Dash"),
    ("Obstacle 5-1", "Ravine Ropebridge"), ("Obstacle 5-2", "Scree Slide"), ("Obstacle 5-3", "Fallen Arch"),
    ("Obstacle 6-1", "Marsh Causeway"), ("Obstacle 6-2", "Reed Stiltwalk"), ("Obstacle 6-3", "Sunken Pillar"),
    ("Obstacle 7-1", "Barrow Stairs"), ("Obstacle 7-2", "Ossuary Crawl"), ("Obstacle 7-3", "Cairn Hopping"),
    ("Obstacle 8-1", "Rookery Ascent"), ("Obstacle 8-2", "Broken Viaduct"), ("Obstacle 8-3", "Rook's Ladder"),
    ("Obstacle 9-1", "Frostledge Traverse"), ("Obstacle 9-2", "Icicle Ladder"), ("Obstacle 9-3", "Blackglass Climb"),
    ("Obstacle 10-1", "Battlement Run"), ("Obstacle 10-2", "Courtyard Vault"), ("Obstacle 10-3", "Siege Ramp"),
    ("Obstacle 11-1", "Caldera Ridge"), ("Obstacle 11-2", "Pumice Hops"), ("Obstacle 11-3", "Ashfall Climb"),
    ("Obstacle 12-1", "Fenweb Crossing"), ("Obstacle 12-2", "Spindlewalk"), ("Obstacle 12-3", "Nesting Ropes"),
    ("Obstacle 13-1", "Deep Shaft Rappel"), ("Obstacle 13-2", "Fossil Gallery"), ("Obstacle 13-3", "Trench Run"),
    ("Obstacle 14-1", "Rift Bridges"), ("Obstacle 14-2", "Breath Ledge"), ("Obstacle 14-3", "Woundstep"),
    ("Obstacle 15-1", "Stormspire Ascent"), ("Obstacle 15-2", "Thunderline Run"), ("Obstacle 15-3", "Skybound Rigging"),
    ("Pillar of Combat", "Pillar of the Vanguard"),
    ("Pillar of Skilling", "Pillar of the Craft"),
    ("Pillar of Generosity", "Pillar of the Open Hand"),
    ("Elite Pillar Of Conflict", "Elite Pillar of the Skirmish"),
    ("Elite Pillar Of Endowment", "Elite Pillar of the Gift"),
    ("Elite Pillar Of Expertise", "Elite Pillar of Mastery"),
]

SHOP_RENAMES: list[tuple[str, str]] = [
    ("Dragon Axe", "Wyrmsteel Axe"),
    ("Dragon Pickaxe", "Wyrmsteel Pickaxe"),
    ("Dragon Angling Rod", "Wyrmsteel Angling Rod"),
    ("Multi-Tree", "Grove Felling"),
    ("Perpetual Haste", "Haste Without End"),
    ("Expanded Knowledge", "Frontier Scholarship"),
    ("Master of Nature", "Steward of Wilds"),
    ("Art of Control", "Hand of Command"),
]

CONSTELLATION_NAME_PAIRS: list[tuple[str, str]] = [
    (key.title(), new) for key, new in CONSTELLATION_RENAMES.items()
]
ASTROLOGY_ACTION_PAIRS: list[tuple[str, str]] = [
    (f"Study {key.title()}", f"Study {new}") for key, new in CONSTELLATION_RENAMES.items()
]

# File-scoped record renames (exact `"name": "old"` match inside that file only).
RECORD_RENAMES: dict[str, list[tuple[str, str]]] = {
    "items.json": ITEM_RENAMES + familiar_item_renames(),
    "skills.json": SKILL_RENAMES + ASTROLOGY_ACTION_PAIRS + PRAYER_RENAMES,
    "constellations.json": CONSTELLATION_NAME_PAIRS,
    "prayers.json": PRAYER_RENAMES,
    "pets.json": [(old.title(), new) for old, new in PET_RENAMES.items()],
    "obstacles.json": OBSTACLE_RENAMES,
    "familiars.json": [(old.title(), new) for old, new in FAMILIAR_RENAMES.items()
                       if old != "golbin_thief"],
    "shop.json": SHOP_RENAMES,
}

# Prose fixes (literal, file-scoped) — descriptions that quote something odd.
TEXT_FIXES: dict[str, list[tuple[str, str]]] = {
    "trader.json": [("Pig bars, still warm from the mould.",
                     "Fresh bars, still warm from the mould.")],
}

# Global word-boundary sweeps for names quoted in prose (quest labels, descriptions,
# achievements). Only distinctive words: creatures like Wolf/Dragon are deliberately
# excluded because monsters use them ("Frostfang Wolf"); their item/action forms are
# covered by the anchored record renames above.
SWEEPS: list[tuple[str, str]] = (
    CONSTELLATION_NAME_PAIRS
    + [("Ent", "Oldroot")]   # quest label "Bind 10 Ent tablets"; verified unique elsewhere
    + ITEM_RENAMES
    + SKILL_RENAMES
    + PRAYER_RENAMES
    + SHOP_RENAMES           # quest label "Buy Multi-Tree"
)


def apply_record_renames(path: Path, renames: list[tuple[str, str]], dry: bool) -> int:
    text = path.read_text(encoding="utf-8")
    changed = 0
    for old, new in renames:
        needle = f'"name": "{old}"'
        n = text.count(needle)
        if n:
            text = text.replace(needle, f'"name": "{new}"')
            changed += n
    if changed and not dry:
        path.write_text(text, encoding="utf-8")
    return changed


def apply_text_fixes(path: Path, fixes: list[tuple[str, str]], dry: bool) -> int:
    text = path.read_text(encoding="utf-8")
    changed = 0
    for old, new in fixes:
        n = text.count(old)
        if n:
            text = text.replace(old, new)
            changed += n
    if changed and not dry:
        path.write_text(text, encoding="utf-8")
    return changed


def apply_sweeps(path: Path, dry: bool) -> int:
    text = path.read_text(encoding="utf-8")
    changed = 0
    for old, new in SWEEPS:
        pattern = re.compile(r"\b%s\b" % re.escape(old))
        text, n = pattern.subn(new, text)
        changed += n
    if changed and not dry:
        path.write_text(text, encoding="utf-8")
    return changed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    total = 0
    for path in sorted(DATA.glob("*.json")):
        n = 0
        for fix in TEXT_FIXES.get(path.name, []):
            n += apply_text_fixes(path, [fix], args.dry_run)
        if path.name in RECORD_RENAMES:
            n += apply_record_renames(path, RECORD_RENAMES[path.name], args.dry_run)
        n += apply_sweeps(path, args.dry_run)
        if n:
            print(f"{path.name}: {n} rename(s)")
            total += n
    print(f"total: {total} change(s)" + (" (dry run)" if args.dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
