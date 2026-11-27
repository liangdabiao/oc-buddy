from pathlib import Path

p = Path('oc-buddy/tools/rasterize_oc.py')
s = p.read_text(encoding='utf-8')
s = s.replace('''    godot_pieces = []
    fails = 0''',
'''    godot_pieces = []
    fails = 0
    weird = [p for p in manifest["pieces"] if str(p.get("png", "")).startswith("w_")]
    print(f"DEBUG pieces={len(manifest['pieces'])} weird={len(weird)} diffs={len(manifest.get('diffs', []))}")
    for w in weird[:3]:
        print(f"  DEBUG weird entry: {w}")''')
p.write_text(s, encoding='utf-8')
print('patched')
