# PIP-OS Scaleform Contract (M2)

Authoritative reverse-engineering of the vanilla Fallout 4 Pip-Boy Scaleform contract, derived by
JPEXS script export of the vanilla `PipboyMenu.swf`, `Pipboy_{Stats,Inv,Data,Map,Radio}Page.swf`,
`Components/ConditionClips/*`, and `PipboyTabs.swf`. Every claim below is traceable to a decompiled
`.as` file. This is the surface our shell (M3) and pages (M4) must preserve/reuse, and the source of
the sound-event table (hard user requirement).

Runtime note: the engine hosts these SWFs in Scaleform GFx 4.x (AS3, `swf-version 15`,
ZLIB-compressed, frameRate 30, frameCount 1 for the shell).

**Frame cadence (binding):** the vanilla `PipboyMenu.swf` header is **frameRate 30.0**, and all five
`Pipboy_*Page.swf` are also 30.0. Loaded child SWFs tick at the ROOT movie's cadence, not their own
declared fps, so every PIP-OS page animation must be **time-based via `getTimer()`** with the delta
clamped to [1/240, 1/12] s — never a hardcoded per-tick delta. We keep the vanilla 30 fps header in
v1 (do not re-author) because PipboyTabs and transplanted vanilla logic may assume frame-based timing.
See `docs/ImplementationNotes.md` "STANDING CONVENTION — time-based animation". The engine-side object is exposed to
ActionScript as **`BGSCodeObj`** (a plain `Object` whose methods are native). All AS→engine calls go
through `Shared.BGSExternalInterface.call(target, methodName, ...args)`, which simply does
`target[methodName].apply(null, args)` and traces if the method is missing. So "BGSCodeObj method"
= a native function the engine installs on that object.

---

## (a) PipboyMenu ⇄ engine BGSCodeObj method surface

### Engine → SWF (methods the engine invokes on the loaded movie / `PipboyMenu` instance)
| Method | Signature | Purpose |
|---|---|---|
| `onCodeObjCreate()` | — | Engine finished creating `BGSCodeObj`. Shell responds by calling `PopulatePipboyInfoObj(DataObj)`. |
| `onCodeObjDestruction()` | — | Teardown. Shell clears pages, nulls `BGSCodeObj`/`DataObj`. |
| `InvalidateData()` | — | Full data refresh. Calls `InvalidatePartialData(0xFFFFFFFF)`. |
| `InvalidatePartialData(mask:uint)` | mask | Partial refresh; dispatches `PipboyChangeEvent` with a `PipboyUpdateMask` to all sub-menus. If no page is loaded yet, triggers `LoadCurrentPage()`. |
| `ProcessUserEvent(event:String, isDown:Boolean):Boolean` | button name, down/up | Routed input. Shell forwards to current page first; unhandled Forward/Back/LTrigger/RTrigger = page nav, StrafeLeft/Right/Left/Right = tab nav, YButton = perk/grid view. |
| `SetPlatform(platform:uint, force:Boolean)` | — | PC/console platform switch; recalculates header text bounds. |
| `onRightThumbstickInput(dir:uint)` | — | Forwarded to current page. |
| `onMobileBackButtonPressed()` | — | Companion-app back button. |

### SWF → engine (BGSCodeObj methods the shell calls) — from `PipboyMenu.as`
| Call | Args | When |
|---|---|---|
| `PopulatePipboyInfoObj(DataObj)` | the `Pipboy_DataObj` | On `onCodeObjCreate`; engine fills the DataObj with all live state. |
| `RegisterMovie(this)` | the menu movie | After mobile settings load; **also how a companion DLL gets the movie reference.** |
| `OnMobileSettingsLoaded(mc)` | settings clip | Companion app only. |
| `onNewPage(index:uint)` | target page | Request page change (engine validates + calls back InvalidateData). |
| `onNewTab(index:uint)` | target tab | Request tab change. |
| `ShowPerksMenu()` | — | "T / Grid View / LEVELUP" opens the perk chart. |
| `PlaySound(event:String)` | UI sound event | See sound table §f. |
| `onBackButtonHandled(bool)` | — | Ack for mobile back. |

Key architectural facts (from `PipboyMenu.as`):
- `DataObj:Pipboy_DataObj` is the **single shared data record**. The engine mutates it in place via
  `PopulatePipboyInfoObj`; the shell then broadcasts changes with `PipboyChangeEvent.DispatchEvent(mask, stage, DataObj, TabNames)`.
- `PageA:Vector.<PipboyLoader>` — five fixed loader slots, one per page.
- `BGSCodeObj` starts as `new Object()`; the engine replaces/populates its native methods.

