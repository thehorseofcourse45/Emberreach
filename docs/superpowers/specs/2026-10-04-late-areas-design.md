# Late areas (230–320) — design

Approved in chat 2026-10-04. Scope A: fill the thin combat range without adding a tier above
the Herald.

- Areas: `ashen_bastion` (205–245, Slayer 105), `gloamreach_marsh` (245–295, Slayer 115).
- Dungeons: `ashen_bastion_keep` (225–250, needs `impending_darkness`), `gloamreach_sink`
  (260–300, needs the Keep).
- Monsters: `bastion_sentinel` 238, `cinder_archer` 244, `bastion_warden` 255 (boss),
  `marsh_hulk` 272, `gloam_witch` 285, `gloam_matron` 292 (boss). Stats interpolated between
  existing neighbours; the balance enemy-curve check must stay clean.
- Hooks: slayer `herald` tier gets the four non-boss monsters; four achievements; first-clear
  rewards use existing items only.
- Authoring: idempotent `tools/late_areas_content.py` (text insertion preserving file layout).
- Art: hue-shifted placeholders written by the same script; real art requested in
  `ART_REQUESTS.md`.
- Verification: `--validate` 0/0, `--balance` no warnings, `--assetreport` all present,
  `--tests` all pass.
