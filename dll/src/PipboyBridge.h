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
}
