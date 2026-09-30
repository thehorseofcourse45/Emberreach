"""Screenshot-diff gate for Emberreach.

Runs the game's real-window sweep (`--shot`, no --headless: a display is required)
and compares every rendered PNG against committed baselines. Exits non-zero when a
screen changed, disappeared, or a baseline is stale — so a layout regression fails
the gate instead of relying on someone eyeballing shots/.

Usage (from the project root):
    python tools/shot_gate.py              run sweep, compare, exit 0/1
    python tools/shot_gate.py --update     run sweep, accept the results as baseline
    python tools/shot_gate.py --compare-only   compare the last run, don't relaunch

Why a tolerance instead of byte-equality: 41 of 49 screens are byte-identical
run-to-run, but 8 contain live values (header clock digits, slider positions) that
differ by design. Those differ on <=0.06% of pixels between two runs of identical
code, so any screen above the threshold (default 0.25%) has really moved.
Baselines are tied to the machine that rendered them (font/GPU rasterisation);
re-run --update on that machine after an intentional UI change.

Listings are filtered to .png: Godot writes .png.import sidecars for anything under
res:// (including this baseline folder), and an import sidecar is not a screen.
"""
import argparse
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN_DIR = os.path.join(BASE, ".shot_gate", "run")
DIFF_DIR = os.path.join(BASE, ".shot_gate", "diff")
BASELINE_DIR = os.path.join(BASE, "tools", "shot_baseline")
DEFAULT_GODOT = r"C:\Godot\Godot_v4.7.2-stable_win64_console.exe"


def godot_binary(cli_value):
    for candidate in (cli_value, os.environ.get("GODOT"), DEFAULT_GODOT, "godot"):
        if candidate and (os.path.isabs(candidate) or shutil.which(candidate)):
            if os.path.isabs(candidate) and not os.path.exists(candidate):
                continue
            return candidate
    return None


def run_sweep(godot):
    if os.path.isdir(RUN_DIR):
        shutil.rmtree(RUN_DIR)
    res_path = "res://.shot_gate/run"
    cmd = [godot, "--path", BASE, "--", "--shot", res_path]
    print("running sweep: ", " ".join(cmd))
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except FileNotFoundError:
        print("error: godot binary not found (%s)" % godot)
        return None
    except subprocess.TimeoutExpired:
        print("error: sweep timed out")
        return None
    output = (proc.stdout or "") + (proc.stderr or "")
    shots = [ln for ln in output.splitlines() if ln.startswith("shot:")]
    if not os.path.isdir(RUN_DIR) or not shots:
        print("error: sweep produced no PNGs — --shot needs a real display (no --headless).")
        for ln in output.splitlines()[-15:]:
            print("  | " + ln)
        return None
    failed = [ln for ln in shots if "FAILED" in ln]
    if failed:
        print("error: %d writes failed inside the sweep:" % len(failed))
        for ln in failed:
            print("  | " + ln)
        return None
    return sorted(n for n in os.listdir(RUN_DIR) if n.lower().endswith(".png"))


def pixel_stats(current_path, baseline_path, tol):
    """Return (size_mismatch, changed_percent) for one image pair."""
    cur = Image.open(current_path)
    base = Image.open(baseline_path)
    if cur.size != base.size:
        return True, 100.0
    a = np.asarray(cur.convert("RGB"), dtype=np.int16)
    b = np.asarray(base.convert("RGB"), dtype=np.int16)
    delta = np.abs(a - b).max(axis=2)
    return False, 100.0 * float((delta > tol).mean())


def write_heatmap(name, current_path, baseline_path, tol):
    cur = Image.open(current_path).convert("RGB")
    base = Image.open(baseline_path).convert("RGB")
    if cur.size != base.size:
        print("  size differs: %s %s vs baseline %s" % (name, cur.size, base.size))
        return
    a = np.asarray(cur, dtype=np.int16)
    b = np.asarray(base, dtype=np.int16)
    mask = (np.abs(a - b).max(axis=2)) > tol
    gray = (np.asarray(cur.convert("L"), dtype=np.float32) * 0.35).astype(np.uint8)
    vis = np.stack([gray] * 3, axis=2)
    vis[mask] = [255, 0, 255]
    os.makedirs(DIFF_DIR, exist_ok=True)
    Image.fromarray(vis).save(os.path.join(DIFF_DIR, name))


