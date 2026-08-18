# PIP-OS Functionality Spec

Every visible element has a defined purpose. Tags: **[LIVE]** real data/action in the final SWF+DLL,
**[FLAVOR]** aesthetic by design (its purpose is texture/world-building — still deliberate),
**[MOCKUP✓]** already interactive in the M1 HTML mockup, **[V2]** documented follow-up, not v1.
Rule of engagement (user-set): nothing drawn may do nothing — a control acts, a readout reads,
flavor is declared flavor.

## M4 build status (2026-08-15) — all five pages BUILT + VERIFIED-STATIC
Every page ([SWF] items) is now implemented in the shipping `PipOS_*Page.swf` and passes
`tools/verify_pages.ps1` (CWS/v15 header, extends PipboyPage, vanilla BGSCodeObj surface). Realized:
- **INV**: sub-tab filter (onNewTab), weight chip (warn-amber/crit-red thresholds), caps, item list,
  item card from engine-filled InfoObj, quick-access slots, R Inspect (real ExamineItem), X Drop,
  C damage cycle, Q Fav (SetQuickkey), Z Sort (SortItemList), T Perk chart. Sounds wired.
- **STAT**: HP/AP meters (live), limb chips (severity color, click→UseStimpak — per-limb targeting is
  not in the engine API, documented), SPECIAL tiles, active effects, level/XP, E Stimpak / R RadAway,
  V toggle, Vault Boy = vanilla ConditionClips composite (`pipos.VaultBoy`).
- **DATA**: Quests/Workshops/Stats sub-tabs, quest list + objectives, R Show-on-Map, C Summary, Track.
- **MAP**: World/Local toggle, marker overlay (projected), click-to-place (SetPlayerMarker), region chip.
- **RADIO**: station list, Enter Tune (toggle off when tuned), time-based oscilloscope, signal %.
Honest deltas from the mockup (no dead controls; not pixel parity): RADS meter has no Pipboy_DataObj
field → shown empty unless the DLL feeds it; item-list header-click sort is via the Z keybar (not
per-column headers) in v1; the DLL 3D character/weapon turntable is stubbed → figure falls back to the
Vault Boy composite and R-Inspect uses the real vanilla examine invoke. In-game GFx render unverified.

**Typeface (resolved):** UI text is **Arimo Stalker Bold embedded in each page** (DefineFont3,
`embedAsCFF="false"`) — device fonts render nothing under Scaleform, so embedding is mandatory. All
five pages were rendered in Ruffle (headless) via `tools/preview_pages.ps1` with zero AS errors, and
the captures confirmed the locked-design selection style (near-white ink + dark shadow), the vector
★/✦ markers, the DATA COMPLETED separator, the centered Vault Boy, and the live radio oscilloscope.

## Global chrome
**M3 CRT chrome BUILT + Ruffle-render-confirmed** (`PipOS_Chrome.swf`, loaded by the shell as a
root-sibling overlay): the badge, telemetry flavor lines, PROPERTY OF VAULT-TEC, CRT bezel + corner
brackets, scanline overlay, clock card (live date/time + PIP-OS(R) V2.7.1), left sidebar tabs
STAT/INV/DATA/MAP/RADIO (clickable → page switch) + flavor side-notes, the EXT section (mirrors
PipboyTabs-injected tabs live), and the CRT boot/collapse animation are all implemented. Real-engine
GFx render still unverified. Footer keybar remains the vanilla (restyled) `ButtonHintBar` for now.

