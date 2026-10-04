# Art requests — late areas pass (Ashen Bastion / Gloamreach Marsh)

The ten files below are **placeholders**: hue-shifted copies of existing art, written by
`tools/late_areas_content.py`. They load and play correctly today. To replace one, overwrite the
file at the same path with new art at the same size (keep the filename; do not rename ids), then run
`godot --headless --path . --import`.

Match the existing style: dark-fantasy pixel art, strong silhouette, readable at small size,
transparent background, no text. Monsters face the player, centred, feet near the bottom edge.

## Monster sprites — 96x96 PNG, `assets/sprites/monsters/<id>.png`

| id | Name | Level | Brief | Placeholder is a recolour of |
|---|---|---|---|---|
| `bastion_sentinel` | Bastion Sentinel | 238 | Heavy ash-grey garrison soldier in scorched plate, tower shield, still at its post. Melee, armoured. | `cinder_colossus` |
| `cinder_archer` | Cinder Archer | 244 | Lean hooded bowman, ember-glow arrows, charred leather. Ranged. | `herald_zealot` |
| `bastion_warden` | Bastion Warden (boss) | 255 | Towering keeper in a cracked ceremonial helm, ring of keys, great gate-halberd. Boss presence. | `dark_herald` |
| `marsh_hulk` | Marsh Hulk | 272 | Hulking mass of peat, bone and reeds, moss on the shoulders, slow and heavy. Melee. | `abyssal_lord` |
| `gloam_witch` | Gloam Witch | 285 | Gaunt robed figure wreathed in sickly green fog, lantern or glass vials. Magic, venom. | `umbral_harbinger` |
| `gloam_matron` | Gloam Matron (boss) | 292 | Enormous, ancient marsh horror half-risen from the water, fog and drowned things around it. Boss presence. | `rift_weaver` |

## Area icons — 64x64 PNG, `assets/icons/areas/<id>.png`

| id | Name | Brief | Placeholder is a recolour of |
|---|---|---|---|
| `ashen_bastion` | Ashen Bastion | Ruined hill fort under an ash-grey sky, one lit window on the wall. | `heralds_march` |
| `gloamreach_marsh` | Gloamreach Marsh | Fog-drowned marsh, dead trees, pale green lights low over the water. | `abyssal_depths` |

## Dungeon icons — 64x64 PNG, `assets/icons/dungeons/<id>.png`

| id | Name | Brief | Placeholder is a recolour of |
|---|---|---|---|
| `ashen_bastion_keep` | The Ashen Keep | A sealed keep gate, chains and a banner, embers at the seams. | `impending_darkness` |
| `gloamreach_sink` | The Gloam Sink | A sinkhole in the marsh, spiral of fog descending into green dark. | `throne_of_the_herald` |
