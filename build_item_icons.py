#!/usr/bin/env python3
"""Rebuild the item icons from the art sheets in C:\\sprites.

Each sheet holds a run of item ids in manifest order (counts below). Icons are
isolated with a connected-component pass rather than by slicing each sheet into
equal cells: equal-cell crops let a neighbour's pixels (or a stray particle)
into the frame, which shifts the trimmed bounding box and is what pushed icons
off centre. After isolation the white background is matted out, the art is
trimmed to its own bounds and fitted into a 32x32 canvas.

Guarantees verified at the end of every run:
  * one asset per unique item id the sheets cover, each 32x32 RGBA with a real
    transparent background
  * every icon's opaque bounding box is centred on the canvas to the exact pixel
  * nothing touches the canvas edge (no clipped art), no visible specks
  * a hand-edited icon is never overwritten (see ours_to_write)

Usage:  python build_item_icons.py [--verify-only] [--force]
"""
from __future__ import annotations

import csv
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SHEETS = Path(r"C:\sprites")
PROJECT = Path(r"C:\Godot\melvor_clone_godot")
DEST = PROJECT / "assets" / "icons" / "items"
BACKUP = PROJECT.parent / "melvor_clone_godot_icons_before_fix"   # outside res:// so Godot ignores it
MANIFEST = PROJECT / "assets" / "manifest" / "asset_manifest.csv"
STATE = PROJECT / "assets" / "manifest" / "item_icons_built.json"

CANVAS = 32          # required on-canvas size
PAD = 2              # transparent margin kept around the art
WHITE = 245          # a channel above this counts as paper
MATTE = 228          # border flood treats pixels this light as background
DILATE = 3           # on paper sheets: bridges detached particles onto their icon
INK_ALPHA = 32       # on pre-cut sheets: alpha at or above this is artwork
MIN_PX = 150         # ignore specks below this before reconciling

# items1..items19, in sheet order: how many items that sheet carries.
NAME_COUNTS = [9, 11, 10, 10, 12, 8, 12, 12, 12, 12, 12, 12, 12, 12, 11, 9, 12, 5, 12]

FIRST_BATCH = 176    # sheets 1-16 carry normal_log .. cosmic_rune
HERB_RUN = 17        # sheets 17-18 carry air_staff .. barrentoe_seed
# sheet 19 draws Damage Reduction I-IV; I already shipped from sheet 6, but the
# new bottles carry the numerals so it is redrawn here rather than left stale.
REDRAWN = ("potion_dr_1",)


# ---------------------------------------------------------------- extraction
def ink_mask(image: Image.Image) -> tuple[np.ndarray, bool]:
    """Where the artwork is, and whether the sheet is already cut out.

    items1-16 are art on white paper: anything not white is artwork, and the
    flood in matte() clears the paper. items17-19 ship with a real alpha
    channel, so alpha is the artwork and a white pixel is a highlight.
    """
    arr = np.asarray(image.convert("RGBA")).astype(np.int16)
    if (arr[:, :, 3] < 250).mean() > 0.05:
        return arr[:, :, 3] >= INK_ALPHA, True
    rgb = arr[:, :, :3]
    return ~((rgb[:, :, 0] > WHITE) & (rgb[:, :, 1] > WHITE) & (rgb[:, :, 2] > WHITE)), False


def blobs(masked: np.ndarray, dilate: int = DILATE) -> list[dict]:
    grown = ndimage.binary_dilation(masked, iterations=dilate) if dilate else masked
    labels, _ = ndimage.label(grown, structure=np.ones((3, 3)))
    out = []
    for index, window in enumerate(ndimage.find_objects(labels)):
        ink = (labels[window] == index + 1) & masked[window]
        if ink.sum() < MIN_PX:
            continue
        ys, xs = np.nonzero(ink)
        y0, x0 = window[0].start, window[1].start
        out.append({"x0": x0 + int(xs.min()), "y0": y0 + int(ys.min()),
                    "x1": x0 + int(xs.max()), "y1": y0 + int(ys.max()),
                    "px": int(ink.sum())})
    return out


def reading_order(bs: list[dict]) -> list[dict]:
    """Group blobs into rows by vertical overlap, then left to right."""
    rows: list[dict] = []
    for b in sorted(bs, key=lambda b: b["y0"]):
        for row in rows:
            if min(row["y1"], b["y1"]) > max(row["y0"], b["y0"]):
                row["y0"] = min(row["y0"], b["y0"])
                row["y1"] = max(row["y1"], b["y1"])
                row["items"].append(b)
                break
        else:
            rows.append({"y0": b["y0"], "y1": b["y1"], "items": [b]})
    out = []
    for row in sorted(rows, key=lambda r: r["y0"]):
        out.extend(sorted(row["items"], key=lambda b: b["x0"]))
    return out


def merge(a: dict, b: dict) -> dict:
    return {"x0": min(a["x0"], b["x0"]), "y0": min(a["y0"], b["y0"]),
            "x1": max(a["x1"], b["x1"]), "y1": max(a["y1"], b["y1"]),
            "px": a["px"] + b["px"]}


