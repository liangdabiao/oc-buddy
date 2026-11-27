#!/usr/bin/env python3
"""Convert congcong... no wait — oc-english upstream data into oc-buddy packs.

Source: cached repo at .build/oc-src/repo (src-tauri/data):
  books/*.json  13 PEP textbooks, 92 units, 3,493 words (en/zh/phonetic)
  grammar.json  13 grammar points (id/title/explain)
  wardrobe.json 50 items (id/name/slot/price)

Output: data/books.json, data/grammar.json, data/shop.json (wardrobe items).
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT.parent
DEFAULT_REPO = WORKSPACE / ".build" / "oc-src" / "repo"
OUT = ROOT / "data"

GRADE_CN = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def parse_book(book: dict) -> dict:
    title = str(book.get("title", ""))
    stage = str(book.get("stage", book.get("id", "")))
    bid = str(book.get("id", ""))
    # pep-primary-g3-s1 -> grade 3, semester 上; s2 -> 下; junior g9 -> 全
    grade = 0
    semester = ""
    gm = None
    for part in (bid, title):
        import re
        gm = re.search(r"[一二三四五六七八九]年级", part)
        if gm:
            break
    if gm:
        grade = GRADE_CN[gm.group(0)[0]]
    if "-s1" in bid or "上册" in title:
        semester = "上"
    elif "-s2" in bid or "下册" in title:
        semester = "下"
    units_out = []
    for u in book.get("units", []):
        words = []
        for w in u.get("words", []):
            en = str(w.get("en", "")).strip()
            if not en:
                continue
            zh = str(w.get("zh", "")).replace("​", "").strip()
            ph = str(w.get("phonetic", "")).replace("​", "").strip()
            words.append({"en": en, "zh": zh, "phonetic": ph})
        units_out.append({
            "id": str(u.get("id", "")),
            "number": len(units_out) + 1,
            "title": str(u.get("title", "")).strip(),
            "words": words,
        })
    return {
        "id": bid,
        "track": stage,
        "grade": grade,
        "semester": semester,
        "title": title,
        "units": units_out,
    }


def main() -> int:
    repo = DEFAULT_REPO
    data_dir = repo / "src-tauri" / "data"
    books_out = []
    warn = 0
    total_words = 0
    for f in sorted((data_dir / "books").glob("*.json")):
        book = json.loads(f.read_text(encoding="utf-8"))
        parsed = parse_book(book)
        n_words = sum(len(u["words"]) for u in parsed["units"])
        total_words += n_words
        parsed["word_count"] = n_words
        books_out.append(parsed)
    books_out.sort(key=lambda b: (0 if b["track"] == "primary" else 1, b["grade"], b["semester"] == "下", b["semester"] == ""))

    grammar = json.loads((data_dir / "grammar.json").read_text(encoding="utf-8"))
    points = grammar.get("points", [])
    wardrobe = json.loads((data_dir / "wardrobe.json").read_text(encoding="utf-8"))

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "books.json").write_text(json.dumps({"books": books_out}, ensure_ascii=False), encoding="utf-8")
    (OUT / "grammar.json").write_text(json.dumps({"points": points}, ensure_ascii=False), encoding="utf-8")
    (OUT / "shop.json").write_text(json.dumps({"items": wardrobe}, ensure_ascii=False), encoding="utf-8")

    print(f"books={len(books_out)} units={sum(len(b['units']) for b in books_out)} "
          f"words={total_words} grammar={len(points)} shop={len(wardrobe)}")
    return 0 if warn == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
