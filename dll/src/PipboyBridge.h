#pragma once

namespace PipOS
{
    // Listens for the Pip-Boy menu opening and pushes the per-tab page modes from Settings into the
    // PIP-OS shell via its public ActionScript method PipboyMenu.SetPageMode(index, mode).
    // This is the S2-HUD precedent: the DLL reads the INI and calls into the movie. The package is
    // fully functional WITHOUT this DLL (shell then defaults every tab to the PipOS page, with the
    // built-in load-failure fallback to the external page). The DLL only enables external passthrough.
    class PipboyBridge
    {
    public:
        static bool Install();  // register the menu open/close sink
    };

    // 0.0.60: called once per frame from CharacterCapture's main-thread capture task while the Pip-Boy is
    // open. Rate-limits internally and re-pushes the equipment panel (root1.PipOS_equip) so in-menu equips
    // show up live (there is no TESEquipEvent source in this commonlib; polling the fixed 10-slot sweep
    // ~2x/s is cheap and thread-correct).
    void RepushEquipmentPeriodic();

    // 0.0.68: vfunc hook on UI::PerformInputProcessing (installed once from PipboyBridge::Install). Observes
    // the game's own input chain for a right-mouse ButtonEvent while the Pip-Boy is open and bumps
    // root1.PipOS_rclickN (GFx never forwards RIGHT_MOUSE_DOWN and GetAsyncKeyState is blind to the RMB in
    // FO4's raw-input runtime -- both field-proven).
    void InstallRightClickHook();

    // 0.0.65: reads root1.PipOS_droplog and logs it on change (dedicated drop diagnostic; bypasses the AS
    // life-trail cap). Called once per frame from CharacterCapture's main-thread task while the Pip-Boy is open.
    void ReadDropLog();
}
