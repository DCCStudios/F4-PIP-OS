# PIP-OS Pip-Boy Rework

A full visual replacement of the Fallout 4 Pip-Boy menu in the "PIP-BOY OS V2.7.1" concept style,
built as a companion to Baka Fullscreen Pip-Boy (Nexus 73560). The concept reference image is the
modern fullscreen terminal look: phosphor-green chrome on a dark scene, left sidebar tabs, live
character portrait center, dense data tables right, item detail card, quick-access row, footer keybar.

## Locked decisions (2026-08-15)

- **Ownership** (REVISED + LOCKED 2026-08-15): our mod owns **only `PipboyMenu.swf`** (the shell)
  and ships all five pages under **new `PipOS_*Page.swf` names**, not the vanilla filenames. Our
  shell loads the PIP-OS page per tab by default (full design, unchanged); a per-tab MCM toggle
  can instead load the external `Pipboy_*Page.swf` that wins the MO2 conflict (e.g. FallUI Map),
  with a load-failure fallback to our page. This supersedes the earlier "own all five files"
  decision. Rationale + RE evidence in `docs/FallUICompat.md`. FallUI Inventory users let FallUI's
  menu win the `PipboyMenu.swf` conflict (PIP-OS simply inactive) — the supported opt-out.
- **PipboyTabs compatibility is required.** Keep the vanilla Scaleform contract (instance names,
  `BGSCodeObj` invoke paths, tab-list structure) so PipboyTabs' DLL can inject extra tabs
  (CHALLENGES - F4NV, Companion Affinity, Magazine Perks, Survival Mode Overhaul). Extra tabs render
  as additional sidebar entries.
- **Item names render as-is** — no Complex Sorter tag stripping/parsing in v1.
- **Companion F4SE DLL targets OG 1.10.163 only** (MagnumOpus). TF3DHUD-master is the reference for
  the live 3D preview clone (equipment, cloth, morphs, own render tree); click-drag rotates it.
- **Power armor Pip-Boy stays vanilla in v1.**
- **Art is vector-first**: chrome/icons authored as vectors in the SWF, vanilla icon libraries reused
  where they fit; AI generation only for organic textures, each piece user-approved before use.
- Footer hotkeys must all map to real current-menu functions (per-page keybars mirror vanilla:
  INV inspect/drop/cycle damage/fav/sort/perk chart, DATA show-on-map/summary, MAP place marker/local
  map, STAT stimpak/radaway). The "E" hotkeys at the top of the concept are ignored.
- Baka provides fullscreen framing; we also override its `PipboyBackgroundMenu*.swf` so the backdrop
  matches the design. 16:9 first; Baka's 16:10/21:9 variants follow later.

## References

- Concept art: user-supplied "PIP-BOY OS V2.7.1" render (INV page). Other pages are designed by us
  in the same language; vanilla fullscreen screenshots supplied for content parity per tab.
- Vanilla SWFs: `D:\Fallout 4 Interface Source\Interface\PipboyMenu.swf`, `Pipboy_{Stats,Inv,Data,Map,Radio}Page.swf`
- FallUI stack (contract + conflict reference): `F:\Modlists\MagnumOpus\mods\FallUI - Inventory`, `- Map`, `- Inventory Fix`, `Fire Rate Shows RPM`
- PipboyTabs framework: `F:\Modlists\MagnumOpus\mods\PipboyTabs` (DLL + PipboyTabs.swf + PBT papyrus API)
- Baka Fullscreen Pip-Boy: `F:\Modlists\MagnumOpus\mods\Baka Fullscreen Pip-Boy and Quick-Boy`,
  source https://github.com/shad0wshayd3-FO4/BakaFullscreenPipboy
- SWF authoring pipeline conventions: `..\FallUI HUDs\S2 HUD Rework` (mxmlc build, font transplant,
  package/verify scripts, F4SE Menu Framework settings page)