def split(masked: np.ndarray, b: dict) -> tuple[dict, dict] | None:
    """Cut a blob that swallowed two icons at the gutter between them."""
    span = b["x1"] - b["x0"] + 1
    height = b["y1"] - b["y0"] + 1
    ink = masked[b["y0"]:b["y1"] + 1, b["x0"]:b["x1"] + 1].sum(axis=0)
    tol = max(3, int(0.08 * height))          # a real gutter is near-empty, not just thinner
    lo, hi = int(span * 0.15), int(span * 0.85)
    runs, start = [], None
    for x in range(lo, hi + 1):
        if ink[x] <= tol:
            start = x if start is None else start
        elif start is not None:
            runs.append((start, x - 1))
            start = None
    if start is not None:
        runs.append((start, hi))
    runs = [r for r in runs if r[1] - r[0] + 1 >= 5]
    if not runs:
        return None
    pick = max(runs, key=lambda r: (r[1] - r[0], -abs((r[0] + r[1]) / 2 - span / 2)))
    cut = b["x0"] + (pick[0] + pick[1]) // 2
    left, right = dict(b), dict(b)
    left["x1"], right["x0"] = cut, cut + 1
    for half in (left, right):
        half["px"] = int(masked[half["y0"]:half["y1"] + 1, half["x0"]:half["x1"] + 1].sum())
        if half["px"] == 0:
            return None
    return left, right


def reconcile(bs: list[dict], masked: np.ndarray, want: int, label: str) -> list[dict]:
    """Bend the detected blobs onto the known item count for this sheet."""
    order = reading_order(bs)
    if len(order) > 1:
        floor = 0.08 * float(np.median([b["px"] for b in order]))
        dropped = [b for b in order if b["px"] < floor]
        order = [b for b in order if b["px"] >= floor]
        if dropped:
            print(f"  {label}: dropped {len(dropped)} speck(s) {[b['px'] for b in dropped]}")

    guard = 0
    while len(order) > want and guard < 40:
        guard += 1
        i = min(range(len(order) - 1), key=lambda i: order[i + 1]["x0"] - order[i]["x1"])
        order[i:i + 2] = [merge(order[i], order[i + 1])]

    median = float(np.median([b["px"] for b in order]))
    guard = 0
    while len(order) < want and guard < 40:
        guard += 1
        targets = [(b["px"], i) for i, b in enumerate(order) if b["px"] > 1.5 * median]
        halves = None
        for _, i in sorted(targets, reverse=True):
            halves = split(masked, order[i])
            if halves:
                print(f"  {label}: split blob @x{order[i]['x0']} ({order[i]['px']}px)")
                order[i:i + 1] = list(halves)
                break
        if not halves:
            break

    if len(order) != want:
        raise SystemExit(f"{label}: reconciled to {len(order)} icons, expected {want}")
    return order


# ---------------------------------------------------------------- rendering
def matte(cell: Image.Image) -> Image.Image:
    """Clear the paper: flood near-white inwards from the border only."""
    arr = np.asarray(cell.convert("RGBA")).copy()
    light = arr[:, :, :3].min(axis=2) >= MATTE
    labels, _ = ndimage.label(light, structure=np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]]))
    edge = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
    edge.discard(0)
    arr[:, :, 3] = np.where(np.isin(labels, list(edge)), 0, 255)
    return Image.fromarray(arr, "RGBA")


def despeckle(icon: Image.Image, floor: int = 4) -> Image.Image:
    """Drop the sub-pixel crumbs resampling leaves at the art's edge."""
    arr = np.asarray(icon).copy()
    labels, count = ndimage.label(arr[:, :, 3] > 0, structure=np.ones((3, 3)))
    if count:
        sizes = np.bincount(labels.ravel())
        arr[np.isin(labels, np.flatnonzero(sizes < floor))] = 0
    return Image.fromarray(arr, "RGBA")


