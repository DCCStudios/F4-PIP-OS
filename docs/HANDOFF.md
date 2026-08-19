# PIP-OS Pip-Boy — Engineering Handoff

**Last updated:** 2026-08-18, after **0.0.76**. Primary active thread: **Live 3D character** (the player model in the inventory figure slot). Secondary open bugs: **inventory item DROP**, and verification of the **right-click context menu**.

This doc is written for another agent/developer picking up mid-stream. Read this top-to-bottom once, then keep the **[Decision tree for the next test](#live-3d--decision-tree-for-the-next-test)** and **[Things NOT to do](#things-not-to-do-hard-won)** sections open while you work.

The single richest source of running history is the project memory index at
`C:\Users\rober\.claude\projects\e--Fallout-4-Modding-F4SE\memory\pipos-pipboy-state.md`
(read the top entries first — newest is authoritative over older). This handoff distills and organizes what matters; the memory file has the blow-by-blow.

---

## 1. Project at a glance

| Thing | Value |
|---|---|
| What it is | Full visual replacement of the Fallout 4 Pip-Boy menu ("PIP-BOY OS V2.7.1"), companion to **Baka Fullscreen Pip-Boy** |
| Repo root | `E:\Fallout 4 Modding\F4SE\PipOSPipboy` |
| Git remote | `https://github.com/DCCStudios/F4-PIP-OS.git`, branch **main** |
| **Runtime target** | **Fallout 4 OG 1.10.163 ONLY** (not NG/next-gen). All REL IDs below are OG. |
| commonlib (build against) | `E:\Fallout 4 Modding\F4SE\FOV Slider F4SE\lib\commonlibf4` — the **FOV-Slider fork** of CommonLibF4 |
| TF3DHUD reference source | `E:\Fallout 4 Modding\F4SE\PluginTemplate\TF3DHUD-master\src` — a **working** live-3D-character HUD mod; our north star for the Live 3D feature |
| Live game log | `%USERPROFILE%\Documents\My Games\Fallout4\F4SE\PipOSPipboy.log` (+ `.prev.log`) |
| Build tool | **xmake** (in `dll/`) |
| Current MO2 instance | `F:\Modlists\MagnumOpus` (see memory `mo2-active-instance`) |

**Two halves of the codebase:**
- **DLL** (`dll/src/*.cpp`) — F4SE plugin: page-mode bridge, native data pushes to the movie, the customization menu, and the Live 3D capture. Built with xmake → `dll\Compile\F4SE\Plugins\PipOSPipboy.dll`.
- **ActionScript SWFs** (`InterfaceSource/*.as`, `InterfaceSource/pipos/*.as`) — the actual menu pages. Built with mxmlc (Apache Flex) via `tools/build_pages.ps1`.

The mod is **fully functional without the DLL** (shell defaults every tab to the PipOS page). The DLL adds native data, the customization page, and Live 3D.

---

## 2. Build / test / package / ship workflow

### Build the DLL
```
cd "E:\Fallout 4 Modding\F4SE\PipOSPipboy\dll"; xmake
```
Output: `dll\Compile\F4SE\Plugins\PipOSPipboy.dll`. Build is ~2–6s.

### Build + gate the SWF pages (only if you touched `InterfaceSource/*.as`)
```
cd "E:\Fallout 4 Modding\F4SE\PipOSPipboy"
python tools\ctor_text_check.py      # CRASH-LAW GATE — must say "ALL PASS"
.\tools\build_pages.ps1              # mxmlc build → build\pages\*.swf + Package\Interface\
.\tools\preview_pages.ps1           # Ruffle render check — must say "ALL PAGES RENDERED CLEAN"
```

### Package a versioned test zip (the **layered** method — see the gotcha in §4)
The shipped zip must contain the pages under the **vanilla load names** (`Pipboy_*.swf`) plus transplanted art the build doesn't regenerate. The reliable recipe is: **extract the previous version's zip, overlay only what changed, re-zip.**
```powershell
$stage = "<scratchpad>\pipos_stageNN"; New-Item -ItemType Directory -Force -Path $stage | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory("$pwd\dist\PipOSPipboy-TestA-0.0.<PREV>.zip", $stage)
$core = Join-Path $stage "00 Core"
$dll = Get-ChildItem -Recurse -Filter "PipOSPipboy.dll" -Path "dll\Compile" | Select-Object -First 1
Copy-Item $dll.FullName "$core\F4SE\Plugins\PipOSPipboy.dll" -Force
# For AS changes ALSO overlay (note the RENAME to vanilla load names):
#   build\pages\PipOS_InvPage.swf   -> $core\Interface\Pipboy_InvPage.swf
#   build\pages\PipOS_StatsPage.swf -> $core\Interface\Pipboy_StatsPage.swf   (etc.)
#   build\pages\PipOS_Chrome.swf    -> $core\Interface\PipOS_Chrome.swf       (chrome keeps its name)
.\tools\make_fomod_zip.ps1 -PayloadDir $core -Version "0.0.NN" -OutZip "dist\PipOSPipboy-TestA-0.0.NN.zip"
```
`make_fomod_zip.ps1` wraps `00 Core` + a generated `fomod/` (MO2 reads `<Version>`). **DLL-only rounds** just overlay the DLL; leave the SWFs from the prior zip untouched.

### Commit + push
```
git add -A
git commit -F "<scratchpad>\commitmsgNN.txt"   # USE -F: inline -m with quotes breaks PowerShell arg passing
git push origin main
```
End commit bodies with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

### Read the game log after a test
The current session writes `PipOSPipboy.log`; `main.cpp` pre-rotates the previous session to `.prev.log` on each launch, with `flush_on(trace)` so nothing is lost. **Check timestamps** — the freshest file is the one the user just tested. Handy filters:
```powershell
$f = "$env:USERPROFILE\Documents\My Games\Fallout4\F4SE\PipOSPipboy.log"
Select-String -Path $f -Pattern "\[3D\]" | Select-Object -Last 20 | % { $_.Line }
```

---

## 3. Things NOT to do (hard-won)

1. **Do NOT switch the Live 3D display quad to `HUDGlassFlat:0`.** 0.0.69 tried mirroring the vanilla item preview's quad name → log said `clipRect skipped: display geometry not ready`, the quad was never created, nothing composited. The engine auto-creates a screen-attached display quad **only for the `ModMenuRenderMesh:0` name** for third-party renderers; `HUDGlassFlat` is a NIF the *Pip-Boy machinery* attaches to *its own* renderer. **Keep `ModMenuRenderMesh:0`.**
2. **Do NOT use `PostEffect kModMenu` on our OWN renderer.** Its deferred composite samples per-tile light lists that are never populated in an offscreen menu render → geometry contributes zero pixels. **Use `kHUDGlass`** (forward composite, no tile dependency). This is why the vanilla item preview works with zero hooks.
3. **Do NOT call `Inventory3DManager::Begin3D()` on an idle manager.** It can deref the null `itemBase`/`tempRef` of an idle manager = main-thread AV. (Removed in the 0.0.72 audit.) The `PipboyScreenModel` renderer already exists at idle in practice — the log shows `enabled=true` without an item selected — so you don't need Begin3D anyway.
4. **Do NOT `Release()` / `End3D()` / `Disable()` the vanilla `PipboyScreenModel` renderer.** The engine owns it. We only **borrow its offscreen slot** (`Offscreen_Set3D`) and do a **tracked symmetric enable** (enable only while our clone occupies the slot; restore the prior disabled state on teardown; see `g_weEnabledVanilla`, `g_usingVanilla`).
5. **Do NOT hand-build `loadedModels` (`BSTArray<LoadedInventoryModel>`) entries.** `LoadedInventoryModel` is exe-internal (forward-declared only); the async `NewInventoryMenuItemLoadTask` would clobber a hand-built entry. That path is a dead end.
6. **Do NOT write pose to `node->SetLocalTransform()` for flattened bones.** The engine's flattened-tree world update walks `BSFlattenedBoneTree::bone[].local` (a raw heap array) and **ignores** node locals for cache efficiency. Write `bone[].local` **directly** (see `CopyFlattenedPose`).
7. **Do NOT point a skin's `worldTransforms[i]` at `node->world` for flattened bones.** Use `&FlattenedBone::world` (the array entry the engine maintains). Node worlds on a flattened skeleton may never be written. (Fixed in 0.0.76.)
8. **Do NOT overwrite the user's `PipOSPipboy.ini`.** In-game customization saves go to `PipOSPipboy_User.ini` (never shipped in the FOMOD; parsed **after** the main ini as an override). A shipped ini would wipe saves on every install (this actually happened pre-0.0.59). Never write diagnostics/red-RT test values to any ini.
9. **Do NOT trust the IDE (clangd) diagnostics.** They constantly show bogus errors (`'F4SE/F4SE.h' file not found`, `std has no string_view`, `RE has no NiAVObject`, `Scaleform undeclared`, etc.) because clangd's include paths are wrong for this project. **xmake is the only arbiter.** Ignore the red squiggles; build to check.
10. **Do NOT ship the red-RT diagnostic.** The 0.0.66 test (`Offscreen_SetClearRenderTarget(true)` + red `Offscreen_SetBackgroundColor`) was a temporary bisection tool; it also **leaked into the vanilla preview's shared render target** (turned the native item-examine view fully red). It's already reverted; don't reintroduce it into a shipping build.
11. **Do NOT run scene-graph / Interface3D / D3D / NiAVObject::Update off the main thread.** The `RunActorUpdates` hook fires on **worker threads >1×/frame**; it only does atomic reads + schedules an F4SE task. All mutation happens in `RunCaptureTask`→`Tick` on the main thread. Keep that discipline for anything you add.

---

## 4. The packaging gotcha (read once, save yourself an hour)

`Package\Interface\` holds our built SWFs named `PipOS_*.swf`, but the **shipped FOMOD zip must rename them to the vanilla load names** the shell requests: `Pipboy_StatsPage.swf`, `Pipboy_InvPage.swf`, `Pipboy_DataPage.swf`, `Pipboy_RadioPage.swf`, `Pipboy_MapPage.swf`. The zip **also** needs, unchanged from the shipped base:
- `PipboyMenu.swf` (the shell copy, 41KB),
- `Pipboy_MapPage.swf` (a **transplanted** 93KB art build — NOT regenerated by `build_pages.ps1`),
- `PipboyBackgroundMenu.swf` (the **transplanted** 27KB build — the `build_pages.ps1` output is a 1.3KB untransplanted version; do NOT ship that one),
- `PipOS_Chrome.swf` (keeps its own name).

Because of this, the reliable packaging method is **§2's layered extract-overlay-rezip**, seeding from the previous version's zip so all the transplanted art carries forward. `tools/package.ps1` exists but does the rename incompletely; the manual layering is what's been used since ~0.0.58.

---

## 5. Live 3D — the whole story

### Goal
Render a live, rotatable capture of the **player's equipped character** into the Pip-Boy inventory figure slot (behind the CRT UI), instead of the vector Vault Boy. Toggle: `bLive3D` in the customization page (default OFF), applies on next Pip-Boy open. The AS side hides the Vault Boy when `root1.PipOS_char3d.available == true`.

### Mechanism (current, 0.0.76)
A `RunActorUpdates` `write_call<5>` hook (`REL::ID(556439)+0x17`) fires on worker threads and schedules `RunCaptureTask` as an F4SE main-thread task. `Tick()` then, **vanilla-renderer-first**:
1. `AcquireVanillaRenderer()` — resolves `PipboyManager::GetSingleton()->inv3DModelManager.str3DRendererName` (`"PipboyScreenModel"`) → `Interface3D::Renderer::GetByName`. This is the engine's own item-preview renderer — **field-proven to composite 3D over this exact fullscreen menu** (it draws the floating weapon when you select an item).
2. Clone the player: `CloneSubtree(player->Get3D(false))` (kCopyExact; controllers detached during clone, restored on source, cleared on clone).
3. `SanitizeClone(clone, source)` — the fix pipeline (see §6).
4. `FrameClone(clone, /*distanceCap*/80)` — scale/yaw/translate to center the framing target at the offscreen origin (cap 80 because the item camera is short-range).
5. `Offscreen_Set3D(clone)` onto the vanilla renderer, add an offscreen light, tracked-enable, log a pose probe.
Own-renderer path (`ConfigureRenderer`/`BuildPreview`/`AttachToRenderer`) is the **fallback** if the vanilla renderer can't be resolved.

### The diagnostic arc (why each version exists)
Two independent bugs were crossed for most of this, which is why it took so long:

| Ver | Change | Result / lesson |
|---|---|---|
| 0.0.58–0.0.64 | fade-node repair (`RepairShaderFadeNodes`) | Cloned geometry's `BSShaderProperty::fadeNode` back-pointer isn't remapped by clone → deferred path drops draw passes. Fixed; **necessary but not sufficient.** |
| 0.0.60 | depth `kStandard3DModel(7)` → `kTerminal(9)` | WRONG (my error, chasing the fade bug). The engine doesn't composite depth 9 under the Pip-Boy. Reverted 0.0.67. |
| 0.0.66 | **red-RT bisection** | Red block composited on screen → **the compositing path works; the model is what's missing.** Also leaked into the vanilla preview's shared RT. |
| 0.0.67 | depth → `kMessage(15)` + `alwaysRenderWhenEnabled` | `[3DDIAG]` dump proved vanilla `PipboyScreenModel` composites at **depth 15**. |
| 0.0.68 | right-click via UI input hook; `[3DDIAG]` renderer diff | Got the vanilla renderer's exact config (see below). |
| 0.0.69 | mirror vanilla quad (`HUDGlassFlat`) | Broke it — quad never created (see NOT-to-do #1). |
| 0.0.70 | `ModMenuRenderMesh` quad @ depth 15 | Proven quad + proven depth; still nothing → model, not compositing. |
| 0.0.71 | `kModMenu` → `kHUDGlass` | Forward composite (dodges tiled-lighting geometry drop). Still nothing on its own. |
| 0.0.72 | **borrow the vanilla renderer** (Plan A.2) | Clone attached to the PROVEN, enabled `PipboyScreenModel` and **still invisible** ⇒ **the fault is the CLONE**, not any renderer. |
| 0.0.73 | rebind skin instances to clone skeleton + `CreateBoneMap` | Skinned meshes skin against the **source player's live skeleton** (raw pointers not remapped). Rebind by name. `102 bound / 229 unresolved`. |
| 0.0.74 | whole-tree name fallback for the 229 | `0 via whole-tree` — the 229 aren't elsewhere; they're **null slots**. |
| 0.0.75 | 4-agent consensus batch: pose copy, alpha restore, segment enable, vanilla-path lights, bhkWorld strip, pose probe | **Pose probe: `Chest world=(-0.0, 50.0, 0.0)`** = clone's flattened tree updates, pose sits exactly at the framed origin ⇒ **pose/framing/tree-update all GOOD.** Still invisible. |
| 0.0.76 | **null skin-bone recovery by pointer identity** | The 229 null slots' stale `worldTransforms[i]` still point into the SOURCE skeleton's bone array → identify the bone by pointer, rebind to the clone's same bone; unrecoverable → NULL the pointer (was: ~70% of the palette sampling the player's world position, shredding the mesh across thousands of units). **← awaiting test result.** |

### `[3DDIAG]` ground truth (the two renderers side by side)
```
VANILLA PipboyScreenModel: depth=15 postfx=2(kHUDGlass) geom=HUDGlassFlat:0
    mat=Materials\Interface\HUDGlassFlat.BGEM mask=HUDShadowFlat:0
    fullPremult=false hideWhenDisabled=true longRange=false offLights=0 alwaysRender=true customRT=-1
OURS  PipOS_Char3D (0.0.71+): depth=15 postfx=2(kHUDGlass) geom=ModMenuRenderMesh:0
    fullPremult=false hideWhenDisabled=true longRange=true(deliberate)  customRT=-1
```
We deliberately keep `ModMenuRenderMesh:0` (NOT-to-do #1) and `longRange=true` (our character sits ~80 units out; the item camera is short-range). Everything else mirrors vanilla.

### The pose-probe fact that matters most
`Chest world=(-0.0, 50.0, 0.0)` in the 0.0.75 log is *decisive*: it means (a) the cloned `BSFlattenedBoneTree` DOES update its bone worlds via `root.Update()`, and (b) framing lands the body at the origin as intended. So **do not** re-chase "the pose is wrong / the tree doesn't update / the model is off-camera." Those are settled. The remaining variable in 0.0.76 was the **skin binding** (the 229 null slots).

---

## 6. Current `CharacterCapture.cpp` map

Anonymous-namespace functions (line numbers as of 0.0.76; they drift — grep by name):

| Function | Role |
|---|---|
| `ForEachAVObject` | recursive NiAVObject visitor (the workhorse) |
| `FindFlattenedBoneTree` | locate the `BSFlattenedBoneTree` in a subtree |
| `FindFlattenedBoneByName` | linear search of `tree->bone[]` by name |
| `TryGetFramingTargetWorld` | framing-target bone world (Head/Chest/Pelvis/Root) |
| `CloneSubtree` | `NiCloningProcess` kCopyExact of the source, controllers detached/restored |
| `RepairShaderFadeNodes` | re-own each geometry's `BSShaderProperty::fadeNode` to the clone (0.0.64) |
| `EngineCreateBoneMap` | `REL::ID(1131947)` — rebuild flattened tree's node ptrs + name hash after clone |
| `EngineEnableAllSegments` | `REL::ID(246125)` — force-enable dismember segments |
| `RestoreShaderAlpha` | force `BSShaderProperty::alpha<=0 → 1` (transparent-material guard) |
| `CopyFlattenedPose` | copy SOURCE `bone[].local` → clone array by name (0.0.75) |
| `LogPoseProbe` | log Chest/Root/COM world at attach (telemetry) |
| `FindNodeByNameRecursive` | whole-clone-tree name search (0.0.74 fallback) |
| `RebindClonedSkins` | **the skin fix** — `CreateBoneMap`, shared-skin guard, per-bone rebind (flattened-array world first, then whole-tree), **null-slot recovery by pointer identity (0.0.76)** |
| `SanitizeClone` | orchestrates the fix pipeline (see below) |
| `FrameClone` | scale/yaw/translate framing (opt `a_distanceCap`) |
| `ApplyIdle` | per-pass breathing wobble + `root.Update()` |
| `ConfigureRenderer` | build OUR renderer (fallback path): kHUDGlass, depth 15, ModMenu quad |
| `ApplyDisplayClipRect` / `EnsureDisplayRoot` | reshape the screen-attached quad to the figure window |
| `AttachToRenderer` | own-path attach: display root, `Offscreen_Set3D`, lights |
| `BuildPreview` | own-path clone→sanitize→frame→attach |
| `AcquireVanillaRenderer` | resolve `PipboyScreenModel` (no Begin3D) |
| `HideAndRelease` | teardown: return borrowed slot, restore enable, drop clone |
| `Tick` | the per-pass driver (vanilla-first, own fallback) |
| `DumpOneRenderer`/`DumpRendererDiag` | `[3DDIAG]` one-time renderer config dump |
| `RunCaptureTask` | main-thread task body (calls Tick, `PushContract` on availability flip) |
| `HookedRunActorUpdates` | worker-thread hook: atomics + schedule only |
| `PushContract`/`SchedulePushContract`/`RegisterContractSink` | `root1.PipOS_char3d` contract to AS |

**`SanitizeClone` order (all before the single flush `root.Update`):** `RepairShaderFadeNodes` → `bhkWorld::RemoveObjects` → `CopyFlattenedPose` → `RestoreShaderAlpha` → `EnableAllSegments` (per geometry) → `RebindClonedSkins` → `root.Update()`. This mirrors TF3DHUD's "all structural fixups precede the final Update" ordering.

`RE_BSSkin.h` in `dll/src/` is a **copied, offset-asserted** `BSSkin::Instance` layout from TF3DHUD (the FOV-Slider fork only forward-declares it). Verified for 1.10.163 (sizeof 0xC0; `bones`@0x10, `worldTransforms`@0x28, `boneData`@0x40, `rootNode`@0x48, `paletteStamp`@0xBC).

---

## 7. Live 3D — decision tree for the next test

After the user tests **0.0.76**, read the log line:
```
[PipOS][3D] skin rebind: N bones rebound (T via whole-tree, F null-slots recovered by pointer identity, D null-slots dropped) across G geometries (S shared skipped, U unresolved)
```
and whether a character appears.

- **Character appears (even distorted/wrong-lit/wrong-size)** → **the chain is CLOSED.** Everything remaining is tuning via the in-game **Figure placement sliders** (Char3DScale / Char3DDistance / Char3DTarget / clip window) — these apply on the next Pip-Boy open, no rebuild. Then polish: lighting intensity, framing, the breathing idle. **This is the win condition.**
- **`F ≈ 229` but distorted/partial body** → the same-index shortcut in the pointer-identity recovery mis-mapped some bones. Change `RebindClonedSkins`'s null-recovery to **name-only** mapping (drop the `k < flattened->boneCount` same-index assumption; always resolve via `FindFlattenedBoneByName` on the source bone's name).
- **`F ≈ 0` (pointer identity matched nothing)** → the stale `worldTransforms` pointers don't aim into the source `BSFlattenedBoneTree::bone[].world` array. Next: also pointer-match against **source NODE `->world`** addresses via a recursive walk of `a_source`, and/or dump a few sample `worldTransforms[i]` addresses next to the source tree's bone-array range to see where they actually point.
- **Still nothing with F≈229 and no distortion** → pose/framing/skin are all correct and it *still* won't draw ⇒ escalate to the **banked endgame (§8): full fresh-skeleton construction.** All four deep-dive agents concluded a whole-root clone is the fragile approach precisely here; TF3DHUD never clones the live actor root.

Always confirm the supporting lines each pass: `pose copy: N` (>0), `pose probe: Chest world=(~0, ~+distance, ~0)`, `shader alpha: N`, `segments: N`, `clone attached to vanilla renderer 'PipboyScreenModel' (enabled=true) + offscreen light configured`.

---

## 8. Banked endgame — full fresh-skeleton construction (if 0.0.76 + name-only don't yield pixels)

This is TF3DHUD's actual recipe (from the deep-dive sweep, agent "construction pipeline" §5). It abandons the whole-root clone and **builds** the preview. Ordered steps with TF3DHUD `Previewer.cpp` refs and OG REL IDs:

1. **Fresh skeleton** — compute `race.skeletonModel[sex]` path (`GetRaceSkeletonModelPath`, `Previewer.cpp:971-984`) → `RE::BSModelDB::Demand(path, loadLevel=3,…)` (`1049-1063`) → clone via a seeded clone.
2. **Flatten** — `g_getActorBodyPart3D(player, root, &kRoot, false)` (`GetActorBodyPart3D` = **157573**) → `g_convertNodeTree(target)` (`ConvertNodeTree` = **633230**) → `CreateBoneMap(root)` (**1131947**, already used) → `FindFlattenedBoneTree` → `CreateBoneMap(flattened)`. (`986-1024`)
3. **Detach/prepare** — `bhkWorld::RemoveObjects(root,true,true)`, `StripControllerChains`, `PreparePreviewTree`.
4. **Per-part body/armor** (`SyncEquipmentsFromBiped`, `1934-2115`) — for each biped slot, clone `biped.object[i].partClone` **with `SeedSkinCloneMappings`** (`PreviewClone.cpp:57-104`): pre-seed `cloneProcess.cloneMap` with `skin->rootNode → previewRoot` and every `sourceBone → previewNode-by-name`, so the cloned armor **shares the fresh skeleton's real bones with zero rebind gaps** (this is why TF3DHUD never has our 229-null problem). Resolve parent (`FindPreviewAttachParent`, `805`), `AttachChild`, strip, `ResolveNullSkinBonesFromFlattenedTree` (`1296`), `MergeAttachmentSkinBones` (`1365`), `RebindSkinInstance` (`1758`).
5. **Default-skin fallback biped** for mask-excluded slots (naked/underwear body): `GetSkin` (**1042540**), `ArmorAddonUseModel` (**976291**).
6. **Segment reset** — `RestoreDisabledSlotVisibility` / `ApplyBipedSkinPartsVisibility` (`PreviewHeadParts.cpp:227,353`).
7. **Body tint + alpha** — `CalculateBodyTintColor` (**134537**), `UpdateBodyTintColorsOnScene` (**49935**), `RestorePreviewShaderAlpha`.
8. **Final rebind** (`RebindPreviewSkinInstances`, `1813`) → **sanitize** (`SanitizePreviewRenderTree`, `PreviewRenderTree.cpp:140`) → **frame** → `PrepareForInterface3DOffscreen` (`PreviewRenderTree.cpp:81`).

Optional fidelity (defer): head (`FixFaceGenHeadSkinInstances` **1131949**, `ResetFaceGenCurrentMorphs` **1174798**, `GetNPCHeadPart` **946253**, `GetDefaultRaceHeadPart` **1120148**); OMOD visuals (`TryAttachMod3DRecurse` **832528**); cloth (`CreateClothFor3D` **1322043**, `SetClothWorld` **19064**, `SetClothSettleOnTransitionToSim` **638869**); segments (`GetNumSegments` **331465**, `SetSegmentDisableCount` **1227683**, `EnableSegment` **1134184**, `DisableSegment` **1466142**).

This is a big round — do it via an **implementation subagent + adversarial audit** (see §11). It's fully scoped; no more investigation needed to start.

**Ruled out by the sweep (don't waste time here):** per-frame animation graph (our clone carries a valid captured pose — NOT required for a first frame); the render-boundary commit hook (`RenderPrepassesAndMenus`) is LOW for the vanilla path (the engine self-commits `offscreenElement`); cloth (cosmetic — static mesh renders without sim); Morph (cosmetic body sliders); the tiled-lighting hooks (structurally can't fire for the vanilla/kHUDGlass path).

---

## 9. TF3DHUD reference map (file:line, OG-relevant)

```
Previewer.cpp
  RebuildPreview .......................... 2239-2321   (once-per-build pipeline)
  LoadPreviewRaceSkeleton ................. 1026-1086
  ConvertPreviewSkeletonToFlattenedTree ... 986-1024
  RefreshPreviewBoneLookup (CreateBoneMap) 1251-1263
  ResolveNullSkinBonesFromFlattenedTree ... 1296-1348  (← ported in 0.0.76)
  RefreshSkinWorldTransformsFromBones ..... 1350-1362
  MergeAttachmentSkinBones ................ 1365-1438
  RebindSkinInstance ...................... 1758-1796  (← model for RebindClonedSkins)
  RebindPreviewSkinInstances .............. 1813-1852  (whole-tree final rebind + sourceSkins guard)
  SyncEquipmentsFromBiped ................. 1934-2115  (per-part body build)
  EnsurePreviewHead ....................... 2159-2228
  ApplyPreviewBodyTint .................... 2230-2237
  CommitRenderState / Impl ................ 2420-2580  (render-boundary; per-frame tail 2564-2579)
PreviewClone.cpp
  SeedSkinCloneMappings ................... 57-104     (the fresh-skeleton "no rebind gaps" trick)
PreviewRenderTree.cpp
  RepairShaderFadeNodes ................... 39-66      (← ported)
  PrepareForInterface3DOffscreen .......... 81-113
  SanitizePreviewRenderTree ............... 140-167    (selective cull: missing-material + NeckGore)
  RestorePreviewShaderAlpha ............... 169-183    (← ported in 0.0.75)
PreviewHeadParts.cpp
  EnableAllSegments ....................... 323-330    (← ported in 0.0.75)
  ApplyBipedSkinPartsVisibility ........... 227-259
  RestoreDisabledSlotVisibility ........... 353-385
Renderer.cpp
  ConfigureImpl ........................... 519-579
  AttachPreviewRoot ....................... 744-759
  ApplyRendererFOV ........................ 276-289
  ApplyDisplayPlacement ................... 458-517
Hooks.cpp
  InstallHooks ............................ 282-324
  HookedRunActorUpdates ................... 130-       (← we use the same call site)
  HookedRenderPrepassesAndMenus ........... 225-234    (render-boundary commit; not ported)
  HookedRenderSceneDeferred / CompositePassCtor 161-223 (tiled-lighting; N/A for kHUDGlass)
Lights.cpp
  ConfigureOffscreenLights ................ 267-286
  ResolveDirectionalLight ................. 161-179    (early-returns interior!)
Animations.cpp
  UpdateAnimationGraphManagerFloat ........ ~3805      (the per-frame pose writer; NOT needed for first pixel)
  SetAnimationGraphTarget ................. ~1819-1830
Address.cpp
  CreateBoneMap ........................... 102
src/RE/BSSkin.h ........................... (source of our RE_BSSkin.h)
```

---

## 10. Engine / commonlib reference

**Key commonlib headers** (`E:\Fallout 4 Modding\F4SE\FOV Slider F4SE\lib\commonlibf4\include\RE\`):
- `I/Interface3D.h` — the `Renderer` (all `Offscreen_*` / `MainScreen_*`, fields: `enabled@04C`, `alwaysRenderWhenEnabled@055`, `depth@074`, `offscreenElement@088`, `offscreenLights@1E0`, cameras `pipboyAspect/nativeAspect/nativeAspectLongRange@1A8-1B8`). **Note `Enable(bool a_unhideGeometries=false)`** — the bool is "also unhide geometries", NOT an on/off flag; `Enable()` turns the renderer on. Passing `false` is correct.
- `P/PipboyManager.h` — `GetSingleton`; `inv3DModelManager` (Inventory3DManager) @040.
- `I/Inventory3DManager.h` — `str3DRendererName@0C0`; `Begin3D`/`End3D`/`ClearModel`/etc. (REL VariantIDs in the header). **`LoadedInventoryModel` is only forward-declared** (exe-internal).
- `B/BSFlattenedBoneTree.h` — `FlattenedBone{ NiTransform local; NiTransform world; i16 parent/child/childCount/sibling; NiPointer<NiNode> node; BSFixedString name; }` (0xA0); tree has `boneCount`, `FlattenedBone* bone`, `BSTHashMap boneMap`.
- `B/BSGeometry.h` — `skinInstance@140`; virtual `GetSegmentData()` (vtable 3B).
- `B/BSShaderProperty.h` — `fadeNode@48`, `alpha@28`. `B/BSLightingShaderProperty.h` derives it.
- `B/bhkWorld.h` — `static RemoveObjects(NiAVObject*, bool recurse, bool force)`.
- `A/Actor.h` — `DropObject(...)` vtable **0EB** (native drop fallback candidate).
- `B/BSInputEventReceiver.h`, `B/ButtonEvent.h`, `I/IDEvent.h`, `U/UI.h` (`VTABLE::UI[0]` = `PerformInputProcessing`).

**REL IDs currently USED in our DLL:** `556439` (RunActorUpdates call site), `1131947` (CreateBoneMap), `1417022` (ForceUpgradeTextures), `246125` (EnableAllSegments).

**Cached vanilla/PBT decompiles** (scratchpad, for the AS side): `as_vanilla_inv`, `as_vanilla_menu`, `as_vanilla_DataPage/RadioPage/MapPage`, `pbt_decomp`, `shell_vanilla_decomp`. ffdec at `E:\Fallout 4 Modding\F4SE\PluginTemplate\jpexs-gui\ffdec.jar`. (Scratchpad root: `C:\Users\rober\AppData\Local\Temp\claude\e--Fallout-4-Modding-F4SE\800cd7d8-599e-4ebe-940c-b0690f31f037\scratchpad`.)

---

## 11. Subagent workflow (what worked)

The Live 3D breakthroughs came from **read-only investigation subagents** (opus, backgrounded) with tightly scoped prompts against BOTH codebases, followed by an **adversarial audit subagent** before shipping anything structural. This pattern repeatedly caught fatal issues:
- The audit of the skin-rebind (0.0.73) returned **DON'T SHIP** and caught (a) the clone's flattened tree needing its own `CreateBoneMap`, and (b) a live-player-corruption path (shared skin instances) — both fixed pre-ship.
- The 4-agent parallel sweep of all of TF3DHUD **cross-validated** findings: two agents independently fingering the flattened bone array, two the shader alpha; and one agent's "commit hook" theory was *demoted* by another's stronger analysis, saving the most expensive port.

Recommended: for the endgame (§8) or any clone-pipeline change, spawn one implementation-plan agent + one adversarial audit agent. Give them exact file paths, the current symptom, the relevant log lines, and "cite file:line; say 'unknown-exe-internal' where headers don't expose it." Do NOT let an agent guess REL IDs — have it read `Address.cpp`.

---

## 12. Other open bugs (not Live 3D)

### Inventory DROP — STILL BROKEN
Pressing R (or the context-menu Drop) plays a select sound but doesn't drop. Diagnostics are **armed** in the current build:
- `onKey` logs `IV.rK` when R (keyCode 82) reaches the handler; `doDrop` logs `IV.d<idx>` pre-guard (shows folder-header `-1` too).
- `doDrop` writes `root1.PipOS_droplog = "<seq>|list=<displayIdx>|inv=<invIdx>|cnt|fav|eq|fid=<unsignedFormID>|<name>"`; the DLL logs it as `[DROP] ...` (bypasses the AS life-trail's 700-char cap that was eating `IV.dr` marks).
Read those on the next test. **Hypothesis:** the engine's `ItemDrop` wants the **display index** (`this._list.selectedIndex`) not the InvItems index (`invIdx`) we currently pass — vanilla passes `List_mc.selectedIndex`; OR it reads the vanilla `List_mc` we don't populate. If the engine call is genuinely inert, **fallback: native `Actor::DropObject`** (vtable 0EB) on the player, using the formID already in the `[DROP]` line (the AS `fidKey()` gives the canonical unsigned form).
Note: engine inventory calls use `uint()`-normalized signed formIDs — the engine hands AS a **signed** formID (high-bit forms read negative); `PipOS_InvPage.as::fidKey()` converts to unsigned. That fixed the weapon-stats join (0.0.63); the same signedness may matter for any formID-keyed engine call.

### Right-click context menu — should WORK, verify
GFx never delivers `RIGHT_MOUSE_DOWN` to the movie, and `GetAsyncKeyState` is blind to the RMB under FO4 raw input (both field-proven). So right-click is forwarded via a **vfunc hook on `UI::PerformInputProcessing`** (`VTABLE::UI[0]`, `write_vfunc(0)`) that watches for a mouse `ButtonEvent` `idCode==1` `QJustPressed` while the Pip-Boy is open and bumps `root1.PipOS_rclickN`. AS `onCharPoll` reads the counter and opens the menu at the row under the cursor (position-based `PipList.rowAtMouse()`, since hover goes stale). Menu actions dispatch **by coordinates** in a capture-phase stage handler. Log lines: `[RC] right-button press seen in UI input chain`, `[RC] SetVariable root1.PipOS_rclickN=N ok=true`, trail `IV.rc`, `CX.<act>`. This worked in the 0.0.68 test; re-verify after the churn.

### Recently FIXED (don't re-open)
Weapon stats "DAMAGE 17 / ACC 0" (0.0.60 `TESBoundObject::ApplyMods` instance data + 0.0.63 signed-formID `fidKey`); equipped indicator; apparel +/- color coding; STATUS/DATA blank-on-re-entry (medic always pumps a data event after a heal); vanilla keybar (removed + `BottomBar_mc` hidden); transparency (`SetBackgroundAlpha(0)` on both pipboy movies); user-ini settings persistence.

---

## 13. Broader project state (context)

Pages STAT/INV/DATA/RADIO/MAP are implemented and rendering; the **Shell Medic** (in `Chrome.as`) works around a vanilla shell wedge where a page loads but never stages (heals by `addChild` + a substitute `PipboyChangeEvent` pump). The **crash law** governs all AS: never create a `TextField` or write geometry on interaction/tick/data paths — pool everything and only update text/visibility/graphics; `tools/ctor_text_check.py` enforces it. `pipos/PipList.as` is the shared list widget; `pipos/Theme.as` the palette/helpers; `pipos/Chrome.as` the CRT overlay + medic. Backlog (non-blocking): legendary-marker polish, open-anim speed already added, Map page round, Misc-objective tracking, QA real icons. See the memory file for the full feature history and the FunctionalitySpec/DESIGN.md ("every UI element has purpose").

---

## 14. Quick start for the continuing agent

1. Read the top of `…\memory\pipos-pipboy-state.md` (0.0.76 entry) and this doc's §5, §7, §12.
2. Ask the user to install **0.0.76** (`dist\PipOSPipboy-TestA-0.0.76.zip`), enable Live 3D, open the Pip-Boy, and send the log.
3. Grep the log for `\[3D\]`, `\[RC\]`, `\[DROP\]`. Apply the §7 decision tree for Live 3D; read `[DROP]` for the drop bug.
4. Build → gate (if AS) → package (§2 layered) → commit `-F` → push. Update the memory file's top entry each round.