| Element | Purpose |
|---|---|
| `PIP-BOY OS V2.7.1` badge | [FLAVOR] product branding; version string doubles as our mod version display |
| `SSS NFO 3247-98A · CONNECTION – STABLE` | [FLAVOR] terminal telemetry dressing |
| `PROPERTY OF VAULT-TEC` | [FLAVOR] |
| Outer frame + corner brackets | [FLAVOR] CRT bezel framing |
| Scanlines / vignette / phosphor glow | [FLAVOR] CRT material treatment |
| Live scanline roll + periodic sweep | [FLAVOR][MOCKUP✓] a fine phosphor line pattern slowly rolls down the whole UI with an occasional brighter sweep band; suppressed under reduced motion |
| Sidebar tabs STAT/INV/DATA/MAP/RADIO | [LIVE][MOCKUP✓][SWF✓ shell] switch main page; SWF mirrors vanilla tab contract (Q/E + click). M3 shell preserves the vanilla Pipboy_Header tab contract + PipboyTabs `_TabNames` injection (verified) |
| Sidebar side-notes (`INV 04.JK.E`, `DB 1A.F7.G`, `GPS 77.7F.E`, `SIG S.T60.B`) | [FLAVOR] bus/diagnostic codes; `GPS` may show real cell coords [V2] |
| EXT entries (CHALLENGES / AFFINITY / MAGAZINES) | [LIVE][MOCKUP✓ stub] PipboyTabs-injected pages mount here; entries appear only when the framework registers them |
| Clock card date + time | [LIVE] engine game date/time (mockup shows fixed 10.23.2287 11:10) |
| `PIP-OS(R) V2.7.1` in clock card | [FLAVOR] |
| Footer keybar | [LIVE][MOCKUP✓] per-page real actions; every chip is clickable and equals its hotkey |
| `Esc · Back` / `Tab` | [LIVE][MOCKUP✓] closes the Pip-Boy; Tab also reopens it. **CRT boot animation** on open (UI blooms vertically from a bright scanline, phosphor overshoot, ~450ms) and the reverse collapse on close (~260ms) — plays over the sharp "gameplay" scene; suppressed under reduced motion. In inspect, Tab/R/Esc all exit inspect instead |

## INV

| Element | Purpose |
|---|---|
| Category sub-tabs (Weapons/Apparel/Aid/Misc/Junk/Ammo) | [LIVE][MOCKUP✓] filter the item list |
| WEIGHT chip | [LIVE] current/max carry weight; goes warn-amber near limit, crit-red over [SWF] |
| Caps chip | [LIVE] player caps |
| EQUIPMENT panel rows | [LIVE] equipped item per slot; click selects that item in the list [V2 — readout only in v1] |
| Character turntable | [LIVE][MOCKUP✓ stand-in] DLL preview clone of the real equipped player; drag = rotate; **no auto-rotate by default — right-click toggles auto-spin** |
| Turntable ring/shadow/scanline + hint caption | [FLAVOR] holo-projector staging; caption doubles as control help |
| QUICK ACCESS slots 1–7 | [LIVE][MOCKUP✓] favorites; hotkey/click consumes (count decrements, slot pulses) |
| Item list headers | [LIVE][MOCKUP✓ via Z] sort indicators; header click sorts by that column [SWF] |
| Item rows (+ ★ suffix) | [LIVE][MOCKUP✓] select → item card; ★ marks favorites |
| Item card (name, caliber, W/V chips, 4 stat pairs, flavor line) | [LIVE][MOCKUP✓] selected item readout; flavor line uses real item description where the game has one, else omitted |
| `R Inspect` | [LIVE][MOCKUP✓] fullscreen inspect (below) |
| `X Drop` | [LIVE][MOCKUP✓] drops selected item |
| `C Cycle Damage` | [LIVE][MOCKUP✓] cycles damage-type readout (ballistic/energy/…) on the card |
| `Q Fav` | [LIVE][MOCKUP✓] toggle favorite ★ / quick-access membership |
| `Z Sort` | [LIVE][MOCKUP✓] cycle sort: name / weight / value (title shows mode) |
| `T Perk Chart` | [LIVE][MOCKUP✓ nav] opens perk chart (`ShowPerksMenu`). The T chip is **shell-provided** — the shell pushes its dynamic GridViewButton (T → `onGridViewPress`) onto every page's `buttonHintDataV`; the PIP-OS chrome **relabels its "Grid View" text to "PERK CHART"** for display. The pending-points `LEVELUP (n)` flashing state is kept verbatim (not relabelled). Exactly one T chip; pages add no second T entry/handler (single input path) |

