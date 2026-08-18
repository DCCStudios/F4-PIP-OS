# PIP-OS Parity + QOL Spec (overnight feature round source of truth)

Extracted from `Previews/pipos-mockup.html` (the approved mockup) + `Previews/reference/*.png` on 2026-08-17
to drive the R3/R4/R5 feature rounds. When this doc and the mockup disagree, the **mockup wins** — every
implementer/reviewer must open the relevant `mockup-*.png` and the cited mockup line before laying out or auditing.
This doc enumerates WHAT to build and the exact semantics; it is not a substitute for reading the reference.

## INV page structure (mockup lines ~403-483, JS ~855-939)
Three columns under the category sub-tabs (Weapons/Apparel/Aid/Misc/Junk/Ammo):
1. **EQUIPMENT panel** (`#equip`): slot -> item rows (Head/Torso/Left Arm/.../Pip-Boy). DLL already pushes this.
2. **CENTER**: `#figurebox` (3D character, drag-to-rotate) above `#qa` Quick Access.
3. **`#invcol`**: `#invlist` (title + sortable header `#invhead` + list body `#invbody`) above `#itemcard`.

### Column layouts per category (CSS grid; `gridCols()` = fixed px or `1fr`)
- **Weapons**: `Name(1fr) | Ammo(1fr-ish) | WT(52px,r) | VAL(52px,r)`. Row c = `[name, ammoString("‑308 (78)"), wt, val]`.
- **Apparel**: `Name(1fr) | Slot(96px,l) | WT(52px,r) | VAL(52px,r)`.
- **Aid / Misc / Junk**: `Name(1fr) | QTY(52px,r) | WT(52px,r) | VAL(52px,r)`.
- **Ammo**: `Name(1fr) | QTY(64px,r) | WT(52px,r) | VAL(52px,r)`.
- Legendary rows: `✦` glyph prefix on the name (mockup uses `em.lgd`); our list uses the vector sparkle marker.
- Right columns are right-aligned (`.num`); Name and apparel Slot are left.

### Item card (`#itemcard`, JS `showCard` ~862-889)
- Title `ic-name` (name minus star/dot markers) + `ic-sub` (e.g. ".308 · LEGENDARY", "EQUIPPED", "MEDICINE").
- Two chips: **WT** (bag icon) `ic-wt`, **VAL** (caps "C" icon) `ic-val`.
- `ic-leg`: legendary effect line, shown only if `it.leg` (e.g. "✦ Does double damage if the target is at full health.").
- `ic-stats`: up to 4 `[label, value]` pairs. Weapons: Damage/Fire Rate/Range/Accuracy (Damage label switches
  Ballistic<->Energy on "Cycle Damage"/C, value ~0.35x for energy — mockup `dmgMode`). Apparel: DMG/Energy/Rad Resist + Effect.
  Aid: Effect/Duration/Addiction/etc. Junk: component yields. Ammo: "Used By".
- `ic-flavor`: one-line flavor string.
- Empty category -> name "—", flavor "Nothing in this category."
- **This is the bottom window the user said is too sparse** — R3 must fill title+sub+WT+VAL+leg+4 stat pairs+flavor
  from real item data (DLL `PipOS_iteminfo` already provides w/v/a; damage/resist/mods need DLL extraction, see below).

## QOL features requested (build in R3 unless noted)

### 1. Sortable NAME / WT / VAL headers (asc + desc)
Mockup has a single cycling "Sort" action (`sortItems` ~1646: cycles SORTS = name(A-Z)/wt(desc)/val(desc)).
**User wants better**: click a column header to sort by it; click again to flip asc/desc; show an arrow indicator
(▲/▼) on the active column. Keep the Z / "Sort" keybar as a cycle fallback. Sort is per-category. Preserve
selection-follows-item where practical, else select row 0. Header cells are the pooled `#invhead` spans -> in our
AS3 they become clickable hit sprites over the header labels (no dead controls: every header sorts).

### 2. Quick Access boxes — icons + non-cutoff name (mockup `#qa`, JS ~1747-1761)
7 numbered slots (hotkeys 1-7). Each: hotkey number `.k`, an icon (mockup uses inline SVG per item type), a count `.n`.
Clicking or pressing 1-7 "uses" the slot (favorites hotbar). **User asks**: give each box an ICON and a way to show
the item NAME without cutoff. Implement: per-slot icon (category/type glyph — vector, font-independent, drawn like
the existing markers), count badge, and a hover TOOLTIP (see #3) showing the full favorited item name (names are too
long for the box, so never bake the name into the box — reveal on hover). DLL likely must push the favorites list
(formID/name/count/type per hotkey slot) similar to PushEquipmentNow.

