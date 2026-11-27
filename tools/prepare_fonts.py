#!/usr/bin/env python3
"""Build the font subset for school-buddy.

- ui.ttf: DengXian subset covering every character that appears in
  data/content.json plus every character that appears in scripts/*.gd
  (UI strings live in code, so scanning the sources covers them).
- code.ttf: DejaVu Sans Mono, copied in full (math glyphs + code).

Then audit: every character needed must exist in the produced cmap.
This is mandatory — a hollow .notdef box passes pixel checks but not cmaps.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT.parent
SCRIPTS = ROOT / "scripts"
UI_SOURCE = Path("C:/Windows/Fonts/Deng.ttf")
CODE_SOURCE = WORKSPACE / "english-buddy" / "assets" / "fonts" / "ipa.ttf"
OUT_UI = ROOT / "assets" / "fonts" / "ui.ttf"
OUT_CODE = ROOT / "assets" / "fonts" / "code.ttf"

EXTRA_CHARS = "āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜüÀÉÎǑŪà0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ()[]{}<>+-*/=.,:;!?'\"|&@#$%^~_ \\①②③④⑤⑥⑦⑧⑨⑩●○·×÷≤≥≠≈±→←√Ωθ²³…—“”‘’、。，；：？！"


def collect_text() -> str:
    parts: list[str] = []

    def walk(node) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("img", "thumb", "id", "source", "cover"):
                    continue
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, str):
            parts.append(node)

    for unit_file in sorted((ROOT / "data").glob("*.json")):
        walk(json.loads(unit_file.read_text(encoding="utf-8")))
    for script in sorted(SCRIPTS.glob("*.gd")):
        parts.append(script.read_text(encoding="utf-8"))
    return "".join(parts) + EXTRA_CHARS


def subset_ui(charset: set[str]) -> None:
    args = [
        str(UI_SOURCE),
        f"--output-file={OUT_UI}",
        "--layout-features=",
        "--no-hinting",
        "--desubroutinize",
    ]
    argv = args + [f"--unicodes={codepoint}" for codepoint in sorted(charset_to_unicodes(charset))]
    subset.main(argv)


def charset_to_unicodes(charset: set[str]) -> list[str]:
    out = []
    for ch in charset:
        cp = ord(ch)
        if cp == 0x0A or cp == 0x0D or cp == 0x09:
            continue
        out.append(f"{cp:04X}")
    return out


IPA_CHARS = "ăŋɒɔəɛɪʃʊʌʒːɚɜɝˈˌɑæðθɪᵻ"


def audit(charset: set[str]) -> list[str]:
    """ui.ttf must cover everything except IPA chars (rendered with code.ttf)."""
    font = TTFont(str(OUT_UI))
    cmap = font.getBestCmap()
    missing = sorted(ch for ch in charset
                     if ord(ch) > 0x20 and ch not in IPA_CHARS and ord(ch) not in cmap)
    code_cmap = TTFont(str(OUT_CODE)).getBestCmap() if OUT_CODE.exists() else {}
    ipa_missing = sorted(ch for ch in IPA_CHARS if ord(ch) not in code_cmap)
    return missing + ipa_missing


def main() -> int:
    text = collect_text()
    charset = set(text)
    charset.add(" ")
    OUT_UI.parent.mkdir(parents=True, exist_ok=True)
    print(f"charset size: {len(charset)}")
    subset_ui(charset)
    if CODE_SOURCE.exists():
        OUT_CODE.write_bytes(CODE_SOURCE.read_bytes())
    else:
        print(f"WARNING: code font source missing: {CODE_SOURCE}", file=sys.stderr)
    missing = audit(charset)
    ui_size = OUT_UI.stat().st_size / 1024
    code_size = OUT_CODE.stat().st_size / 1024 if OUT_CODE.exists() else 0
    print(f"ui.ttf {ui_size:.0f} KiB, code.ttf {code_size:.0f} KiB")
    if missing:
        print(f"MISSING GLYPHS ({len(missing)}):", file=sys.stderr)
        for ch in missing[:80]:
            print(f"  U+{ord(ch):04X} {ch!r}", file=sys.stderr)
        return 1
    print("cmap audit passed: no missing glyphs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