---

## (b) Pipboy_DataObj — the per-page data binding record

`Pipboy_DataObj` (`Pipboy_DataObj.as`) is a flat property bag; `NUM_PAGES=5`, `NUM_SPECIAL=7`. The
engine writes, the SWF reads (getters). Pages subscribe to `PipboyChangeEvent` and pull the fields
relevant to their `GetUpdateMask()`. Field → page consumer map:

| Field(s) | Type | Consuming page | Notes |
|---|---|---|---|
| `CurrentPage`, `CurrentTab` (`StoredTabs[]`) | uint | shell/header | Per-page stored tab index. |
| `PlayerName` | String | STAT | |
| `CurrHP/MaxHP`, `CurrAP/MaxAP` | Number | STAT meters | |
| `CurrWeight/MaxWeight` | Number | INV weight chip | warn/crit thresholds are our styling |
| `StimpakCount`, `RadawayCount` | uint | STAT keybar | |
| `CurrentHPGain`, `SelectedItemHPGain` | Number | STAT/INV | stimpak/aid preview |
| `HeadCondition`, `TorsoCondition`, `LArm/RArm/LLeg/RLegCondition` | Number | STAT limb chips | per-limb condition (0..1 fraction of limb HP) |
| `BodyFlags`, `HeadFlags` | uint | STAT ConditionBoy | drive the Condition_Body_\<flags\> / Condition_Head frame (see §e) |
| `Caps` | uint | INV caps chip | |
| `DateMonth/Day/Year`, `TimeHour` | uint/Number | clock card | `TimeHour` is fractional hours |
| `CurrLocationName` | String | MAP region/grid | |
| `XPLevel`, `XPProgressPct` | uint/Number | STAT level+XP | |
| `InvItems[]`, `InvComponents[]`, `InvFilter`, `InvSelectedItems[]` | Array/int | INV list | `InvFilter` = category bitflag; `InvSelectedItems[tab]` = restore index per tab |
| `SortMode` | uint | INV sort | index into SortText |
| `FavoritesList[]` | Array | INV quick-access cross | |
| `HolotapePlaying` | Boolean | INV (holotape) | |
| `ActiveEffects[]` | Array | STAT effects panel | |
| `SPECIALList[]` (7) | Array | STAT Special | attribute objects |
| `PerksList[]`, `PerkPoints` | Array/uint | STAT Perks | PerkPoints>0 flashes the LEVELUP button |
| `QuestsList[]` | Array | DATA quests | |
| `WorkshopsList[]` | Array | DATA workshops | |
| `GeneralStatsList[]` | Array | DATA stats | misc stat counters |
| `WorldMapMarkers[]`, `LocalMapMarkers[]` | Array | MAP | native marker set |
| `WorldMapTextureName`, `World/LocalMap{NW,NE,SW}Corner` (Point) | String/Point | MAP | map extents for marker projection |
| `RemovedMapMarkerIds[]`, `RemoveAllMapMarkers` | Array/Bool | MAP | |
| `RadioList[]` | Array | RADIO | station objects (name, freq, active, reception) |
| `TotalDamages[]`, `TotalResists[]`, `SlotResists[]`, `UnderwearType` | Array/uint | INV PaperDoll | resist rollups + paperdoll |
| `ReadOnlyMode` | int | all | 0=none,1=default,2=offline,3=demo (companion) |

Update masks live in `PipboyUpdateMask` (bitmask; `.Intersects()` used by sub-menus). Each page
returns its mask from `GetUpdateMask()` — e.g. `Pipboy_InvPage` returns `PipboyUpdateMask.Inventory`.

---

## (c) PipboyPage interface + PipboyLoader page-load contract

### PipboyLoader (`Shared/AS3/COMPANIONAPP/PipboyLoader.as`)
`extends flash.display.Loader`. In normal (non-companion) mode `load()` is a straight
`super.load(request, context)`. In companion mode it round-trips the URL through
`ExternalInterface "GetAssetPath"`. Our shell runs in normal mode.

### Loader table (vanilla `PipboyMenu.LoadCurrentPage`)
```
LoaderContext(false, ApplicationDomain.currentDomain)   // shared domain — pages reuse shell classes
switch(CurrentPage): 0→Pipboy_StatsPage.swf 1→Pipboy_InvPage.swf 2→Pipboy_DataPage.swf
                     3→Pipboy_MapPage.swf   4→Pipboy_RadioPage.swf
PageA[CurrentPage].contentLoaderInfo.addEventListener(COMPLETE, onPageLoadComplete)
```
`onPageLoadComplete`: `content as PipboyPage` → `page.InitCodeObj(BGSCodeObj)` → `addChild(page)` →
push `GridViewButton` into `page.buttonHintDataV` → `ButtonHintBar_mc.SetButtonHintData(...)` →
`InvalidateData()`. **`LoaderContext` uses `ApplicationDomain.currentDomain` — first definition wins;
this is why swappable pages can rely on shell-defined classes and why FallUI's InvPage (which needs
FallUI-menu-seeded classes) can't load under a foreign shell.**

