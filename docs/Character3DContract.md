# PIP-OS Live 3D Character - DLL <-> AS3 Capture Contract

Status: DLL side implemented (gated, default OFF). AS3 wiring is a LATER round. This file defines the
contract that later round consumes so it has a fixed target.

Source of the technique: `PluginTemplate/TF3DHUD-master` (live equipped-player capture). Implemented in
`dll/src/CharacterCapture.cpp`.

## What the DLL does (when enabled)

When `[Character] bLive3D=true` (see below), the DLL:

1. Installs a single frame hook (`RunActorUpdates`, `REL::ID(556439)+0x17`, OG 1.10.163) - the same hook
   point Full Body Awareness uses with this CommonLibF4 fork.
2. Creates a named offscreen 3D renderer `RE::Interface3D::Renderer` called **`PipOS_Char3D`** (the vanilla
   workbench / container 3D-preview subsystem).
3. While the Pip-Boy menu is open, clones the player's third-person biped root into that renderer's offscreen
   scene, frames + lights it, and plays a subtle procedural breathing idle. The clone carries the player's
   CURRENT worn armor / apparel / baked body morphs and the equipped weapon (the weapon is a biped object on
   the cloned root). The offscreen render target is composited to screen via a screen-attached display mesh
   (`Interface/GunModMenu/ModMenuRenderMesh.nif`, geometry `ModMenuRenderMesh:0`).
4. Rebuilds the clone on each Pip-Boy open (captures equipment worn at that open) and releases it on close.

Everything scene/renderer/D3D related runs on the game MAIN thread, is null-guarded at every step, and
disables the feature for the session on any failure (falling back to the placeholder). It never hard-crashes
by design (null-guards + main-thread-task affinity; `catch(...)` is NOT relied on for AV safety).

### Threading model (0.0.25 audit fix)

The `RunActorUpdates` hook (`REL::ID(556439)+0x17`) is NOT reliably the main thread on this fork: it fires
more than once per frame on BSMTAManager / HighFPSPhysics worker threads. Running scene-graph + D3D mutation
there (clone/attach/idle/teardown) is this project's worst crash class. So:

- The hook body does ONLY cheap atomic reads and SCHEDULES the whole build/attach/idle/teardown pass onto the
  main thread via `F4SE::GetTaskInterface()->AddTask`. It touches no scene graph, no D3D, no UI menu map.
- A "task in flight" atomic collapses the worker-thread multiplicity so N hook fires never queue N clones.
  F4SE tasks drain serially on the main thread, so exactly one capture pass runs at a time.
- Pip-Boy open/close is tracked by the `MenuOpenCloseEvent` sink (fires on the UI/main thread) into an atomic
  the hook reads, so the hook never inspects the UI menu map off-thread.
- Menu-close teardown (`HideAndRelease`) is itself scheduled via `AddTask`, so renderer/D3D lifecycle
  (Disable / `Offscreen_Set3D(nullptr)` / NiPointer release) is main-thread only.

The re-clone guard (`!g_previewRoot || g_dirty || g_sourceRoot != source`) is unchanged; it is now evaluated
and acted on inside the main-thread task.

## The AS3-visible contract

On every Pip-Boy open, the DLL pushes a dynamic member onto the movie root (same idiom as
`PipboyBridge.PushEquipmentNow`, via a deferred UI task):

```
root1.PipOS_char3d = {
    active   : Boolean,   // true => the DLL live-3D path is installed this session
    available: Boolean,   // true => an offscreen player clone is currently live/rendering
    renderer : String     // "PipOS_Char3D" - the Interface3D renderer name (AS3 wiring key)
}
```

If the member is absent (feature off or DLL not present), the AS3 figure slot MUST fall back to the vanilla
ConditionBoy Vault Boy composite - exactly as it does today (see `docs/ScaleformContract.md` section (e)).

`available` re-push timing (0.0.25): the DLL pushes this member on open with `available:false` (the clone is
built one main-thread task later, not synchronously on open), then RE-PUSHES it with `available:true` the
moment the offscreen clone actually goes live in the capture task, and again with `available:false` when the
clone is released on close. So AS3 can poll `root1.PipOS_char3d.available` (or re-read it after a short delay)
to learn exactly when the capture is ready, and must never treat a transient `available:false` as permanent
while `active` is true. A false `available` is never left set when the clone succeeds, and never set true when
the build failed.

