#pragma once

namespace PipOS
{
    // M5 HEADLINE FEATURE -- live equipped-player 3D capture for the PIP-OS INV/STAT figure slot.
    //
    // Ported (architecture) from PluginTemplate/TF3DHUD-master: the equipped third-person player 3D is
    // cloned into an offscreen RE::Interface3D::Renderer, framed + lit, and driven each frame so it shows
    // the player's CURRENT equipment / apparel / body morphs and holds the equipped weapon (the weapon is a
    // biped object on the cloned root, so it comes along for free). A subtle procedural breathing idle keeps
    // the figure alive. The offscreen render target is composited to screen via a screen-attached display
    // mesh (the vanilla workbench-preview mechanism).
    //
    // HARD SAFETY CONTRACT (this build auto-installs while the user sleeps -- it must not hard-crash):
    //   * CONFIG-GATED, DEFAULT-OFF via [Character] bLive3D (Settings::Live3D()). When false, Install()
    //     returns false immediately and installs NO engine hooks / allocates NO trampoline -- byte-identical
    //     to the v1 stub. The base menu behavior with the feature off is unchanged.
    //   * Degrade, never crash. Every capture step is null-guarded; any failure disables the feature for the
    //     session and the SWF figure slots fall back to the vanilla ConditionBoy composite. (catch(...) does
    //     NOT catch a Windows AV under /EHsc -- correctness here is null-guards + main-thread-task affinity.)
    //   * Thread affinity. The RunActorUpdates hook is NOT reliably the main thread on this fork (fires on
    //     worker threads). So ALL scene-graph / renderer / D3D work is deferred to the game MAIN thread via
    //     F4SE::GetTaskInterface()->AddTask; the hook body only reads atomics + schedules. A "task in flight"
    //     atomic collapses worker-thread multiplicity so N hook fires never queue N clones. Menu-close
    //     teardown is scheduled the same way, keeping renderer/D3D lifecycle main-thread only.
    //
    // See docs/Character3DContract.md for the DLL<->AS3 capture contract the later AS3 wiring round consumes.
    class CharacterCapture
    {
    public:
        // Self-gates on Settings::Live3D(). Returns true only if the feature is enabled AND the hook set was
        // installed; false (like the v1 stub) when disabled or when setup failed -> callers use the placeholder.
        static bool Install();

        // True once an offscreen capture of the player is live this session (drives the AS3 contract value).
        static bool IsCaptureAvailable();
    };
}