## Fullscreen Inspect (R)

| Element | Purpose |
|---|---|
| Backdrop blur+dim | [FLAVOR] focus staging (matches vanilla ExamineMenu) |
| Fly-to-center scale-up + reverse on exit | [FLAVOR][MOCKUP✓] vanilla-style zoom transition |
| Weapon turntable | [LIVE][MOCKUP✓ single model] real selected weapon mesh in SWF; drag rotate, holds side profile until dragged |
| Title | [LIVE][MOCKUP✓] selected item name |
| STATS panel | [LIVE][MOCKUP✓] full stat readout incl. ammo/weight/value |
| CURRENT MODS panel | [LIVE][MOCKUP✓ sample] real attached OMOD list |
| `W Prev / S Next` | [LIVE][MOCKUP✓] cycle items without leaving inspect |
| `Wheel Zoom` | [LIVE][MOCKUP✓] camera distance zoom |
| `R / Esc Exit` | [LIVE][MOCKUP✓] fly back, restore menu |

## STAT

| Element | Purpose |
|---|---|
| Sub-tabs Status / Special / Perks | [LIVE][MOCKUP✓] |
| HP / AP / RADS meters | [LIVE] live vitals; RADS blocks HP tail [SWF] |
| Limb condition chips (anchored around the figure: head/arms/legs/torso) | [LIVE][MOCKUP✓] per-limb ActorValue condition; severity color (amber <70, red <35); **click = apply a stimpak to that limb** (consumes one, heals, pulses; no-op at 0 stimpaks or full limb) |
| `V Vault Boy / Character` | [LIVE][MOCKUP✓] toggles the center figure between the DLL character capture and the Vault Boy. **Mockup uses a Meshy-generated Vault Boy stand-in**; the shipping page composites the vanilla `Components/ConditionClips/Condition_Body_<state>.swf` + `Condition_Head.swf` per damage state, placed per `Shared.AS3.ConditionBoy` (decompiled — authoritative placement for M4). Keybar label reflects the target |
| SPECIAL tiles (Status) | [LIVE] current attribute values |
| Character figure | [LIVE][MOCKUP✓] **same live 3D DLL capture as INV** (the single WebGL canvas is reparented into the STAT figure slot when STAT is active), drag-rotate + right-click auto-spin; `V` toggles to the vanilla Vault Boy |
| Active Effects panel | [LIVE] current magic effects with source |
| Level chip + XP bar | [LIVE] |
| `E Stimpak (n)` / `R RadAway (n)` | [LIVE][MOCKUP✓] consume, count updates in keybar, target bar pulses |
| Special sub-tab rows | [LIVE][MOCKUP✓] select → attribute description panel (Vault Boy anim [V2]) |
| Perks sub-tab rows | [LIVE][MOCKUP✓] select → rank + perk description |

## DATA

| Element | Purpose |
|---|---|
| Sub-tabs Quests / Workshops / Stats | [LIVE][MOCKUP✓] active tab shown by the three-dot `• • •` indicator (parity; matches INV — was a solid underline bar) |
| `QUEST LOG` / `WORKSHOPS` / `STATS` panel header | [MOCKUP✓] left-panel heading, text switches per sub-tab (parity; was a bare panel) |
| Quest list — active section | [LIVE][MOCKUP✓] running quests, select → objectives |
| **Miscellaneous entry** | [LIVE][MOCKUP✓] container quest; each sub-objective individually selectable/trackable |
| **`COMPLETED` separator** | [LIVE][MOCKUP✓] divides finished quests (dimmed) from active ones |
| `OBJECTIVES · <quest>` detail header | [LIVE][MOCKUP✓] right-panel heading (mockup `#objtitle`); static `OBJECTIVES` when nothing selected |
| Objectives panel | [LIVE][MOCKUP✓] checkbox rows; done = filled+struck; click selects/tracks that objective |
| Track quest | [LIVE] `Enter` / gamepad `A` (ProcessUserEvent `Accept`) or a row click tracks the selected quest. The misleading keybar `TRACK` chip was removed (parity: mockup DATA keybar has none, and the chip was dead on Workshops/Stats) — the action is unchanged, only the chip is gone |
| `R Show on Map` | [LIVE][MOCKUP✓] jumps to MAP focused on the tracked objective |
| `C Show Summary` | [LIVE][MOCKUP✓] toggles quest description panel |
| Workshops table | [LIVE][MOCKUP✓ sample] settlement stats; row select; R shows settlement on map [SWF] |
| Stats panels (General/Combat/Crafting) | [LIVE][MOCKUP✓ sample] engine misc-stat counters |