### PipboyPage API (what any page SWF must implement) — `PipboyPage.as` / `PipboySubMenu.as`
- `extends PipboyPage extends PipboySubMenu extends BSUIComponent`.
- `InitCodeObj(codeObj:Object)` / `ReleaseCodeObj()` — receive/drop the BGSCodeObj (stored as `BGSCodeObj`, exposed via `get codeObj`).
- `get TabNames():Array` (`_TabNames`) — sub-tab labels; **PipboyTabs appends to this array (see §d).**
- `get buttonHintDataV():Vector.<BSButtonHintData>` — footer keybar; built in `PopulateButtonHintData()`.
- `ProcessUserEvent(event, isDown):Boolean`, `onRightThumbstickInput(dir)`, `GetIsUsingRightStick()`.
- `CanSwitchFromCurrentPage()`, `CanSwitchTabs(idx)`, `CanLowerPipboy()`.
- `GetUpdateMask():PipboyUpdateMask` + `onPipboyChangeEvent(e)` — data binding entry point.
- Lifecycle: `onAddedToStage`/`onRemovedFromStage` register/unregister `PipboyChangeEvent` and the
  mobile back button.
- Events dispatched up to the shell: `PipboyPage.LOWER_PIPBOY_ALLOW_CHANGE`, `PipboyPage.BOTTOM_BAR_UPDATE`.

### M3 shell change (implemented, verified)
Our patched `PipboyMenu.swf` preserves the entire contract above and changes **only** the loader
filename table + adds fallback:
- Default per tab loads `PipOS_{Stats,Inv,Data,Map,Radio}Page.swf`.
- `PageModes[5]` (0=pipos default, 1=external). `SetPageMode(index, mode)` is public so the companion
  DLL (or a config) can set external passthrough from the INI (S2-HUD precedent: DLL reads INI, calls
  into the movie via the `RegisterMovie` reference).
- `onPageLoadError` (IOErrorEvent): in pipos mode a missing `PipOS_*Page.swf` falls back to the
  external `Pipboy_*Page.swf` (vanilla/FallUI, always present); in external mode a failed external page
  falls back to the PipOS page. Guarantees the menu never dead-loads.

---

## (d) PipboyTabs hook points (contract we must NOT break)

