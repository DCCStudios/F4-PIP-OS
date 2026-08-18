# FallUI Compatibility Investigation

Investigated 2026-08-15 against the MagnumOpus and LoreOut modlists, by decompiling (JPEXS script
export) vanilla `PipboyMenu.swf` / `Pipboy_InvPage.swf` and FallUI - Inventory's replacements,
plus FallUI - Map's `Pipboy_MapPage.swf`.

## How the Pip-Boy menu is actually assembled (vanilla contract)

`PipboyMenu.swf` does **not** contain the pages. `PipboyMenu.as` keeps
`PageA: Vector.<PipboyLoader>` and runtime-loads the five page SWFs **by filename** —
`Pipboy_StatsPage.swf`, `Pipboy_InvPage.swf`, `Pipboy_DataPage.swf`, `Pipboy_MapPage.swf`,
`Pipboy_RadioPage.swf` — with `LoaderContext(false, ApplicationDomain.currentDomain)`; each page
implements `PipboyPage`. Two consequences:

1. **Pages are swappable modules.** Any SWF conforming to the `PipboyPage` API works under any
   shell that preserves this loader contract.
2. **Pages share the shell's ApplicationDomain.** A page can rely on classes the shell defined
   (first-loaded definition wins) — which is exactly what FallUI does.

## What FallUI actually is

- **FallUI - Inventory** replaces `PipboyMenu.swf` and `Pipboy_InvPage.swf` (plus Barter/
  Container menus). It keeps *every* vanilla class and contract (why PipboyTabs coexists) and
  adds the author's `M8r.*` framework (~58 classes in the menu): config loader
  (`../MCM/Settings/FallUI.ini` + FIS `ItemSorter` XML), color theming via
  `M8r.Mods.config.stdColor` ColorTransforms, extended list/entry/item-card components, and an
  **addon framework**: `BaseFwCore` scans `Data/Interface/UI-Framework/Pipboy/*.swf` (and an
  ItemCard addon dir) via `BGSCodeObj.GetDirectoryListing`, loads them, and exposes
  `registerHook` + `PipboyApi` to addon SWFs.
- **FallUI's `Pipboy_InvPage.swf` is NOT standalone**: it embeds only 9 M8r classes and imports
  dozens more (`PipboyFwCore`, `GameItemDataExtractor`, helpers) that only FallUI's
  `PipboyMenu.swf` seeds into the shared domain. It cannot load under a vanilla or PIP-OS shell.
- **FallUI - Map's `Pipboy_MapPage.swf` IS standalone**: all 32 M8r classes it uses are embedded.
  It runs under any vanilla-contract shell.
