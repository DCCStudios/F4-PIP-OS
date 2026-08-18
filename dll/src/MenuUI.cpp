#include "PCH.h"
#include "MenuUI.h"
#include "Settings.h"

#include "F4SEMenuFramework.h"

// PIP-OS in-game customization page (F4SE Menu Framework).
//
// MECHANISM (replicated from S2 HUD Rework's MenuUI): Menu Framework is an ImGui-driven in-game menu. A
// consumer plugin registers a page by calling the header-only shim (F4SEMenuFramework.h), which resolves the
// framework's exported functions from the already-loaded F4SEMenuFramework.dll at call time. There is NO JSON
// config and NO SWF -- the page IS the ImGui render callback below. SetSection() names the tree node; each
// AddSectionItem() adds a leaf whose render function draws with ImGuiMCP:: widgets.
//
// The page binds ImGui widgets DIRECTLY to the live Settings singleton fields (pVeilAlpha()/pCrtBreathe()/...),
// so edits are immediate in the singleton. They reach the menu the next time the Pip-Boy opens, via the
// menu-open push to root1.PipOS_settings (PipboyBridge) which the AS3 reads with fallback to its own const
// defaults. "Save" writes only the [Customization] keys of PipOSPipboy.ini so the choice survives a restart.
//
// HONEST OPACITY FRAMING: the veil slider controls ONLY the PIP-OS-owned world-dim veil (default 0.10). A
// near-solid BLACK world behind the Pip-Boy is NOT this veil: it is Baka Fullscreen Pip-Boy's own "Black
// Background" option (bBackground=1 / fBackgroundAlpha ~0.85 in Data/MCM/Settings/BakaFullscreenPipboy.ini, a
// user override some presets ship ON), which this mod cannot override. The page says so and sends the user to
// Baka's MCM "Black Background" toggle for a brighter world.

namespace
{
    bool g_registered = false;