From `PipboyTabs.as` (the framework's `PipboyTabs.swf`, loaded by its DLL over the menu):
- On ADDED_TO_STAGE it reads **`stage.getChildAt(0)["Menu_mc"]`** → the `PipboyMenu` instance, and
  **`stage.getChildAt(0)["pbt"]`** → the native code object the DLL registers.
- Tab injection: `this.Menu.getChildAt(4)["_TabNames"].push(aName)` and sets the new tab's index to
  `_TabNames.length - 1`. **So `Menu.getChildAt(4)` must be the current `PipboyPage`, and pages must
  keep the `_TabNames:Array` field.**
- It subscribes to `PipboyChangeEvent` to show/hide its custom tab clips per `CurrentPage`/`CurrentTab`.
- `registerTab(id,name,page,type,data,showList,precision)` builds SkillsTab/AVIFSTab/FactionTab/NoteTab.

**Implications enforced in M3:** we did not rebuild the shell from scratch (which would perturb the
display-list child index used by `getChildAt(4)` and the `Menu_mc`/symbol names). We patched only the
`PipboyMenu` ABC method table. Verification confirmed via independent body-diff that the **47 untouched classes are byte-identical
to vanilla** (SHA-256 per class) and only `PipboyMenu.as` changed — additively patched (loader table +
`SetPageMode` + `onPageLoadError`), with the vanilla BGSCodeObj API preserved. The SymbolClassTag
`<tags>`/`<names>` bindings (PipboyMenu, Pipboy_BottomBar, …, ReadOnlyWarning, MapPlaceholder) are
identical between vanilla and patched, so PipboyTabs' `getChildAt(4)`/`_TabNames` injection still works. **PIP-OS pages (M4) must keep
`_TabNames:Array` public and must be `addChild`'d as the same display index the shell uses so
`getChildAt(4)` resolves to the page.**

---

## (e) ConditionBoy composite contract (STAT Vault Boy)

From `Shared/AS3/ConditionBoy.as` (authoritative placement for M4 STAT):
- Loads **`Components/ConditionClips/Condition_Head.swf`** once (a MovieClip with condition frames).
- `set BodyFlags(v)` loads **`Components/ConditionClips/Condition_Body_<v>.swf`** (v = `DataObj.BodyFlags`,
  a damage-state index; vanilla ships `Condition_Body_0..16.swf`). Reloads whenever the flag changes;
  `unloadAndStop()`s the previous.
- `set HeadFlags(v)` just marks dirty; the head clip is a single MovieClip whose **frame** is selected:
  `HeadClip_mc.gotoAndStop(HeadFlags + 1)`.
- Composite/placement (in `redrawUIComponent`):
  - `BodyClip_mc.Head_mc.addChild(HeadClip_mc)` — the head clip is parented into the body clip's
    `Head_mc` slot (the body art defines where the head goes).
  - `BodyClip_mc.scaleX = BodyClip_mc.scaleY = 1.2`.
  - `addChild(BodyClip_mc)` (replacing child 0).
- Both loads use `LoaderContext(false, ApplicationDomain.currentDomain)`.

M4 STAT should instantiate a `ConditionBoy` (or replicate this logic), feed it `DataObj.BodyFlags`
and `DataObj.HeadFlags`, and place it in the figure slot. This is the shipping Vault Boy — the Meshy
Vault Boy in the mockup was preview-only.

---

## (f) UI SOUND EVENT TABLE (hard requirement)

All UI sounds route through `BGSExternalInterface.call(BGSCodeObj, "PlaySound", "<event>")` (plus the
dedicated perk-sound calls). Events below are the **exact literals** found in the decompiled vanilla
SWFs (menu/inv/stats/data/map/radio) and FallUI reference. Reception on the engine side is the
Fallout 4 `UI...` sound descriptor set.

### Confirmed vanilla sound events (RE-verified)
| Event literal | Fired by (vanilla) | Meaning |
|---|---|---|
| `UIGeneralFocus` | `PipboyMenu.onListPlayFocus` (BSScrollingList.PLAY_FOCUS_SOUND), Map | list row focus move |
| `UIMenuOK` | Map select/confirm | select / OK |
| `UIMenuCancel` | Map cancel | cancel / back |
| `UIMenuPrevNext` | shared list nav | prev/next step |
| `UIMenuQuantity` | `Pipboy_InvPage.onQuantityModified` | quantity spinner tick |
| `UIPipBoyMapRollover` | Map | map marker rollover |
| `UIPipBoyMapZoom` | Map | map zoom |
| `UIPipBoyFavoriteMenuDPadA` / `...DPadB` / `...DPadC` | Favorites cross (`FavoritesCross.selectionSound` via `onFavSelection`) | quick-access ring move |
| `UIBarterHorizontalRight` | shared list (barter-derived) | horizontal step |

### Dedicated (non-PlaySound) audio calls
| Call | Fired by | Meaning |
|---|---|---|
| `PlayPerkSound()` / `StopPerkSound()` | perk chart open/scroll | perk chart ambience |
| `PlaySmallTransition()` | Data/Map page transitions | small whoosh on view change |

### Pip-Boy raise/lower (open/close) signature pair
The signature raise/lower is played engine-side when the Pip-Boy menu opens/closes (not from a SWF
`PlaySound` literal — it is triggered by the menu open/close state machine). Our shell keeps that
behavior by preserving the vanilla open/close path; the CRT boot/close animation (FunctionalitySpec)
is layered on top and does not replace the engine's raise/lower audio.

### PIP-OS interaction → sound assignment (per FunctionalitySpec "Sound assignment")
Map every PIP-OS control that gives visual feedback to a confirmed event above:
| PIP-OS interaction | Sound event |
|---|---|
| Sidebar tab switch / page prev-next | `UIMenuPrevNext` |
| Sub-tab switch | `UIMenuPrevNext` |
| List/row focus move (INV/DATA/RADIO/PERK/SPECIAL) | `UIGeneralFocus` |
| Select / OK / tune / place-marker / objective-track | `UIMenuOK` |
| Cancel / back / close-inspect | `UIMenuCancel` |
| Favorite toggle (quick-access ring move) | `UIPipBoyFavoriteMenuDPadA/B/C` (ring position), else `UIMenuOK` on commit |
| Drop item / quantity adjust | `UIMenuQuantity` (spinner), `UIMenuOK` (commit drop) |
| Sort mode cycle (Z) | `UIMenuPrevNext` |
| Damage-type cycle (C) | `UIMenuPrevNext` |
| Inspect open / close (zoom in/out pair) | open `UIMenuOK`, close `UIMenuCancel` |
| Stimpak / RadAway use | `UIMenuOK` (engine also plays the item-use SFX via `UseStimpak`/`UseRadaway`) |
| Radio tune on/off | `UIMenuOK` (on) / `UIMenuCancel` (off) |
| Map marker place / rollover / zoom | `UIMenuOK` / `UIPipBoyMapRollover` / `UIPipBoyMapZoom` |
| Pip-Boy open/close | engine raise/lower (preserved) |

Rule (FunctionalitySpec): every control with visual feedback plays exactly one of these; pure
readouts play nothing.

---

## Additional per-page BGSCodeObj surfaces (for M4 data plumbing)

Reuse these exact calls when rebuilding each page's presentation (start from the vanilla page logic,
reskin the visuals, keep the plumbing):

