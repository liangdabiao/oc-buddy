// Generate per-fragment SVGs for every OC body/hair/face/outfit piece,
// calling the upstream character.js builder (viewBox 0 0 200 300).
// Output: SVGs into OUT_DIR + manifest.json describing Godot sprite slots.
//
// Run: node tools/gen_oc_parts.mjs <upstream_repo_src_js_dir> <out_dir>

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const SRC = resolve(process.argv[2]);        // .../src/js
const OUT = resolve(process.argv[3]);        // output dir
const UP = pathToFileURL(SRC + '/character.js').href;
const UPW = pathToFileURL(SRC + '/wardrobe.js').href;

const C = await import(UP);
const W = await import(UPW);

// static wardrobe art must be registered before building (getArt looks here)
C.registerCustomArt(Object.entries(W.WARDROBE_ART).map(([id, art]) => ({ id, art })));

mkdirSync(OUT, { recursive: true });

const manifest = { viewBox: [C.VB_W, C.VB_H], pieces: [] };

function emit(name, fragment) {
  if (!fragment || fragment.trim() === '') return null;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${C.VB_W} ${C.VB_H}" width="${C.VB_W}" height="${C.VB_H}">${fragment}</svg>`;
  writeFileSync(`${OUT}/${name}.svg`, svg);
  return `${name}.png`;
}

// ---- body pieces (per skin tone), from a bare cfg
const nSkin = C.SKIN_TONES.length;
for (let s = 0; s < nSkin; s++) {
  const l = C.buildCharacterLayers({ skin: s });
  manifest.pieces.push({ slot: 'armL', key: `body_s${s}`, png: emit(`body_s${s}_armL`, l.armL) });
  manifest.pieces.push({ slot: 'armR', key: `body_s${s}`, png: emit(`body_s${s}_armR`, l.armR) });
  manifest.pieces.push({ slot: 'legL', key: `body_s${s}`, png: emit(`body_s${s}_legL`, l.legL) });
  manifest.pieces.push({ slot: 'legR', key: `body_s${s}`, png: emit(`body_s${s}_legR`, l.legR) });
  manifest.pieces.push({ slot: 'core_body', key: `body_s${s}`, png: emit(`body_s${s}_core`, l.core) });
}

// ---- hair: back layer is pure hair; front needs diff (mixed with CORE)
const nHair = C.HAIR_LIST.length;
const nHairC = C.HAIR_COLORS.length;
for (let h = 0; h < nHair; h++) {
  for (let c = 0; c < nHairC; c++) {
    const l = C.buildCharacterLayers({ skin: 0, hair: h, hairColor: c });
    const png = emit(`hairb_${h}_${c}`, l.back);
    if (png) manifest.pieces.push({ slot: 'hair_back', key: `hair_${h}_${c}`, png });
    // front: emitted as full core fragment (CORE + eyes-less mouth-less + hair front)
    // we rasterize and diff downstream; here emit the mixed fragment
    const lf = C.buildCharacterLayers({ skin: 0, hair: h, hairColor: c });
    const front_mixed = emit(`hairf_mix_${h}_${c}`, lf.core);
    if (front_mixed) manifest.diffs = manifest.diffs || [];
    manifest.diffs.push({ base: 'body_s0_core', top: `hairf_mix_${h}_${c}`, out: `hairf_${h}_${c}`, slot: 'hair_front', key: `hair_${h}_${c}` });
  }
}

// ---- eyes (with mirror) per style x color, per skin
const nEyes = C.EYE_LIST.length;
const nEyeC = C.EYE_COLORS.length;
for (let e = 0; e < nEyes; e++) {
  for (let c = 0; c < C.EYE_COLORS.length; c++) {
    for (let s = 0; s < nSkin; s++) {
      const l = C.buildCharacterLayers({ skin: s, eyes: e, eyeColor: c });
      manifest.diffs.push({ base: `body_s${s}_core`, top: emit(`eyemix_s${s}_${e}_${c}`, l.core), out: `eyes_s${s}_${e}_${c}`, slot: 'eyes', key: `eyes_${e}_${c}_s${s}` });
    }
  }
}

// ---- mouths per skin
const nMouth = C.MOUTH_LIST.length;
for (let m = 0; m < nMouth; m++) {
  for (let s = 0; s < nSkin; s++) {
    const l = C.buildCharacterLayers({ skin: s, mouth: m });
    manifest.diffs.push({ base: `body_s${s}_core`, top: emit(`mouthmix_s${s}_${m}`, l.core), out: `mouth_s${m}_s${s}`, slot: 'mouth', key: `mouth_${m}_s${s}` });
  }
}

// ---- blush per skin
for (let s = 0; s < nSkin; s++) {
  const l = C.buildCharacterLayers({ skin: s, showBlush: true });
  manifest.diffs.push({ base: `body_s${s}_core`, top: emit(`blushmix_s${s}`, l.core), out: `blush_s${s}`, slot: 'blush', key: `blush_s${s}` });
}

// ---- wardrobe: 50 items; wear one at a time, diff each affected layer
const items = JSON.parse(readFileSync(new URL('./wardrobe_items.json', import.meta.url)));
for (const item of items) {
  const slotName = item.slot;
  for (let s = 0; s < nSkin; s++) {
    const outfit = {};
    outfit[slotName] = item.id;
    const lWith = C.buildCharacterLayers({ skin: s, outfit });
    const lBase = C.buildCharacterLayers({ skin: s });
    for (const layer of ['back', 'armL', 'armR', 'legL', 'legR', 'core']) {
      if (lWith[layer] === lBase[layer]) continue;      // untouched layer
      const top = emit(`w_${item.id}_s${s}_${layer}`, lWith[layer]);
      if (!top) continue;
      // back layer has no body base piece: diff against a transparent canvas
      const base = layer === 'back' ? '' : `body_s${s}_${layer}`;
      manifest.diffs.push({ base, top, out: `w_${item.id}_s${s}_${layer}`, slot: `w_${slotName}`, key: `${item.id}_s${s}` });
    }
  }
  manifest.pieces.push({ slot: `w_${slotName}`, key: item.id, item: item.id });
}

writeFileSync(`${OUT}/manifest.json`, JSON.stringify(manifest, null, 1));
console.log(`emitted pieces+diffs; pieces=${manifest.pieces.length} diffs=${(manifest.diffs || []).length}`);