## MAP

| Element | Purpose |
|---|---|
| Sub-tabs World / Local | [LIVE][MOCKUP✓] map modes (engine-rendered map both) |
| Map canvas | [LIVE][MOCKUP✓ placeholder art] engine world/local map + native markers |
| Player triangle / quest gear / location dots / labels | [LIVE] engine marker set, PIP-OS styling |
| Click → custom marker | [LIVE][MOCKUP✓] place/move player custom marker |
| Region chip (`Commonwealth`) | [LIVE] current worldspace name |
| Grid chip (`GRID C-4 · SANCTUARY HILLS`) | [FLAVOR] sector readout; nearest-location name is real [SWF] |
| Legend chip | informational key for marker glyphs |
| `R Local Map` | [LIVE][MOCKUP✓] toggle world/local |
| Mockup-note chip | mockup-only; deleted in SWF |

## RADIO

| Element | Purpose |
|---|---|
| `FREQUENCIES` panel header | [MOCKUP✓] left stations-panel heading (parity; was a bare panel) |
| Station rows | [LIVE][MOCKUP✓] select; signal % is real reception, `ON AIR` marks tuned |
| `Enter / Tune` | [LIVE][MOCKUP✓] tune selected; tuning the tuned station switches receiver off |
| `OSCILLOSCOPE` panel header | [MOCKUP✓] scope-panel heading (parity; was a bare panel) |
| Oscilloscope | [LIVE-synced][MOCKUP✓] waveform while playing, flatline + `NO SIGNAL` when off (vanilla behavior) |
| `#freqrow` large MHz readout (`_freq`) | [FLAVOR][MOCKUP✓] big frequency number; **flavor** — see MHz mapping note below |
| Station NAME sub-line (`_dj`) | [LIVE][MOCKUP✓] real station name (the mockup's DJ half is omitted — no DJ name exists in engine data, never fabricated) |
| SIGNAL line (`_signal`) | reflects tuned station reception % [SWF] (`ON AIR` when active but no reception value); mockup fixed `STRONG` |

**MHz mapping [FLAVOR] (`PipOS_RadioPage.stationMHz`).** FO4 radio stations expose NO real carrier
frequency, so the `MHz` shown in `#freqrow` is a display-only pseudo-frequency **derived deterministically
from the station NAME** — the same station name always yields the same number (stable across sessions and
selection). Known vanilla stations are pinned to their mockup values (Diamond City Radio → `102.5`,
Classical Radio → `98.7`, Radio Freedom / Minutemen → `94.3`, Vault 111 Distress → `87.1`); any other
(modded) station hashes its name into the US FM band (`87.9`–`107.9 MHz`, `0.2` steps). Per the
[[ui-every-element-has-purpose]] rule, this element is deliberate flavor and is declared flavor here; the
station NAME beside it is the real, live datum.

## Input paths (single live path per action — round-5)
Each action has EXACTLY ONE runtime path (no double-fire). Keybar actions go through `ProcessUserEvent`
named controls (fire on keyboard's mapped key AND gamepad button); list navigation + genuinely-custom
toggles use raw `KEY_DOWN`; list-row activation is the single `Accept` control + mouse click.

| Page | Action | Driven by (single path) | PC key / pad |
|---|---|---|---|
| all | list up / down | raw KEY_DOWN (list nav) + mouse | Up/Down / (pad list-scroll not wired — see note) |
| all | row activate | ProcessUserEvent `Accept` + mouse click-selected | Enter / A |
| all | prev/next page, prev/next tab | shell forwards Forward/Back/StrafeL/R + sidebar click | shell hotkeys / sidebar |
| all | Perk chart | **shell** GridView `YButton`→ShowPerksMenu (pages no longer handle T); chrome relabels the chip "Grid View"→"PERK CHART" (LEVELUP flash kept) | T / Y |
| INV | Drop | ProcessUserEvent `XButton` | X / X-pad |
| INV | Inspect (examine) | ProcessUserEvent `R3` | R / R3 |
| INV | Sort | ProcessUserEvent `L3` | Z / L3 |
| INV | Favorite | ProcessUserEvent `RShoulder` | Q / R1 |
| INV | Cycle damage | ProcessUserEvent `LShoulder` | C / L1 |
| STAT | Stimpak | ProcessUserEvent `Accept` | E / A |
| STAT | RadAway | ProcessUserEvent `XButton` | R / X-pad |
| STAT | Vault Boy / character toggle | ProcessUserEvent `LShoulder` | V / L1 |
| DATA | Show on Map | ProcessUserEvent `XButton` | R / X-pad |
| DATA | Summary | ProcessUserEvent `LShoulder` | C / L1 |
| DATA | Track objective | ProcessUserEvent `Accept` | Enter / A |
| MAP | World/Local toggle | ProcessUserEvent `XButton` | R / X-pad |
| MAP | Place marker | ProcessUserEvent `Accept` + map click (mouse) | Enter / A / click |
| RADIO | Tune | ProcessUserEvent `Accept` + mouse click-selected | Enter / A / click |

Known limitation (documented): the custom `PipList` (replacing BSScrollingList) is navigated by mouse
and keyboard fully; gamepad vertical LIST scrolling is not bound to a named control in v1. All keybar
ACTIONS are gamepad-reachable via the named controls above.

## Sound assignment (SWF requirement, M3/M4)
Every interaction that gives visual feedback also plays the appropriate UI sound in game — no
silent controls, no sounds on pure readouts. Source the exact sound-event names from the vanilla
Pip-Boy SWFs and Baka Fullscreen Pip-Boy's usage during M2 RE (vanilla routes them through
`BGSCodeObj.PlaySound` with `UIMenu*`/`UIPipBoy*` events). Minimum map to confirm against RE:
tab/sub-tab switch (prev/next), list row focus move, select/OK, cancel/back, favorite toggle,
drop, sort mode, inspect open/close (zoom in/out pair), stimpak/RadAway use, radio tune on/off,
map marker place, Pip-Boy open/close (the signature raise/lower pair). Log the confirmed table
in `docs/ScaleformContract.md` when M2 lands.

**✅ M2 landed:** the confirmed sound-event table (UIGeneralFocus, UIMenuOK, UIMenuCancel,
UIMenuPrevNext, UIMenuQuantity, UIPipBoyMapRollover, UIPipBoyMapZoom, UIPipBoyFavoriteMenuDPadA/B/C,
UIBarterHorizontalRight, plus PlayPerkSound/StopPerkSound/PlaySmallTransition) and the PIP-OS
interaction→sound assignment map are in `docs/ScaleformContract.md` §(f). Wire these in M4.

## Interaction feedback (global)
- Every click on an interactive element (tabs, sub-tabs, keybar chips, list rows, objectives,
  quick slots) fires a brief brightness pulse on the element plus a phosphor ripple at the
  pointer. The ripple is drawn at stage level so it survives list re-renders. Suppressed under
  `prefers-reduced-motion`.

## Not present by design
- No sliders exist in the menu; sliders live in the MCM / F4SE Menu Framework settings pages (M6).
- The "E" hotkeys from the concept art's top corners were dropped per user instruction (round 1).
- Power armor Pip-Boy: vanilla in v1 (locked decision).