    void __stdcall RenderCustomizationPage()
    {
        auto* settings = PipOS::Settings::GetSingleton();

        ImGuiMCP::TextWrapped(
            "Customize the PIP-OS Pip-Boy. Changes apply the next time you open the Pip-Boy. "
            "Press Save to keep them across sessions (writes the [Customization] block of "
            "PipOSPipboy.ini); without Save they last only for this session.");
        ImGuiMCP::Spacing();

        ImGuiMCP::SeparatorText("Background dimming");
        ImGuiMCP::SliderFloat("PIP-OS dimming", settings->pVeilAlpha(), 0.0F, 0.60F, "veil alpha %.2f");
        ImGuiMCP::TextDisabled(
            "How dark PIP-OS makes the world BEHIND the Pip-Boy (our own veil layer). 0.00 = no added "
            "dim; 0.10 is the default. IMPORTANT: if the world behind the Pip-Boy is a near-solid BLACK "
            "screen, that is NOT this veil and NOT PIP-OS. It is Baka Fullscreen Pip-Boy's own \"Black "
            "Background\" option (some presets and patches force it ON via bBackground=1 in "
            "BakaFullscreenPipboy.ini). Open Baka's MCM and turn \"Black Background\" OFF to get the world "
            "back. This slider only tunes the small extra dim PIP-OS adds on top.");

        ImGuiMCP::Spacing();
        ImGuiMCP::SeparatorText("CRT effects");
        ImGuiMCP::Checkbox("Phosphor breathing", settings->pCrtBreathe());
        ImGuiMCP::TextDisabled("Slow, subtle glow oscillation on the CRT overlay.");
        ImGuiMCP::Checkbox("Power-on open animation", settings->pOpenAnim());
        ImGuiMCP::TextDisabled("Short phosphor fade-in of the chrome + veil each time the Pip-Boy opens.");

        ImGuiMCP::Spacing();
        ImGuiMCP::SeparatorText("Inventory");
        ImGuiMCP::Checkbox("Group tagged items into folders", settings->pFolders());
        ImGuiMCP::TextDisabled(
            "Groups inventory items under collapsible folder headers when their names carry FIS / "
            "Complex Sorter category tags. Off = a flat item list. Untagged inventories are flat either way.");
        ImGuiMCP::Checkbox("Show RPM instead of Fire Rate", settings->pShowRPM());
        ImGuiMCP::TextDisabled("Weapon cards show rounds-per-minute instead of the vanilla Fire Rate value.");

        ImGuiMCP::Spacing();
        ImGuiMCP::SeparatorText("Experimental");
        ImGuiMCP::Checkbox("Live 3D character (experimental)", settings->pLive3D());
        ImGuiMCP::TextColored(
            ImGuiMCP::ImVec4(0.90F, 0.62F, 0.16F, 1.0F),
            "Experimental and OFF by default. Renders a live rotatable equipped-player capture behind the "
            "menu instead of the Vault Boy. TURNING IT ON/OFF only takes effect after a game RESTART (the "
            "capture hook is installed once at load), and it is the least-tested option -- leave it off unless "
            "you are testing it.");

        ImGuiMCP::Spacing();
        ImGuiMCP::SeparatorText("Figure placement (Live 3D)");
        ImGuiMCP::TextDisabled(
            "Where and how big the live 3D character sits in the Pip-Boy figure slot. Unlike the toggle above, "
            "these apply on the NEXT Pip-Boy open -- no restart -- so you can tune the fit iteratively. The "
            "defaults estimate the center-column figure box; expect to nudge them once in-game.");
        // clipRect = the on-screen window (positive centered extents, display-plane world units ~+-148 x /
        // +-80 y). Bind straight to the live Settings fields, exactly like the veil/breathe sliders.
        ImGuiMCP::SliderFloat("Window left",   settings->pChar3dClipLeft(),   0.0F, 148.0F, "%.1f");
        ImGuiMCP::SliderFloat("Window top",    settings->pChar3dClipTop(),    0.0F,  80.0F, "%.1f");
        ImGuiMCP::SliderFloat("Window right",  settings->pChar3dClipRight(),  0.0F, 148.0F, "%.1f");
        ImGuiMCP::SliderFloat("Window bottom", settings->pChar3dClipBottom(), 0.0F,  80.0F, "%.1f");
        ImGuiMCP::TextDisabled(
            "The window straddles screen-center; each value is the distance from center to that edge. Setting "
            "both left and right (or both top and bottom) to 0 spans the whole screen on that axis.");
        ImGuiMCP::Spacing();
        ImGuiMCP::SliderFloat("Model scale",     settings->pChar3dScale(),    0.05F,   2.0F, "%.3f");
        ImGuiMCP::SliderFloat("Camera distance", settings->pChar3dDistance(), 50.0F, 600.0F, "%.0f");
        static const char* const kTargets[] = { "Head", "Chest", "Pelvis", "Root" };
        ImGuiMCP::Combo("Framing target", settings->pChar3dTarget(), kTargets, 4);
        ImGuiMCP::TextDisabled(
            "Model scale sizes the figure; camera distance pulls the camera back (bigger = smaller figure). "
            "Framing target is the body point centered in the frame.");

        ImGuiMCP::Spacing();
        ImGuiMCP::Separator();
        ImGuiMCP::Spacing();

        if (ImGuiMCP::Button("Save")) {
            settings->SaveCustomization();
        }
        ImGuiMCP::SameLine();
        if (ImGuiMCP::Button("Reset to defaults")) {
            // Defaults reproduce 0.0.37 behavior exactly (veil 0.10, breathe/open-anim/folders on, live3D off).
            *settings->pVeilAlpha() = 0.10F;
            *settings->pCrtBreathe() = true;
            *settings->pOpenAnim() = true;
            *settings->pFolders() = true;
            *settings->pShowRPM() = false;
            *settings->pLive3D() = false;
            // Figure-slot placement estimate (matches the Settings ctor / Load defaults).
            *settings->pChar3dScale() = 0.45F;
            *settings->pChar3dDistance() = 200.0F;
            *settings->pChar3dTarget() = 1;
            *settings->pChar3dClipLeft() = 46.0F;
            *settings->pChar3dClipTop() = 56.0F;
            *settings->pChar3dClipRight() = 52.0F;
            *settings->pChar3dClipBottom() = 30.0F;
        }
        ImGuiMCP::SameLine();
        if (ImGuiMCP::Button("Reload from file")) {
            settings->Load();
        }
    }
}

namespace PipOS::MenuUI
{
    void Register()
    {
        if (g_registered) {
            return;
        }
        if (!F4SEMenuFramework::IsInstalled()) {
            logger::info(
                "[PipOS] F4SE Menu Framework not installed; the in-game customization page is unavailable. "
                "All options can still be edited in PipOSPipboy.ini.");
            return;
        }

        F4SEMenuFramework::SetSection("PIP-OS Pip-Boy");
        F4SEMenuFramework::AddSectionItem("Customization", RenderCustomizationPage);
        g_registered = true;
        logger::info("[PipOS] Registered the customization page with F4SE Menu Framework");
    }
}