Log tag for the whole feature: `[PipOS][3D]`.

## The DLL<->engine boundary the later AS3 round still needs to resolve

FO4 Scaleform cannot sample an arbitrary D3D render target directly; TF3DHUD (and this port) do NOT feed a
texture into the GFx movie. Instead the offscreen render is composited to the HUD by the engine through the
**screen-attached display mesh**, positioned in 3D screen space - NOT inside a Scaleform display-object slot.

So the later round has two options for placing the figure in the INV/STAT slot, both DLL-assisted:

- **(A) Screen-space alignment (matches TF3DHUD).** The DLL positions the screen-attached display mesh (via
  the renderer's `pipboyAspect`/`nativeAspect` camera frustum + an anchor/offset) so it lands over the SWF
  figure slot's on-screen rectangle. The AS3 side communicates the target rect (in movie units) to the DLL;
  the DLL maps it to the display-mesh clip rect. TF3DHUD's `Renderer.cpp` `ApplyDisplayClipRectImpl` /
  `ApplyDisplayPlacement` are the reference (the clip-rect vertex-buffer reshaping is NOT yet ported here -
  the full display mesh is used for now).
- **(B) Pip-Boy post-effect route.** Reconfigure the renderer's `Offscreen_SetPostEffect` /
  `OffscreenMenuSize` to the Pip-Boy sizing and let the existing Pip-Boy compositor place it. Requires more
  engine reverse-engineering than TF3DHUD provides.

Recommendation for the next round: option (A). The DLL already owns the renderer and the display mesh; wiring
the SWF-slot rect -> display-mesh placement is a bounded addition. Expose the target rect from AS3 (e.g. a
`root1.PipOS_char3d_rect = {x,y,w,h}` the DLL reads in its frame tick) and port
`ApplyDisplayClipRectImpl` to reshape the quad.

## Config

`Data/F4SE/Plugins/PipOSPipboy.ini`:

```
[Character]
bLive3D=false      ; DEFAULT OFF. true => install the live-3D hook + renderer.
Char3DFov=70.0     ; optional, offscreen camera FOV
Char3DScale=0.45   ; optional, model scale in the offscreen frame
Char3DYaw=160.0    ; optional, model yaw (degrees)
```

When `bLive3D=false` (default), `CharacterCapture::Install()` returns immediately: NO trampoline is
allocated, NO engine hooks are installed, NO renderer is created. Menu behavior is byte-identical to the v1
stub. Do NOT ship this key set to `true`; the orchestrator gates + packages it after audit.

## Ported vs deferred (honest scope)

Ported: Interface3D offscreen renderer config, exact biped-root clone (+ source-controller detach),
render-tree sanitize / fade-node repair, bounds-centered framing, single front light, the RunActorUpdates
frame-tick driver, procedural breathing idle, the AS3 contract push.

Deferred (documented, with reasons):
- Live animation-graph clone + idle state machine (TF3DHUD `Animations.cpp`, 127 KB) -> replaced by the
  procedural breathing idle. The figure is posed from the live third-person skeleton snapshot at open.
- FaceGen morph / head-part / cloth high-detail head reconstruction (`Morph`/`PreviewHeadParts`/
  `PreviewCloth`) -> the exact clone already carries the live baked body morphs + current head at
  third-person LOD; high-detail face is not reconstructed.
- Frame-audit signature rebuild state machine (`PreviewRebuilder.cpp`) -> rebuild-on-open instead. Equipment
  changed WHILE the Pip-Boy is open reflects on the next open.
- Render-boundary commit + tiled-lighting deferred hooks (`RenderPrepassesAndMenus` / `RenderSceneDeferred` /
  composite-pass ctor) -> this fork ships no `REL::ASM` branch-gateway, so those function-entry hooks are not
  portable here without hand-rolled prologue patching (a crash risk in an untestable auto-install). All scene
  work runs in the single proven `write_call<5>` frame hook under a lock. Possible visual consequence when
  enabled: under ENB tiled-lighting the offscreen composite may be mis-lit. This is a VISUAL issue, never a
  crash.
- Display-mesh clip-rect vertex-buffer reshaping (`Renderer.cpp ApplyDisplayClipRectImpl`) -> the full
  display mesh is used; precise SWF-slot alignment is the next round (option A above).
