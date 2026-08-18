# Vanilla Parity Matrix (Round 11)

Goal: our pages BEHAVE like vanilla (function) while LOOKING like PIP-OS (our drawing). Derived from
JPEXS P-code of the vanilla PipboyMenu shell + all 5 Pipboy_*Page + ListFilterer + PipboySubMenu/PipboyPage.
Status: MATCHED / GAP(fix) / DEFERRED / DELIBERATE-DIFF(reason).

## Shell <-> page lifecycle (all pages)
| Item | Vanilla | Ours | Status |
|---|---|---|---|
| Page load | shell LoadCurrentPage -> PageA[i].load(name) -> onPageLoadComplete: InitCodeObj(BGSCodeObj), addChild, push GridViewButton, InvalidateData | same shell (stock) | MATCHED |
| Page switch | onNewPage(i)->engine->InvalidateData; InvalidatePartialData: if CurrentPage==null -> ClearPages(unloadAndStop ALL)+LoadCurrentPage | shell-driven (stock) | MATCHED (shell) |
| Change dispatch | base onPipboyChangeEventInternal calls page.onPipboyChangeEvent ONLY if UpdateMask.Intersects(GetUpdateMask()) | our GetUpdateMask returns correct per-page mask | MATCHED |
| Register | base onAddedToStage: PipboyChangeEvent.Register(stage,...) + MobileBackButton.Register | base runs (we don't override onAddedToStage except via ADDED_TO_STAGE listener) | MATCHED |
| super.onPipboyChangeEvent | vanilla pages call super first (base handles ReadOnly via internal; the protected onPipboyChangeEvent base is empty) | our pages did NOT call super | GAP->FIXED (added; harmless-but-correct) |
| stage.focus | vanilla InvPage sets stage.focus=List_mc so the list owns keyboard | our stage KEY_DOWN listener catches keys regardless of focus | DELIBERATE-DIFF (PipList uses a stage listener, not focus) |

## Input
| Item | Vanilla | Ours | Status |
|---|---|---|---|
| List up/down | BSScrollingList attaches KEY_DOWN to STAGE -> moveSelectionUp/Down | pages now stage.addEventListener(KEY_DOWN) | MATCHED (round 10) |
| Action buttons | ProcessUserEvent named controls (XButton/R3/RShoulder/LShoulder/L3/Accept) | same | MATCHED |
| Mouse in page | BSScrollingList entries are timeline MovieClip symbols w/ buttonMode; page sets stage.focus | PipList rowHit sprites: graphics.beginFill(0,0)+buttonMode+CLICK | GAP(F4) — in game clicks don't register; 0-alpha geometry SHOULD hit-test in GFx, so cause is likely cursor/focus/mouseChildren; needs live probe. Keyboard is the working path. |

## F1 — INV category filtering
| Item | Vanilla | Ours (before) | Status |
|---|---|---|---|
| Filter | List_mc.filterer.itemFilter = DataObj.InvFilter; show item if !has filterFlag OR (filterFlag & InvFilter)!=0 | showed ALL DataObj.InvItems | GAP->FIXED |
| Per-tab mask | engine sets DataObj.InvFilter when CurrentTab changes (masks are engine-side) | n/a (we now honor InvFilter) | MATCHED |
| Sort | engine SortItemList reorders InvItems; SortText labels | we don't sort client-side (engine pre-sorts) | MATCHED |
| Selection restore | List_mc.selectedIndex = filterer.ClampIndex(InvSelectedItems[CurrentTab]) | basic (PipList clamps) | PARTIAL (index maps to original InvItems via _invMap) |
| Index semantics | selectedIndex indexes the FULL InvItems (filterer only hides display) | we map filtered->original for all BGS calls | FIXED |

## F2/F3 — live tab switch / first-open wrong content
Root-cause status: the shell path is stock and works for vanilla pages, so the gap is in how OUR pages
participate. Confirmed-applicable parity fixes this round: super.onPipboyChangeEvent + F1 index sanity.
Remaining hypotheses (need live probe with logging): (a) PipboyTabs injects into getChildAt(4)/_TabNames
and shows its own tab-content clips per CurrentPage/CurrentTab; on first open a stored PipboyTabs sub-tab
may own the slot (the "Challenges" content) until a data-change re-selects tab 0 — our pages reset
_TabNames in the constructor on every reload, which can desync PipboyTabs' injected indices. (b) The
"stacked STATUS labels" is a TESTA-ONLY artifact: our page draws its own sub-tab strip AND the stock
header renders _TabNames; the patched shell's chrome dims the header, TestA's stock shell does not.
DEFERRED to patched-shell retest (chrome present) + a logging pass.

## Per-page BGSCodeObj call surface (movie->engine) — all MATCHED to vanilla names/args
- STAT: UseStimpak/UseRadaway, PlaySound. INV: SelectItem/onInvItemSelection(idx,ItemCard.InfoObj,
  PaperDoll.selectedInfoObj,this)/updateItem3D/ExamineItem/ItemDrop(idx,count)/SetQuickkey/SortItemList(this).
  DATA: onQuestSelection/SetQuestActive/ShowQuestOnMap/ShowWorkshopOnMap/PlaySmallTransition.
  RADIO: ToggleRadioStationActiveStatus/OnScrollingStopped. MAP: now stock vanilla page (full contract).
- DELIBERATE-DIFF: we omit companion-app / quantity-menu / favorites-cross / component-view / paperdoll
  sub-UIs (documented [V2]); core item actions preserved.

## MapPage / Background
- MAP: DELIBERATE-DIFF -> ship stock Pipboy_MapPage.swf (native renderer needs MapHolder/masks/
  SelectionInfo/MarkerHolder our page can't safely reproduce). PIP-OS map styling deferred.
- Background: ship faithful Baka-structure PipboyBackgroundMenu.swf (release: omit, keep Baka's).

## Counts (this round)
MATCHED: lifecycle+input+call-surface core. GAPS CLOSED: F1 filtering(+index map), super.onPipboyChangeEvent.
DEFERRED: F2/F3 (need live probe), F4 mouse (need live probe), PIP-OS MAP styling, P-code-preserving shell.