- 3D preview clone: `..\PluginTemplate\TF3DHUD-master`
- JPEXS decompiler: `..\PluginTemplate\jpexs-decompiler-master` / `jpexs-gui`

## M1 feedback round 1 (2026-08-15)

- Mockup background is the user's in-game 4K screenshot (blurred/darkened), simulating the live scene.
- Typeface: **Arimo Stalker Bold** (embedded from the S2 HUD build; Apache 2.0). Monofonto was the
  user's alternative but no TTF exists on disk. In-game font transplant happens at M4.
- **No condition stat anywhere, no penetration** — concept-art flavor only; FO4 has neither.
- Selected-row text: near-white with dark drop shadow (green-on-green readability complaint).
- Character stand-in: FO Cascadia soldier renders (front/back cutouts via `tools/prep_mockup_images.ps1`),
  flip-card drag rotation, vector AR-15 slung on the front face (pending user approval — offer an AI
  image pass if the vector prop isn't good enough). Real implementation is a live 3D capture of the
  actual player character (M5 preview clone) — the images are mockup-only.
- All sub-tabs are fleshed out: INV Weapons/Apparel/Aid/Misc/Junk/Ammo with per-category columns and
  item cards; STAT Status/Special/Perks; DATA Quests/Workshops/Stats; MAP World/Local.
- MAP page: the engine renders the same world/local map Fullscreen Pip-Boy shows today; our SWF only
  draws chrome and markers over it (noted on the mockup itself).
- Mockup is now template + build: `Previews/pipos-mockup.template.html` + `tools/build_mockup.ps1`
  (token-injects base64 assets) -> `Previews/pipos-mockup.html`.

## M1 feedback round 2 (2026-08-15)

- Fixed: sub-tab panels (STAT Special/Perks, DATA Workshops/Stats) rendered below the fold —
  inline `display:grid` beat the `.sub` hide rule; layout moved to `.sub.cols.shown` classes.
- Quick Access label moved under the slots; item-card stat values nowrap/right-aligned.
- Icons per user reference: caps = circle + script "C" (Nuka cap), weight = ring-handle weight.
- Drag fix: `draggable=false`, `preventDefault`, window-level pointer listeners, `touch-action:none`.
- **Meshy pipeline live** (user's key at `C:\Users\rober\Documents\meshy key.txt`, never echoed):
  nano-banana-pro image-to-image gave the soldier an AR-15 (multi-view, 9 cr, approved by user);
  image-to-3D produced `Previews/assets/gen/soldier.glb` (30k tris, 2k texture, 4.3 MB, 30 cr).
  Gotcha: multi-view i2i task ids are rejected as `input_task_id` — pass the frame as a base64
  `image_url` instead. 3D model awaiting user approval (back-side pouches simplified).
- Mockup now embeds the GLB with a custom ~200-line inline WebGL viewer (no three.js): turntable
  with inertia + idle spin, phosphor rim light, flip-card fallback. See user skill `ui-mockup-webgl`.
- Workflows saved as user skills: `meshy-generation`, `ui-mockup-webgl`.

## M1 feedback round 3 (2026-08-15)

- Weight icon iterations: kettlebell → ring-handle weight → **distinct backpack** (dome top,
  handle, zip line, front pocket) per user; item-card chip had been missed earlier due to a
  whitespace variant (lesson: grep for the old asset's signature after replace-all).
- Spin pivot fixed: bbox center made him orbit (rifle skews the mesh inside its bounds); pivot
  and camera now use the spine axis (head-slab + feet-slab centroid average).
- **Rig + animate pipeline**: Meshy rigging (5 cr, from the i23d task) + animation action 0
  "Idle" breathing loop (3 cr) → `Previews/assets/gen/soldier_anim.glb` (7.5 MB). Viewer
  upgraded to skinned rendering: live node hierarchy, channel sampling, GPU skinning with a
  compiled-in bone count, static fallback. Credits total so far ≈ 47.
- Low-motion idle chosen deliberately: the rifle is fused into the mesh, so big arm motion
  (combat stances) would stretch it.

## M1 feedback round 4 (2026-08-15)

- "He's gone" bug: accessor component-count map lacked MAT4, so inverse bind matrices read as
  empty arrays → NaN joint matrices → all vertices collapsed (no GL errors). Found by exporting
  a `window.__pipos` probe and driving the built page headless (puppeteer-core + installed Edge)
  — NaN serializes to null in JSON, which was the tell. Headless render test lives at
  scratchpad `test_mockup.js`; consider promoting a copy into `tools/`.
- Hardened viewer: `uSkin[0]` location fallback, webglcontextlost → flip-card revert, camera
  margin 1.12→1.24. Weight icon now a filled rucksack silhouette per user's second reference
  (evenodd holes for handle/flap/pocket; chips' stroke CSS overridden per-path).

## M1 feedback round 5 (2026-08-15)

- User reverted the breathing idle — static model back (build prefers `soldier.glb`;
  `soldier_anim.glb` kept on disk if ever wanted). Quick Access label enlarged to 12px.
- `<meta charset="utf-8">` added — file:// loads showed mojibake without it (artifact HTTP
  header masked the omission).
- **R-press Inspect**: viewer refactored to multi-scene (createScene per GLB, shared programs,
  scene switch resets orbit). R / keybar-chip click toggles a weapon turntable with an
  "Inspect · <item>" chip; Esc or page switch exits. Camera now fits by bounding radius
  (weapons are long, not tall); spine pivot applies only to humanoid-proportioned models.
- Weapon asset: nano-banana t2i (3 cr; PS gotcha — single-element `image_urls` unrolls to a
  string, index with `@(...)`[0]; task id saved for resume so the failed download cost nothing)
  → image-to-3d chained via `input_task_id` (plain t2i mode chains fine, unlike multi-view).

## M1 feedback round 5 addendum (2026-08-15)

- Weapon pipeline delivered `weapon.glb` (4.3 MB, 30 cr + 3 cr t2i, ~80 cr project total).
  R-press Inspect verified headless: title chip, weapon turntable, R/Esc/keybar-click toggles.
- Weapon rendered ghost-pale at first: thin geometry puts every fragment at grazing angle so the
  rim term washed it; ambient/rim now per-scene uniforms (`uLit`), and the remaining lightness is
  the actual albedo (Meshy strips lighting from base color; its dark thumbnails are PBR+AO).

## M1 feedback round 6 (2026-08-15)

- Column headers now share per-column alignment with their cells (the right-align rule was
  scoped `.row .num` and missed `.head`; text columns like Ammo/Slot are left-paired).
- **Inspect is now the vanilla-style fullscreen takeover**: `#inspectlay` overlay dims+blurs the
  menu via backdrop-filter; the WebGL canvas reparents into it (context survives) and
  FLIP-animates from the character panel to center screen, scaling from ~0; on landing the
  title, STATS table, and CURRENT MODS panel fade in. W/S cycle items, wheel zooms (camera dist
  multiplier), R/Esc flies it back. No idle spin during inspect — side profile holds like vanilla.

## M1 feedback round 7 (2026-08-15)

- **User rule (standing): every drawn element has a defined purpose** — controls act, readouts
  read, flavor is declared flavor. Full inventory in `docs/FunctionalitySpec.md`; audit every
  milestone against it.
- Mockup now functional everywhere: X drop, Q fav ★, Z sort cycle (title shows mode), C damage-
  type cycle, quick slots 1–7 consume+pulse, E/R consumables with live keybar counts + bar pulse,
  DATA R/C (show-on-map / summary toggle), MAP click-to-place custom marker + R world/local,
  RADIO select+Enter tune with off-state flatline scope, T perk chart nav from every page,
  Esc closes the Pip-Boy (scene sharpens, ESC reopens), every keybar chip clickable.
- Quest log rebuilt: active quests, **Miscellaneous with individually selectable objectives**,
  `COMPLETED` separator with dimmed finished quests. All verified headless (test_actions.js).

## M1 feedback round 8 (2026-08-15)

- Click feedback everywhere (element pulse + stage-level pointer ripple that survives list
  re-renders; reduced-motion suppressed). Auto-rotate now opt-in via right-click on the viewport.
- **STAT limb rework**: the limbs panel is gone; six limb chips anchor around the figure
  (head/arms/legs/torso) with severity colors, and clicking a chip applies a stimpak to that
  limb (count/keybar update, bar pulses). `V` toggles the center figure between the DLL
  character capture and the **vanilla Vault Boy** — extracted from
  `Interface/Components/ConditionClips/Condition_Body_0.swf` + `Condition_Head.swf` via JPEXS
  SVG export (art sits off-stage: widen the viewBox, render headless, namespace colliding
  ffdec ids when compositing two exports, tint white→phosphor). Recipe matters for M4: vanilla
  Vault Boy condition art loads per damage state from those component SWFs.

## M1 feedback round 9 (2026-08-15)

- Right-click auto-spin fixed (two bugs: any-button drags capturing the pointer, and the
  contextmenu listener firing twice via bubbling — button guard + stopPropagation). Hint caption
  now word-wraps inside the panel.
- **Sounds are a standing SWF requirement** — every interactive control gets the appropriate
  vanilla UI sound event; exact event names to be confirmed during M2 RE (vanilla + Baka
  reference). Spec section added.
- **Legendary inspect**: Instigating .308 Hunting Rifle added; ✦ glow marker in list + item
  card effect line; inspect shows pulsing ✦ LEGENDARY badge + vanilla-style effect sentence
  under the title, and the hologram rim light shifts gold while inspecting a legendary
  (uRimC shader uniform).
- **FallUI compatibility investigated** — full findings in `docs/FallUICompat.md`. Headline:
  vanilla PipboyMenu runtime-loads pages by filename (pages are swappable modules); FallUI Map
  is standalone, FallUI InvPage requires FallUI's menu-seeded M8r framework. Recommendation
  (pending user approval): ship our pages as `PipOS_*Page.swf`, own only `PipboyMenu.swf`,
  per-tab external-page passthrough with load-failure fallback.

## Milestones

1. **M1 — Design mockups** ✅ DONE (user-approved): interactive HTML preview of all five pages.
   `Previews/pipos-mockup.html`, published as an artifact.
2. **M2 — Contract RE** ✅ DONE (VERIFIED-STATIC): `docs/ScaleformContract.md` — full BGSCodeObj
   surface, Pipboy_DataObj field→page map, PipboyPage/PipboyLoader contract, PipboyTabs hook points,
   ConditionBoy composite, and the UI sound-event table.
3. **M3 — Chrome SWF** ✅ DONE (VERIFIED-STATIC contract + CRT chrome restyle, Ruffle-render-confirmed):
   PIP-OS `PipboyMenu.swf` = vanilla shell with ONLY the PipboyMenu class additively patched (loader
   table → `PipOS_*Page.swf` + `SetPageMode` + fallback; PLUS load a separate `PipOS_Chrome.swf` CRT
   overlay as a ROOT SIBLING of Menu_mc). Verified: 47/48 classes byte-identical, SymbolClass unchanged,
   and a child-index safety check confirms Menu_mc.getChildAt(4)=page is preserved (PipboyTabs-safe).
   Chrome (`pipos.Chrome`, separate SWF, embedded Arimo): CRT bezel, live clock card, clickable phosphor
   sidebar (STAT/INV/DATA/MAP/RADIO + side-notes + EXT section mirroring PipboyTabs-injected tabs),
   badge/telemetry, scanlines, time-based CRT boot/collapse. Rendered clean in Ruffle (chrome-only host).
4. **M4 — Page SWFs** ✅ BUILT + VERIFIED-STATIC + RUFFLE-COMPOSITE-CONFIRMED (real-engine GFx still
   unverified): all five `PipOS_*Page.swf` authored as code-only PipboyPage subclasses (mxmlc + external
   stub SWC), **re-authored to the true 876x700 stage** with a left sidebar gutter, live DataObj
   bindings + vanilla BGSCodeObj calls + M2 sound table, **single input path per action**
   (ProcessUserEvent named controls; no double-fire; gamepad-reachable), STAT figure via the vanilla
   ConditionClips Vault Boy composite, Arimo Stalker Bold embedded (DefineFont3). Each: CWS/version 15,
   extends PipboyPage, zero stubs embedded (verify_pages.ps1 PASS). Proven with chrome+page COMPOSITES
   rendered at 876x700 (0 AS errors; content fits, sidebar clear).
   **Design-fidelity pass (round 6):** re-laid to the M1 mockup — INV 3-column (EQUIPMENT | CHARACTER |
   LIST-with-headers + CARD), STAT framed meters + SPECIAL tiles + limb chips around the figure + LEVEL
   bar; footer keybar (from buttonHintDataV); sidebar tab icons + EXTENSIONS/[EXT]; rounded panels +
   glow + vector icons. Side-by-side proof: `Previews/round6-fidelity-sidebyside.png` (ref | composite ×5).
5. **M5 — Preview DLL** ✅ BUILT (compiles + links + valid PE; in-game unverified; capture STUBBED):
   `dll/` OG-only commonlibf4 plugin — OG 1.10.163 gate, INI→`root1.Menu_mc.SetPageMode` bridge via a
   MenuOpenClose sink (no code hooks), Vault-Boy fallback stub for the 3D capture. 551 KB DLL emitted.
6. **M6 — Package** ✅ DONE (VERIFIED-STATIC): `tools/{build_shell,verify_shell,build_pages,
   verify_pages,preview_pages,package}.ps1` → `dist/PipOSPipboy-1.0.0.zip` (mod-root layout: Interface\
   + F4SE\, no Data\ wrapper; shell + 5 pages + PipOS_Chrome + PipboyBackgroundMenu override + INI +
   compiled DLL + Arimo license + README with 11-step in-game checklist).

**Baka background override** ✅ SHIPPED 16:9 (BUILT-UNVERIFIED vs Baka DLL): `PipboyBackgroundMenu.swf`
1920x1080 CRT framing, structural drop-in (same class name + Background_mc + header). 16:10/21:9/Small
variants NOT shipped yet. Extends MovieClip not Baka's IMenu — documented risk + fallback in README.

---

## AUTHORITATIVE MOCKUP REFERENCE (2026-08-17, from user STAT+INV screenshots)
This SUPERSEDES the round-6 captures as the layout of record. Target is natively **16:9
widescreen, full-width**, everything over the blurred game world (CRT transparency). NO vanilla
UI anywhere (no vanilla bottom bar; all readouts integrated).

THIN TOP HEADER STRIP (dim-green FLAVOR [ui-every-element-has-purpose: documented flavor]):
  left "PIP-BOY OS V2.7.1" | center "SSS NFO 3247-98A · CONNECTION — STABLE" | right "PROPERTY OF VAULT-TEC".

LEFT COLUMN = Item A chrome (0.0.21), top->bottom:
  - Page tabs stacked VERTICALLY, each = icon + label in a rounded box: STAT(pulse) INV(lock)
    DATA(document) MAP(pin) RADIO(antenna). ACTIVE = lit/filled box + left accent bar; inactive = outline.
  - Between tabs, small DIM FLAVOR codes: "INV 04.JK.E" "DB 1A.F7.G" "GPS 77.7F.E" "SIG S.T60.B"
    (documented flavor telemetry).
  - Below RADIO: label "EXTENSIONS · PIPBOYTABS", then PipboyTabs addon pages as tabs w/ [EXT] badge:
    CHALLENGES[EXT] AFFINITY[EXT] MAGAZINES[EXT]. Source = PipboyTabs _TabNames beyond index 4; read
    dynamically if feasible, static 3 acceptable first pass. Click => TryToSetPage(5+).
  - Bottom-left: clock block "10.23.2287" / "11:10 AM" / "PIP-OS(R) V2.7.1".

MAIN AREA sub-tabs (horizontal, top): STAT = STATUS/SPECIAL/PERKS; INV = WEAPONS/APPAREL/AID/MISC/
  JUNK/AMMO (mockup shows 6, NO "MODS" — but ENGINE categories drive it; flag if game gives 7).

INV PAGE content:
  - Top-right integrated readouts: WEIGHT 128.6/210 and caps 5247 (NOT a vanilla bottom bar).
  - LEFT EQUIPMENT panel: rows HEAD/TORSO/LEFT ARM/RIGHT ARM/LEFT LEG/RIGHT LEG/UNDER ARMOR/OUTFIT/
    BACKPACK/PIP-BOY, each = EQUIPPED ITEM NAME. Mockup: HEAD=GP-5 Gas Mask, TORSO=Mercenary Jacket,
    L/R ARM=Leather Armwrap, L/R LEG=Combat Pants, UNDER ARMOR=Wasteland Undershirt, OUTFIT=Loner
    Trench Coat, BACKPACK=Field Backpack, PIP-BOY=Pip-Boy 3000 Mark IV. => 0.0.20 DLL equip push target.
  - CENTER: real 3D EQUIPPED CHARACTER (not Vault Boy) caption "LIVE CAPTURE · DRAG TO ROTATE · RIGHT-
    CLICK TO AUTO-SPIN · IN-GAME: YOUR EQUIPPED CHARACTER" = M5 3D-capture goal (DEFERRED; Vault Boy is
    placeholder). Below: QUICK ACCESS = 7 slots, each ITEM-TYPE ICON + count (mockup 3/2/1/2/2/4/3).
    => P4 quick-access redesign MUST have icons (hunt an item-type/category glyph source; DLL may push
    an icon id if AS can't derive it).
  - RIGHT: INVENTORY·WEAPONS list, columns NAME/AMMO/WT/VAL ALL FILLED per row (e.g. "Automatic Combat
    Rifle ★ | 5.56 (225) | 11.1 | 214"; ammo = TYPE (count)); ★ = favorite. => per-row-columns target;
    currently BLOCKED (no stable AS row key). Backtick dump of InvItems[0] is decisive — if a hidden
    weight/value/formID field exists, columns become fillable. Until then columns stay blank; do NOT fake.
  - BELOW list: item card — name / caliber (5.56×45MM) / wt / caps / DAMAGE·BALLISTIC / FIRE RATE /
    RANGE / ACCURACY / description (ItemCard InfoObj render already covers most).

STAT PAGE content (FUTURE custom build; currently stock vanilla — record only): STATUS/SPECIAL/PERKS;
  HP/AP/RADS horizontal bars; SPECIAL = 7 tiles (STR/PER/END/CHA/INT/AGI/LCK + values); 3D character
  centered w/ LIMB-HEALTH labels+bars (HEAD top, L/R ARM mid, L/R LEG lower, TORSO bottom); LEVEL + XP
  bar top-right; ACTIVE EFFECTS panel right (EFFECT/SOURCE table, e.g. "+10% XP gained / Well Rested").

BOTTOM KEYBAR (both pages): ESC BACK + context keys. INV: R INSPECT / X DROP / C CYCLE DAMAGE / Q FAV /
  Z SORT / T PERK CHART. STAT: E STIMPAK / R RADAWAY / V VAULT BOY / T PERK CHART.

16:9 SPIKE reinforced: the mockup is natively 16:9; our 876×700 squish is the root of the cramped gap.
