# PIP-OS Implementation Notes (M2-M6)

Running log of decisions, gotchas, and verification evidence. Honesty tags:
VERIFIED-STATIC (built + round-trip re-decompile checked) / BUILT-UNVERIFIED / STUBBED / NOT DONE.

## STANDING CONVENTION — time-based animation only (frame-cadence trap)
Sourced from S2 HUD Rework's hard-won lesson (its DEVELOPMENT_STATUS.md). Applies to the shell and
every PIP-OS page:
- A loaded child SWF runs on the ROOT movie's frame cadence, not its own declared fps. Our
  `PipOS_*Page.swf` are children of `PipboyMenu.swf`, so their declared fps is irrelevant — they tick
  at the shell's cadence.
- **Authored fps (recorded):** vanilla `PipboyMenu.swf` header = **frameRate 30.0** (frameCount 1,
  version 15, ZLIB). All five vanilla `Pipboy_*Page.swf` = frameRate 30.0 as well. Baka Fullscreen
  Pip-Boy hosts/overrides the background movie but does not change the Pip-Boy menu's frame cadence;
  we keep the vanilla 30 fps header and do NOT re-author fps in v1 (PipboyTabs + any transplanted
  vanilla logic may hold frame-based timing assumptions).
- **Rule:** NEVER advance an animation by a hardcoded per-tick delta and never assume 60/30 Hz. Drive
  every animation (CRT boot/close, brightness pulses, pointer ripples, scanline sweep, meter fills,
  list-scroll easing) from measured elapsed time via `flash.utils.getTimer()`, with the per-frame
  delta clamped to **[1/240, 1/12] seconds** (S2's proven clamp; survives pauses/hitches/alt-tab).
  Helper: `pipos.Ticker` (getTimer-based, clamped) — use it for any animated element.
- If transplanted vanilla page code uses frame-count-based timing, convert those spots to elapsed
  time and note each conversion here. (v1 pages are event-driven and contain no ENTER_FRAME per-tick
  deltas, so they are compliant by construction; the Ticker helper is in place for future animation.)
- Related: elements positioned by native code every rendered frame move at engine rate; children
  parented under a natively-moved container inherit that smooth motion, while re-projecting into our
  own overlay each ENTER_FRAME steps at movie cadence — prefer native-driven parents where possible
  (relevant to the M5 character-capture panel).

## Build environment (confirmed on disk)
- JPEXS ffdec: `E:\...\PluginTemplate\jpexs-gui\ffdec.bat` (v26.2.1). Invoke via PowerShell (Bash
  chokes on the spaces in the .bat path -> "operable program or batch file"). PowerShell is reliable.
- Flex/AIR SDK: `E:\Fallout 4 Modding\F4SE\_tools\flex\bin\mxmlc.bat` + `_tools\airsdk` (playerglobal 32.0).
  Used by S2 HUD Rework; available for authoring page SWFs in M4.
- CommonLibF4 checkout: `E:\Fallout 4 Modding\F4SE\FOV Slider F4SE\lib\commonlibf4` (multi-runtime).
- Vanilla shell header: SWF version 15, ZLIB, frameRate 30, frameCount 1. Our patched shell keeps
  these exactly (verified).

## M2 - ScaleformContract.md  (VERIFIED-STATIC, doc)
- Decompiled vanilla PipboyMenu + all 5 pages + PipboyTabs.swf + ConditionClips.
- Extracted the full BGSCodeObj method surface, Pipboy_DataObj field->page map, PipboyPage/PipboyLoader
  contract, PipboyTabs hook points, ConditionBoy composite, and the UI sound-event table (hard req).
- Key RE findings that shaped M3:
  - Pages are runtime-loaded by filename with `LoaderContext(false, ApplicationDomain.currentDomain)`.
  - **PipboyTabs does `stage.getChildAt(0)["Menu_mc"]` then `Menu.getChildAt(4)["_TabNames"].push(...)`.**
    => the shell's display-list child ordering and the `Menu_mc`/SymbolClass names are load-bearing.
    Rebuilding the shell from scratch would risk breaking this; **patching the vanilla shell in place
    is the contract-safe path.** This is why M3 is an AS3 patch, not a rebuild.

## M3 - PIP-OS PipboyMenu.swf shell  (VERIFIED-STATIC)
Approach: copy vanilla PipboyMenu.swf, replace ONLY the `PipboyMenu` ActionScript class via
`ffdec -replace <swf> <swf> PipboyMenu PipboyMenu_patched.as`. Source: `build\shell\PipboyMenu_patched.as`
(derived from the clean decompile; minimal edits).

Patch content (contract-preserving):
- Loader table now returns `PipOS_{Stats,Inv,Data,Map,Radio}Page.swf` by default.
- `PageModes:Array` (5, default 0=pipos) + public `SetPageMode(index, mode)` so the companion DLL /
  a config can select external passthrough (mode 1 -> `Pipboy_<Tab>Page.swf`).
- `onPageLoadError` (IOErrorEvent): pipos-mode load failure falls back to the external page (always
  present: vanilla/FallUI); external-mode failure falls back to the PipOS page. Menu never dead-loads.
- Everything else (Header/BottomBar/ButtonHintBar wiring, InvalidateData path, tab/page nav, event
  listeners, SymbolClass, display list) is untouched.

Verification (see `tools/verify_shell.ps1`, all PASS):
- Header still `version 15 / ZLIB / frameCount 1`.
- **Class inventory identical to vanilla: 48/48, zero Compare-Object differences.**
- Re-decompiled PipboyMenu.as contains `PipOS_StatsPage.swf`, `SetPageMode`, `onPageLoadError`.
- SymbolClass tag intact (PipboyMenu / Pipboy_BottomBar / ... / ReadOnlyWarning / MapPlaceholder).
Gotcha: JPEXS `-replace` of AS3 is flagged EXPERIMENTAL and ignores `[Embed]` metadata (it edits the
existing ABC in place, so the embedded assets are preserved regardless). Round-trip confirmed clean.

Not done in M3: the PIP-OS visual chrome (CRT sidebar/clock/keybar restyle of the shell art). The
current shell keeps vanilla chrome art. Contract correctness was prioritised over shell cosmetics per
the triage order; chrome restyle is shape/sprite-tag work deferred with M4 page art.

## M4 - PIP-OS page SWFs  (BUILT + VERIFIED-STATIC; in-game render unverified)
All five pages authored as code-only `PipboyPage` subclasses built with mxmlc (Apache Flex 4.16.1) and
verified. Technique (S2-precedent): the shell-provided classes (PipboyPage/PipboySubMenu/BSUIComponent/
Pipboy_DataObj/PipboyChangeEvent/PipboyUpdateMask/BSButtonHintData/BGSExternalInterface) are compiled
against **external stubs** (`InterfaceStubs\` -> `PipOSStubs.swc`), so they are NOT embedded in the
page; at runtime they resolve to the shell's real definitions via the shared ApplicationDomain
(`LoaderContext(false, currentDomain)`). Verified: re-decompile shows only the page class + `pipos.*`
toolkit embedded, zero stub classes.
- Presentation is rebuilt in AS3 (Graphics API + TextFields) to the PIP-OS phosphor design (palette
  from the mockup: `pipos.Theme`). A reusable phosphor list widget (`pipos.PipList`) replaces the
  vanilla BSScrollingList presentation while keeping the same selection/press event flow.
- Data plumbing is vanilla-equivalent per page (verified BGSCodeObj call surface):
  - INV: `onInvItemSelection`/`SelectItem`/`ExamineItem`(R-Inspect via the real vanilla examine invoke)/
    `ItemDrop`/`SortItemList`/`SetQuickkey`/`updateItem3D`/`onNewTab`; item-card rendered from the
    engine-filled InfoObj Array we pass into `onInvItemSelection`.
  - STAT: HP/AP meters + limb chips + SPECIAL + active effects + level from DataObj; `UseStimpak`/
    `UseRadaway`; STAT figure = `pipos.VaultBoy` (my reimplementation of ConditionBoy.as, loads the
    game's `Components/ConditionClips/Condition_Body_<BodyFlags>.swf` + `Condition_Head.swf` and
    composites per the decompiled placement -- no Meshy art, no DLL). `V` toggles Vault Boy / character.
  - DATA: `onQuestSelection`/`SetQuestActive`/`ShowQuestOnMap`/`ShowWorkshopOnMap`/`PlaySmallTransition`;
    quests/workshops/stats sub-tabs, objectives panel.
  - MAP: chrome + marker overlay projected from DataObj corners; `RegisterMap`/`UnregisterMap`/
    `SetPlayerMarker`/`onSwitchBetweenWorldLocalMap`. Engine-map rendering into our container is
    in-game item #1 for MAP; `MAP=external` (FallUI) is the documented robust path.
  - RADIO: stations from `RadioList`; `ToggleRadioStationActiveStatus`; oscilloscope animated by
    `pipos.Ticker` (time-based, getTimer clamp per the frame-cadence rule) - waveform when tuned,
    flatline when off.
- Sounds from the M2 table (§f) wired on every interaction (`PlaySound` UIGeneralFocus / UIMenuOK /
  UIMenuCancel / UIMenuPrevNext / UIPipBoyFavoriteMenuDPadA / UIPipBoyMapZoom, etc.). No silent controls.
- Verified by `tools/verify_pages.ps1` (all PASS): every page header = CWS/version 15 (matches the
  vanilla pages), document class `extends PipboyPage`, zero stub classes embedded, real BGSCodeObj
  surface present. What static verification cannot prove: that GFx text/vector renders as laid out and
  that the engine populates our InfoObj/marker/map bindings identically to the vanilla page instances
  (in-game smoke test #1). Layout coordinates are a 1280x720 reference; Baka scales the shell.
Build/verify: `tools/build_pages.ps1` (compc stub SWC + mxmlc per page) then `tools/verify_pages.ps1`.

## M5 - companion DLL  (BUILT: compiles + links + valid PE; in-game unverified; capture STUBBED)
`dll/` is an OG-only commonlibf4 plugin mirroring F4Parkour conventions (xmake.lua with
`set_runtimes("MD")`, res template, PCH logging shim, `COMMONLIB_RUNTIMECOUNT=1`). **It now builds
clean** with `cd dll && xmake f -m releasedbg -a x64 -y && xmake` -> `dll/Compile/F4SE/Plugins/
PipOSPipboy.dll` (551 KB, MZ PE, exports F4SEPlugin_Query/Version). It:
- gates load to OG 1.10.163 (`RuntimeVersion() == RUNTIME_1_10_163`), refuses + logs otherwise;
- reads `Data\F4SE\Plugins\PipOSPipboy.ini [Pages]` (Settings.cpp);
- on Pip-Boy menu open (a `MenuOpenCloseEvent` sink -- no code hooks installed), invokes
  `root1.Menu_mc.SetPageMode(i, mode)` on the shell movie (PipboyBridge.cpp, correct commonlib types
  `Scaleform::GFx::Movie::Invoke` printf-style);
- stubs the live character capture (CharacterCapture.cpp returns false, logged -> pages use Vault Boy).
Still BUILT-UNVERIFIED in game: the Invoke target path and the menu-open-vs-first-page-load ordering
need one runtime pass (in-game smoke test #3). The Invoke form matches ScreenArcherMenu/PhotoModeF4's
approach to FO4 menus. The package is fully functional WITHOUT this DLL (default = PIP-OS pages).

## Round-7 — layout hygiene (clearance/containment only; no features, no restyle)
User verdict on 6.2: "bars going outside windows, text/hotkeys overlapping windows, limb boxes over the
character — everything should have clearance and not look cramped." Made clearance a RULE via shared
`Theme` constants applied everywhere, not per-spot hand-tuning. All five pages + chrome; 0 AS errors.

New `Theme` constants (single source of truth):
- `PAD = 12` — uniform panel inner inset. Bars, text, tiles, list rows, headers, values are all inset by
  PAD; nothing touches a panel border. Meter/XP/scope bars are inset on BOTH ends.
- `GUTTER = 12` — minimum gap between adjacent panels (INV/STAT/DATA/RADIO columns re-pitched to it).
- `KEYBAR_Y = 646` — top of the reserved footer keybar strip. **`BB` lowered 654 → 634** so every panel's
  bottom ends 12px above the strip; the chrome keybar row now pins to `KEYBAR_Y` (was `SH-54`), so chips
  never overlap a panel.
- `panelR(g, rects, …)` — draws a panel AND records its rect; each page collects `_panels` and exposes
  `debugRects()` for the clearance overlay.

Rule 3 (clip backstop): `scrollRect` sized to the interior on every content container that can overflow —
`PipList` (rows/values clipped to the list box), INV card, STAT meters/special/effects/level, DATA detail
(summary now rendered *inside* it), MAP `_mapArea` (markers clipped to the frame), and the RADIO scope
(now drawn PAD-inset with amplitude clamped, so the waveform never touches its frame).

Per-page (the reviewer's verified offenders, all fixed):
- **STAT — limb/figure overlap redesigned.** The six limb chips no longer sit on top of the Vault Boy;
  they're in TWO columns in the figure panel's side gutters (left HEAD/L ARM/L LEG, right R ARM/R LEG/
  TORSO), each with a 1px leader line to its limb region, and the figure is scaled down (VaultBoy 320→190)
  so columns + figure + leaders all clear. Chips remain clickable stimpak targets. HP/AP/RADS + XP bars
  inset both ends. New 3-column split: meters/SPECIAL (206..404) | figure (416..650) | LEVEL+EFFECTS
  (662..858) with 12px gutters.
- **INV** — 12px gutters (EQUIP 206..344 | CHAR 356..514 | LIST/CARD 526..858); keybar chips clear all
  panel bottoms (BB); QUICK ACCESS label + 7-slot row anchored inside the CHARACTER panel with PAD.
- **DATA** — Enter TRACK chip clears the detail panel (BB); summary moved into the clipped detail panel.
- **RADIO** — scope waveform PAD-inset + clipped (no longer touches the frame); Enter TUNE clears the list.
- **MAP** — `MAP_H` 566→556 so the frame bottom clears the keybar; legend + GRID chip moved fully inside
  the panel with PAD; **fixed the region readout** (`_region.x` was hard-set to 940, off the 876 stage —
  now right-aligned to `INFO_R`); markers clipped to the frame.
- **Chrome sidebar** — the `EXTENSIONS · PIPBOYTABS` header + [EXT] rows were sitting on / below the rail's
  bottom border; the rail height is now computed to fully contain them (page rows + EXT header + injected
  rows + PAD).

Verification (this round judged on clearance):
- Added a DEBUG overlay to the CompositeHost (`?debug=1`, forwarded via preview.html): strokes every panel
  rect (magenta) + its PAD inset (cyan) + the keybar strip (yellow) + the page body box, reading each
  page's `debugRects()`. One debug capture per page in `scratchpad/swf_preview/out/DBG_*.png` — inspected:
  no content crosses any inset line, and every panel clears the keybar strip on all five.
- Re-rendered all five clean composites (`COMP_*.png`, 0 AS errors) + regenerated the side-by-side sheet.
- verify_shell + verify_pages PASS (shell untouched); zip repackaged.

## Round-6.2 — kill the double T chip via chrome relabel (shell-untouched)
Follow-up to 6.1's in-game finding: shipping BOTH a static page "PERK CHART" chip and the shell's
dynamic GridView/LEVELUP chip would put two T entries on the keybar (confusing-controls violation).
Fixed without touching the shell:
- **Reverted 6.1 fix-2's mechanism** (not its goal): removed the static `$PERK CHART` `BSButtonHintData`
  + its `_perk` field + the `doPerkChart` mirror from `PipOS_InvPage`. (6.1 fix-1 keybar swap kept.)
  verify_pages confirms InvPage no longer calls `ShowPerksMenu` — the shell owns that call again.
- **Chrome relabel** (`Chrome.rebuildKeybar`): the shell's `onPageLoadComplete` already pushes its
  GridViewButton (PCKey T, callback `onGridViewPress`→`ShowPerksMenu`) onto every page's
  `buttonHintDataV`, and the chrome renders chips live from that vector — so in game there is exactly
  ONE T chip with the correct action. Added a display-only rename: after `$`-strip + upper-case, a hint
  whose text == `"GRID VIEW"` displays `"PERK CHART"`. The `LEVELUP (n)` flashing variant does not match
  and is kept verbatim (informative). `onTextClick` still routes to the hint's own callback — unchanged.
- **Harness parity:** the CompositeHost mock doesn't run the shell, so it now pushes a GridViewButton-
  equivalent (`$Grid View`, T, no-op callback) onto the INV page's `buttonHintDataV` before render, so
  the INV composite shows the single relabeled `T PERK CHART` chip as it renders in game. Scoped to the
  INV target — other composites unaffected.
- Re-rendered all five composites (0 AS errors); INV shows one relabeled T chip, no page duplicate.
  Sheet regenerated, verify_shell + verify_pages PASS, zip repackaged. Docs (FunctionalitySpec T-chip
  rows) updated: T chip = shell-provided + chrome-relabelled, LEVELUP flash preserved.

## Round-6.1 — targeted keybar/layout fixes (composite-confirmed, 0 AS errors)
Four narrow fixes, no redesign. All five composites re-rendered at 876x700 (0 AS errors), side-by-side
sheet regenerated, verify_shell + verify_pages PASS, zip repackaged (399 KB). Shell untouched.
- **Fix 1 (INV keybar swap) — ROOT CAUSE:** in `PipOS_InvPage.PopulateButtonHintData` the `PCKey`
  (2nd `BSButtonHintData` ctor arg = the DISPLAY glyph) was crossed: Inspect had `"X"`, Drop had `"R"`,
  so the chrome (which renders `hd.PCKey`+`hd.ButtonText`) drew "X INSPECT | R DROP". Locked spec / M1
  mockup is **R = Inspect, X = Drop**. Swapped the two PCKey strings only; the gamepad control names
  (Inspect=`R3`, Drop=`XButton`) and PSN/Xenon glyphs were already correct and are unchanged, so the
  single input path is untouched. Corrected the FunctionalitySpec input-path table (it had recorded the
  swapped keys). **Keybar audit (page → chip:key vs spec): all pages match.** INV Inspect R / Drop X /
  Cycle C / Fav Q / Sort Z / Perk T; STAT Stimpak E / RadAway R / VaultBoy V; DATA ShowOnMap R /
  Summary C / Track Enter; MAP Local R / Place Enter; RADIO Tune Enter. Only INV was wrong.
- **Fix 2 (INV missing T PERK CHART chip):** added a `BSButtonHintData("$PERK CHART","T","PSN_Y",
  "Xenon_Y",1,doPerkChart)` to INV's hint vector; `doPerkChart` mirrors the shell's `onGridViewPress`
  exactly (`BGSCodeObj.ShowPerksMenu`). NO T key handler added — the T KEY stays on the shell's
  YButton→ShowPerksMenu path (single input path); the chip only adds a clickable mirror via onTextClick.
  **IN-GAME FINDING (report):** the patched shell's `onPageLoadComplete` already pushes its own
  `GridViewButton` (T, label "Grid View" / "LEVELUP (n)" when PerkPoints>0, flashing) onto EVERY page's
  `buttonHintDataV`. So in game INV will render BOTH our static "PERK CHART" chip and the shell's
  dynamic Grid View/LEVELUP chip (two T entries). The composite harness does not run the shell, so it
  shows only our PERK CHART chip. De-duping would require touching the shell (forbidden) and would
  suppress the LEVELUP flash — left as-is; flagged for the user to decide.
- **Fix 3 (STAT SPECIAL/L-LEG overlap):** the 7 SPECIAL tiles at pitch 31 (tw 29) ran to x=433, past
  the SPECIAL panel's right edge (404) and INTO the L LEG limb chip (left edge x=426). Shrank tile
  width 29→24 (pitch 26): 7 tiles now span 218..398, fully inside the panel and clear of L LEG. Swept
  all five composites at 876x700 — no other overlaps.
- **Fix 4a (STAT active-effects "2 of 3"):** not a page cap (the effects loop already draws up to 10,
  no scrollRect clip) — the STAT composite mock only defined 2 effects. Added the 3rd
  (`RAD RESIST +10`) to the CompositeHost mock; all 3 rows now render.
- **Fix 4b (INV quick-slot 7 offset):** the 7 slots at pitch 25/bw 22 ran to global x=528, past the
  CHARACTER panel edge (514), so slot 7 poked into the list gutter. Shrank to pitch 20/bw 18 with a
  10px inset: slots now span 366..504, evenly in-row inside the panel.

## Round-6 — design fidelity (make the composites look like the M1 mockup)
User verdict on round-5: "doesn't really look like the preview." The mockup (`Previews/pipos-mockup.html`)
is the design contract; this round closes the visual gap with no new features / no contract changes.
Method: captured the mockup per-page as reference targets (`scratchpad/swf_preview/render_refs.js` ->
`out/ref_*.png`), then iterated each page against its ref via the 876x700 CompositeHost, and produced a
side-by-side proof sheet (`Previews/round6-fidelity-sidebyside.png`, ref | composite per page).

Global / chrome:
- **Footer keybar** (was missing, biggest gap): `pipos.Chrome` now renders mockup-style boxed key +
  label chips sourced LIVE from `CurrentPage.buttonHintDataV` (labels = `ButtonText` with `$` stripped,
  key = `PCKey`), each clickable -> `BSButtonHintData.onTextClick()` (same action). Plus ESC BACK.
- **Sidebar**: vector tab icons per page (pulse/bag/db/pin/wave), active row gets a rounded highlight +
  green tick + glow, and the EXTENSIONS · PIPBOYTABS section shows injected tabs as rows with an [EXT]
  chip (still driven by the live `TabNames` beyond `STD_TABS`).
- **Theme upgrade** (propagates to all pages): `panel()` is now translucent rounded-8 with hairline edge
  + 4 corner accent ticks; added `meterInto` (framed label/value bar), `chipInto` (WEIGHT/CAPS + W/V
  chips with vector `iconCaps`/`iconWeight`), `keycap`, `heading`, `glow` (GlowFilter on bright
  headings/values), `diamond`/`caret` bullets, and typography hierarchy (dim label / bright value).
- **PipList**: optional multi-column mode (`columns` + adapter `cols[]`) with a header row, rounded
  selection bar, zebra rows, near-white selected ink + shadow, vector star/sparkle markers.
- Ruffle gotcha fixed: `Graphics.drawOval` does not exist -> `drawEllipse` (it threw in the Chrome
  constructor and blanked everything until fixed).

Per page (composite vs mockup):
- **INV** (worst offender) re-laid to the mockup's THREE columns: EQUIPMENT (slot rows) | CHARACTER
  (Vault Boy + holo staging line + shadow ellipse + "CAPTURE OFFLINE · VAULT BOY (DLL PENDING)" caption
  + QUICK ACCESS row) | INVENTORY list with NAME|AMMO|WT|VAL headers + item card (title, DMG line,
  diamond-bulleted stat-pair grid, flavor). WEIGHT/CAPS header chips with vector caps/weight icons and
  warn-amber/crit-red weight states.
- **STAT** re-laid: framed HP/AP/RADS meters; 7 SPECIAL tiles (big value + small label); limb-condition
  chips ANCHORED AROUND the figure (head top, arms sides, legs lower, torso bottom) as clickable stimpak
  targets with per-limb bar + severity color; LEVEL chip + XP bar; ACTIVE EFFECTS panel (EFFECT|SOURCE).
- **DATA / MAP / RADIO** inherit the richer panels + typography + keybar + sidebar; MAP legend already
  vector dots; RADIO scope + info panel framed.

Deliberate deviations (documented, not regressions):
- No blurred game-scene backdrop in the composites — that layer is the Baka `PipboyBackgroundMenu.swf`
  (shipped separately, 1920x1080) which renders behind the scaled menu in game; the harness shows dark.
- INV item card + AMMO/WT/VAL columns and DATA objectives/detail are blank in the composites because the
  harness does not run the engine callbacks that fill the InfoObj / fire selection detail; in game these
  populate (the plumbing is wired and unchanged).
- EQUIPMENT panel values are placeholders ("-") — equipped-per-slot is a [V2] readout per FunctionalitySpec.
- Proportions are adapted to 1.25:1 (876x700) with the sidebar gutter; the mockup is 16:9. The visual
  language matches; exact column widths differ, and long list names can still ellipsize in the narrower
  876 list column.
- Contract unchanged this round: shell untouched (all 6 verify_shell checks still PASS), pages still
  CWS/v15 + extends PipboyPage + zero stubs embedded, single input path per action preserved.

## Round-5 — coordinate space, chrome split, input paths, background (adversarial SHIP-WITH-FIXES)
The reviewer confirmed round-4 held (contract, loader, mouse-safety, dynamic members, PipboyTabs
name-lookup, Baka scaling, DLL gating, no secrets) but found three MAJORs static/per-SWF checks could
not see. All fixed and re-proven with TOGETHER composites at the true stage size.

**MAJOR-1 — coordinate space (the big one).** The shell and all five vanilla pages are **876x700**
(17520x14000 twips, v15) — verified directly, and reconfirmed by the Baka check (Baka ships NO
PipboyMenu/page SWFs, only PipboyBackgroundMenu*.swf at 1920x1080/1920x1200/2560x1080/876x700). My
pages + chrome were authored at 1280x720 with absolute coords spanning past x=876 — off-stage in game.
Re-authored ALL five pages and the chrome to 876x700 via shared `Theme` constants
(SW=876, SH=700, CX=206, CR=858, CW=652, TITLE_Y=16, SUB_Y=44, BY=78, BB=654, INFO_R=650). Verified
by re-rendering every page in the CompositeHost at an 876x700 stage — content fits, nothing clipped.

**MAJOR-2 — chrome/page occlusion.** Reserved an explicit **left sidebar gutter** (page content starts
at CX=206, right of the chrome sidebar x<=190) and a **bottom telemetry strip** (chrome at y>664; page
body ends at BB=654), and a top-right **clock-safe zone** (page readouts right-align to INFO_R=650,
clear of the clock at x>=664/y<72). Proven with a new **CompositeHost** (`scratchpad\swf_preview\
CompositeHost.as`, recompiled at `-default-size=876,700`) that renders chrome + a page TOGETHER and
screenshots the true space. All 5 composites captured (`out\COMP_*.png`), 0 AS errors, sidebar clear
of content on every page. Adopted as the required verification (`render_composite.js`).

**MAJOR-3 — input paths (single live path per action).** Root-caused the double-fire: pages handled
actions in BOTH raw KeyboardEvent and ProcessUserEvent. Fix:
- Removed Enter(13) from `PipList.handleKey` (nav-only now) and added `pressSelected()`; activation is
  the single ProcessUserEvent **"Accept"** path (fires for keyboard Enter AND gamepad A), plus mouse
  click on the selected row (`onItemPress`). No keyboard/gamepad double-fire.
- Moved every keybar action to `ProcessUserEvent` **named controls** (XButton/R3/L3/RShoulder/
  LShoulder/Accept), matching vanilla's proven mapping, and removed them from raw `onKey` (which now
  drives only list up/down navigation + genuinely-custom toggles). This makes the actions reachable on
  gamepad (the raw-key-only versions were keyboard-only despite carrying PSN/Xenon hint glyphs).
- Removed the page-level **T / Perk-chart** handler and its keybar chip on INV and STAT — the shell
  already pushes the GridView(T)->ShowPerksMenu hint into every page, so the collision is gone.
- Known limitation (documented): our custom `PipList` replaces BSScrollingList, so vertical LIST
  scrolling on a gamepad (as opposed to the action buttons) is not wired to a named control in v1 —
  mouse + keyboard fully navigate the lists; keybar actions work on both. Per-page input table is in
  FunctionalitySpec.

**Chrome split (unlocked by the Baka finding).** Split the chrome into two layers: (1) the INTERACTIVE
chrome stays in `PipOS_Chrome.swf` in the 876x700 menu space (sidebar + side-notes + EXT mirror + clock
+ telemetry + boot/collapse); (2) the FULL-SCREEN CRT bezel / corner brackets / vignette / scanline
field moved to a **`PipboyBackgroundMenu.swf` override at 1920x1080** (16:9 first). Removing the outer
bezel from the menu-space chrome freed room for the sidebar-gutter math. Also hardened chrome collapse:
`teardown()` stops the ticker and `parent.removeChild(this)` at collapse end, guarded by a `_dead` flag,
so rapid open/close cannot accumulate chrome instances or leave a ticker running.

**Background override (deferred locked deliverable, now shipped 16:9).** Decompiled Baka's
`PipboyBackgroundMenu.swf` (1920x1080, v15, ZLIB, 30fps; SymbolClass binds `PipboyBackgroundMenu`;
document class `extends Shared.AS3.IMenu` with a `Background_mc` child). Our
`PipboyBackgroundMenu.swf` is a structural drop-in: same class name + `Background_mc` + dims + header,
drawing the dark phosphor ground, vignette, outer CRT bezel + corner brackets, and scanline field
(pure vector, 1.3 KB, no font). Rendered standalone (0 errors). **BUILT-UNVERIFIED risk:** ours extends
MovieClip, NOT Baka's IMenu base (reproducing that whole base is out of scope). If Baka's DLL requires
the IMenu type or a method we don't expose, the fullscreen framing could misbehave — the README fallback
is "don't install our PipboyBackgroundMenu.swf; keep Baka's" (menu chrome/pages unaffected). The 16:10 /
21:9 / Small variants are **NOT shipped yet** (documented follow-ups).

**DLL SetPageMode timing.** Documented (PipboyBridge.cpp + README step 6): the bridge pushes modes on
the kMenuOpenClose "opening" edge, which precedes the shell's first LoadCurrentPage in the common case;
a forced page reload is deliberately avoided as disruptive; worst case an external-mode tab shows the
PipOS page until the first tab switch that session, and the load-failure fallback keeps every tab
functional regardless.

## Round-4 — shell CRT chrome restyle (contract-safe overlay; Ruffle-render-confirmed)
The highest-risk edit. Route chosen (constraint #6): the chrome is a **separate `PipOS_Chrome.swf`**
(`pipos.Chrome` + embedded Arimo; NO shell-contract classes, all menu/data access dynamic), loaded by
small additive calls in the already-patched PipboyMenu and attached as a **ROOT SIBLING of Menu_mc**
(`this.parent.addChild`) — never a child of Menu_mc. This keeps PipboyTabs' contract intact:
- 47 vanilla classes stay byte-identical (verified); only PipboyMenu.as changed, additively.
- Menu_mc's own child list is untouched, so `Menu_mc.getChildAt(4)` still resolves to the page.
  `verify_shell.ps1` now includes a **child-index safety check**: asserts chrome is added via
  `this.parent.addChild(this._chrome)` and that NO chrome `addChild` targets Menu_mc, and that the
  vanilla page-addChild path in `onPageLoadComplete` is preserved. PASS.
- SymbolClass bindings + header (v15/ZLIB/frameCount 1/30fps) unchanged. PASS.
Additive PipboyMenu hooks (all in the one patched class): ADDED_TO_STAGE → load `PipOS_Chrome.swf`;
onPipOSChromeLoaded → `parent.addChild`, dim vanilla `Header_mc` via ColorTransform alpha=0 (present +
functional for the PipboyTabs data path, just visually receded); `InvalidatePartialData` →
`_chrome.updateData(DataObj, this)`; `onCodeObjDestruction` → `_chrome.playCollapse()`.
Chrome contents (drawn via Graphics API + TextFields, embedded font): CRT bezel + corner brackets;
clock card (live DataObj date/time + PIP-OS(R) V2.7.1); left sidebar STAT/INV/DATA/MAP/RADIO with
current-page highlight (near-white + shadow) + flavor side-notes, **clickable** →
`menu.TryToSetPage/TryToSetTab` (dynamic); an **EXT section that shows only the PipboyTabs-injected
tabs** (live `menu.CurrentPage.TabNames` beyond each page's standard sub-tab count `STD_TABS`=
[3,7,3,2,1] — avoids showing untranslated `$`-keys; injected names are already display strings);
PIP-BOY OS V2.7.1 badge + telemetry flavor; PROPERTY OF VAULT-TEC; scanline overlay; CRT boot bloom
(~450ms, vertical, overshoot) on open + collapse (~260ms) on close — all **time-based via `pipos.Ticker`**
(getTimer, clamped dt). Reduced-motion: FO4/Scaleform exposes no reduced-motion signal to the SWF, so
the animation ships **unconditionally** (noted per instruction).
Input safety: the chrome sets `mouseEnabled=false` on the frame/scanlines/telemetry/clock; only the
sidebar hit-rects consume input, so pages beneath still receive clicks.
Verification: full `verify_shell.ps1` (6 checks incl. child-index safety) PASS; chrome rendered in
Ruffle via a **chrome-only harness** (`scratchpad\swf_preview\ChromeHost.as` instantiates `pipos.Chrome`
with mock data — the coordinator's allowed fallback; I did NOT run the CompositeHost-loads-real-shell
path, since the vanilla init path is unlikely to boot under Ruffle) — 0 AS errors, capture confirms
bezel, clock, sidebar+highlight+side-notes, EXT=injected-only (CHALLENGES/AFFINITY), badge/telemetry,
scanlines. Still unverified in the real engine: the chrome loading + `parent.addChild` timing, the
`_chrome.updateData` reflection calls, and Header ColorTransform under GFx.
Deferred polish (noted by the coordinator, next time pages are touched): quick-access names wrap
mid-word (ellipsize on one line); MAP legend words lack their glyph icons (use vector dots).

## Round-3 fixes — Ruffle visual review (all 8 confirmed via fresh captures)
Adopted the scratchpad Ruffle harness (`swf_preview\`: PreviewHost.as force-links the shell-contract
classes, mocks BGSCodeObj, drives each page with live-shaped data, screenshots via headless Edge) as a
repo verify step: `tools/preview_pages.ps1` (run after `build_pages`/`verify_pages`; inspect
`swf_preview\out\*.png`). ConditionClips sit at the server root under `Components\ConditionClips` —
relative URLs resolve against the ROOT movie URL, which in game is `Interface\`, confirming the path.
All five pages render with **zero AS errors**.

1. **[BLOCKER] Font** — `Theme.FONT="Arial"` (device font) would draw NOTHING in game (Scaleform has no
   OS font provider). Now embeds **Arimo Stalker Bold** (locked M1 typeface, Apache 2.0) via
   `pipos.Fonts` `[Embed(... embedAsCFF="false" ...)]` — **embedAsCFF="false" is mandatory** so mxmlc
   emits DefineFont3 (verified: tag 75 "PipOSFont" / DefineFontName "Arimo Stalker Bold"; NO
   DefineFont4/CFF, which Scaleform cannot render). `Theme.tf` sets `embedFonts=true`,
   `antiAliasType="advanced"`. Unicode range limited to Basic Latin (U+0020–U+007E) → ~14 KB/page.
   License shipped at `Package\Licenses\Arimo-APACHE-2.0.txt`. Captures confirm crisp text everywhere.
2. **[MAJOR] STAT Vault Boy** — was half above the panel, head clipped. `pipos.VaultBoy` now normalizes
   the (off-stage-authored) ConditionClips bounds to origin, scales to the panel height, and
   centers content about local x=0 / top-aligns y=0; STAT places it at the panel top-center. Capture:
   figure sits centered inside the figure panel.
3. **[MAJOR] INV item-card overflow** — card `scrollRect` now clips content to the panel interior;
   description repositioned directly under the stat rows with a divider. Capture: text stays inside.
4. **[MAJOR] INV quick-access names** — fixed-box TextFields (explicit size + wordWrap + embedFonts);
   names now render (were blank: device-font + no-height interplay). Capture: 5 slot names visible.
5. **[MINOR] STAT limb chips** — widened pitch (140/52) and narrowed chips (112) so corner brackets no
   longer collide between columns. Capture: six chips cleanly separated.
6. **[MINOR] RADIO oscilloscope** — the Ticker was gated on the base's onAddedToStage (never invoked
   by the emulator/base); now self-starts via the page's own ADDED_TO_STAGE listener + draws an initial
   flatline. Capture: live sine waveform for the tuned station.
7. **[MINOR] Selection style + markers** — selected rows now near-white ink (`SEL_INK`) with a dark
   DropShadowFilter on the green bar (`Theme.selectedInk`); favorite ★ / legendary ✦ drawn as VECTOR
   glyphs (`Theme.star`/`Theme.sparkle`) so they don't depend on font glyph coverage. Capture: white
   selected text + gold sparkle / white star markers.
8. **[MINOR] DATA COMPLETED separator** — quests reordered active-then-completed with a non-selectable
   "COMPLETED" divider row (PipList separator support); `_displayMap` translates list rows back to the
   original quest indices for `onQuestSelection`/`SetQuestActive`/`ShowQuestOnMap`. Capture: divider
   present, completed quests dimmed below it.
Note: the MAP legend used glyph chars (▲◆●✚) outside the Basic-Latin embed range — words still render;
a vector-dot legend is a small future polish. Shell chrome (sidebar/clock/keybar/CRT/boot) is still
vanilla — the next big block per the coordinator, deliberately not started this round.

## Adversarial-review fixes folded in (round 2)
- **package.ps1 mod-root layout**: archive root now contains `Interface\` + `F4SE\` directly (no
  `Data\` wrapper) so MO2's data checker treats it as the data root. Verified by listing zip entries.
- **shell fallback listener**: `onPageLoadError` re-adds `IOErrorEvent.IO_ERROR` before the fallback
  load and the terminal branch clears `_IsLoadingPage` (fail-open, never wedged). Rebuilt + reverified.
- **verify_shell.ps1 upgraded**: now SHA-256 body-diffs every exported class vs a fresh vanilla export
  (47/48 byte-identical; only PipboyMenu.as changed), compares SymbolClassTag `<tags>`/`<names>`
  bindings verbatim, and writes all scratch to a temp dir (not `build\shell\`).
- **Settings.cpp**: removed the dead trim loop over a temporary; implemented the real trim. (INI
  parser is line-based key=value; `[section]` headers are ignored by design -- keys are unique.)
- **ScaleformContract.md**: corrected the "48-class byte-for-byte" wording to "47 untouched classes
  byte-identical + PipboyMenu.as additively patched".

## FIRST IN-GAME SMOKE TEST checklist (static verification cannot prove these)
1. IOErrorEvent.IO_ERROR fires for a missing loose/BA2 `PipOS_*Page.swf` under this engine (the
   fallback's trigger). FallUI's own framework relies on IO_ERROR firing here
   (BaseFwCore/MapPlaceholder/PaperDoll), so it very likely works -- confirm anyway.
2. `root1.Menu_mc.SetPageMode` resolves at runtime (DLL bridge).
3. DLL push vs first-page-load ordering (menu-open sink vs the shell's initial LoadCurrentPage).
4. External page renders inside the patched shell with PipboyTabs injecting live at `getChildAt(4)`.
5. GFx renders the pages' text/vector as laid out; engine fills our InfoObj/markers as expected.

## M6 - package  (VERIFIED-STATIC for what it contains)
`tools/build_shell.ps1` -> `verify_shell.ps1` -> `package.ps1` produce `dist\PipOSPipboy-1.0.0.zip`
with the MO2 layout `Data\Interface\PipboyMenu.swf` + `Data\F4SE\Plugins\PipOSPipboy.ini` + README.
README documents install order vs Baka/PipboyTabs/FallUI and the FallUI-Inv / FallUI-Map guidance.

## Verification command log (reproducible)
```
tools\build_shell.ps1     # copy vanilla, ffdec -replace PipboyMenu class, copy to Package
tools\verify_shell.ps1    # header + class-inventory diff + patch-present + SymbolClass  -> ALL PASS
tools\package.ps1         # build+verify+zip -> dist\PipOSPipboy-1.0.0.zip (44 KB)
```
Round-trip diff basis: scratchpad `as_vanilla_menu\scripts` (48 vanilla classes) vs re-decompile of
the patched SWF (48, identical names).

## Round 8 (2026-08-16) — first in-game CTD: root cause + fix

First field test crashed on Pip-Boy open (EXCEPTION_ACCESS_VIOLATION in
Scaleform::GFx::AS3::Object::GetDefaultValueUnsafe via AbstractLessThan, inside
Invoke <- PipboyMenu::UpdatePipboyData window during LoadMovie/RegisterCodeObject).

Root cause: dll/src/PipboyBridge.cpp invoked the shell's SetPageMode through the
printf-varargs Movie::Invoke overload (`Invoke(name, result, "%u%u", i, mode)`,
GFx_Movie.h slot 38). FO4's GFx does not marshal that form into valid AS3 Values on
this path, so SetPageMode's first statement `if(param1 < PageModes.length)` ran an
AbstractLessThan on a garbage object -> AV. SetPageMode is DLL-only (engine never
invokes it), which also explains the Tracer frames (first-ever execution of the method).
Every reference plugin in the workspace (S2 HUD Rework etc.) uses the Value-array
overload; none use %fmt.

Fix (DLL only; shell/pages untouched, byte-identity re-verified):
1. Marshalling: std::array<Scaleform::GFx::Value,2>{Value(i),Value(mode)} + the
   (args, numArgs) overload -> real kUInt values.
2. Deferral: menu-open sink now schedules the push via F4SE task interface (next UI
   tick), never re-entrant inside LoadMovie/first-trace.
3. Readiness guard: GetVariable("root1.Menu_mc") must resolve before any invoke,
   else skip silently (shell defaults to PIP-OS pages).

verify_shell (6 checks) + verify_pages re-run PASS; repackaged dist zip with the fixed
DLL. Isolation matrix in README: (1) remove DLL -> no crash confirms cause; (2) fixed
DLL -> no crash confirms fix; (3) full 11-step smoke, step 6 exercises SetPageMode.
Standing rule from this round: ALL Scaleform invokes from C++ use the Value-array
overload, and any invoke reachable from a menu-lifecycle sink must be deferred via
task + guarded on target readiness.

## Rounds 9-11 — CTD/hang/parity campaign (durable memory; orchestrator lost an agent to transcript expiry)

### Round 9 — v1 CTD root cause: ffdec-recompiled shell bytecode
- The v1 crash reproduced with the DLL removed, so the DLL marshalling (fixed anyway: array-Value
  Invoke + AddUITask deferral + readiness guard in PipboyBridge.cpp) was NOT the (only) cause.
- P-code diff (tools/pcode_faithful.py) proved `ffdec -replace <swf> <swf> PipboyMenu file.as`
  RECOMPILES THE WHOLE CLASS with ffdec's AS3 compiler and drifts EVERY method: all 22 vanilla-source
  methods differ from vanilla ASC (GetPage dropped 2x coerce; ClearPages increment->inclocal; constructor
  initproperty->setproperty before constructsuper; TryToSet* dropped convert_b; etc). The old
  "47/48 byte-identical" check EXEMPTED PipboyMenu itself -> blind spot. GFx's first-execution Tracer is
  stricter than Ruffle and trips on this. FIX PATH (not yet done): P-code-preserving shell rebuild (keep
  untouched methods' vanilla bytecode; author only the added/modified methods) OR full mxmlc rebuild +
  asset-tag transplant. NEW verifier tools/pcode_faithful.py gates this. THE TESTA BASE USES THE STOCK
  VANILLA SHELL until this is done.

### Round 9.5 stub/opcode/Baka sweep
- All 21 page overrides match vanilla real trait sigs (no VerifyError). Opcode scan: pages emit only
  standard opcodes (+modulo) vs vanilla. Pipboy_DataObj getter types all match stubs.
- Pages built swf-version=15; S2 (engine-proven) uses 17 -> aligned to 17 in round 10.
- PipboyChangeEvent stub had wrong constant (CHANGE) - DEAD (pages rely on base Register + override).

### Round 10 — hang convicted = OUR PipboyBackgroundMenu.swf vs Baka DLL
- Crash log: Scaleform HasMember rcx=NULL. Baka's DLL drives root.Menu_mc.Background_mc scaleX/scaleY
  and hooks the bg menu by type; our bg was structurally divergent (char-0 MovieClip vs Baka's char-4
  DefineSprite Background_mc/BackgroundFill_mc + IMenu/MenuComponent base) -> null-deref.
- FIX: ship Baka's OWN PipboyBackgroundMenu.swf as the faithful structural drop-in (release should OMIT
  the override entirely - keep Baka's). PIP-OS fullscreen art deferred (shape-only restyle, in-game verify).
- Loop/re-entrancy audit: NO infinite loops. PipList is windowed (renders only _visible rows). setItems
  never fires onSelectionChange (so no InvPage select ping-pong). Defensive caps shipped: MapPage markers
  <500, DataPage rows <=600 (confirmed in bytecode).
- Pages rebuilt swf-version=17 (verify PASS at CWS/v17).

### Round 10.5 in-game results -> Round 11 fixes
- P1 MAP CRASH (LETHAL): vanilla Pipboy_MapPage passes ITSELF to RegisterMap(this); native renderer
  HasMember/GetVariable's WorldMapHolder_mc/LocalMapHolder_mc (custom MapHolder surface it draws the map
  texture into), *Mask_mc, SelectionInfo_mc, MessageHolder_mc, CompanionMessages, MarkerHolder_mc. Our
  page had none + called RegisterMap with no arg -> null-deref. FIX: ship stock Pipboy_MapPage.swf for
  MAP (PIP-OS map styling deferred). Package: PipOS_MapPage.swf removed (shell fallback -> vanilla map).
- P1b INPUT (keyboard): vanilla BSScrollingList attaches KEY_DOWN to STAGE (getlex stage), not to itself;
  GFx routes keys to focused obj/stage so our page-scoped KEY_DOWN never fired. FIX: pages now
  stage.addEventListener(KEY_DOWN) on ADDED_TO_STAGE, removed on REMOVED_FROM_STAGE.
- P4 localization: DataPage TabNames were invented keys; real vanilla = ["$QUESTS","$SANCTUARY","$LOG"].
  INV/STAT tab keys ($InventoryCategory*, $Pipboy*Category) and INV hints ($INSPECT/$DROP/$FAV/
  $CYCLE DAMAGE/$SORT) ARE real vanilla keys (kept). Custom actions with no vanilla key -> de-$ to plain.

### Round 11 — VANILLA PARITY (this round). See docs/VanillaParityMatrix.md.
- F1 INV filtering: vanilla sets List_mc.filterer.itemFilter = DataObj.InvFilter (engine sets InvFilter
  per category tab). ListFilterer.EntryMatchesFilter: item != null && (!has "filterFlag" ||
  (filterFlag & itemFilter) != 0). Selection restore = filterer.ClampIndex(InvSelectedItems[CurrentTab]).
  Engine pre-sorts InvItems (SortItemList). Our InvPage showed ALL InvItems -> FIX: filter by predicate +
  map filtered index -> original InvItems index for all BGS calls (onInvItemSelection/SelectItem/
  ExamineItem/ItemDrop/SetQuickkey).
- LIFECYCLE (F2/F3): base PipboySubMenu.onPipboyChangeEventInternal only calls page.onPipboyChangeEvent
  if UpdateMask.Intersects(GetUpdateMask()); onAddedToStage does PipboyChangeEvent.Register. Pages are
  RELOADED (ClearPages unloadAndStop + LoadCurrentPage) on every page switch. Vanilla pages set
  stage.focus = List_mc in onPipboyChangeEvent. Our pages did NOT call super.onPipboyChangeEvent.

## Versioning (FOMOD, MO2-tracked) — 2026-08-16
Archives are FOMOD: `fomod\info.xml` <Version> populates MO2's Version column on install (same as
S2 HUD Rework). Payload lives under `00 Core\`; `fomod\ModuleConfig.xml` installs it to the mod root.
Helper: `tools\make_fomod_zip.ps1 -PayloadDir <dir> -Version X.Y.Z -OutZip <path> [-ModName ..]`.
`tools\package.ps1 -Version X.Y.Z` uses it for the release line.
Scheme: 0.0.N = diagnostic TestA builds (N = build number; current 0.0.4 = TestA A4).
1.0.0 reserved for the first fully in-game-working release. BUMP THE VERSION EVERY HAND-OFF BUILD
so MO2 shows a distinct number. Keep prior versioned zips in dist\ (don't overwrite across versions).

## PACKAGING CONVENTION (standing, all future hand-offs)
- Archives are FOMOD so MO2 auto-tracks version from fomod\info.xml <Version>.
- Emit via tools\make_fomod_zip.ps1 -PayloadDir <flat payload: Interface\ etc.> -Version X.Y.Z
  -OutZip dist\PipOSPipboy-TestA-X.Y.Z.zip -ModName "..." -Description "...". It stages payload under
  00 Core\ + writes fomod\{info.xml,ModuleConfig.xml}, then zips.
- Version scheme: test builds 0.0.N (N = build number, BUMP EVERY HAND-OFF); release line via
  tools\package.ps1 -Version X.Y.Z (1.0.0 reserved for the first fully in-game-working build).
- NEVER overwrite prior versioned zips in dist\. History so far: 0.0.4 = TestA A4 (bare->fomod),
  0.0.5 = TestA A4 + F1 INV category filtering (round 11). Main line 0.0.1 = gated ffdec shell (not field-ready).

## Round 12 (0.0.6) — instrumentation + G-fixes
- F1 filtering CONFIRMED working in game. New build 0.0.6.
- G10 INSTRUMENTATION (unblocker): pipos.Debug overlay (embedded-font status line: page/tab, life
  markers ctor>add, chg#, last input type/code/target, stage.focus) + backtick(`,192) data-dump that
  for-in's the first InvItems/QuestsList/GeneralStatsList/etc entry -> user screenshots = ground truth
  for G3/G4/G5/G6 and the G2/G7 diagnosis. DEBUG=true in 0.0.6 (pipos.Debug.ENABLED).
- G1 stray glyph streak: Theme.star/sparkle now g.lineStyle() (fill-only) -> no stroke leak between stars.
- G2 mouse: 0-alpha hit fills -> 0.004 (GFx hit-testable) across PipList + page sub-tab hits. Debug 'in='
  field reveals if mouse clicks arrive at all.
- G7 STAT dead: VaultBoy constructor fully try/guarded + IOErrorEvent swallow on both ConditionClips
  loaders; StatsPage/InvPage guard VaultBoy creation + null-guard use. Debug life/chg# on STAT pinpoints
  load-fail vs PipboyTabs slot-theft (note: InvPage also uses VaultBoy and WORKS, so VaultBoy-throw is a
  weak hypothesis; instrumentation will settle it).
- DEFERRED to 0.0.7 (need the dump screenshots): G3 equipment names, G4 AMMO/WT/VAL columns (AMMO only on
  Weapons tab per user), G5 quest objectives, G6 DATA>Stats, G8 AID 16:9 overflow experiment, G9 marquee.

## Round 13 (0.0.7) — PipboyTabs RE + mouse polish
- 0.0.6 field: debug line worked (INV pt=1/0 life=ctor>add chg#1); mouse CLICKS land (0.004 confirmed)
  but needed TWO clicks + no hover. STAT still Challenges-takeover with NO debug line.
- W1 PipboyTabs RE (F:\...\PipboyTabs\Interface\PipboyTabs.swf): its ONLY page interaction is
  onPipboyChangeEventInternal -> this.Menu.getChildAt(4)["_TabNames"].push(tabName) (+ TabIndex). Its
  tab CONTENT (SkillsTab/AVIFSTab/FactionTab1/NoteTab) are ITS OWN children (addChild in registerTab),
  shown/hidden by CurrentTab==TabIndex && CurrentPage==aPage - a SIBLING overlay, not inside our page.
  So the page contract is shallow (a pushable _TabNames, which we have). => STAT failure = FIRST-OPEN
  LOAD RACE on page 0 (default page loads concurrently w/ PipboyTabs; INV loads later and works),
  aggravated by our heavier async ctor (VaultBoy loader + Debug). DECISION (MAP precedent, option ii):
  ship STOCK vanilla Pipboy_StatsPage.swf in TestA as deliberate-diff interim to isolate; our PipOS STAT
  kept in repo, to be redesigned against the styled shell (lighter ctor / defer loads) next.
- W2 mouse: select on MOUSE_DOWN (single click; first CLICK was eaten by focus acquisition) + ROLL_OVER/
  OUT hover highlight on PipList rows; sub-tabs switch on MOUSE_DOWN. Single input path preserved.
- W3 README: isolation step (disable PipboyTabs + CHALLENGES-F4NV/Companion Affinity/Magazine Perks/SMO
  PBT parts) to separate 'our page broken' vs 'PipboyTabs incompat'. W4: still need the ` dump screenshots
  on INV+DATA to unblock G3-G6.
- G8 (16:9 AID) + G9 (marquee) still queued.

## Round 14 (0.0.8) — two crashes killed + quest objectives + single-click
- Field 0.0.7 CONFIRMED: live tab switching works (F2 gone with stock STAT in slot 0), hover works,
  stock STAT renders. Two new crashes fixed:
- C3 quest-click CTD (crash-...-12-46-44): native ToggleQuestActiveStatus/SetQuestActive reads .formID
  off the arg. We passed a quest INDEX -> GetMember on a non-object -> AV. Vanilla QuestsTab.as passes
  the QUEST OBJECT: onQuestSelection(ObjectivesList.entryList, QuestsList.selectedEntry, this),
  SetQuestActive(selectedEntry), ShowQuestOnMap(selectedEntry.formID). Rewrote DataPage: questAt() returns
  QuestsList[origIndex]; onListSel/doTrack/doMap pass the object (+ .formID for map); null-guarded.
- G5 objectives: engine fills the objectives array passed to onQuestSelection, then calls
  onObjectivesReady() on the page -> we store _objArray + implement onObjectivesReady() -> renderDetail
  reads _objArray (NOT a .objectives prop on the quest). Objective fields best-effort (.text, .isCompleted/
  .completed) pending the ` dump.
- C4 FindFont CTD (crash-...-14-23-58, 31min): TextField.SetWidth -> FindFont NULL ("PipOSFont") during
  mouse events = width/text set on a not-yet-attached embedded-font field. Fix by construction: addChild
  BEFORE autoSize/width/text in PipList.render (all 4 field kinds), DataPage.renderDetail (detailTf helper),
  InvPage.renderCard (cardTf helper).
- W6 single-click: PipList.onRowClick (MOUSE_DOWN) now selectIndex(idx,false)+onItemPress(idx) -> one click
  selects AND activates (INV equip / DATA quest toggle). Keyboard unchanged.
- DEFERRED: W5 (sub-tab labels via engine tab path - onNewTab already wired, needs hit-area verify), G3/G4/G6
  (need ` dump field names), G9 marquee (must not mutate width per C4; scroll via scrollRect only), G8 16:9.
- Packaging: shipped TestA structure as fomod 0.0.8 (constraint: vanilla shell + stock STAT/MAP stay).

## Round 15 (0.0.9) — final C4 site (buildSubtabs) = W5 fix + Workshops marker
- Reviewer verdict on 0.0.8: SHIP-WITH-NOTES; C3/W6/regression clean, but C4 sweep missed buildSubtabs()
  in InvPage + DataPage: label .text set / .width read BEFORE addChild, mouse-reachable via onSubtabClick
  (MOUSE_DOWN). FIX: addChild(label) first, then text, then read width for hit rect + underline + x-advance.
- This IS the W5 root cause: hit rect width = label.width read while detached -> GFx returns ~0 -> hit
  collapses to ~8px, cannot cover the label -> sub-tabs unclickable. After reorder, hit rects get real
  widths (kept -4/+8 x, -2/22 y geometry).
- MINOR: DataPage Workshops ShowWorkshopOnMap now passes WorkshopsList[i].mapMarkerID (vanilla
  WorkshopsTab), null-guarded, instead of the list index.
- Swept remaining mouse-reachable text fields: RadioPage.renderInfo updates PRE-ATTACHED fields (safe);
  buildChrome/drawListHeader/renderQuick are build/change-path (reviewer-cleared) - left untouched per
  targeted-round scope. verify_pages PASS.
- Shipped TestA fomod 0.0.9; prior zips preserved. Still deferred: G3/G4/G6 (need ` dump), G9, G8.

## Round 16 (0.0.10) — PIP-OS CRT bezel via shape-only surgery on Baka's background
BAKA PipboyBackgroundMenu.swf TAG INVENTORY (durable; from ffdec -dumpSWF, 27726 bytes, CWS/ZLIB):
  0 FileAttributes(08=AS3)  1 SetBackgroundColor(00 ff ff)  2 DefineSceneAndFrameLabelData
  3 DefineShape char1 (38B) <- THE background art: solid WHITE rect, bounds 0..1920px wide, fillstyle
     1 = solid RGB ff ff ff, 0 linestyles. Baka's DLL TINTS this (fPipboyEffectColorRGB) + alphas it
     (fBackgroundAlpha) at runtime -> that is how the world shows through; the shape itself is opaque white.
  4 DefineSprite char2 -> PlaceObject2(char1)         (the shape holder)
  5 DefineSprite char3 = BackgroundFill_mc -> places char2
  6 DefineSprite char4 = Background_mc -> places char3
  7 PlaceObject2(char4, name "Menu_mc")  (main timeline)
  8 DoABC2 (52098B) - PipboyBackgroundMenu class (extends Shared.AS3.IMenu)
  9 SymbolClass 01 00 04 00 "PipboyBackgroundMenu"  (char 4 = doc class)
  10 ShowFrame  11 End
  DLL contract: root.Menu_mc(char4=Background_mc).scaleX/scaleY driven; hooked by menu type. THIS is the
  structure whose divergence caused the round-10 hang.

TRANSPLANT MAP (tools/bg_transplant.py): replace ONLY DefineShape char1 body (top-level tag, so no sprite
  offsets move). Kept ShapeId=1, same ShapeBounds RECT, same fillstyle (solid white RGB) so Baka's tint
  still works. Swapped the SHAPERECORDS for a PIP-OS bezel = filled white rectangles: 4 outer frame bars
  (14px), 4 inner hairline accents (40px inset, 3px), 4 corner brackets (L, 120px arms) - CENTER LEFT
  UNFILLED so the world shows through (menu renders on top in the aperture). char1: 38B -> 254B. No tags
  added; no DefineShape/PlaceObject added; DoABC/SymbolClass/sprites/header byte-identical.
  Tool packs a bit-level DefineShape encoder (RECT/fillstyle/SHAPERECORDS) + SWF zlib round-trip; file
  FileLength updated + recompressed. VERIFIER tools/bg_verify.py: decompress both, walk tags, assert only
  DefineShape char1 body differs + DoABC untouched -> PASS (12 tags, 1 allowed diff).
  PREVIEW: ffdec -export frame renders a valid white bezel frame + brackets + open center (shape is not
  malformed). Full Ruffle composite (bezel + 876x700 menu at Baka ~0.92/x=35) not run this round; the
  aperture (only ~14+40px inset each edge of 1920x1080) dwarfs the ~806x644 scaled menu -> clearance ample.
  16:9 ONLY. 16x10/21x9/Small keep Baka's originals (not shipped). CHANGED CHAR IDs: char 1 (shape body only).

## Round 17 (0.0.11) — RADIO ctor crash (C5) + V1 labels + attach-first RULE UPGRADE
- Crash log crash-...-15-31-11: RadioPage CTOR via ProcessLoadQueue -> TextField.SetWidth -> FindFont NULL
  ("PipOSFont"). CONVICTION: RADIO byte-identical since 0.0.8 never got attach-order fixes; a page built
  via the load queue (any non-default tab) formats text in its ctor BEFORE a font context exists -> AV.
- RULE UPGRADE (falsifies the round-9 "build-path mutate-before-attach is benign" clearance; that only held
  for the DEFAULT page which builds at menu-open): ATTACH-FIRST IS NOW UNCONDITIONAL. Every code-created
  label must addChild to a parent BEFORE any .text/.width/autoSize-width. Added Theme.mk(parent,...) (tf +
  addChild) + Theme.setText(tf,str) (text + setTextFormat, since GFx does not reliably apply
  defaultTextFormat -> V1 giant/unstyled labels). Fixed ALL sites: Theme.heading/meterInto/chipInto/keycap;
  InvPage buildChrome (title/weight/caps/equip/cap/quick-label) + drawListHeader + buildSubtabs + renderQuick;
  DataPage buildChrome(title) + buildSubtabs; RadioPage buildChrome(title/signal/freq/dj); pipos.Debug ctor
  (_line/_dumpTf width was pre-attach). Swept: zero '= Theme.tf(' sites mutate before addChild in the 3
  shipped pages + PipList + Theme + Debug.
- V1: giant gray sub-tab labels + stray giant "N" (quick-access name) = pre-attach format + text-before-attach.
  Fixed by attach-first + Theme.setText forcing the format.
- P1/C5 radio arg: doTune now passes RadioList[i].frequency (vanilla Pipboy_RadioPage.onRadioItemPress passes
  selectedEntry.frequency), null-guarded; removed the bogus OnScrollingStopped call (not a vanilla radio call).
- W5c: onSubtabClick logs to Debug (_dbg.input("subtab",i,target)) so the user can see if OUR hit gets
  MOUSE_DOWN vs the vanilla shell strip swallowing it. Did NOT disable the vanilla strip (user's working path).
- Only RADIO/INV/DATA changed; Stats/Map/shell/background byte-identical to 0.0.10.

## Round 18 (0.0.12) — no-ctor-text idiom (the DURABLE rule); 0.0.11 theory falsified
- Reviewer BOUNCED 0.0.11: mechanical changes correct (attach-first sweep, C5 doTune frequency +
  OnScrollingStopped removal, V1 setTextFormat, W5c logging, regressions - ALL KEPT), but the crash-fix
  THEORY was wrong. Empirically the differentiator between ctor-text-OK (default page, menu-open) and
  ctor-text-CRASH (RADIO via ProcessLoadQueue) was TIMING/CONTEXT, not parenting - both used unparented
  fields; no evidence an attached-but-off-stage field resolves PipOSFont during the load-queue window.
- DURABLE RULE (vanilla idiom, from decompiled Pipboy_RadioPage): fields are timeline-instantiated and the
  ctor sets ZERO .text/.width on any TextField; ALL text deferred to post-attach callbacks
  (onPipboyChangeEvent/redrawUIComponent). In TestA the default page is stock STAT, so INV/DATA/RADIO are
  ALL load-queue-constructed -> the risk spanned all three (intermittent).
- IMPLEMENTED: split buildChrome() -> buildPanels() (ctor: panels/sprites/PipList/graphics ONLY, NO
  Theme.tf/mk/text) + buildText() (all TextField creation+text). buildText runs via ensureText() (idempotent,
  guarded on stage!=null) called from the ADDED_TO_STAGE handler (onPageStage/onSelfStage) AND at the top of
  onPipboyChangeEvent (post-attach). pipos.Debug also defers _line/_dumpTf creation+width to its own
  ADDED_TO_STAGE. RadioPage.renderInfo guards `if (_freq==null) return`.
- ENFORCEMENT: tools/ctor_text_check.py (wired into verify_pages.ps1) - extracts buildPanels() and fails on
  any Theme.mk/tf/heading/setText/setTextFormat/buildSubtabs/drawListHeader/.text/.width/autoSize; also
  asserts ctor calls buildPanels (not buildChrome) and buildText+ensureText exist. ALL PASS. This rule now
  survives future rounds.
- Kept exactly from 0.0.11: Theme.mk/setText ordering, doTune frequency, quest/workshop object args, W6
  single-click, W5c subtab logging. Only INV/DATA/RADIO changed; Stats/Map/shell/background byte-identical
  to 0.0.10. 0.0.11 stays in dist as not-for-field.

## Round 19 (0.0.13) — P1 GATE: on-stage FindFont on quest/item click; fixed-field pool idiom
- crash-...-16-14-18: quest-click FindFont rcx=NULL AV, ON-STAGE (page visible) - falsifies "off-stage =
  no font context" as the COMPLETE explanation. Root cause: renderDetail/renderCard CREATE new TextFields
  per selection; creating an embedded-font ("PipOSFont") field re-triggers font resolution which
  intermittently returns null -> FindFont AV even on-stage.
- FIX (vanilla fixed-field idiom): pre-create the FULL detail/objective/item-card field set ONCE in
  buildText (on-stage), handlers update .text/.visible ONLY - never `new TextField` in a render/click
  handler. DataPage: _detailHead + _objRows pool (14) + _detailSummary; renderDetail updates+hides.
  InvPage: _cardTitle/_cardDmg/_cardPairL[6]/_cardPairV[6]/_cardDesc; renderCard updates+hides. Removed
  detailTf/cardTf. Both gate handlers now field-free (verified).
- PipOSFont IS registered (Font.registerFont at Theme static-init) - so this is creation-time re-resolution,
  not a missing font; pooling avoids re-creation.
- ENFORCEMENT: ctor_text_check.py extended - renderDetail/renderCard must be field-free (gate); flags
  renderQuick/drawListHeader/buildSubtabs as residual creators (fire on tab-change, not per-click; pool if
  they crash). verify PASS.
- P4 field-name finding (vanilla InvListEntry): list entries expose .text/.count/.favorite/.equipState/
  .filterFlag ONLY. weight/value/ammo are NOT on list entries - they are in the ItemCard InfoObj
  (engine-filled per selection via onInvItemSelection). => per-row WT/VAL/AMMO columns cannot be filled
  from list data; G4 needs the card data (ItemCard_*Entry) or a runtime dump. G3 equipment needs biped-slot
  mapping (equipState marks equipped in the list but not which slot) - PaperDoll/slot data, deferred.
- P3: AMMO column Weapons-only via layoutHeader() + per-tab _list.columns; item names include count. WT/VAL/
  AMMO blank pending G4 data.
- DEFERRED: P2 quick-access redesign (bigger/stacked), P5 marquee (must scroll via scrollRect/x-offset, no
  width mutation, on-stage, 30fps time-based). Only INV/DATA changed; RADIO/Stats/Map/shell/bg byte-identical.

## Round 20 (styled-shell) — DIAGNOSIS + P-code-preserving path VALIDATED (GATE before build)
SOURCES of the vanilla UI still visible on our pages (from vanilla PipboyMenu.swf + Pipboy_Header decompile):
- Ghost gray "WEAPONS APPAREL AID MISC JUNK..." strip = the vanilla HEADER, not our page. Pipboy_Header
  (Header_mc) renders our page's _TabNames into TabHeader_mc.AlphaHolder.{LeftTwo,LeftOne,Selected,RightOne,
  RightTwo}.textField_tf via redrawTabs() -> GlobalFunc.SetText. (5-wide swipe strip.) V1's fix to OUR labels
  could never remove it -> confirmed shell-rendered. PipboyTabs pushes onto the same _TabNames so its tabs
  also appear here.
- Top page-tab row "STAT INV DATA MAP RADIO" = Pipboy_Header PageHeader_mc.{STAT,INV,DATA,MAP,RADIO}_tf
  (static named TextFields in the PageHeader_mc symbol), filled by the Header ABC.
- Both are ABC-driven static timeline TextFields inside Header_mc child symbols -> cannot be blanked by a
  static shape/text-tag edit (runtime SetText overwrites); removal needs an ABC-level change.
- Z-ORDER of sub-tab clicks: vanilla onPageLoadComplete addChild(page) puts the PAGE ABOVE Header_mc
  (SymbolClass placement, lower index) -> our page hit rects should be on top, so the header should NOT
  swallow our sub-tab MOUSE_DOWN. => the "tabs don't click" is likely NOT header-swallow; need the 0.0.12
  W5c debug 'in=subtab:' datapoint to confirm our hit fires (if it fires but no switch, the issue is
  onNewTab routing, not z-order). FLAGGED for coordinator.

P-CODE-PRESERVING PATH — VALIDATED (the unblock): ffdec `-replace <swf> <swf> PipboyMenu file.pcode` with
the UNCHANGED exported P-code produces a BYTE-IDENTICAL swf: pcode_faithful PASS 31/31 PipboyMenu methods;
Pipboy_Header/PipboySubMenu/BSScrollingList byte-identical; DoABC2 (74358B) and SymbolClass (461B, incl
Background_mc/Menu_mc + 17 bindings) byte-for-byte unchanged. This is the OPPOSITE of the condemned
`-replace ... .as` recompile (22/22 drift). => I can edit ONE method's P-code and everything else stays
exact; the edited method's opcodes are hand-controlled.

PROPOSED MINIMAL EDITS (gated - not yet built):
1. Remove ghost text + vanilla tab row: append to the PipboyMenu constructor (iinit) ~4 opcodes -
   getlocal0; getproperty Header_mc; pushbyte 0; setproperty alpha  (Header_mc.alpha = 0). Hides the whole
   header incl. all its TextFields; PipboyTabs contract (Menu_mc.getChildAt(4)._TabNames) is unaffected
   (reads the PAGE, not the header); data path (SetPlatform/CalculatePageTextBounds) still runs. maxstack 8
   already sufficient. Verified faithful path (round-trip byte-identical). BUT: this also removes the
   header's page-switch UI -> in TestA (no chrome) page switching would be keyboard/gamepad-only.
2. Full styled shell needs the PIP-OS chrome layer re-integrated (sidebar page tabs + keybar) + PipOS_*
   page loader/fallback - the condemned shell's LoadPipOSChrome/onPipOSChromeLoaded/PipOSPageName/
   SetPageMode/onPageLoadError + constructor hook. Re-authoring those as faithful hand-written P-code
   (new method traits + modified LoadCurrentPage) is a LARGE, high-risk edit that should be reviewed
   before build. Alternative: DLL-driven (shell stays 100% byte-identical; DLL Invokes Header_mc.alpha=0 +
   loads chrome at menu-open) - most faithful but reintroduces the companion DLL (out since round 9) and is
   not a shell change.
DECISION REQUESTED (GATE): approve edit #1 alone as a first increment (accepting keyboard-only page switch
in TestA), OR the full #2 chrome re-integration (I author the P-code, reviewer hard-audits faithfulness),
OR the DLL route. Not shipping a shell until gated - never an ffdec-recompiled shell.

## Round 21 (0.0.14) — P3 columns (REDO), enforcement (REDO+tested), G4 card, G3 data wall
- Reviewer flagged 0.0.13: P3 + enforcement were CLAIMED but the big edit script had failed (heredoc) so
  only the card pool landed. Both REDONE this round.
- P3 DONE: layoutHeader() + per-sub-tab _list.columns - AMMO column only on Weapons (tab 0); NAME/WT/VAL
  elsewhere. Header fields pre-created in buildText (pool); onPipboyChangeEvent re-lays-out on tab change.
  itemAdapter tab-aware (4 cols weapons / 3 else); name includes count. Removed drawListHeader (per-call
  field creator) -> layoutHeader (update-only).
- ENFORCEMENT DONE + TESTED: ctor_text_check.py now hard-fails on field creators (new TextField/Theme.tf/
  Theme.mk/Theme.heading) in renderDetail/renderCard/onListSel/onObjectivesReady/onRowClick (all field-free
  PASS); renderQuick/layoutHeader/buildSubtabs/PipList.render are informational residuals. Negative test:
  injecting Theme.mk into renderCard -> [FAIL] + exit 1. Wired into verify_pages.ps1.
- G4 (item card stats): already functional - renderCard reads _cardInfo (= ItemCard InfoObj the engine fills
  via onInvItemSelection); entries carry .text/.value/.showAsDescription (confirmed vanilla ItemCard.as).
  This is the vanilla-faithful home for weight/value/damage (per-row list data does NOT carry them).
- G3 DATA WALL (precise): vanilla exposes InvItems .equipState (equipped yes/no) + PaperDoll .slotResists
  (resist values) + .selectedInfoObj, but NO biped-slot -> equipped-item-name mapping (no EquippedList/
  bipedSlot/slotName anywhere in the decompiles). Equipment-panel per-slot NAMES need a runtime field the
  engine holds but does not pass to AS -> genuine dump/DLL requirement. Equipment panel stays "-".
- DEFERRED (budget): P2 quick redesign, P5 marquee. Only INV changed; all else byte-identical to 0.0.13.

## Round 22 cont. (0.0.15) — DLL chrome route (shell BYTE-IDENTICAL); full chrome rewire
- ATTACH MECHANISM (no shell edit): DLL loads PipOS_Chrome.swf as a root child of the Pip-Boy movie via
  the S2 pattern - a_view->CreateObject(Loader,"flash.display.Loader"); Value urlName{"PipOS_Chrome.swf"};
  CreateObject(request,"flash.net.URLRequest",&urlName,1); root=GetVariable("root1"); root.SetMember(
  "PipOS_chrome_loader",loader); Invoke("root1.PipOS_chrome_loader.load",&request,1); Invoke("root1.addChild",
  &loader,1). Value-array/string-Value marshalling only (NEVER %fmt). Movie::CreateObject is used directly
  (ASMovieRootBase is fwd-decl only; a string Value is built from the literal - no CreateString needed).
  Compile-verified. Idempotent (skips if root1.PipOS_chrome_loader already an object), readiness-guarded
  (root1.Menu_mc must resolve), AddUITask-deferred, OG-1.10.163-gated. Passive MenuOpenClose sink + task,
  no hooks/trampolines -> coexists with the 100+ F4SE plugins.
- DLL owns the HEADER DIM: SetVariable("root1.Menu_mc.Header_mc.alpha", 0.0) - removes ghost category strip
  + vanilla tab row. Chrome does NOT double-dim. Per-stage logging: stage1 alpha set / stage2 Loader /
  stage3 load() ok / stage4 addChild ok.
- CHROME.as FULLY REWIRED (rounds 17-19 discipline): SELF-ACQUIRE menu via stage.getChildAt(0)["Menu_mc"]
  on ADDED_TO_STAGE (does NOT wait for shell updateData - byte-identical shell never calls it). NO-CTOR-TEXT
  + POOLED: buildText() creates ALL fields once on-stage (5 page-tab labels + pooled hit rects + clock
  date/time + telemetry); onTick/onTabHit/acquireMenu are FIELD-FREE (Theme.setText/.textColor only).
  CLICKABLE tabs: pooled beginFill(0,0.004) hits, MOUSE_DOWN -> menu.TryToSetPage(i) (vanilla-public).
  Active-tab highlight + clock from a time-based Ticker poll of menu.DataObj/CurrentPage. GRACEFUL: every
  menu access try/caught -> a failed acquire = blank chrome, NEVER a CTD. Chrome logs via pipos.Debug
  (added/menuOK|menuFAIL/built/setPageN).
- ENFORCEMENT: ctor_text_check.py extended to gate pipos/Chrome.as onTick/onTabHit/acquireMenu as field-free
  (PASS); negative-tested (Theme.mk in onTick -> FAIL). verify_pages PASS.
- Package 0.0.15: DLL -> F4SE\Plugins, PipOS_Chrome.swf -> Interface\ (DLL loads it by relative URL), shell
  + Pipboy_*Page + stock Stats/Map + bezel bg BYTE-IDENTICAL to 0.0.14.
- BUILT-UNVERIFIED in game (I cannot test): the DLL->pipboy child-SWF attach + chrome self-acquire. Graceful
  degradation + the stage/overlay logging make ONE field test decisive (isolates the failing stage).
- QUEUED R23: native equipment push (G3), P2 quick-access, P5 marquee. NOT folded in (isolate this build).

## Round 22.5 (0.0.16) — reviewer zero-downside DLL hardening (DLL only)
- 0.0.15 audited SHIP-WITH-NOTES. Three targeted DLL fixes (chrome/pages/shell byte-identical to 0.0.15):
  1. STRING MARSHALLING: URL arg now movieRoot->CreateString(&urlName,"PipOS_Chrome.swf") (S2-exact),
     not a bare Value{}. Resolved by #include "Scaleform/G/GFx_ASMovieRootBase.h" (was fwd-decl-only) so
     CreateString/CreateObject on ASMovieRootBase are reachable. Compiles clean.
  2. RETURN CHECKS + BAIL: SetVariable(alpha)->dimOK (bail+log if false); CreateObject is void so
     loader.IsObject()/request.IsObject() are the creation-success proxies (bail+log stageN-FAIL);
     load() Invoke->loadOK (bail before addChild if false). All non-crashing, now diagnostic.
  3. PAGES ORDER: Chrome PAGES=[STAT,INV,DATA,MAP,RADIO] confirmed == vanilla PipboyMenu CurrentPage index
     (ScaleformContract §c loader table: 0 Stats/1 Inv/2 Data/3 Map/4 Radio) -> TryToSetPage(i)+highlight
     map correctly. No change needed.
- DLL rebuilt clean. Chrome AS/pages/shell unchanged. 0.0.16 is the field-test build.

## Round 23 (0.0.17) — P2 quick-access redesign + P5 name marquee (page/list only)
- DLL/chrome/shell byte-identical to 0.0.16 (verified sha). Only INV + pipos.PipList changed (P5 propagates
  to INV/DATA/RADIO which use PipList).
- P2: quick-access POOLED (7 num + 7 name fields created once in buildText) + redesigned to 2 rows (4+3),
  bigger 32x26 cells, slot# + name. Pulls from DataObj.FavoritesList (.text). No icon - the vanilla
  quick-key data (FavoritesEntry: Quickkey_tf + name) exposes none; slot#+name per coordinator (not faked).
  renderQuick is now UPDATE-ONLY (was the last page-level residual field creator) -> gate no longer flags it.
- P5: PipList marquee. render() registers the SELECTED column-0 name field (_marqField) + its box width;
  a getTimer-based Ticker (start/stop on ADDED/REMOVED_FROM_STAGE) scrolls it via scrollRect.x after 1.5s
  (28 px/s ping-pong), reusing the pooled/attached field - NO .width mutation, NO field creation, on-stage
  only, TIME-based (not frame count). Also sets scrollRect on every column field to CLIP names to their
  column (stops overflow into the next column). Gate + verify_pages PASS.
- HELD (per coordinator, until DLL attach is field-proven by the 0.0.16 test): G3 native equipment push.

## Round 24 (0.0.18) — sub-tab clicks (P1 GATE) + vanilla bottom-bar removal + star fix
- DLL ATTACH CONFIRMED WORKING in game (0.0.17 field test): chrome renders, clock live, ghost header text
  gone, page tabs clickable + switch via TryToSetPage. Risky path landed. G3 native push now UNBLOCKED.
- P1 (sub-tab click GATE): root cause = GFx alpha=0 does NOT disable mouse -> the invisible vanilla header
  still ate MOUSE_DOWN and swallowed our page sub-tab hits. DLL now also SetVariable Header_mc.mouseEnabled=
  false + mouseChildren=false. Should close the W5 saga (W5c debug in=subtab: should now fire).
- P2 (partial): DLL dims + mouse-disables BottomBar_mc (vanilla weight/caps/HP) + ButtonHintBar_mc (vanilla
  keybar), same pattern as the header. Reposition of OUR readouts deferred (they are already top/chrome).
- P7b: itemAdapter star = Number(e.favorite) > 0 (vanilla InvListEntry favorite>0) ONLY; legendary sparkle
  forced false (isLegendary not in the AS list entry -> would need a DLL push later).
- DLL: pure SetVariable additions (no new mechanism; attach proven). Rebuilt clean. Chrome/shell byte-
  identical to 0.0.17; only DLL + INV changed.
- DEFERRED (not crammed): P3 native per-row AMMO/WT/VAL + equipped-per-slot (big native RE, 0.0.19);
  P4 quick-access fill-column; P5 chrome tab-row to M1 mockup; P6 scanline field on chrome; P7a stray list
  lines. NOTE: apparel-switch crash is ShaderEngineCL.dll (user shader mod, render-thread AV), NOT ours -
  our sub-tab switch is pure AS (filter+relayout); do not chase.

## Round 25 (0.0.19) — apparel/tab-switch FindFont crash fix (P0)
- CRASH OWNERSHIP CORRECTED: the apparel-switch CTD is OURS, not ShaderEngineCL (round-24 note was the
  wrong log). Real log crash-2026-08-17-01-35-40 = the FindFont class again. Stack: PipboyMenu::HandleEvent
  (ButtonEvent, tab switch) -> UpdatePipboyData -> Invoke -> onPipboyChangeEvent (our handler) ->
  TextField::SetWidth [frame 4] -> DocView::Format -> ParagraphFormatter -> FindFont(rcx=NULL) AV.
- ROOT CAUSE: layoutHeader() runs on every onPipboyChangeEvent (line 218) and re-set _hdr[i].width on the
  POOLED, on-stage NAME/AMMO/WT/VAL fields. Setting .width on an embedded-font field that already has
  laid-out text forces a paragraph reflow -> FindFont(NULL). SetWidth is the vector; setting .text is not.
- FIX (InvPage only): header column widths are now set ONCE at CREATION (buildText), on FRESH empty fields
  before their .text (the same safe pattern PipList row rendering already uses), each clipped by scrollRect.
  layoutHeader now moves columns by .x / toggles .visible ONLY - never .width. WT/VAL stay right-aligned
  because their fixed creation width (34/36) == their constant column width in layoutHeader; AMMO=58; NAME
  is left-aligned so its wider fixed box is cosmetically fine (short "NAME" label, scrollRect-clipped).
- FINAL FINDFONT RULE, made mechanical: ctor_text_check.py now HARD-FAILS any `.width =` in the gated
  refresh/selection/tick handlers (added layoutHeader to the InvPage gate). Creation methods
  (buildText/buildPanels, PipList.render) may set .width on fresh fields - word-wrap + right-aligned column
  boxes structurally require it, and only refresh-path re-mutation of pooled fields crashes. Negative-tested
  (inject .width into layoutHeader -> FAIL; restore -> PASS). Wired via verify_pages (already invokes it).
- SWEEP: full-tree grep of `.width =` on TextFields -> layoutHeader was the ONLY refresh/handler-path site;
  every other is one-time creation on a fresh field. No other conversions needed.
- BUILD: rebuilt Pipboy_InvPage.swf only (mxmlc, 26988 b). Packaged 0.0.19 by extracting the 0.0.18 payload
  and swapping in ONLY the new InvPage (renamed PipOS_->Pipboy_) so everything else is guaranteed identical.
  SHA-256 verified: DLL/INI/PipOS_Chrome/PipboyMenu/PipboyBackgroundMenu/DATA/RADIO/STATS/MAP all MATCH
  0.0.18; only Pipboy_InvPage.swf DIFFERS. verify_pages + ctor_text_check ALL PASS. dist\PipOSPipboy-TestA-
  0.0.19.zip (v0.0.19, fomod info.xml).
- QUEUED (coordinator, not this build): 0.0.20 = DLL native equipment-per-slot push (P3(b); per-row cols
  stay blocked - no stable AS row key, reviewer confirming). Then 0.0.21 = chrome page-tabs to a LEFT
  vertical column (mockup fidelity, chrome-only, TryToSetPage + CurrentPage highlight). Then 16:9 feasibility
  spike (diagnosis-first: uPipboyTargetWidth/Height INI 1752x1400 vs 876x700 movie, Baka root-scale ~0.92
  x=35; author one 16:9 INV variant alongside the 876x700, never deploy the user's INI).

## Round 25b (0.0.20) — DLL native equipment-per-slot push (P3(b))
- Equipment panel is a FIXED set of biped slots (not list rows) -> no stable row-key needed, so P3(b) is
  unblocked even though per-row WT/VAL/AMMO stays blocked. DLL reads worn armor natively and pushes a 10-row
  name array to the page; the page fills the pooled per-slot fields.
- NATIVE READ (crash-safety = #1 risk; runs on the UI-task thread, same proven path as the chrome attach):
  PlayerCharacter::GetSingleton() [null-guard] -> ->inventoryList (BGSInventoryList*, @0xF8) [null-guard] ->
  ForEachStack(filter=armor, cont): per equipped Stack (Stack::IsEquipped()==flags.any(kSlotMask)) ->
  item.object->As<TESObjectARMO>() [null-guard, skip non-armor] -> armo->bipedModelData.bipedObjectSlots
  (uint32 mask) [==0 skip] -> item.GetDisplayFullName(stack.extra.get()) [null/empty -> armo->GetFullName()
  -> null/empty skip]. Name copied into std::string immediately (engine buffer may be reused). ENTIRE native
  section in try/catch; any failure degrades to gathered/blank, never CTD. (No explicit rwLock: menu-open is
  quiescent on the main thread; try/catch backstops a concurrent realloc.)
- BIPED-SLOT -> PANEL-ROW MAP (bit i of bipedObjectSlots == RE::BIPED_OBJECT index i == CK slot 30+i). Row
  order MUST equal InvPage SLOTS[]. First equipped armor whose mask hits a row's bit fills it (no overwrite);
  a multi-slot item may fill several rows (correct paper-doll):
    0 HEAD        = bit0 HairTop(30) | bit16 Headband(46)     [headgear/masks/helmets]
    1 TORSO       = bit11 [A]Torso(41)                        [over-armor chest]
    2 L.ARM       = bit12 [A]LeftArm(42)
    3 R.ARM       = bit13 [A]RightArm(43)
    4 L.LEG       = bit14 [A]LeftLeg(44)
    5 R.LEG       = bit15 [A]RightLeg(45)
    6 UNDER ARMOR = bit6  [U]Torso(36)                        [undergarment torso]
    7 OUTFIT      = bit3  Body(33)                            [full-body outfit]
    8 BACKPACK    = bits24-28 Unnamed1..5(54-58)              [common modded pack slots]
    9 PIP-BOY     = bit30 Pipboy(60)
- MARSHALLING: movieRoot->CreateArray + CreateString + Value::PushBack (S2 pattern); root.SetMember
  ("PipOS_equip", arr) on root1. Readiness-guarded (root1 IsObject), idempotent (overwrites each open),
  OG-gated (plugin-wide), graceful try/catch on both read and marshal. Pushed from the menu-open AddUITask
  right after AttachChromeNow(view): AttachChromeNow(view); PushEquipmentNow(view);
- AS RECEIVER (InvPage): pooled _equipVal[] (the 10 per-slot value TextFields, created in buildText, now
  pushed into the array). New applyEquip() reads stage.getChildAt(0).PipOS_equip (==root1, the chrome idiom),
  guards stage/child/member/element null, and Theme.setText's each field (UPDATE-TEXT-ONLY; NO field creation,
  NO .width). Called at buildText end (open-race: picks up an already-present push) AND on every
  onPipboyChangeEvent (refresh). applyEquip added to ctor_text_check GATE -> field-free + width-free PASS.
- BUILD: DLL rebuilt via xmake (releasedbg, clean, 565248 b, sha 9e6b4859). InvPage rebuilt (mxmlc, 27172 b).
  Packaged 0.0.20 off the 0.0.19 payload swapping ONLY the DLL + Pipboy_InvPage.swf. SHA-256 verified vs
  0.0.19: DLL + Pipboy_InvPage DIFFER; INI/PipOS_Chrome/PipboyMenu/PipboyBackgroundMenu/DATA/RADIO/STATS/MAP
  all MATCH. verify_pages + ctor_text_check ALL PASS. dist\PipOSPipboy-TestA-0.0.20.zip (v0.0.20).
- FOR REVIEWER (hard native-RE audit): every deref null-guarded (PC, inventoryList, object, armo, name);
  non-armor + zero-mask + empty-name skipped; try/catch on read + marshal; main-thread via AddUITask; no new
  RE call left unguarded. Slot map is stylized (documented) - HEAD may catch helmet-only, and unusual modded
  slot usages may land on "-"; acceptable per brief (any null/unmapped -> "-").
- DESIGN.md: recorded the authoritative 2026-08-17 mockup reference (STAT+INV) superseding round-6 captures.
- QUEUED next (unchanged): 0.0.21 Item A left-column chrome (now precisely spec'd in DESIGN.md); then 16:9 spike.

## Round 26 (0.0.21) — Item A: vertical left-column chrome (chrome-only)
- Rewrote pipos/Chrome.as from a horizontal top tab bar to a VERTICAL LEFT COLUMN in the reserved sidebar
  gutter (x<196; Theme's own header comment already reserved it, pages start content at CX=206 -> zero
  overlap with equipment/list panels). The old top bar was the deviation; this matches BOTH the mockup and
  Theme's original reservation.
- LAYOUT (all pooled fields created ONCE in buildText, on-stage; NO .width set on any text field; right/center
  placement done by READING .width which is safe):
  * top strip: PIP-BOY OS V2.7.1 (L) / SSS NFO... CONNECTION: STABLE (C) / PROPERTY OF VAULT-TEC (R) - flavor.
  * 5 page tabs STAT/INV/DATA/MAP/RADIO, box BW=182 TABH=30 pitch 48 from y=46; icon(vector glyph)+label;
    dim flavor code under tabs 0..3 (INV 04.JK.E / DB 1A.F7.G / GPS 77.7F.E / SIG S.T60.B).
  * EXTENSIONS - PIPBOYTABS group + CHALLENGES/AFFINITY/MAGAZINES [EXT] tabs (static first pass).
  * clock block moved to bottom-left (date/time/PIP-OS(R) V2.7.1) - frees top-right for the page's WEIGHT/CAPS.
- ACTIVE HIGHLIGHT: paintTabs(cp) redraws boxes/icons/accents + sets label colors; active page = filled box
  (SEL .16) + SEL outline + bright left accent bar, others faint outline. Called once at build + from onTick
  ONLY when menu.DataObj.CurrentPage changes. GRAPHICS + textColor only -> field-free + width-free.
- CLICK: onTabHit parses "pt<i>"/"ex<j>" -> TryToSetPage(i) / TryToSetPage(5+j) (proven path, try/caught).
  Root stays mouseEnabled=false, mouseChildren=true; only the per-tab hit rects (alpha .004) consume mouse,
  so page clicks still pass through.
- Per-page vector icons (drawIcon, font-independent line-art): STAT pulse, INV lock, DATA document, MAP pin,
  RADIO antenna; EXT rows use a diamond marker.
- GATE: added paintTabs to the Chrome ctor_text_check GATE. onTick/onTabHit/acquireMenu/paintTabs all PASS
  field-free + width-free.
- CRAMPING NOTE (evidence for the 16:9 spike): the column FITS the x<196 gutter and there is spare VERTICAL
  room (tabs+ext end ~y402, clock at ~628 -> a gap). The pressure is HORIZONTAL - "CHALLENGES" (~90px at
  size 12) nearly fills the 182px box, and the whole 876-wide 5:4 frame squeezes the sidebar AND the page
  content band (652px) vs the natively-16:9 mockup. Nothing overlaps; it's tight, not broken.
- DEAD-BUTTON CAVEAT (vs the "every element has purpose" rule): the [EXT] tabs are inert unless the matching
  PipboyTabs addon pages exist (TryToSetPage on a missing page = safe no-op). Documented; recommend a later
  pass that reads the real addon list and hides missing ones. Flavor codes/top strip are documented flavor.
- BUILD: mxmlc chrome only (20758 b). Packaged 0.0.21 off the 0.0.20 payload swapping ONLY PipOS_Chrome.swf.
  SHA-256 vs 0.0.20: PipOS_Chrome DIFFERS; DLL/INI/PipboyMenu/PipboyBackgroundMenu/all 5 Pipboy_* pages MATCH.
  ctor_text_check + verify_pages(chrome unaffected) PASS. dist\PipOSPipboy-TestA-0.0.21.zip (v0.0.21).
- NEXT: 16:9 feasibility spike (diagnosis-first per DESIGN.md: uPipboyTargetWidth/Height 1752x1400 vs 876x700
  movie, Baka root-scale ~0.92 x=35; author one 16:9 layout variant alongside 876x700; never deploy the INI).

## Round 27 (WSSPIKE-0.0.22) — 16:9 feasibility spike (diagnosis-first, opt-in, throwaway)
- GOAL: determine what governs the Pip-Boy render aspect and whether a natively-16:9 PIP-OS is achievable,
  BEFORE committing to a full re-author. Additive/opt-in; default behavior byte-unchanged from 0.0.21.
- MECHANISM MAP (from CommonLibF4 GFx + the memory 'coordinate space truth'):
  * Movie STAGE = 876x700, baked into the byte-identical vanilla PipboyMenu.swf; our pages load as ROOT
    children -> bound to that coordinate space. We cannot change the stage without editing the shell (condemned).
  * uPipboyTarget{Width,Height}=1752x1400 (Fallout4Prefs.ini) = the render-target/viewport pixels, exactly
    2x 876x700 and SAME 1.251 aspect. It sets RTT RESOLUTION, not the movie's logical coordinate space.
  * Scaleform ScaleModeType (kNoScale/kShowAll/kExactFit/kNoBorder) governs how the 876x700 stage maps to
    the viewport: ShowAll => pillarbox on a wider viewport (no new usable width); ExactFit => horizontal
    stretch/distortion; NoScale/NoBorder => can REVEAL a wider visibleFrameRect (usable authoring space).
  * Baka fullscreen: ships NO menu/page SWFs, only 16:9/16:10/21:9 BACKGROUND variants (1920x1080) + a DLL
    that transforms root1 (~0.92 scale, x=35) to fit the 876x700 content into its 16:9 frame. So today it's
    a TWO-LAYER split: 16:9 background art + 5:4 interactive content centered inside = the 'cramped' gap.
- THE DECISIVE MEASUREMENT (our DLL already holds the Movie*): GetViewport (buffer=RTT dims, view rect,
  gfxScale, aspectRatio), GetViewScaleMode, GetVisibleFrameRect (x1,y1,x2,y2 = the true usable coord space),
  + root1 x/y/scaleX/scaleY (Baka's transform). If visibleFrameRect stays ~0..876 wide => letterboxed, 16:9
  needs DLL/Baka cooperation; if it can widen toward ~1244 => native 16:9 authoring is possible.
- IMPLEMENTED: DiagnoseViewport(view, level) gated by [Widescreen] WidescreenSpike (Settings; default 0 =
  never called). level1 = read-only log (safe); level2 = reversible probe: SetViewScaleMode(kNoBorder) +
  SetViewAlignment(kCenter) + re-log visibleFrameRect (tests whether a wider frame appears; Baka may re-assert).
  All reads try/guarded. Called in the menu-open AddUITask after PushEquipmentNow, only if flag>0.
- KEY HYPOTHESIS to confirm in the log: with a 16:9 Baka background the game viewport is likely ALREADY 16:9
  (>=1752 wide) but the movie is ShowAll-pillarboxed to 5:4. If so, the wide viewport EXISTS -> our DLL can
  switch the scale mode (kNoBorder) so pages author into the wider frame, NO Fallout4Prefs change required.
  That would make 16:9 highly feasible with a DLL-set scale mode + a Theme coordinate-constant re-author.
- BUILD/PACKAGE: xmake DLL rebuilt clean (viewport API resolved). Spike = 0.0.21 payload + new DLL + INI
  ([Widescreen] section, default 0) + spike README (run steps + the OPTIONAL user-applied Fallout4Prefs
  uPipboyTarget 16:9 lever - NEVER deployed by us). SHA vs 0.0.21: DLL + INI DIFFER; all 8 SWFs MATCH.
  dist\PipOSPipboy-WSSPIKE-0.0.22.zip. Shipping 0.0.21 untouched.
- NEXT: user runs WidescreenSpike=1 (and optionally 2, and optionally the uPipboyTarget 16:9 edit) and sends
  PipOSPipboy.log; the visibleFrameRect + scaleMode numbers decide go/no-go on a full 16:9 migration.
- 16:9 SPIKE RESULT (from coordinator, informational): ShowAll already exposes visibleFrameRect
  (-184.2,0)..(1060.2,700) = 1244x700 usable movie-units; NoBorder made it WORSE (876x493, cropped). So
  widescreen = re-author pages to the ~1244 frame, NO scale-mode/INI change. SEPARATE future round; 0.0.23
  keeps the stage 876x700 and touches NO coord constant for widescreen.

## Round 28 (0.0.23, 2026-08-17) — field response to the 0.0.21 in-game test + a NEW P0 crash
Built off the 0.0.21 payload (TestA method: swap ONLY changed files into the prior payload; PipboyMenu shell
byte-identical vanilla, Pipboy_StatsPage + Pipboy_MapPage stay STOCK vanilla, PipboyBackgroundMenu untouched).
Changed & re-shipped: Pipboy_InvPage.swf, Pipboy_DataPage.swf, Pipboy_RadioPage.swf, PipOS_Chrome.swf, the DLL.
verify_pages + ctor_text_check ALL PASS; xmake DLL clean. dist\PipOSPipboy-TestA-0.0.23.zip (v0.0.23).
(package.ps1 was NOT used - it rebuilds the condemned ffdec-patched shell + PipOS_ page names; the DLL route
requires the vanilla shell + Pipboy_ page names, so the payload-swap line is the only correct packaging path.)

- **P0 (NEW hard CTD) — VERIFIED-STATIC.** crash-2026-08-17: DocView::FindFont(NULL) <- ParagraphFormatter::
  Format <- DocView::Format <- DocView::GetViewRect <- **TextField::SetWidth (frame[4])** <- OnKeyDown, while
  arrowing the WEAPONS (columns) list. Root cause: PipList.render() multi-column path set `cf.width = cw` on
  each freshly-created cell, and render() runs on EVERY selection change (key nav). Overturns the old "width
  on a fresh field is safe" carve-out for the RENDER path. FIX: columns are now SetWidth-free - auto-sized
  cells (Theme.tf autoSize follows text), positioned by .x (right-align = cx+cw-cf.width via a width READ),
  clipped with scrollRect (NOT SetWidth). NO `.width =` remains anywhere in PipList.render or any per-row/
  selection/tick/hover path. Mechanized: ctor_text_check now has a WIDTH-ONLY gate over PipList.render/
  onMarqTick/onRowOver/onRowOut/drawHover/selectIndex/onWheel (render legitimately creates row fields, so it
  gates WIDTH ONLY, not creation). Single-column radio/quest lists never hit this (no columns => no SetWidth).
- **P1-A subtab clicks — VERIFIED-STATIC (routing), BUILT-UNVERIFIED (in-game).** InvPage+DataPage onSubtabClick
  now acquire the shell (stage.getChildAt(0)["Menu_mc"], cached) and call `menu.TryToSetTab(i)` (the guarded
  path keyboard/engine uses), falling back to the direct onNewTab only if the menu ref is null. Kept sfx +
  PlaySmallTransition.
- **P1-B equipment overflow — VERIFIED-STATIC.** Per-slot value fields clip to eqW (=138-2*PAD) via scrollRect
  (SetWidth-free; applyEquip only re-sets .text). Long equipped names stop at the panel edge, no bleed into
  the Vault Boy panel.
- **P1-C marquee + hover — VERIFIED-STATIC (mechanism), BUILT-UNVERIFIED (in-game).** The NAME cell is now an
  auto-sized field (renders its FULL text) clipped by an external scrollRect; the marquee slides scrollRect.x
  so the clipped glyphs actually reveal (the old fixed-width field clipped its own glyphs -> sliding showed
  blank). Added HOVER targeting: onRowOver makes an overflowing hovered NAME the marquee target; onRowOut
  reverts to the selected row and resets scroll; render() clears stale refs. No .width, no field creation,
  time-based via Ticker.
- **P1-D WT/VAL/AMMO columns — BUILT (call wired), UNVERIFIED in-game.** (Audit caught the first pass: the
  function was defined but NEVER called, so the map was never set. FIXED: the MenuSink UI task now calls
  PushItemInfoNow(view) right after PushEquipmentNow(view); DLL rebuilt + re-swapped into the 0.0.23 zip.)
  DLL PushItemInfoNow builds
  root1.PipOS_iteminfo[<displayName>]={w,v,a} for every inventory object (weight/value via the engine generic
  accessors TESWeightForm::GetFormWeight / TESValueForm::GetFormValue with null instance data == base per-unit;
  ammo = weapon's ammo full name, weapons only). Pushed on menu-open on the UI task (same affinity as the
  equip push), null-guarded, try/caught. InvPage.itemAdapter looks up the bare row name (String(e.text)) and
  fills cols [nm,a,w,v] (weapons) / [nm,w,v] (else); miss => blank, never throws. Risk: name is the join key
  (non-unique/renamed items may miss); the item CARD remains the exact per-selection source.
- **P2-A top-band clearance — VERIFIED-STATIC.** Theme TITLE_Y 16->28, SUB_Y 44->58, BY 78->94 (BB 634 kept,
  still 12px above KEYBAR_Y=646). Radio SCOPE_Y 78->94 to match. Chrome top strip y 6->16 (+right end pulled
  in 8px), sidebar BX 10->16 / BW 182->176 / TAB_Y0 46->62 to clear the top-left/right border brackets. STAT/
  MAP are stock vanilla so they keep vanilla positions (pre-existing, not introduced here).
- **P2-B debug status line — VERIFIED-STATIC.** New Debug.SHOW_STATUS_LINE=false gates ONLY the persistent
  yellow status line (not created when off); ENABLED stays TRUE so the backtick(192) data dump still works.
- **P2-C favorite star — VERIFIED-STATIC, behavior matches vanilla exactly.** Ground truth = vanilla
  InvListEntry.SetEntryText: `FavIcon.visible = param1.favorite > 0`, `LegendaryIcon.visible = isLegendary`.
  Our star rule was already favorite>0 (correct); aligned it to the literal vanilla test `e.favorite > 0` and
  ADDED legendary = e.isLegendary (vanilla-faithful). Conclusion: stars on favorited weapons are CORRECT
  (vanilla shows the same); no false-positive bug in our code.
- **P2-D radio stray artifacts — VERIFIED-STATIC.** radioAdapter set legendary:(active) -> Theme.sparkle drew
  a stray amber triangle by the ON-AIR row; the "ON AIR" right-text already conveys active, so dropped the
  sparkle (legendary:false). The P1-C marquee rewrite also retired the old scrollRect.x-on-fixed-width path
  that could leave a clip-window artifact on the selected weapon row.
- **P2-E DATA STATS blank — BUILT-UNVERIFIED (assertion + fallback; still needs the user's backtick dump).**
  Decompile READ (vanilla StatsTab): GeneralStatsList feeds a CATEGORY list, and each category's .statArray
  feeds a VALUE list (Stats_ValuesListEntry: base text=entry.text, Value_tf=entry.value). That is the strong
  hypothesis for why our single flat list showed no text, but it is NOT confirmed against live data yet -
  the decisive proof is the backtick(192) dump of GeneralStatsList[0] on the DATA page. FIX (buildStatsDisplay)
  is written to be robust to EITHER shape: per category push a header (separator, label=cat.text||cat.name)
  then its statArray rows (label=st.text, right=st.value); if a category has no statArray, render it as one
  label/value row. So even if the shape differs, the flat fallback still shows text. workshopAdapter left
  as-is (WorkshopsList entries carry .text, vanilla-correct; not the same issue).
- **P2-F objective wrap — VERIFIED-STATIC.** _objRows created once with multiline+wordWrap and 44px headroom;
  renderDetail spaces rows by measured textHeight (read-only), summary follows. No .width on the refresh path.
- **P2-G map covers tab column — NOT DONE (documented).** Not actioned: MAP ships STOCK vanilla
  (Pipboy_MapPage.swf), so our PipOS_MapPage.as is not in the build and editing it changes nothing in game.
  The real issue is a Z-ORDER/layer problem: the engine's native map (RegisterMap on the stock vanilla page)
  renders across the whole movie and paints over the DLL-loaded PipOS_Chrome sidebar (a root child). Fixing it
  needs the engine map constrained to a sub-rect or the chrome forced above the engine map layer - neither is
  solvable from our shipped surface this round without a custom map page (which is the very thing that CTD'd in
  round 11). Left for a dedicated MAP round; do not fake.

## ROUND 30 (0.0.24-WIDE) — 16:9 FULL RE-AUTHOR to the M1 mockup

The widescreen frame is confirmed free (spike: ShowAll already exposes a ~1352x761 root1-local budget,
16:9). This round re-lays Chrome + Inv/Data/Radio pages to the mockup (`Previews/pipos-mockup.template.html`,
1600x900 canvas), adds the dropped CRT polish, and logs the actual authoring transform. STAT + MAP stay
STOCK vanilla (unchanged from 0.0.23) and are NOT rebuilt. Fallback build `dist/PipOSPipboy-TestA-0.0.23.zip`
(876x700) is preserved untouched.

- **Coordinate system — single-knob origin fix (`pipos/Theme.as`).** The mockup canvas (1600x900) maps to
  root1-local by one uniform scale + origin: `MS=0.8`, `FX=-200`, `FY=24`, with helpers `mx(v)=FX+v*MS`,
  `my(v)=FY+v*MS`, `ms(v)=v*MS`. Canvas(0,0)->(-200,24), canvas(1600,900)->(1080,744) — comfortably INSET
  inside the measured budget X[-238,1114] Y[0,761] on every side (no edge-clipping risk). Derived layout
  constants: `CX=-8`, `CR=1052.8`, `CW=1060.8` (mockup main left240/right1566); `SUB_Y=72` (sub-tab strip =
  top of main), `BY=113.6` (grid top), `BB=667.2` (grid bottom). Every page + the chrome derive all geometry
  from `mx/my/ms`, so an origin-shifted first screenshot is a ONE-NUMBER fix (see report).

- **DLL transform-chain log (`dll/src/PipboyBridge.cpp`, `LogTransformChain`).** UNCONDITIONAL, INFO level
  (NOT behind WidescreenSpike), fired once per Pip-Boy open in the MenuSink UI task BEFORE the chrome attach:
  logs `root1` x/y/scaleX/scaleY AND `root1.Menu_mc` x/y/scaleX/scaleY (present-guarded) + visibleFrameRect.
  Confirms the pages' real authoring transform so the first screenshot + `[PipOS][XFORM]` line pin any origin
  correction to FX/FY/MS. WidescreenSpike (`DiagnoseViewport`) left intact; scale mode UNCHANGED (ShowAll).
  Dead-code trap avoided: the call site was wired (DLL grew 578,560 -> 581,120 B; `XFORM` string present).

- **Chrome (`pipos/Chrome.as`, full rewrite of geometry + polish).** CRT bezel (rounded frame inset per
  mockup #frame 16/26/16/16 r10 + 16px corner L-brackets) in a `_bg` layer below the tabs. Thin top strip
  (boxed OS id | center NFO | right property tag). Vertical left tab column laid to mockup sidebar (top60
  left34 W176): 54px tabs (icon + label, active = SEL-fill + PHOS border + 3px accent bar), flavor codes
  between tabs, EXTENSIONS/[EXT] group, clock card pinned bottom-left. All positions via `mx/my/ms` arrays.
  Proven acquire/TryToSetPage routing/onTick data poll UNCHANGED. **CRT polish (was dropped at 876, now
  unblocked via the chrome layer):** a topmost mouse-transparent `_crt` overlay (mouseEnabled=false +
  mouseChildren=false) with (a) central phosphor glow (radial, low alpha = fail-safe), (b) edge vignette as 4
  LINEAR gradient bands (linear renders reliably in GFx — a mis-honoured radial can't flat-darken the screen),
  (c) rolling scanlines: 1px-on/2px-off phosphor hairlines drawn ONCE, animated by `.y` (roll) + `.alpha`
  (ease-in 0->0.55 over ~3s) time-based via Ticker. No text in the overlay; ctor_text_check onTick gate stays
  green (no field creation, no `.width`).

- **INV (`PipOS_InvPage.as`).** Three-column mockup grid 296|1fr(528)|470 gap16 via `EQX/EQW/CCX/CCW/LX/LW`
  (all `Theme.mx/ms`). EQUIPMENT panel (10 biped slots, name clipped by scrollRect — DLL `PipOS_equip` feed
  unchanged). CENTER = Vault Boy placeholder (fitHeight 400, centered) + caption + a single centered row of 7
  QUICK-ACCESS slots. LIST panel (NAME/AMMO/WT/VAL, header widths WT40/VAL44/AMMO64 fixed once at creation,
  layoutHeader repositions by `.x` only) + item CARD below. WEIGHT/CAPS readouts moved into the sub-tab strip
  right side (mockup `.chips`), page title HIDDEN (sidebar shows the page). Data plumbing + PipList untouched.

- **DATA (`PipOS_DataPage.as`).** Two-panel mockup grid 1fr(880)|430 gap16 (quest/list left, detail right)
  via `Theme.ms/mx`; detail inner width -> `ms(430)-2P`. Title hidden. Quest/objective/stats plumbing intact.

- **RADIO (`PipOS_RadioPage.as`).** Mockup grid 1fr(750) stations | 560 scope gap16: `SCOPE_X=mx(1006)`,
  `SCOPE_W=ms(560)`, `SCOPE_H=ms(415)` oscilloscope + freq/DJ/signal info panel below. Title hidden. Tune
  plumbing (frequency-arg) + time-based scope UNCHANGED.

- **FindFont-rule compliance.** Re-laying columns is the highest-risk area. Every `.width =` set is at CREATION
  on a fresh empty field in buildText/buildPanels (equip clip fields, card desc, list header cells, quick names,
  clock fields) — NONE on any render/selection/tick/hover/marquee path. ctor_text_check (incl. the PipList and
  Chrome width gates) + verify_pages: ALL PASS. PipList render stays width-free (unchanged).

- **What stayed stock vanilla.** STAT (`Pipboy_StatsPage.swf`) + MAP (`Pipboy_MapPage.swf`) carried
  byte-identical from 0.0.23, as are `PipboyMenu.swf` (byte-identical vanilla shell) and
  `PipboyBackgroundMenu.swf`. In the wide frame these two pages render at their vanilla 876x700-era positions
  (left-anchored, not filling the 16:9 width) — acceptable this round; a custom STAT page + the MAP Z-order
  round are future work.

- **Package.** TestA payload-swap off 0.0.23: swapped the 3 re-authored pages (shipped under vanilla
  `Pipboy_{Inv,Data,Radio}Page.swf` names), `PipOS_Chrome.swf`, and the new DLL; kept shell/StatsPage/MapPage/
  Background byte-identical. `dist/PipOSPipboy-TestA-0.0.24.zip` (fomod Version 0.0.24). ctor_text_check +
  verify_pages + xmake ALL PASS. NOT overwritten: 0.0.23 or any prior zip.

## ROUND 31 (0.0.25) — field-test fixes on the WORKING 16:9 layout (0.0.24)

0.0.24 field test confirmed the 16:9 mockup match is WORKING and placement is CORRECT (Menu_mc=identity;
FX=-200/FY=24/MS=0.8 UNCHANGED this round — bug-fix only, no re-layout). DLL is UNCHANGED (byte-identical
0.0.24 LogTransformChain build; P0-B fix is AS-side, so no rebuild). Fixed pages: Inv/Data/Radio + Chrome.

- **P0-A CRASH (SetY -> FindFont on page-switch) — FIXED, VERIFIED-STATIC.** crash-2026-08-17-04-38-01
  frame[4]=`TextField::SetY` via LoaderInfo::ExecuteCompleteEvent -> addChild -> ADDED_TO_STAGE handler.
  ROOT CAUSE (single offender): `PipOS_InvPage.buildText` set the LIST-header cells' `.width/.height` + text,
  THEN called `layoutHeader()`, which set `.x` AND `.y` on those already-texted embedded-font fields during
  the fragile page loader-complete context -> SetY -> DocView::Format -> FindFont(NULL). No other page
  buildText had geometry-after-text (audited all three + their helpers per-variable). FIX: header cells now
  set ALL geometry (width/height/x/y) on the fresh empty field BEFORE setText (default non-weapons layout
  inline), `layoutHeader()` is NO LONGER called from buildText, and `layoutHeader` repositions columns by
  `.x` ONLY (removed every `.y = hy`; `.y` is constant, set once at creation) on the resolved-font refresh
  path. `ctor_text_check` EXTENDED with two gates (both negative-tested for teeth + no false-positives):
  (1) per-variable geometry-after-text over PAGE build methods (buildText/buildSubtabs) — FAILs if any
  `.x/.y/.width/.height` set on a field appears after that same field's `.text`/`setText`; (2) reposition-only
  gate over layoutHeader/applyEquip — FAILs on any `.y/.height/.width` set (must slide by `.x` only).
  Chrome.buildText is intentionally out of scope (attaches on a UI task with the font resolved, not the
  page ProcessLoadQueue path; its top-strip labels legitimately read width to center/right-align).
- **P0-B PAGE MOUSE DEAD — DIAGNOSTIC LANDED (ENABLED) + BEST-EFFORT STRUCTURAL FIX (unverified in game).**
  Investigation (static, from the shell decompile): pages are `addChild`'d directly onto `Menu_mc`
  (PipboyMenu.onPageLoadComplete) as its TOP child; IMenu/PipboySubMenu/BSUIComponent set NO mouseChildren=
  false; Debug overlay is mouseEnabled=false. So structurally mouse SHOULD fall through to the page. The one
  thing prior static analysis never checked: the DLL wraps the chrome in a `flash.display.Loader` added to
  root1 ABOVE Menu_mc, and that Loader defaults to mouseEnabled=true with frame-spanning bounds (our CRT
  overlay) — a strong hypothesis that GFx returns the Loader as the hit target for every point NOT over a
  chrome tab, blocking fall-through to the page (matches the exact symptom: chrome tabs work, everything
  behind chrome is dead). FIX (AS-side, `Chrome.onAdded`): set the parent Loader `mouseEnabled=false` +
  `mouseChildren=true` — mirrors the chrome sprite's OWN proven pattern one level up (the evidence it's safe:
  the chrome sprite itself is mouseEnabled=false/mouseChildren=true and its tab children work). DIAGNOSTIC
  (`PipOS_InvPage`, LEFT ENABLED, `Debug.SHOW_STATUS_LINE=true` this build): capture-phase MOUSE_DOWN on
  stage (SMD) and on the page (PMD) log the hit-target name + coords; `logAncestors()` logs the page's
  parent-chain mouseEnabled/mouseChildren flags (E?/C?) to the status line. Next field test is decisive:
  SMD-only fires -> something above the page eats it (Loader fix insufficient / another cover); PMD fires ->
  mouse reaches the page (subtabs/rows should then work); an ancestor showing C0 names the mouse-disabled
  node. HONEST TAG: fix is a strong hypothesis, NOT verified in game; diagnostic guarantees the next test
  isolates the cause regardless.
- **P1-A CRT overlay — FIXED, preview-render confirmed.** `Chrome.buildCRT` rewritten: covers the FULL
  visible frame (root1-local X[-238,1114] Y[0,761], 1352x761) instead of the bezel inset; vignette dropped
  from 4x150px black bands @0.5 alpha to LOW alpha 0.20 over WIDE 230px bands with smooth linear falloff
  (gentle darkening reaching well inward, NO hard center hole); central radial glow lowered to 0.05; subtle
  0.06 scanlines span the whole frame as the primary texture (ease-in + roll unchanged). Chrome render
  (recompiled ChromeHost) confirms the subtle full-frame scanline + soft vignette, heavy border gone.
- **P1-B chrome tab HOVER — ADDED, code-verified (static; needs mouse to see live).** ROLL_OVER/ROLL_OUT on
  every page-tab + ext-tab hit sprite set `_hoverIdx` and repaint; a hovered-but-inactive tab gets a brighter
  border + label + faint fill (mockup .tabbtn:hover); active always wins in paintTabs so hover never fights
  it. Graphics + textColor ONLY (paintTabs gate stays green).
- **P1-C star->corner LINES — FIXED, preview-render VERIFIED.** Root cause was the favorite ★ / legendary ✦
  fills sharing `_rows.graphics` with the row backgrounds/brackets (a stray edge from each glyph back toward
  the list (0,0) corner). FIX (decisive/structural): markers now draw onto a DEDICATED `_markers:Sprite`
  layer (mouse-transparent, topmost, cleared each render) so they can NEVER share a pen path with the row
  graphics. Preview INV render (favorited 10MM PISTOL + legendary INSTIGATING/RIGHTEOUS rows) shows clean
  glyphs, zero stray lines.
- **P2 — layout tweaks, preview-confirmed.** VaultBoy x = CCW/2 (was CCW/2 - 95): VaultBoy composites its
  figure centered about its own local x=0, so the figure now sits on the character-column midline. WEIGHT->
  CAPS gap widened 20 -> 52 in the sub-tab chip strip (clear air between the WEIGHT value and CAPS icon).
- **Package.** TestA payload-swap off 0.0.24: swapped `Pipboy_{Inv,Data,Radio}Page.swf` + `PipOS_Chrome.swf`
  (the 4 rebuilt SWFs); DLL/ini/PipboyMenu(shell)/PipboyBackgroundMenu/Pipboy_StatsPage/Pipboy_MapPage
  carried BYTE-IDENTICAL from 0.0.24. `dist/PipOSPipboy-TestA-0.0.25.zip` (fomod Version 0.0.25, 545.6 KB).
  ctor_text_check (with the 2 new gates) + verify_pages + preview_pages ALL PASS. NOT overwritten: 0.0.23,
  0.0.24, or any prior zip. DEFERRED (user agrees): FallUI/Complex-Sorter category-tag name parsing.

## Round — 0.0.26 (DATA quest-click crash + world-dim veil; AS-only)
Two 0.0.25 field-test issues. DLL / shell / background / STAT / MAP byte-identical to 0.0.25; only the
PipList-bearing pages (`Pipboy_{Data,Inv,Radio}Page.swf`) + `PipOS_Chrome.swf` rebuilt.

- **P0 — DATA quest-click FindFont CRASH (renderDetail SetY-after-text). FIXED, static-verified + gated.**
  Root cause exactly as diagnosed: the 0.0.25 P2-F wrap change made `renderDetail` set each objective row's
  `.text` then its `.y` (`row.y = yy` + dynamic `textHeight` measurement) — geometry-after-text on the
  RENDER/SELECTION path (`onListSel/onObjectivesReady -> renderDetail -> TextField::SetY -> Format ->
  FindFont(NULL)`), which proves the reviewer's deferred SHOULD-FIX was a real crash, not a boundary.
  FIX: objective rows + the summary now have FIXED slot positions set ONCE at creation in `buildText`
  (`OBJ_SLOT=44`, row `oi.y = 40 + oi*44`; summary `.y = 40 + 7*44`), multiline+wordWrap set once; the
  render path is now UPDATE-ONLY (`.text/.visible/.textColor`), never touching `.y`. The `textHeight`
  dynamic-spacing was dropped (fixed generous spacing = the deliberate crash-safety trade). Same FindFont
  class hardened on the OTHER render paths flagged latent:
  - `PipList.render` — separator (`sep.y` before `sep.text`, `sep.x`-by-width-read kept after), columns
    (`cf.y` before `cf.text`), single-column right cell (`rt.y` before `rt.text`). Fresh cells each render,
    but reordered so the render-path gate is satisfied and no `.y`-after-text remains.
  - `PipOS_InvPage.renderCard` — the 6 pooled stat-pair fields had `lt.x/lt.y/vt.y` set per render (pooled
    text-bearing = same class). Positions are deterministic per index, so they're now set ONCE at creation;
    `_cardDesc.y` fixed at creation too. renderCard is update-only + the value's right-align `.x`-by-width-read.
  ENFORCEMENT: `ctor_text_check.py` extended with a RENDER_GEO_GATE covering `renderDetail/onListSel/
  onObjectivesReady` (Data), `renderCard/onListSel/onRowClick` (Inv), and `PipList.render` — FAILs on
  `.y/.width/.height` set after text on the same field (per-variable, textual), `.x` allowed (designated-safe
  right-align). Negative-tested (injected `row.y = 5;` after setText in renderDetail -> FAIL; reverted).
  All render-path methods PASS. NOTE (honest): the gate is textual/per-method — it cannot see the
  pooled-field-across-renders lifecycle, so the REAL guarantee is behavioral (fixed geometry at creation);
  the gate is a tripwire for the textual pattern, not a proof.
- **P1 — "HOLE IN THE MIDDLE" world-dim veil. AS-ONLY (approach (a)); IN-GAME-GATED for the visible effect.**
  `Chrome.attachVeil()` (called from `onAdded`, guarded + idempotent by named child `PipOS_veil`) creates a
  mouse-transparent dark `Sprite` (fill `0x000000 @0.42`, rect `-260,-20,1400x800` spanning the frame budget)
  and `root1.addChildAt(veil, 0)` — beneath `Menu_mc`/pages and the chrome Loader, above the world that shows
  through the movie. So the world + Baka bg art dim uniformly; our pages/chrome render on top, unaffected
  (the veil is strictly below `Menu_mc`, so it CANNOT darken our UI). No DLL change. Every step try/caught
  (blank-no-veil, never a CTD). HONEST TAG: the actual world-dim is in-game-gated (a preview has no live-world
  stand-in behind root1); what IS verified offline is that the chrome still builds/renders 0-errors with the
  veil code present, and that the layer is structurally below the pages. Cross-movie `root1.addChildAt` of a
  chrome-created Sprite is the residual in-game unknown (mirrors the S2-proven DLL `root1.addChild` of the
  Loader); on failure it logs `veilFAIL` and degrades to the old look — no crash. CRT scanlines/vignette
  unchanged (kept as-is).
- **KEPT (not regressed):** 16:9 origin (Theme FX=-200/FY=24/MS=0.8 untouched), Loader mouse fall-through
  fix, tab hover, columns/item-info, marquee, star=favorite, softened CRT, `SHOW_STATUS_LINE`/INV mouse
  diagnostic (LEFT ON per spec — confirm INV clicks next test, then revert).
- **Package.** TestA payload-swap off 0.0.25: swapped `Pipboy_{Data,Inv,Radio}Page.swf` + `PipOS_Chrome.swf`;
  DLL/ini/PipboyMenu(shell)/PipboyBackgroundMenu/Pipboy_StatsPage/Pipboy_MapPage carried BYTE-IDENTICAL from
  0.0.25 (verified equal bytes). `dist/PipOSPipboy-TestA-0.0.26.zip` (fomod Version 0.0.26, ~558.8 KB,
  testzip OK). ctor_text_check (with the new render-path gate, negative-tested) + verify_pages + preview_pages
  ALL PASS. NOT overwritten: 0.0.23 / 0.0.24 / 0.0.25 or any prior zip.

## Round — 0.0.27 (INV item card fix + diagnostic cleanup + chrome hardening; AS-only)
Built on the audited-clean 0.0.26. DLL / shell / background / STAT / MAP byte-identical to 0.0.26; changed
SWFs: `Pipboy_InvPage.swf` (P0+P1), `PipOS_Chrome.swf` (P2+P1), and `Pipboy_{Data,Radio}Page.swf` (P1
status-line-off only, via the shared Debug flag). 16:9 origin (Theme FX=-200/FY=24/MS=0.8) UNTOUCHED.

- **P0 — INV item-detail card was ALWAYS EMPTY (never worked in game). FIXED; render path preview-verified,
  engine data fill in-game-gated.** Root cause exactly as diagnosed: `renderCard()` was ONLY reachable from
  `onListSelectionChangeCallback()`, a VANILLA `BSScrollingList` hook — but selection is driven by our own
  `PipList`, which never fires it, so the card never rendered even though `onInvItemSelection` had already
  filled `_cardInfo`. FIX: `onListSel(i)` now calls `this.renderCard()` directly, AFTER the
  `onInvItemSelection(oi, _cardInfo, _paperInfo, this)` external call returns (the engine fills `_cardInfo`
  synchronously by reference before it returns), and BEFORE `updateItem3D`. `onListSelectionChangeCallback ->
  renderCard` is KEPT (harmless if the engine also calls it). renderCard is update-only (`setText` + the
  designated-safe `.x`-by-width-read for right-aligned values); it never sets `.y/.width` on a text-bearing
  field (the stat-pair slot geometry is fixed at creation in buildText, 0.0.26 hardening), so no FindFont
  vector was introduced. GEOMETRY VERIFIED CORRECT (no fix needed): `LX=mx(1096)`, `LW=ms(470)`, the `_card`
  sprite at `(LX+PAD, cardTop+PAD)` with `scrollRect(0,0, LW-2·PAD, (BB-cardTop)-2·PAD)`, and renderCard's
  `CWID = LW-2·PAD` all derive from the 16:9 `Theme.mx/ms` knob and are internally consistent — content lands
  inside the visible lower card box. PROOF: the preview harness (whose mock `onInvItemSelection` fills
  `_cardInfo` the same synchronous way the engine does) now renders a FULL card — title "10MM PISTOL", "DMG
  BALLISTIC", the six stat pairs (DAMAGE/FIRE RATE/RANGE/ACCURACY/WEIGHT/VALUE), and the description — inside
  the box. HONEST TAG: this validates the render path + geometry offline; the actual ENGINE fill of
  `_cardInfo` in game is still gated (agent can't invoke the real BGSCodeObj callback). DIAGNOSTIC added to
  the backtick (`) dump: `_cardInfo.length`, `_cardInfo[0]` (title), `_cardInfo[1]` (a later pair entry), so
  if the direct render still shows empty in game, one screenshot separates a data problem (engine didn't fill
  `_cardInfo`) from a render/geometry problem.
- **P1 — mouse diagnostic + yellow status line REMOVED (mouse confirmed working in game, 0.0.25 field test).**
  `Debug.SHOW_STATUS_LINE = false` (kills the persistent yellow line on every page); `Debug.ENABLED` stays
  TRUE so the backtick data dump (now incl. the card dump) still works. `PipOS_InvPage`: removed the
  capture-phase `onStageMouseDbg`/`onPageMouseDbg` loggers + `logAncestors` and their add/removeEventListener
  wiring in `onPageStage`/`onPageUnstage` (the KEY_DOWN listener + `ensureText` kept). The Chrome.onAdded
  Loader-transparency mouse fix was NOT touched.
- **P2 — Chrome `[EXT]` badge geometry-before-text hardening + gate extension, negative-tested.**
  `Chrome.buildText` set `badge.y` AFTER `Theme.setText(badge,"[EXT]")` — the exact FindFont
  geometry-after-text pattern (stable ~26 builds only because the chrome font resolves at attach). Normalized:
  `badge.y` (the fixed slot) is set on the fresh empty field BEFORE setText; `badge.x = BX+BW-8-badge.width`
  legitimately reads width and stays AFTER text (the designated-safe `.x`-by-width-read). `ctor_text_check.py`
  extended: a new section scans EVERY `Chrome.as` method (via `FUNC_RE`) for `.y/.width/.height`-after-text on
  the same field (`.x` exempt), skipping methods that set no text. NEGATIVE-TESTED: re-injected `badge.y`
  after setText -> `[FAIL] pipos/Chrome.as::buildText geometry-AFTER-text ['badge.y after text']`; reverted;
  now `[PASS] pipos/Chrome.as::buildText` and `::onTick`.
- **KEPT (not regressed):** 16:9 origin, working page mouse (Loader fall-through fix), hover, all 0.0.26 crash
  fixes, the world-dim veil, columns/item-info, marquee, star=favorite, softened CRT.
- **Package.** TestA payload-swap off 0.0.26: swapped `Pipboy_{Inv,Data,Radio}Page.swf` + `PipOS_Chrome.swf`;
  DLL/ini/PipboyMenu(shell)/PipboyBackgroundMenu/Pipboy_StatsPage/Pipboy_MapPage carried BYTE-IDENTICAL from
  0.0.26 (verified equal bytes: DLL 581120, shell 41723, BG 27928, Stats 52762, Map 93570 all SAME).
  `dist/PipOSPipboy-TestA-0.0.27.zip` (fomod Version 0.0.27, testzip OK). ctor_text_check (with the new
  Chrome gate, negative-tested) + verify_pages + preview_pages ALL PASS. DLL NOT rebuilt (no C++ change).
  NOT overwritten: 0.0.23 / 0.0.24 / 0.0.25 / 0.0.26 or any prior zip.

## Round — 0.0.28 (world-dim veil lightened; AS-only, one line)
Built on the audited-clean 0.0.27. SINGLE change: the world-dim veil was over-dimming. At `0.42` black
the game world behind the whole menu read near-black in game — the veil stacks on top of the scene's own
darkness AND the CRT vignette, so `0.42` (world at 58% brightness on paper) landed far darker in practice.
The M1 mockup shows the world clearly visible but dimmed (~0.6 brightness, blurred; we can only dim, not
blur).
- **Change.** `pipos/Chrome.as`: introduced `private static const VEIL_ALPHA:Number = 0.20;` and used it in
  `attachVeil`'s `g.beginFill(0x000000, VEIL_ALPHA)` (was the inline literal `0.42`). Self-documenting +
  one-line to re-tune. EVERYTHING else about the veil is byte-for-byte the same intent: still `0x000000`,
  still the full-frame rect `drawRect(-260,-20,1400,800)` (covers the budget X[-238,1114] Y[0,761]), still
  `mouseEnabled=false`+`mouseChildren=false`, still `root1.addChildAt(veil,0)` (below Menu_mc/pages, above
  the world), still try/caught + idempotent (named-child guard) + logs `veilOK`/`veilFAIL`. No Loader mouse
  fix, CRT, or page code touched. Graphics-only alpha change: no text, no geometry-after-text, no new
  FindFont surface.
- **TUNABLE — in-game-gated.** `0.20` is a first estimate to let the world read through like the mockup while
  still knocking down the bright-center "hole." Whether `0.20` is right or wants another nudge is the USER's
  call from ONE screenshot; changing it is now a single-constant edit. Do not over-claim the visual — a
  preview has no live-world stand-in behind root1, so this cannot be validated offline.
- **Verify.** ctor_text_check ALL PASS (incl. the Chrome gate — the veil change adds no text/geometry). Chrome
  built 0-errors with the veil present (`PipOS_Chrome.swf` 22353 B). verify_pages + preview_pages ALL PASS.
- **Package.** TestA payload-swap off 0.0.27: ONLY `PipOS_Chrome.swf` changed. Byte-diff vs the 0.0.27 zip
  confirmed: `PipOSPipboy.dll`, `PipOSPipboy.ini`, `PipboyMenu.swf` (shell), `PipboyBackgroundMenu.swf`, and
  ALL five `Pipboy_*Page.swf` (Inv/Stats/Data/Map/Radio) + `fomod/ModuleConfig.xml` are byte-identical SAME;
  only `PipOS_Chrome.swf`, `README-TestA.txt`, and `fomod/info.xml` (Version 0.0.28) differ.
  `dist/PipOSPipboy-TestA-0.0.28.zip` (fomod Version 0.0.28, ~545.4 KB). DLL NOT rebuilt (no C++ change).
  NOT overwritten: 0.0.23 / 0.0.24 / 0.0.25 / 0.0.26 / 0.0.27 or any prior zip.

## Round — 0.0.29 (real FindFont ROOT CAUSE: auto-size list cells + veil anti-stack)
Built on 0.0.28. Two items. AS-only (DLL unchanged, byte-identical to 0.0.28). Four SWFs changed:
`Pipboy_InvPage`, `Pipboy_DataPage`, `Pipboy_RadioPage` (all share the `pipos/PipList` fix) and `PipOS_Chrome`.

### P0 — Auto-size FindFont crash (the REAL root cause), verified from crash-2026-08-17-06-38-33
- **Root cause.** Crash frame: `DocView::FindFont(NULL) <- Format <- GetViewRect <- TextField::SetWidth`
  (frame 4), fired from a MOUSE/KEY event while a list re-renders. There is NO literal `.width =` on that
  path — the SetWidth is triggered INTERNALLY by AUTO-SIZE. `Theme.tf(size,color,bold,align)` sets
  `autoSize = RIGHT/CENTER/LEFT` (never none). `PipList.render` created its row cells with `Theme.tf`, so
  setting `.text` made Scaleform RESIZE the field -> internal `SetWidth` -> reflow -> `FindFont`. `render()`
  runs on EVERY selection/click, so DATA quest lists, RADIO stations, and DATA workshops/stats crashed
  intermittently (0.0.26/0.0.28 were byte-identical on this path and only got lucky). NOTE: the earlier claim
  that "the INV column path was already fixed to autoSize=none" was INCORRECT — the shipped columns path was
  still auto-sized (0.0.23 removed the explicit `.width=` but left the cells AUTO-SIZE, which reintroduced the
  crash by the newly-understood mechanism). BOTH the columns path AND the label/right/separator paths were
  auto-size; all were fixed this round.
- **Fix (`pipos/PipList.render`, every row path).** Each fresh cell is now `autoSize = "none"` with an EXPLICIT
  `width` set on the empty field BEFORE `.text` (geometry-before-text is safe; the auto-size resize DURING
  `.text` was the vector), then `Theme.setText` (no resize), then a `scrollRect` clip. Details:
  - **Columns.** `cf.autoSize="none"; cf.width = isName ? 4000 : cw; cf.height=20; cf.y=ty; cf.x=cx;`
    then `Theme.setText(cf,...)` then `cf.scrollRect=(0,0,cw,20)`. Right/centre columns align by the field's
    own FORMAT inside the fixed-width box (Theme.setText forces the format) — NO post-text `.width` read
    (the old `cf.x = cx+cw-cf.width` is gone). The NAME/flex cell keeps the marquee: a large fixed field
    width (4000) renders its FULL text and the EXTERNAL `scrollRect` viewport (== column width) reveals the
    clipped glyphs when the ticker slides `scrollRect.x` — marquee methods (onMarqTick/onRowOver/onRowOut)
    UNCHANGED.
  - **Label + right (single-column lists: DATA quests/workshops/stats, RADIO).** `lbl.autoSize="none";
    lbl.width = this._w - markX - rightReserve - 8;` before text + scrollRect clip. `rt.autoSize="none";
    rt.width = rightReserve(96); rt.x = this._w - 12 - rightReserve;` (constant box left) + right-align via
    format inside the box (no width read).
  - **Separator.** `sep.autoSize="none"; sep.width = min(this._w-40,240); sep.x=(this._w-sepW)/2;` (computed
    from known numbers, NOT a width read) + center-align; the GROUND background punches the divider-line gap.
  - **Net:** walked `render` — NO field on ANY row path is auto-size when its `.text` is set. Every field is
    `autoSize="none"` with width set before text. Confirmed in the SHIPPED bytecode (decompiled
    `Pipboy_DataPage` PipList.render): each cell emits `autoSize="none"` -> `.width=` -> `Theme.setText` ->
    `scrollRect`, in that order, on all four paths.
- **`renderDetail` (DataPage) confirmed safe.** Objective rows are POOLED fields created `autoSize="none"` +
  multiline + wordWrap in `buildText`; `renderDetail` only updates `.text/.visible/.textColor`. No auto-size
  field's text is set there. wordWrap reflows lines but does not resize the field / call SetWidth — left as-is.
- **Enforcement (ctor_text_check.py).** (a) Removed `render` from the width-only gate (render now LEGITIMATELY
  sets width-before-text; width-AFTER-text is still caught by the render geometry gate). (b) NEW auto-size gate:
  for render/selection methods, any field FRESHLY created via `Theme.tf/Theme.mk/new TextField` and then texted
  MUST set `.autoSize` (to "none") before the text; pooled fields (created in buildText) are scoped out.
  Negative-tested: dropping one `cf.autoSize="none"` line makes the gate FAIL
  (`render AUTO-SIZE text ['cf texted without prior autoSize=none']`); restored -> PASS.
- **Known same-class residual (documented, NOT this round).** `buildSubtabs` (Inv/Data) still creates fresh
  auto-size fields on the tab-change refresh path — it genuinely needs `t.width` to lay out variable-width tab
  labels + hit rects, and it fires on tab-change (rare) not per-selection; field-tested working. Kept in the
  ctor_text_check INFO note (not the hard gate). Pooled auto-size fields updated on selection (InvPage
  `renderCard` value fields, RadioPage `renderInfo`, Inv weight/caps) are a lower-risk variant (created once
  on-stage in buildText, not fresh-in-render) and were not the cited crash; left as-is.

### P1 — World-dim veil: anti-stack + 0.10 (`pipos/Chrome.as`)
- `0.20` still read near-black in game. Root cause of the over-dim = the veil STACKED across Pip-Boy re-opens:
  `root1` persists; each open reloaded the chrome and re-ran `attachVeil`, but the old guard only SKIPPED when
  a veil already existed — it never removed a stale one — so alpha piled up open-over-open.
- **Fix.** `attachVeil` now REMOVES any existing `PipOS_veil` (`root1.removeChild`) before adding, so exactly
  ONE veil is ever present. `VEIL_ALPHA` 0.20 -> **0.10**. Added a `REMOVED_FROM_STAGE` teardown (`removeVeil`,
  via a remembered `_veilRoot` since `stage` is null on removal) so a closed Pip-Boy leaves no orphan. Kept:
  `0x000000`, full-frame `drawRect(-260,-20,1400,800)`, `mouseEnabled=false`+`mouseChildren=false`,
  `addChildAt(veil,0)`, try/caught, logs (`veilOK`/`veilFAIL`/`veilGone`). Graphics-only; no text/geometry.
- **In-game-gated.** If 0.10 WITH anti-stack is still too dark, the darkness is NOT the veil (would point to
  Baka's own compositing) — anti-stack + 0.10 should fix it if stacking was the cause.

### Verify / package
- ctor_text_check ALL PASS (auto-size gate negative-tested). verify_pages ALL PASS (CWS/v17, extends
  PipboyPage, no embedded stubs). preview_pages ALL 5 render 0 AS errors; DATA + RADIO captures inspected —
  left labels, right-aligned TRACKED/DONE/ON AIR, centred COMPLETED separator all correct after the
  autoSize="none" conversion (alignment not broken).
- **Byte-diff (TestA payload-swap off 0.0.28):** CHANGED = `Pipboy_InvPage.swf` (28432->28513),
  `Pipboy_DataPage.swf` (24931->25014), `Pipboy_RadioPage.swf` (23186->23266), `PipOS_Chrome.swf`
  (22353->22561). SAME (byte-identical) = `PipOSPipboy.dll`, `PipOSPipboy.ini`, `PipboyMenu.swf` (shell),
  `PipboyBackgroundMenu.swf`, `Pipboy_StatsPage.swf`, `Pipboy_MapPage.swf`.
- `dist/PipOSPipboy-TestA-0.0.29.zip` (fomod Version 0.0.29, ~546.4 KB). DLL NOT rebuilt (no C++ change).
  NOT overwritten: 0.0.23 / 0.0.24 / 0.0.25 / 0.0.26 / 0.0.27 / 0.0.28 or any prior zip.

## ROUND 40 (0.0.30) — the REAL FindFont root cause: embedded-font glyph coverage + sanitize

This SUPERSEDES the width / auto-size / geometry-before-text theories of 0.0.19-0.0.29. Those were all
real reformat *triggers*, but never the *cause*. The cause, verified from `pipos/Fonts.as` + the crash logs,
is a single fact: the embedded Arimo was compiled with `unicodeRange="U+0020-U+007E"` (ASCII only) and
Scaleform GFx has NO device-font fallback. The moment ANY TextField formats a glyph outside that range --
curly quotes, em/en dash, bullet, ellipsis, accented Latin, (TM), or an exotic CJK/emoji from a weapon-mod /
quest / station name -- `FindFont` returns null and the game takes an access violation
(SetWidth/SetY -> GetViewRect -> Format -> FindFont(NULL)). The setter that re-triggered Format was
INCIDENTAL; the unfontable character was the crash. That is exactly why every width/auto-size/geometry fix
only moved the odds -- the trigger changed, the fuel (an unfontable char) did not.

- **Part A -- GUARANTEE (`pipos/Theme.as`).** New `Theme.sanitize(s)` + `Theme.inRange(c)`. `sanitize` does a
  char-code scan: in-range code points pass through unchanged; out-of-range are mapped to a readable in-range
  equivalent (`' ' `->`'`, `" "`->`"`, dashes/minus->`-`, bullet/mid-dot->`*`, ellipsis->`...`, (TM)/(C)/(R),
  Unicode spaces->space, zero-width/line/para->dropped) or, worst case, `?`. The output is 100% within the
  embedded range by construction -- no unfontable glyph can reach Format. `setText` now calls `sanitize`, and
  EVERY page/chrome text path routes through `setText` (or `sanitize` for Debug's `appendText`/status line).
  Audited via `grep '\.text ='`: the only remaining raw `.text =` are `Theme.setText` itself, a comment, and
  `Debug` (now wrapped in `sanitize`). Chrome + PipList already used `setText` exclusively.
- **Part B -- FIDELITY (`pipos/Fonts.as`).** `unicodeRange` widened to
  `U+0020-U+007E,U+00A0-U+00FF,U+2010-U+2022,U+2026-U+2026,U+2122-U+2122` (single code points expressed as
  one-char ranges). **mxmlc accepted the comma-separated multi-range syntax with no error.** Now Latin-1
  accents, the common typographic punctuation, ellipsis and (TM) render NATIVELY instead of being flattened.
  `inRange()` mirrors this range EXACTLY, so Part A adapts automatically if the range is ever re-tuned. Arimo
  carries all glyphs in this range, so in-range == embedded for this font.
- **Coverage proof.** A faithful port of `inRange`/`sanitize` was run over
  `' " -- ... * cafe (TM) <CJK><emoji>`, a Nuka-Cola(TM) "Quantum" 'special' 90-degree resume string, and the
  MapPage `GRID <mid-dot>` literal: every output character is inside the embedded range (typographics/accents
  kept native; CJL/emoji -> `?`). Before: those strings crashed on Format; after: guaranteed fontable.
- **0.0.29 handling KEPT** (defense in depth, not reverted): `autoSize="none"` + width-before-text +
  scrollRect list cells, geometry-before-text discipline. It is simply no longer load-bearing for
  crash-safety -- sanitize is. As a bonus, the StatsPage/MapPage source `.text =` sites were also routed
  through `setText` with geometry-before-text (future-proofing; those pages still ship STOCK vanilla this
  round, so the change does not enter the payload).

### Verify / package
- `build_pages` clean (mxmlc accepted the widened range). `verify_pages` ALL PASS (CWS/v17, extends
  PipboyPage, no embedded stubs). `ctor_text_check` ALL PASS. `preview_pages` ALL 5 render 0 AS errors.
- **SWF size delta** (widened glyph table, ~+11 KB each, expected): `Pipboy_InvPage` 28513->39618 (+11105),
  `Pipboy_DataPage` 25014->36091 (+11077), `Pipboy_RadioPage` 23266->34327 (+11061), `PipOS_Chrome`
  22561->33613 (+11052).
- **Byte-diff (TestA payload-swap off 0.0.29):** CHANGED = the four above + `README-TestA.txt`. SAME
  (byte-identical, SHA-256 verified) = `PipOSPipboy.dll`, `PipOSPipboy.ini`, `PipboyMenu.swf` (shell),
  `PipboyBackgroundMenu.swf`, and the STOCK vanilla `Pipboy_StatsPage.swf` / `Pipboy_MapPage.swf`.
- `dist/PipOSPipboy-TestA-0.0.30.zip` (fomod Version 0.0.30, ~589.8 KB). DLL NOT rebuilt (no C++ change).
  NOT overwritten: 0.0.23 - 0.0.29 or any prior zip.
- **In-game proof is the user's** -- clicking through items / quests / stations that previously CTD'd,
  especially names with special characters (unique/legendary weapon mods, quotes, accents, trademarks). This
  SHOULD end the FindFont crash class; sanitize makes an unfontable glyph structurally impossible to format.