### 3. Item mouseover tooltip popup (new; not fully in mockup — mockup uses card+inspect)
On hover over any inventory row (and any quick-access box), show a small phosphor popup near the cursor with useful
at-a-glance info: name (full, uncut), sub-type, WT, VAL, and the 1-2 most relevant stats (weapon: Damage/Fire Rate;
apparel: DMG/Rad Resist; aid: Effect; ammo: Used By). Must be pooled/update-only (crash rule), clipped to stay
on-screen, and mouse-transparent so it never eats row clicks. Dismiss on roll-out. Keep it subtle (mockup palette).

### 4. Expand button on the rightmost INV box (`#invcol`) with animation
Add a control on the inventory list panel that expands it to occupy a larger portion of the window (e.g. overlaps the
center/figure column) so more rows are visible, with a short slide/grow animation; a second press collapses it.
While expanded, `_visible` row count grows and the list re-lays out. No dead control; add a keybar hint + hotkey.
Animation via a tween on the panel rect + list geometry — but remember the crash rule: geometry tweens must run on
the POOLED fields' container transforms / scrollRect / the panel Shape, NOT by re-creating fields. Prefer animating
a container Sprite's `.scaleY`/mask height and bumping `_visible` at the end, over per-field width writes.

### 5. Inspect (R4) — fix to match mockup `#inspectlay` (HTML 676-681, CSS 154-199, JS `setInspect`/`cycleInspect`)
Full-screen inspect overlay: blur+dim the menu (`rgba(4,10,6,.38)` veil), the selected item "flies" to center as a
3D model (`#glcanvas.flying`, transition `.45s cubic-bezier(.22,.9,.32,1)`), then `#inspectlay.focused` fades in
`#ins-title`, `#ins-leg` (legendary badge with `lgdpulse` glow), `#ins-stats` (left, slide-up), `#ins-mods`
("Current Mods" right, slide-up). Keybar: `W PREV / S NEXT / WHEEL ZOOM / R EXIT`. Reuses the shared 3D canvas
(inspect "owns the canvas while active"). Our AS3 must present the same states; the 3D item model degrades to a
stylized card if no capture. Weapons carry a `mods:[...]` list (mockup line 784) — DLL must extract current mods.

## FallUI / Complex Sorter compatibility (R4) — tags + folders
- Complex Sorter / FIS write category **tag prefixes** into item display names, e.g. `[Weapon]`, `[Aid|Food]`,
  `{Legendary}`, `(Junk)` and icon-font codepoints. FallUI shows these as **folders**. Current locked decision
  (docs/FallUICompat.md) was "tags shown as-is"; **user now wants folder grouping**. Implement: a tag PARSER that
  strips the leading tag/prefix from the display name for the row label, and GROUPS rows under collapsible folder
  headers by the parsed tag (folders = separator rows that expand/collapse; remember our list already supports
  separator rows). Strip FIS private-use-area icon glyphs (they're outside our font -> sanitize already drops them,
  but parse+remove so the name reads clean). Keep raw name available for the DLL join keys.
- Filename decoupling (ship pages as `PipOS_*Page.swf`, per-tab external passthrough) is the FallUI-menu coexistence
  enabler from the lock — reconcile the vanilla-name TestA packaging vs the decoupled-name lock in R4.

## CRT breathing + open/close animation (R5) — mockup CSS
- `scanroll` 14s linear (scanline drift), `scansweep` 9s ease-in-out (bright band sweeps down), figurebox `scan`
  6s. Legendary `lgdpulse` 2.2s. The "breathing" = slow opacity/vignette pulse on the CRT frame (Chrome.as buildCRT
  already draws vignette/scanlines rolled by Ticker — add a slow sine breathe on vignette alpha + a periodic sweep band).
- Open/close: the mockup boots `pipclosed` and animates open. In game the Pip-Boy open is engine-driven, but our
  chrome/veil can fade/scan-in on `MenuOpenClose` (DLL already gets the event). Keep subtle; honor reduced-motion by
  making it skippable/instant if a config flag is off.

## F4SE Menu Framework settings page (R5)
Reference implementation: `..\FallUI HUDs\S2 HUD Rework` (has a working F4SE Menu Framework settings page + build/
package scripts). Add a PIP-OS settings page exposing customization options; **first/required option: background
OPACITY** (the world-dim/veil the user keeps flagging — expose 0-100%). Other candidates: CRT effect intensity,
breathing on/off, live-3D-character on/off (the R2 gate), animation/reduced-motion, per-tab external-page passthrough
toggles (FallUICompat A), expand-panel default, sort default. Wire each setting through the DLL Settings.* -> INI ->
menu. NEVER deploy the user's Fallout4Prefs.ini; the Menu Framework page writes our own INI only.

## Cross-cutting rule (applies to EVERY round)
All new interactive UI obeys the 0.0.31 crash-structural law: no `new TextField` and no geometry writes
(`.width/.height/.x/.y/.autoSize`) on any handler-reachable path — pool fields once in a build window; handlers touch
only text/color/visible/scrollRect/filters/format. Tooltips, folders, expand, sort indicators, inspect panels: all pooled.