- Third-party "FallUI patches" in the lists (Fire Rate Shows RPM, Modern Replacer currency,
  FallUI - Inventory Fix's StatsPage) are **full-file rebuilds of FallUI's SWFs**, not addons —
  they inherit the same dependency shape as the file they rebuild.

## Compatibility strategy (recommended)

**A. Decouple our page filenames — the single highest-value change.**
Ship PIP-OS pages as `PipOS_StatsPage.swf` … `PipOS_RadioPage.swf`. Only `PipboyMenu.swf`
conflicts with FallUI. Our shell chooses per tab (MCM setting): load the PIP-OS page, or load
the external `Pipboy_*Page.swf` — whatever wins the MO2 conflict. This gives, with zero extra
engineering per mod:
- FallUI - Map, Simply Smaller Map Markers, and any vanilla-contract page mod keep working
  inside PIP-OS chrome ("external" mode for that tab).
- Guard: wrap external page loads; if the page throws on init (missing M8r definitions), fall
  back to the PIP-OS page and surface an MCM note ("this page requires the FallUI menu").

**B. M8r-dependent pages (FallUI InvPage and its rebuilds): supported by stepping aside, not by
hosting.** Users who want FallUI's inventory let FallUI's `PipboyMenu.swf` win the conflict —
everything FallUI works untouched; PIP-OS is simply not active. Document this as the supported
choice. (Seeding FallUI's framework classes from our shell so their InvPage loads is technically
conceivable but fragile and needs FallUI permissions — rejected for v1.)

**C. [V2] Reverse integration via FallUI's own addon framework.** For FallUI-menu users, ship
the PIP-OS character-capture panel as a FallUI Pipboy addon SWF in
`Data/Interface/UI-Framework/Pipboy/` using `PipboyApi`/`registerHook`; the DLL detects which
menu is active. Best-of-both-worlds path once v1 ships.

**D. Feature parity where users lose FallUI Inv.** RPM display (already planned via DLL), and FIS
tag PARSING into collapsible folders (see the 2026-08-17 decision update below); FIS icon rendering
inside our item card is a [V2] evaluation.

## Decision — LOCKED 2026-08-15 (user: "lock it")
Adopt **A**: own only `PipboyMenu.swf`; ship pages as `PipOS_*Page.swf`; per-tab external-page
passthrough (MCM toggle) with load-failure fallback to the PIP-OS page. Plus **B** (FallUI-Inv
users let FallUI's menu win, PIP-OS inactive) and **D** (RPM via DLL; FIS tags shown as-is).
**C** (reverse integration as a FallUI Pipboy addon) remains a documented V2 path.

### Decision UPDATE — 2026-08-17 (supersedes "FIS tags shown as-is")
The prior D lock ("FIS tag *display* untouched, names shown as-is") is **SUPERSEDED**. Complex Sorter /
FIS / FallUI rewrite in-game item names with leading category **tag prefixes** (`[Weapon]`, `{Legendary}`,
`(Aid|Food)`) and Private-Use-Area icon glyphs (U+E000–U+F8FF) that our font does not carry (they render
as tofu). PIP-OS now **parses** those tags and presents FIS/FallUI-style **collapsible folders** in the
inventory list, instead of showing the raw tagged strings.

- **Parser** (`PipOS_InvPage.parseTag`): strips all PUA icon glyphs anywhere in the string; recognises a
  LEADING bracket token `[..]`/`{..}`/`(..)` (with `|` sub-tags, e.g. `[Aid|Food]` → groups under `Aid`);
  strips up to a few STACKED leading tokens for the clean label; the first plausible token is the group
  tag. Conservative guard (≤24 chars, tag-ish chars only, ≥1 letter) so a real name that merely contains
  parentheses mid-string is never falsely grouped. Returns `{tag, clean}`.
- **Display vs. join**: the row keeps the RAW in-game name (`row.text`) + `formID`; the card/tooltip/inspect
  DLL joins (`PipOS_iteminfo` by bare name, `PipOS_itemstats`/`itemmods` by formID) are UNCHANGED — only the
  DISPLAYED label (list NAME cell, card title, tooltip name, inspect title) is the tag-stripped clean name.
- **Folders**: tagged items group under clickable folder-header rows (pooled PipList **separator** rows with
  a vector open/closed caret + child count); collapse state is remembered per-category-per-tag across
  refreshes/sorts; ungrouped items fall into a trailing `MISC` folder. An UN-tagged inventory renders exactly
  flat as before (zero behaviour change). Master switch stubbed as `Theme.FOLDERS` (a Menu Framework UI
  toggle for it is a later round). Sorting (NAME/WT/VAL headers + Z/Sort) applies to items WITHIN each folder.

### M3 implications now fixed by this lock
- Shell's page-loader table points at `PipOS_StatsPage.swf … PipOS_RadioPage.swf` by default.
- Each of the 5 tabs carries a `[Pages] <Tab>=pipos|external` setting; `external` loads the
  live `Pipboy_<Tab>Page.swf`. Wrap external loads in try/error handler → fall back + MCM note.
- Only `PipboyMenu.swf` conflicts in MO2; keep the vanilla Scaleform contract intact inside it so
  PipboyTabs still injects (unchanged from the PipboyTabs-compat lock).