def render(cell: Image.Image, pre_matted: bool = False) -> Image.Image:
    if pre_matted:
        rgba = cell.convert("RGBA")
        arr = np.asarray(rgba).copy()
        arr[:, :, 3] = np.where(arr[:, :, 3] >= 8, arr[:, :, 3], 0)   # shed the soft fringe
        rgba = Image.fromarray(arr, "RGBA")
    else:
        rgba = matte(cell)
    box = rgba.getchannel("A").getbbox()
    if box is None:
        raise SystemExit("a cell came out empty")
    art = rgba.crop(box)
    limit = CANVAS - 2 * PAD
    scale = min(limit / art.width, limit / art.height)
    w, h = max(2, round(art.width * scale)), max(2, round(art.height * scale))
    w -= w % 2          # even size => the canvas margin splits evenly, pixels stay centred
    h -= h % 2
    art = art.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS))
    canvas.alpha_composite(art, ((CANVAS - w) // 2, (CANVAS - h) // 2))
    return despeckle(canvas)


# ---------------------------------------------------------------- ownership
def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {"built": {}, "manual": []}


def ours_to_write(dest: Path, state: dict) -> bool:
    """Only overwrite files this script wrote and nobody has touched since.
    Anything hand-edited is left alone, permanently, unless --force is passed."""
    if "--force" in sys.argv or not dest.exists():
        return True
    if dest.stem in state["manual"] or digest(dest) != state["built"].get(dest.stem):
        state["manual"] = sorted(set(state["manual"]) | {dest.stem})
        return False
    return True


# ---------------------------------------------------------------- driver
def names() -> list[str]:
    with MANIFEST.open(encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    ids = [r[2] for r in rows[1:] if r and r[0].startswith("icons/items/")]
    start = ids.index("air_staff")
    out = (ids[:FIRST_BATCH]
           + ids[start:start + HERB_RUN]
           + list(REDRAWN)
           + ids[start + HERB_RUN:ids.index("potion_skilling_4") + 1])
    if len(out) != sum(NAME_COUNTS):
        raise SystemExit(f"resolved {len(out)} item ids, sheets carry {sum(NAME_COUNTS)}")
    return out


def verify(files: list[Path]) -> None:
    assert len(files) == len(set(names())), f"{len(files)} files on disk, {len(set(names()))} expected"
    for path in files:
        im = Image.open(path)
        assert im.size == (CANVAS, CANVAS), f"{path.name} is {im.size}"
        assert im.mode == "RGBA", f"{path.name} is {im.mode}"
        alpha = im.getchannel("A")
        assert alpha.getextrema()[0] == 0, f"{path.name} has no transparent pixel"
        box = alpha.getbbox()
        assert box is not None, f"{path.name} is empty"
        x0, y0, x1, y1 = box
        cx, cy = (x0 + x1 - 1) / 2, (y0 + y1 - 1) / 2
        assert abs(cx - (CANVAS - 1) / 2) < 1e-9, f"{path.name} off centre by {cx - 15.5}px in x"
        assert abs(cy - (CANVAS - 1) / 2) < 1e-9, f"{path.name} off centre by {cy - 15.5}px in y"
        assert x0 > 0 and y0 > 0 and x1 < CANVAS and y1 < CANVAS, f"{path.name} is clipped"
        labels, count = ndimage.label(np.asarray(alpha) > 0, structure=np.ones((3, 3)))
        if count:
            sizes = np.bincount(labels.ravel())
            for index in np.flatnonzero(sizes < 4)[1:]:
                peak = int(np.asarray(alpha)[labels == index].max())
                assert peak < 24, f"{path.name} carries a visible {sizes[index]}px speck (alpha {peak})"
    print(f"verified {len(files)} icons: {CANVAS}x{CANVAS} RGBA, centred, unclipped, no visible specks")


def main() -> None:
    files = sorted(DEST.glob("*.png"))
    if "--verify-only" in sys.argv:
        verify(files)
        return

    wanted = names()
    DEST.mkdir(parents=True, exist_ok=True)

    if files and not BACKUP.exists():
        BACKUP.mkdir(parents=True)
        for path in files:
            shutil.copy2(path, BACKUP / path.name)
        print(f"backed up {len(files)} previous icons to {BACKUP}")

    state = load_state()
    state.setdefault("built", {})
    state.setdefault("manual", [])
    if "--force" in sys.argv and state["manual"]:
        keep = BACKUP / "hand_edited"          # --force really does overwrite; bank the tweaks first
        keep.mkdir(parents=True, exist_ok=True)
        for name in state["manual"]:
            if (DEST / f"{name}.png").exists():
                shutil.copy2(DEST / f"{name}.png", keep / f"{name}.png")
        print(f"--force: copied {len(state['manual'])} hand-edited icon(s) to {keep} first")
    written = kept = 0
    offset = 0
    for sheet, count in enumerate(NAME_COUNTS, start=1):
        source = Image.open(SHEETS / f"items{sheet}.png")
        masked, pre_matted = ink_mask(source)
        found = reconcile(blobs(masked, 0 if pre_matted else DILATE), masked, count, f"items{sheet}")
        row = [b["y0"] for b in reading_order(found)]
        print(f"items{sheet}: {count} icons{' (pre-cut)' if pre_matted else ''} (row tops {row})")
        for name, blob in zip(wanted[offset:offset + count], found):
            dest = DEST / f"{name}.png"
            if not ours_to_write(dest, state):
                kept += 1
                continue
            cell = source.crop((max(0, blob["x0"] - 2), max(0, blob["y0"] - 2),
                                min(source.width, blob["x1"] + 3),
                                min(source.height, blob["y1"] + 3)))
            icon = render(cell, pre_matted)
            temp = DEST / f"{name}.png.tmp"
            icon.save(temp, format="PNG", optimize=True)
            temp.replace(dest)
            state["built"][name] = digest(dest)
            written += 1
        offset += count

    STATE.write_text(json.dumps(state, indent=1, sort_keys=True), encoding="utf-8")
    if kept:
        print(f"kept {kept} hand-edited icon(s) untouched: {', '.join(state['manual'])}")
    print(f"wrote {written}, kept {kept} -> {STATE.name} records who owns what")
    verify(sorted(DEST.glob("*.png")))
    print(f"last item written: {wanted[-1]}")


if __name__ == "__main__":
    main()
