"""Close the acquisition gaps the content validator reports.

Three edits, all data-only:

1. God-tier gear becomes craftable. Each Warden dungeon already drops its signature shard on
   every kill (`shard_item`), so the four sets only needed a recipe to stop being decoration.
   The sets are Forgecraft work that needs the matching elemental shard, a refined summoning
   shard as a binding agent, Ghoststeel bars and Prismatic Essence.
2. The five higher summoning shards become refinable in Conjuring, tier by tier, so binding a
   stronger familiar is a project rather than a drop-table lottery. The top tier is consumed by
   the two-handed weapons, which gives every shard tier a use.
3. `ship_upgrade_kit` is deleted: nothing grants it, nothing consumes it and no script mentions
   it. Removing dead content is better than inventing a system to justify it.

Run:  python tools/endgame_content.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"

ELEMENTS = [
    # area shard, its gear prefix, binding shard tier for armour, two-hander binding tier
    ("air", "shard_air", "crimson", "binding_crimson"),
    ("water", "shard_water", "azure", "binding_azure"),
    ("earth", "shard_earth", "silver", "binding_silver"),
    ("fire", "shard_fire", "umbral", "binding_umbral"),
]

# piece -> (level, interval, xp, element shard, binding qty, bars, essence)
PIECES = [
    ("helmet", 95, 20.0, 600, 2, 1, 3, 2),
    ("platelegs", 98, 22.0, 1000, 3, 2, 5, 3),
    ("platebody", 100, 24.0, 1200, 3, 2, 6, 4),
    ("boots", 96, 18.0, 400, 1, 1, 2, 1),
    ("gloves", 96, 18.0, 400, 1, 1, 2, 1),
    ("godsword", 105, 30.0, 2500, 5, 3, 8, 6),
]

# Refining the summoning shards: (action id, output, level, xp, inputs)
# XP is priced against the crafting band for each level (see `--balance`), not chosen for feel:
# at a 6s interval these land between 36K and 360K XP/h across a 100-level span.
SHARD_CHAIN = [
    ("refine_crimson_shard", "summoning_shard_crimson", 12, 60,
     {"summoning_shard_green": 5, "pure_essence": 1}),
    ("refine_azure_shard", "summoning_shard_blue", 45, 150,
     {"summoning_shard_crimson": 3, "pure_essence": 2}),
    ("refine_silver_shard", "summoning_shard_silver", 70, 260,
     {"summoning_shard_blue": 3, "pure_essence": 5}),
    ("refine_umbral_shard", "summoning_shard_black", 95, 420,
     {"summoning_shard_silver": 3, "rune_essence": 20}),
    ("refine_gilded_shard", "summoning_shard_gold", 112, 600,
     {"summoning_shard_black": 3, "prismatic_essence": 3}),
]

BINDING_ITEM = {
    "crimson": "summoning_shard_crimson",
    "azure": "summoning_shard_blue",
    "silver": "summoning_shard_silver",
    "umbral": "summoning_shard_black",
}


def load(name):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def save(name, obj):
    (DATA / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main():
    items = load("items.json")
    skills = load("skills.json")
    created = []

    for skill_id, actions in (("smithing", skills["smithing"]["actions"]),
                              ("summoning", skills["summoning"]["actions"])):
        for action in actions:
            created.append(action["id"])

    # --- 1. god-tier crafting ---------------------------------------------------------
    forge = skills["smithing"]["actions"]
    for element, area_shard, armour_binding, sword_binding in ELEMENTS:
        for piece, level, interval, xp, shard_qty, bind_qty, bars, essence in PIECES:
            item_id = f"{element}_godsword" if piece == "godsword" else f"{element}_god_{piece}"
            if item_id not in items:
                raise SystemExit(f"missing item {item_id}")
            # Armour is bound with its region's shard tier; the two-handers need the top tier.
            binding_item = "summoning_shard_gold" if piece == "godsword" \
                else BINDING_ITEM[armour_binding]
            action_id = f"forge_{item_id}"
            if action_id in created:
                continue
            forge.append({
                "id": action_id,
                "name": items[item_id]["name"],
                "level_required": level,
                "base_interval": interval,
                "base_xp": xp,
                "input_items": {
                    area_shard: shard_qty,
                    binding_item: bind_qty,
                    "dragonite_bar": bars,
                    "prismatic_essence": essence,
                },
                "output_items": {item_id: 1},
                "mastery_action_time": interval,
            })
            created.append(action_id)
            print(f"smithing: {action_id} -> {item_id}")

    # --- 2. summoning shard chain -----------------------------------------------------
    conjure = skills["summoning"]["actions"]
    for action_id, output, level, xp, inputs in SHARD_CHAIN:
        if action_id in created:
            continue
        conjure.append({
            "id": action_id,
            "name": items[output]["name"],
            "level_required": level,
            "base_interval": 6.0,
            "base_xp": xp,
            "input_items": inputs,
            "output_items": {output: 1},
            "mastery_action_time": 6.0,
        })
        created.append(action_id)
        print(f"summoning: {action_id} -> {output}")

    save("skills.json", skills)

    # --- 3. drop dead content ---------------------------------------------------------
    if "ship_upgrade_kit" in items:
        del items["ship_upgrade_kit"]
        save("items.json", items)
        print("items: removed ship_upgrade_kit (no source, no use, unreferenced)")

    print("done")


if __name__ == "__main__":
    main()
