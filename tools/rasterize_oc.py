#!/usr/bin/env python3
"""Rasterize OC fragment SVGs (resvg) and alpha-diff mixed fragments into
per-part PNGs + a Godot-ready manifest.

- parts: rendered directly (they are pure fragments)
- diffs: render base fragment and top fragment, keep pixels where they differ
  (top drawn over base), producing an isolated top-piece PNG
All outputs share the 200x300 viewBox, rasterized at 2x (400x600).
"""

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT.parent
PARTS = ROOT / ".build" / "oc-parts"
OUT = ROOT / "assets" / "oc"
RESVG = WORKSPACE / ".build" / "resvg" / "resvg.exe"
WIDTH = 400


def render(svg: Path, png: Path) -> bool:
    png.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run([str(RESVG), "--width", str(WIDTH), str(svg), str(png)],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        print(f"  resvg FAIL {svg.name}: {r.stderr.strip()[:100]}", file=sys.stderr)
        return False
    return png.exists()


def diff(base_png: Path, top_png: Path, out_png: Path) -> bool:
    b = Image.open(base_png).convert("RGBA")
    t = Image.open(top_png).convert("RGBA")
    if b.size != t.size:
        t = t.resize(b.size, Image.LANCZOS)
    bp, tp = b.load(), t.load()
    w, h = b.size
    out = Image.new("RGBA", b.size, (0, 0, 0, 0))
    op = out.load()
    n = 0
    for y in range(h):
        for x in range(w):
            bpix, tpix = bp[x, y], tp[x, y]
            if bpix != tpix:
                op[x, y] = tpix
                n += 1
    out_png.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_png, optimize=True)
    return n > 0


def main() -> int:
    manifest = json.loads((PARTS / "manifest.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)

    godot_pieces = []
    fails = 0
    weird = [p for p in manifest["pieces"] if str(p.get("png", "")).startswith("w_")]
    print(f"DEBUG pieces={len(manifest['pieces'])} weird={len(weird)} diffs={len(manifest.get('diffs', []))}")
    for w in weird[:3]:
        print(f"  DEBUG weird entry: {w}")

    # pass 1: direct piece fragments
    cache: dict[str, Path] = {}
    for piece in manifest["pieces"]:
        if "png" not in piece:
            continue                          # wardrobe item placeholder
        svg = PARTS / (piece["png"].replace(".png", ".svg"))
        png = OUT / piece["png"]
        if render(svg, png):
            cache[piece["png"]] = png
            godot_pieces.append({"slot": piece["slot"], "key": piece["key"],
                                 "png": piece["png"]})
        else:
            fails += 1

    # pass 2: diffs (base/top are piece-fragment PNGs rendered above or mixed tops)
    diff_out = []
    for d in manifest.get("diffs", []):
        top_svg = PARTS / (d["top"][:-4] + ".svg") if d["top"].endswith(".png") else PARTS / (d["top"] + ".svg")
        top_png = OUT / f"{d['top']}.png"
        if not render(top_svg, top_png):
            fails += 1
            continue
        if not d["base"]:
            base_png = OUT / "__transparent.png"
            if not base_png.exists():
                Image.new("RGBA", (WIDTH, int(WIDTH * manifest["viewBox"][1] / manifest["viewBox"][0])), (0, 0, 0, 0)).save(base_png)
        else:
            base_png = OUT / f"{d['base']}.png"
        if not base_png.exists():
            # base may be a mixed fragment too (e.g. core with hair) — render it
            base_svg = PARTS / f"{d['base']}.svg"
            if base_svg.exists():
                if not render(base_svg, base_png):
                    fails += 1
                    continue
            else:
                print(f"  base missing {d['base']} for {d['out']}", file=sys.stderr)
                fails += 1
                continue
        out_png = OUT / f"{d['out']}.png"
        if diff(base_png, top_png, out_png):
            diff_out.append({"slot": d["slot"], "key": d["key"], "png": d["out"] + ".png"})
        cache[d["out"] + ".png"] = out_png

    godot_pieces.extend(diff_out)

    # final Godot manifest: pieces + optional items list
    wardrobe = json.loads((ROOT / "tools" / "wardrobe_items.json").read_text(encoding="utf-8"))
    godot = {
        "viewBox": manifest["viewBox"],
        "render_width": WIDTH,
        "pieces": godot_pieces,
        "items": [{"id": w["id"], "name": w["name"], "slot": w["slot"], "price": w["price"]}
                  for w in wardrobe],
    }
    (OUT / "oc_manifest.json").write_text(json.dumps(godot, ensure_ascii=False), encoding="utf-8")

    total = sum(p.stat().st_size for p in OUT.glob("*.png"))
    print(f"pieces={len(godot_pieces)} fails={fails} total={total / 1024 / 1024:.1f} MiB")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
