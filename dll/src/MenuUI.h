#pragma once

namespace PipOS::MenuUI
{
    // Registers the PIP-OS customization page with F4SE Menu Framework (ImGui in-game menu). No-op and
    // silent if Menu Framework is not installed -- the page is a pure enhancement; every setting also lives
    // in PipOSPipboy.ini. Call once, at kPostLoad (the framework DLL is guaranteed mapped by then).
    void Register();
}
