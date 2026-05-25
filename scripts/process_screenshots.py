#!/usr/bin/env python3
"""
Crop Pixel 7 (1080×2400) emulator captures down to Play-Store-ready
1080×1920 (9:16) frames.

Play Console rejects phone screenshots whose min:max aspect ratio sits
outside [9:16, 16:9]. Pixel 7 captures at 9:20 — too tall — so they're
rejected as-is. This script:

  1. Strips the system status bar (top 88 px) and gesture nav pill area
     (bottom 60 px) — pure chrome with no app content.
  2. Hard-crops the bottom further to land at 1080×1920 (9:16).
     The top 1920 is kept because that's where the selling content sits
     (animated wordmark, Tonight's Pick, action row, top rec cards) —
     losing the bottom rec rows is preferable to losing the hero.

Also writes a 1080×2252 "loose" variant — the minimum-chrome crop — in
case you want to upload the taller frame instead (some Play accounts
report 1080×2400 working today; 1080×2252 is well under the rejection
threshold but preserves more app content).

Usage:
  python3 scripts/process_screenshots.py <input-dir> [--out <dir>]

Defaults output dir to <input-dir>/processed.

Reads any *.png in input-dir; writes:
  <input>/<name>-1080x1920.png      Play-safe (9:16)
  <input>/<name>-1080x2252.png      Loose (chrome-trimmed only)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

# Pixel 7 emulator chrome heights — fixed values, both screenshots.yml +
# screenshots-real.yml pin `profile: pixel_7` so dimensions are
# deterministic. Conservative — leave a few px of slop so we don't clip
# into the AppBar by accident.
STATUS_BAR_PX = 88
NAV_PILL_PX = 60

EXPECTED_W = 1080
EXPECTED_H = 2400

PLAY_W = 1080
PLAY_H = 1920  # 9:16

LOOSE_W = 1080
LOOSE_H = EXPECTED_H - STATUS_BAR_PX - NAV_PILL_PX  # 2252


def crop_one(src: Path, out_dir: Path) -> bool:
    """Process one PNG. Returns True on success, False on skip."""
    img = Image.open(src)
    if img.size != (EXPECTED_W, EXPECTED_H):
        print(
            f"  SKIP {src.name} — expected {EXPECTED_W}×{EXPECTED_H}, "
            f"got {img.size[0]}×{img.size[1]}",
            file=sys.stderr,
        )
        return False

    # Loose crop: chrome only.
    loose = img.crop((0, STATUS_BAR_PX, EXPECTED_W, EXPECTED_H - NAV_PILL_PX))
    assert loose.size == (LOOSE_W, LOOSE_H), loose.size
    loose_path = out_dir / f"{src.stem}-1080x2252.png"
    loose.save(loose_path, format="PNG", optimize=True)

    # Play-safe crop: take top PLAY_H from the chrome-trimmed image. Keeps
    # the AppBar + hero + top rec cards intact; loses the bottom rows of
    # the rec list, which is acceptable — they aren't the selling content.
    play = loose.crop((0, 0, PLAY_W, PLAY_H))
    assert play.size == (PLAY_W, PLAY_H), play.size
    play_path = out_dir / f"{src.stem}-1080x1920.png"
    play.save(play_path, format="PNG", optimize=True)

    print(f"  OK  {src.name} → {play_path.name} + {loose_path.name}")
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input_dir", type=Path, help="dir with raw 1080×2400 PNGs")
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output dir (default: <input>/processed)",
    )
    args = ap.parse_args()

    if not args.input_dir.is_dir():
        print(f"input not a directory: {args.input_dir}", file=sys.stderr)
        return 2

    out_dir = args.out or (args.input_dir / "processed")
    out_dir.mkdir(parents=True, exist_ok=True)

    pngs = sorted(p for p in args.input_dir.glob("*.png") if p.is_file())
    if not pngs:
        print(f"no PNGs in {args.input_dir}", file=sys.stderr)
        return 1

    print(f"Processing {len(pngs)} PNG(s) → {out_dir}")
    n_ok = sum(1 for p in pngs if crop_one(p, out_dir))
    print(f"\nDone — {n_ok}/{len(pngs)} processed.")
    print(f"Play-safe (1080×1920): use the *-1080x1920.png set.")
    print(f"Loose (1080×2252):     use the *-1080x2252.png set if Play accepts taller.")
    return 0 if n_ok > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
