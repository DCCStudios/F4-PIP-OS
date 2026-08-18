# PIP-OS mockup reference screens

Per-screen renders of the approved design mockup (`Previews/pipos-mockup.html`, artifact
`4d9ce822-...`), at the mockup's native **1600x900** stage. These are the visual source of truth
for matching layout, spacing, color, and content. **Consult the relevant image before laying out or
reviewing any page.** DESIGN.md's textual "AUTHORITATIVE MOCKUP REFERENCE" is the words; these are the
picture. When the two disagree, the image wins (e.g. STAT SPECIAL is an attribute *list*, not tiles).

## Files
- `mockup-inv.png` — INVENTORY / Weapons (default). 3-col: EQUIPMENT (slot->item) | 3D character + QUICK ACCESS (icons+count) | NAME/AMMO/WT/VAL list + item card below. Top-right WEIGHT/CAPS.
- `mockup-stat.png` — STAT / Status (default).
- `mockup-stat-special.png` — STAT / SPECIAL: S.P.E.C.I.A.L. attribute LIST (attribute | value) + selected-attribute description panel + LEVEL bar top-right.
- `mockup-stat-perks.png` — STAT / Perks.
- `mockup-data.png` — DATA / Quests (default): quest list | selected-quest objectives detail.
- `mockup-data-workshops.png` — DATA / Workshops.
- `mockup-data-stats.png` — DATA / Stats.
- `mockup-map.png` — MAP / World.
- `mockup-map-local.png` — MAP / Local.
- `mockup-radio.png` — RADIO: station list + oscilloscope + station info.
- `mockup-inv-apparel.png` / `-aid` / `-misc` / `-junk` / `-ammo` — INV category views (same 3-col layout, different list content; useful for per-category content + column behavior).
- `mockup-inv-inspect.png` — INV **inspect overlay** (interactive state): R/click-inspect dims+blurs the menu, the item flies to center as a 3D model, keybar `W PREV / S NEXT / WHEEL ZOOM / R EXIT`.
- `mockup-radio-tuned.png` — RADIO with a station tuned (interactive state).

### Interactive button-pressed states (rendered via the extended injector, see below)
- `mockup-inv-energy.png` — INV / Weapons after `C CYCLE DAMAGE` once: item card Damage row reads `DAMAGE · ENERGY` (energy conversion, e.g. 65 ballistic -> 23 energy) instead of `DAMAGE · BALLISTIC`.
- `mockup-inv-sort-weight.png` — INV / Weapons after `Z SORT` x1: title `INVENTORY · WEAPONS · BY WEIGHT`, rows reordered heaviest-first (Fat Man 30.7 -> Laser Musket 12.6 -> ...).
- `mockup-inv-sort-value.png` — INV / Weapons after `Z SORT` x2: title `INVENTORY · WEAPONS · BY VALUE`, rows reordered by value (Fat Man 512 -> Instigating 485 -> ...).
- `mockup-stat-vaultboy.png` — STAT / Status after `V VAULT BOY` (Character toggle): the STAT figure slot shows the green Vault Boy figure (`#statfigvb`) in place of the live 3D character; keybar chip reads `V CHARACTER`.
- `mockup-data-summary.png` — DATA / Quests after `C SHOW SUMMARY`: the quest summary block (`#questsummary`, hidden by default) is shown beneath the objectives panel.
- `mockup-map-marker.png` — MAP / World after `M1 PLACE MARKER`: a custom `CUSTOM MARKER` diamond is drawn on the world map at map center.
- `mockup-inv-inspect-apparel.png` — INV **inspect overlay on an APPAREL item** (GP-5 Gas Mask): apparel subtab -> row 0 -> inspect. Title/stat/mod panels are the apparel item (different content from the weapon `mockup-inv-inspect.png`); captured in the `.focused` state (panels faded in). NOTE: the live mockup gates inspect to Weapons only (`if (on && curCatKey !== "weapons") return;`); this reference required the opt-in `window.__allowAnyInspect` relaxation baked into `_ref_render.html` (see below). The 3D mesh is the mockup's single shared inspect model (only one inspect GLB exists), so the flown-in model matches the weapon inspect; the identifying difference is the title and the stat/mod panels.
- `mockup-inv-legendary.png` — INV / Weapons with the legendary weapon row selected: `✦ Instigating .308 Hunting Rifle` row (with the `✦` legendary marker) is selected; the item card shows `.308 · LEGENDARY` and the `#ic-leg` line `✦ Does double damage if the target is at full health.`

All show the Pip-Boy OPEN with the world dimmed+blurred behind it (the target backdrop transparency),
the left vertical tab column (STAT/INV/DATA/MAP/RADIO + flavor codes + EXTENSIONS/[EXT] + clock),
the thin top telemetry strip, and the footer keybar.

## How to regenerate (headless Chrome, no puppeteer needed)
The mockup switches pages via a `.shown` class and boots into a `pipclosed` state, so a small
injected script (a) removes `pipclosed` to force OPEN and (b) reads `#page[:sub]` from the URL hash
to select the page/sub-tab. Steps:

