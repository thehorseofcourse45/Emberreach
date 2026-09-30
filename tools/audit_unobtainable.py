"""Audit: items with no acquisition path, and materials nothing consumes.

Models BOTH data edges and the code paths that mint items at runtime, because several
real sources are code, not data:
  * SummoningManager._gain_mark mints "<fam>_mark" on a level-up roll.
  * FarmingManager.harvest turns a seed into its product_item.
  * ShopManager's skillcape stall and SlayerManager's shop synthesise offers from item
    rows (equipment_slot 5 + requires_level, and slayer_cost) rather than a shop file.

Run:  python tools/audit_unobtainable.py
"""
import json
import glob
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def L(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
        return json.load(f)


I = L("items.json")
S = L("skills.json")
M = L("monsters.json")
D = L("dungeons.json")

prod = {}


def add(i, src):
    if isinstance(i, str) and i and i != "gp":
        prod.setdefault(i, set()).add(src)


# skills
for sk, sv in S.items():
    if not isinstance(sv, dict):
        continue
    for a in sv.get("actions", []):
        for k in (a.get("output_items") or {}):
            add(k, "skill")
        for s in (a.get("secondary_outputs") or []):
            add(s.get("item_id"), "skill")
        # a failed craft leaves this behind
        add(a.get("fail_output_item"), "skill_fail")

# monster loot
for mid, m in M.items():
    if not isinstance(m, dict):
        continue
    for l in m.get("loot_table", []) or []:
        if isinstance(l, dict):
            add(l.get("item_id"), "loot")

# dungeons
for did, d in D.items():
    if not isinstance(d, dict):
        continue
    add(d.get("shard_item"), "dungeon")
    for key in ("loot_table", "completion_reward", "rewards_first_clear"):
        v = d.get(key)
        if isinstance(v, list):
            for r in v:
                if isinstance(r, dict):
                    add(r.get("item_id"), "dungeon")
        elif isinstance(v, dict):
            for k in (v.get("items") or {}):
                add(k, "dungeon")


# every other data file: item_id / items / grant_items / reward / rewards / output_items
for f in glob.glob(os.path.join(ROOT, "data", "*.json")):
    base = os.path.basename(f)[:-5]
    if base in ("items", "skills", "monsters", "dungeons"):
        continue
    with open(f, encoding="utf-8") as fh:
        dd = json.load(fh)

    def walk(o):
        if isinstance(o, dict):
            if isinstance(o.get("item_id"), str):
                add(o["item_id"], base)
            for k, v in o.items():
                if isinstance(v, dict) and k in (
                    "items", "grant_items", "reward", "rewards", "output_items", "rewards_first_clear",
                ):
                    for x in v:
                        add(x, base)
                walk(v)
        elif isinstance(o, list):
            for e in o:
                walk(e)

    walk(dd)

# --- code edges: RaidManager grants raid_shop.alt_items as wave picks ---------
for aid in L("raid_shop.json").get("alt_items", []):
    add(aid, "raid_alt_items")

# --- code edges: FarmingManager.harvest turns a seed into its product ----------
for i, v in I.items():
    if isinstance(v, dict) and v.get("product_item"):
        add(v["product_item"], "seed")

# --- code edges: SummoningManager._gain_mark mints "<fam>_mark" ---------------
for fid, fv in L("familiars.json").items():
    if isinstance(fv, dict) and not fid.startswith("_"):
        add("%s_mark" % fid, "summoning_mark")

# --- dynamic paths handled in code, not data
for i, v in I.items():
    if not isinstance(v, dict):
        continue
    if (v.get("slayer_cost") or 0) > 0:
        add(i, "slayer_shop")
    if int(v.get("equipment_slot", -1)) == 5 and v.get("requires_level"):
        add(i, "cape_stall")
    # EquipmentManager.upgrade() mints upgrade_path, spending upgrade_materials. The
    # materials are a sink (below); the output is a producer, and without this the two
    # tiers above a platebody read as unobtainable even though the mechanic is real.
    if v.get("upgrade_path") and str(v["upgrade_path"]) in I:
        add(str(v["upgrade_path"]), "equipment_upgrade")

# --- code edges: ShopManager.STALL_ALL_SKILLS capes (gated, not slot-derived) --
for cape in ("max_skillcape", "cape_of_completion"):
    add(cape, "cape_stall")

items = [i for i in I if not i.startswith("_") and isinstance(I[i], dict)]
miss = [i for i in items if i not in prod]
print("items %d | TRULY unobtainable: %d" % (len(items), len(miss)))
for m in miss:
    print("   %-26s %-28s %s" % (m, I[m].get("name"), I[m].get("item_type")))

# --- reverse: materials nothing ever consumes ---------------------------------
consumed = set()
for sk, sv in S.items():
    if not isinstance(sv, dict):
        continue
    for a in sv.get("actions", []):
        for k in (a.get("input_items") or {}):
            consumed.add(k)
for i, v in I.items():
    if isinstance(v, dict) and v.get("upgrade_materials"):
        for k in v["upgrade_materials"]:
            consumed.add(k)
orphans = [
    i for i in items
    if i not in consumed and I[i].get("item_type") != "equipment"
]
print("\nmaterials nothing consumes: %d" % len(orphans))
print("   " + ", ".join(orphans[:70]))