def main():
    ap = argparse.ArgumentParser(description="Emberreach screenshot-diff gate")
    ap.add_argument("--update", action="store_true", help="accept the current render as baseline")
    ap.add_argument("--compare-only", action="store_true", help="compare the last run without relaunching")
    ap.add_argument("--tol", type=int, default=8, help="per-channel delta ignored as AA noise (default 8)")
    ap.add_argument("--max-changed", type=float, default=0.25,
                    help="max percent of pixels allowed to differ (default 0.25)")
    ap.add_argument("--godot", default=None, help="path to the Godot binary")
    args = ap.parse_args()

    if args.compare_only:
        if not os.path.isdir(RUN_DIR):
            print("error: no previous run at %s" % RUN_DIR)
            return 2
        current = sorted(n for n in os.listdir(RUN_DIR) if n.lower().endswith(".png"))
    else:
        godot = godot_binary(args.godot)
        if godot is None:
            print("error: no Godot binary found; pass --godot or set $GODOT")
            return 2
        current = run_sweep(godot)
        if current is None:
            return 2

    if args.update:
        if os.path.isdir(BASELINE_DIR):
            shutil.rmtree(BASELINE_DIR)
        shutil.copytree(RUN_DIR, BASELINE_DIR, ignore=shutil.ignore_patterns("*.import"))
        print("baseline updated: %d files -> %s" % (len(current), os.path.relpath(BASELINE_DIR, BASE)))
        return 0

    if not os.path.isdir(BASELINE_DIR):
        print("error: no baseline yet — run: python tools/shot_gate.py --update")
        return 2

    baseline = sorted(n for n in os.listdir(BASELINE_DIR) if n.lower().endswith(".png"))
    missing = [n for n in baseline if n not in current]   # screen no longer rendered
    stale = [n for n in current if n not in baseline]     # new screen, no baseline
    failures = []
    noise = 0.0
    for name in current:
        if name not in baseline:
            continue
        try:
            size_mismatch, pct = pixel_stats(os.path.join(RUN_DIR, name),
                                             os.path.join(BASELINE_DIR, name), args.tol)
        except Exception as exc:  # unreadable/corrupt PNG is a failure, not a crash
            failures.append((name, "unreadable: %s" % exc))
            print("FAIL  %-28s unreadable: %s" % (name, exc))
            continue
        if size_mismatch:
            failures.append((name, "dimensions changed"))
            print("FAIL  %-28s dimensions changed" % name)
            write_heatmap(name, os.path.join(RUN_DIR, name), os.path.join(BASELINE_DIR, name), args.tol)
        elif pct > args.max_changed:
            failures.append((name, "%.3f%% changed" % pct))
            print("FAIL  %-28s %.3f%% changed (limit %.3f%%)" % (name, pct, args.max_changed))
            write_heatmap(name, os.path.join(RUN_DIR, name), os.path.join(BASELINE_DIR, name), args.tol)
        else:
            noise = max(noise, pct)
            print("PASS  %-28s %.3f%% changed" % (name, pct))

    for name in missing:
        failures.append((name, "missing from run"))
        print("FAIL  %-28s missing from run" % name)
    for name in stale:
        failures.append((name, "no baseline (run --update)"))
        print("FAIL  %-28s no baseline (run --update)" % name)

    print("")
    print("=== screenshot gate: %d compared, %d failed, %d missing, %d stale ===" % (
        len(current) - len(stale), len(failures), len(missing), len(stale)))
    print("largest tolerated drift: %.3f%% (limit %.3f%%)" % (noise, args.max_changed))
    if failures:
        print("heatmaps: %s" % os.path.relpath(DIFF_DIR, BASE))
        return 1
    print("result: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
