# Verification Gates — #16–18 Progression QoL

## Q1 — Full Godot regression suite
- Tier: runnable
- CHECK: `'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --tests`
- EXPECT: `ALL TESTS PASSED`

## Q2 — End-to-end progression
- Tier: runnable
- CHECK: `'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --selftest`
- EXPECT: `ALL TESTS PASSED`

## Q3 — Content and script validation
- Tier: runnable
- CHECK: `'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --validate`
- EXPECT: `0 error(s)`

## Q4 — Responsive UI rendering
- Tier: manual
- Gate: The real non-headless window renders Action Queue, Storage auto-sell, and Combat Simulator at 420, 900, and 1440 pixels without clipping or missing controls.

## Q5 — Persistence and live-state isolation
- Tier: runnable
- CHECK: `'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --tests`
- EXPECT: `progression QoL persistence and simulator isolation`