**INV (`Pipboy_InvPage.as`)** — keybar: HolotapePlay/Read(Enter), Inspect(X→`ExamineItem`),
Drop(R→`ItemDrop`), Fav(Q→favorites cross → `SetQuickkey`), CycleDamage(C→PaperDoll.IncrementDisplayedDamageType),
ComponentView(C→`ToggleComponentFavorite`/`onComponentViewToggle`), Sort(Z→`SortItemList` → `onSortComplete`).
Data calls: `SelectItem(index)`, `onInvItemSelection(index, ItemCard.InfoObj, PaperDoll.selectedInfoObj, this)`,
`updateItem3D(index)`, `onModalOpen(bool)`, `toggleMovementToDirectional(bool)`, `onShowHotKeys(bool)`.
Lists: `List_mc:BSScrollingList` (`listEntryClass="InvListEntry"`, numListItems=10), `ComponentList_mc`,
`ComponentOwnersList_mc`, `ItemCard_mc:ItemCard`, `PaperDoll_mc:PaperDoll`. SortText =
`["$SORT","$SORT_DMG","$SORT_ROF","$SORT_RNG","$SORT_ACC","$SORT_VAL","$SORT_WT"]`.

**STAT (`Pipboy_StatsPage.as`)** — `UseStimpak()`, `UseRadaway()`, `onPerksTabOpen()`, `onPerksTabClose()`,
`PlayPerkSound()`, `StopPerkSound()`; ConditionBoy fed by BodyFlags/HeadFlags + limb conditions;
Special/Perks scrolling lists; ActiveEffectsWidget.

**DATA (`Pipboy_DataPage.as`)** — `onQuestSelection(...)`, `SetQuestActive(...)`, `ShowQuestOnMap(...)`,
`ShowWorkshopOnMap(...)`, `OnScrollingStarted/Stopped(...)`, `PlaySmallTransition()`. Sub-tabs
Quests/Workshops/Stats; Miscellaneous quest container with individually selectable objectives.

**MAP (`Pipboy_MapPage.as`)** — `RegisterMap()`/`UnregisterMap()`, `SetPlayerMarker(...)`,
`ClearPlayerMarker()`, `CenterMarkerRequest(...)`, `FastTravel(...)`, `onSwitchBetweenWorldLocalMap(...)`,
`onScanButtonClicked/onManualModeButtonClicked/onGPSModeButtonClicked`, `onModalOpen(bool)`,
`PlayFocusSound()`. Engine renders the actual map; our SWF draws chrome + markers over it.

**RADIO (`Pipboy_RadioPage.as`)** — `ToggleRadioStationActiveStatus(...)`,
`OnScrollingStarted/Stopped(...)`. Station list from `DataObj.RadioList`; oscilloscope synced to
`HolotapePlaying`/active station; tuning the active station toggles it off (vanilla behavior).

---

## Verification of this document
- Evidence base: JPEXS `-export script` of vanilla `PipboyMenu.swf`, `Pipboy_{Stats,Inv,Data,Map,Radio}Page.swf`,
  `PipboyTabs.swf`, `Components/ConditionClips/*` (staged under scratchpad `as_vanilla_*`, `as_pbt`, `as_statspage`).
- Sound literals extracted by regex over every decompiled `.as` (`PlaySound",\s*"<event>"` and `"UI…"` constants).
- BGSCodeObj method names extracted by regex over `BGSExternalInterface.call(...,"<method>"`.
- Contract-preservation claims for M3 verified by re-decompiling the patched shell (class inventory
  identical 48/48; SymbolClass tag unchanged). Commands + results in `docs/ImplementationNotes.md`.
