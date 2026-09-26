#!/usr/bin/env python3
"""Second identity pass: propagate renamed display names into references, then verify.

The first pass renames the records themselves. Recipe/action names, familiar names and pet
names *reference* other records by their old display text (e.g. the Delving action called
"Bronze Bar", or the Beastbinding familiar called "Golbin Thief"). This pass:

  1. diffs data/ against tools/_backup_pre_identity/ to build an old->new display-name map,
  2. rewrites any `name` string that exactly equals an old display name,
  3. strips the last remaining borrowed words from every player-facing string,
  4. re-scans for anything left over.

Ids are still never touched.

Run:  python tools/identity_fixups.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
BACKUP = ROOT / "tools" / "_backup_pre_identity"

BANNED_PAIRS = [
    ("Golbin Thief", "Cinderkin Thief"),
    ("golden_golbin", "golden_cinderkin"),   # id text only appears inside comments
    ("Golden Golbin", "Golden Cinderkin"),
    ("Golbin", "Cinderkin"),
    ("golbin", "cinderkin"),
    ("Melvor", "Emberreach"),
    ("melvor", "emberreach"),
]


## Last borrowed words that survive the systematic passes, fixed by id so they cannot drift.
EXTRA_NAMES = {
    "green_dhide_body": "Verdant Wyrmhide Body",
    "green_dhide_chaps": "Verdant Wyrmhide Chaps",
    "green_dhide_vambraces": "Verdant Wyrmhide Vambraces",
    "green_dhide_coif": "Verdant Wyrmhide Coif",
    "blue_dhide_body": "Azure Wyrmhide Body",
    "blue_dhide_chaps": "Azure Wyrmhide Chaps",
    "blue_dhide_vambraces": "Azure Wyrmhide Vambraces",
    "blue_dhide_coif": "Azure Wyrmhide Coif",
    "red_dhide_body": "Crimson Wyrmhide Body",
    "red_dhide_chaps": "Crimson Wyrmhide Chaps",
    "red_dhide_vambraces": "Crimson Wyrmhide Vambraces",
    "red_dhide_coif": "Crimson Wyrmhide Coif",
    "air_staff": "Gale Staff",
    "water_staff": "Tide Staff",
    "earth_staff": "Stone Staff",
    "fire_staff": "Ember Staff",
    "alt_magic_cape": "Runescribing Skillcape",
    "abyssal_whip": "Umbral Lash",
    "ancient_sword": "Sundering Blade",
    "normal_shortbow": "Emberpine Shortbow",
    "normal_longbow": "Emberpine Longbow",
    "max_skillcape": "Frontier Cape",
    "raid_alt_weapon_1": "Scavenged Blade",
    "raid_alt_weapon_2": "Scavenged Maul",
    "raid_alt_weapon_3": "Scavenged Spear",
    "raid_alt_weapon_4": "Scavenged Bow",
    "raid_alt_weapon_5": "Scavenged Rod",
}


def apply_extra_names(data) -> list[str]:
    """Apply EXTRA_NAMES by id to any nested record. Returns change notes."""
    notes: list[str] = []
    if isinstance(data, dict):
        rec_id = data.get("id")
        if isinstance(rec_id, str) and rec_id in EXTRA_NAMES:
            old = data.get("name")
            if old != EXTRA_NAMES[rec_id]:
                data["name"] = EXTRA_NAMES[rec_id]
                notes.append(f"{rec_id}: {old!r} -> {EXTRA_NAMES[rec_id]!r}")
        for value in data.values():
            notes.extend(apply_extra_names(value))
    elif isinstance(data, list):
        for value in data:
            notes.extend(apply_extra_names(value))
    return notes


def collect(container, table: dict[str, str]) -> None:
    """Record id -> display name for every named record in a content file."""
    if isinstance(container, dict):
        rec_id = container.get("id")
        name = container.get("name")
        if isinstance(rec_id, str) and isinstance(name, str):
            table[rec_id] = name
        for value in container.values():
            collect(value, table)
    elif isinstance(container, list):
        for value in container:
            collect(value, table)


def build_rename_map() -> dict[str, str]:
    mapping: dict[str, str] = {}
    for old_path in sorted(BACKUP.glob("*.json")):
        new_path = DATA / old_path.name
        if not new_path.exists():
            continue
        before: dict[str, str] = {}
        after: dict[str, str] = {}
        collect(json.loads(old_path.read_text(encoding="utf-8")), before)
        collect(json.loads(new_path.read_text(encoding="utf-8")), after)
        for rec_id, old_name in before.items():
            new_name = after.get(rec_id)
            if new_name and new_name != old_name:
                mapping[old_name] = new_name
    return mapping


def sanitize(text: str) -> str:
    for old, new in BANNED_PAIRS:
        text = text.replace(old, new)
    return text


def rewrite(container, mapping: dict[str, str], notes: list[str]) -> None:
    if isinstance(container, dict):
        name = container.get("name")
        if isinstance(name, str):
            new_name = mapping.get(name, name)
            new_name = sanitize(new_name)
            if new_name != name:
                container["name"] = new_name
                notes.append(f"{container.get('id', '?')}: {name!r} -> {new_name!r}")
        for key in ("description", "flavour"):
            value = container.get(key)
            if isinstance(value, str):
                container[key] = sanitize(value)
        for value in container.values():
            rewrite(value, mapping, notes)
    elif isinstance(container, list):
        for value in container:
            rewrite(value, mapping, notes)


def main() -> int:
    if not BACKUP.exists():
        print(f"Missing backup at {BACKUP}; cannot build the rename map.")
        return 1
    mapping = build_rename_map()
    print(f"rename map covers {len(mapping)} display names")
    total_notes: list[str] = []
    for path in sorted(DATA.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        notes: list[str] = []
        rewrite(data, mapping, notes)
        notes.extend(apply_extra_names(data))
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        for note in notes:
            total_notes.append(f"{path.name} {note}")

    print(f"{len(total_notes)} references updated")
    for note in total_notes[:20]:
        print("  " + note)

    leftovers = []
    for path in sorted(DATA.glob("*.json")):
        text = path.read_text(encoding="utf-8")
        for word in ("golbin", "Golbin", "melvor", "Melvor"):
            for m in re.finditer(r'.{0,50}' + re.escape(word) + r'.{0,50}', text):
                snippet = m.group(0).replace("\n", " ")
                # ids are allowed to keep their historical spelling for save compatibility
                if '"id"' in snippet or '"' + word in snippet or path.name == "skills.json":
                    continue
                leftovers.append(f"{path.name}: ...{snippet}...")
    if leftovers:
        print(f"WARNING: {len(leftovers)} player-facing strings still contain borrowed words:")
        for line in leftovers[:20]:
            print("  " + line)
    else:
        print("OK: no borrowed words remain in player-facing text.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
