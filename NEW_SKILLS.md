# Five new non-combat skills

All five appear in the non-combat sidebar and start at level 1 on existing saves. Existing earned XP is preserved.

| Skill | Core loop | Base days to 99 / 120 |
|---|---|---:|
| Ranching | Buy pens and animals, supply crop feed, collect produce, breed variants, retire animals | 8 / 35 |
| Inscription | Make paper and ink, research recipes once, scribe quality texts and equippable tomes | 4 / 18 |
| Engineering | Craft parts and devices, select work, install workers, maintain hourly fuel | 5 / 23 |
| Enchanting | Disenchant spare gear for typed essence; spend essence, runes, gems and boss catalysts to enchant individual pieces | 4 / 20 |
| Dreamwalking | Select a dreamscape and offline allocation; return for Essence, events and Bazaar rewards | 6 / 28 |

These are base training-time forecasts, assuming the best unlocked activity and available materials. They exclude bonuses, research rewards and supply gathering. Ranching assumes twelve fed animals in six pens; building up the ranch adds time, while animal mastery and skillcape speed shorten it. Dreamwalking counts allocated offline hours, assumes newly unlocked dreamscapes are selected, and excludes depth/mastery bonuses. At eight allocated dream hours per night, six training days represents about eighteen nights before bonuses.

## Controls and connections

- **Ranching:** Farming crops make feed. Buy stock from the ranch controls or Provisionier; theft, encounters and breeding can also supply animals. A pen holds two matching animals. Fed animals produce at full speed; hunger decays to 25%. Collect yields XP, produce and manure. Breeding requires a pair, sufficient happiness and six elapsed hours. Manure is applied before planting and benefits one crop. Produce connects to Cooking, Artifice, Bowyering, Apothecary and Starreading.
- **Inscription:** Research is finite and stops after one completion. Crafting rolls Faded, Inked or Illuminated quality. Use texts from the scriptorium and select an XP/glyph target. Tome XP is a fraction of its crafting XP; it supplements other training. Haste, doubling and mastery effects expire on the shared real-time clock. Equippable tomes use the offhand slot. A skillcape permits a second active mastery glyph.
- **Engineering:** Two slots initially; level and mastery/cape upgrades raise the limit to six. Install a crafted device and choose an unlocked activity. Fuel is paid for an hour up front and unused prepaid time persists in saves. Workers use base action rates, success chances, XP and outputs without the player's target-skill modifiers. Mastery improves efficiency and upkeep. The Farmhand collects and replants real plots; a fueled Scavenger can recover additional drops from defeated monsters.
- **Enchanting:** Unequip gear into Storage first. Protected items cannot be recycled or changed. Actions occupy the main activity slot and consume their costs before rewards. One copy becomes a derived enchanted item; other copies retain their properties. Replacing an enchant overwrites that piece's property; a skillcape permits two. Higher tiers require catalysts from dungeon bosses. Dungeon-cleared signature weapon effects apply Burn or Slow in real combat. Disenchanting refunds part of the spent essence.
- **Dreamwalking:** The slider reserves 0–100% of your capped offline time. The waking allocation is processed first, then dreams; clocks, feed, fuel and buff expiry continue through both. Longer dreams gain depth. Nightmares can remove a small part of session Essence; mastery mitigates them. Event choices are saved and can be resolved in the return summary or Dreamwalking screen. Bazaar bonuses and purchases have real effects. Lucid Draught is reserved for one offline dream and is consumed once.

Each skill has a pet, mastery pool effects, a skillcape, potion support, and progression tasks at levels 10, 50 and 99. Border Collie and Sandman familiar tablets are crafted through Beastbinding.

## Checks

Run `Godot --headless --path . res://tools/new_skills_check/check.tscn` for the focused mechanics, persistence, offline allocation and layout checks. It restores the player's save files afterward. The normal `-- --tests` suite checks existing gameplay and content references. New generated skill and squid sprites are transparent 32×32; matching existing item art supplies the remaining icons. The asset manifest is regenerated with `python gen_assets_manifest.py`.