1. Append this to a copy of `pipos-mockup.html` (call it `mockup_ref.html`):
   ```html
   <script>(function(){function a(){try{var s=document.getElementById('stage');
   if(s)s.classList.remove('pipclosed','pipopening','pipclosing');
   var h=(location.hash||'').replace('#','')||'inv',p=h.split(':'),pg=p[0],sub=p[1];
   document.querySelectorAll('.tabbtn').forEach(function(b){b.classList.remove('active')});
   var b=document.querySelector('.tabbtn[data-page="'+pg+'"]');if(b)b.classList.add('active');
   document.querySelectorAll('.page').forEach(function(x){x.classList.remove('shown')});
   var e=document.getElementById('page-'+pg);if(e)e.classList.add('shown');
   if(sub&&e){e.querySelectorAll('.subtab').forEach(function(o){o.classList.remove('active')});
   var t=e.querySelector('.subtab[data-sub="'+sub+'"]');if(t)t.classList.add('active');
   e.querySelectorAll('.sub').forEach(function(z){z.classList.toggle('shown',z.dataset.sub===sub)});}}catch(_){}}
   if(document.readyState!=='loading')a();else document.addEventListener('DOMContentLoaded',a);
   setTimeout(a,500);setTimeout(a,1400);setTimeout(a,2500);})();</script>
   ```
2. For each screen run (output path MUST be absolute; Chrome resolves relative paths against its own cwd):
   ```
   chrome --headless --disable-gpu --no-sandbox --no-first-run --hide-scrollbars \
     --window-size=1600,900 --virtual-time-budget=6000 --user-data-dir=<unique temp> \
     --screenshot=<ABSOLUTE out.png> "file:///<abs>/mockup_ref.html#<page[:sub]>"
   ```
   Hashes: `inv`, `stat`, `stat:special`, `stat:perks`, `data`, `data:workshops`, `data:stats`,
   `map`, `map:local`, `radio`. (INV categories use `data-cat`, not `data-sub`; the Weapons view
   covers the INV layout.) Note: a running desktop Chrome can steal the invocation — a unique
   `--user-data-dir` per run avoids the singleton attach; the world-behind renders because headless
   Chrome here has working WebGL (the 3D character shows).

## Regenerating the interactive button-pressed states (`_ref_render.html`)
The 8 interactive screens above are NOT reproducible by page/sub selection alone — they need a
button/hotkey sequence fired after the Pip-Boy opens. `_ref_render.html` is a kept scratch copy of
`pipos-mockup.html` (it IS the regenerator; do not delete it) with:
1. An **extended injector** appended at end-of-file. It reuses the base open+select logic but parses an
   extended hash grammar and then fires the scenario actions on a delay after the open+select settle.
2. One surgical, opt-in source relaxation: the inspect guard `if (on && curCatKey !== "weapons") return;`
   is changed to `... && !window.__allowAnyInspect) return;`. The live mockup gates the fullscreen inspect
   overlay to Weapons only, and `INV`/`curCatKey` are closure-scoped (not reachable from the injector), so
   the apparel-inspect reference can only be captured by letting the injector set `window.__allowAnyInspect
   = true` first. Default mockup behavior is unchanged unless that flag is set. This edit lives ONLY in
   `_ref_render.html`, never in `pipos-mockup.html`.

**Extended hash grammar:** `#page[:sub][|scenario]`. The `page[:sub]` part selects the tab exactly as the
base injector; the optional `|scenario` id (after a pipe) fires a button/hotkey sequence via the mockup's
`window.__act(label)` / `window.__setInspect(bool)` hooks and DOM clicks, ~2800ms after load (after the
open+select re-runs at 500/1400/2500ms). Use a larger `--virtual-time-budget=8000` so animations/fades
(and the ~470ms inspect fly-in + `.focused` fade) finish before capture.

**Scenario map** (hash -> output -> action):
| Hash | Output PNG | Action |
|------|-----------|--------|
| `inv\|energy` | `mockup-inv-energy.png` | `__act('Cycle Damage')` x1 |
| `inv\|sortwt` | `mockup-inv-sort-weight.png` | `__act('Sort')` x1 (SORTS increments first: 1 = by weight) |
| `inv\|sortval` | `mockup-inv-sort-value.png` | `__act('Sort')` x2 (= by value) |
| `stat\|vaultboy` | `mockup-stat-vaultboy.png` | `__act('Vault Boy')` x1 |
| `data\|summary` | `mockup-data-summary.png` | `__act('Show Summary')` x1 (`#questsummary` starts `display:none`) |
| `map\|marker` | `mockup-map-marker.png` | `__act('Place Marker')` x1 |
| `inv\|inspect-apparel` | `mockup-inv-inspect-apparel.png` | click `#invtabs .subtab[data-cat="apparel"]` -> click `#invbody .row` 0 -> set `__allowAnyInspect` -> `__setInspect(true)` |
| `inv\|legendary` | `mockup-inv-legendary.png` | click the `#invbody .row` whose text matches `Instigating` (the `leg` item), leaving it selected |

**Command (per screen), from `.../Previews/reference/`:**
```
chrome --headless --disable-gpu --no-sandbox --no-first-run --hide-scrollbars \
  --window-size=1600,900 --virtual-time-budget=8000 --user-data-dir=<unique temp> \
  --screenshot=<ABSOLUTE out.png> "file:///<abs>/_ref_render.html#<page[:sub]|scenario>"
```
Rendered 2026-08-17 with `C:\Program Files\Google\Chrome\Application\chrome.exe` (spaces in the file:// URL
percent-encoded as `%20`; output paths absolute). Each was opened and visually verified: Pip-Boy OPEN,
correct page, and the specific state present.
