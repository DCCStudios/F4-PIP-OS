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
// OPACITY CONTRACT: the veil slider controls one uniform, full-visible-frame black layer below the pages.
// Scanlines, phosphor glow, and frame borders stay independent. The formerly mandatory 230-unit edge vignette
// is now a separate default-off CRT option so it cannot make the slider appear to affect only the center.

namespace
{
    bool g_registered = false;

    void __stdcall RenderCustomizationPage()
    {
        auto* settings = PipOS::Settings::GetSingleton();

        ImGuiMCP::TextWrapped(
            "Customize the PIP-OS Pip-Boy. Changes apply the next time you open the Pip-Boy. "
            "Press Save to keep them across sessions (writes PipOSPipboy_User.ini, which build "
            "updates never overwrite); without Save they last only for this session.");
        ImGuiMCP::Spacing();

        ImGuiMCP::SeparatorText("Background transparency");
        ImGuiMCP::SliderFloat("Background opacity", settings->pVeilAlpha(), 0.0F, 1.0F, "black layer %.2f");
        ImGuiMCP::TextDisabled(
            "Opacity of one uniform black layer behind the complete PIP-OS UI. 0.00 is fully transparent; "
            "1.00 is black. CRT scanlines, phosphor texture, and frame borders are intentionally unaffected.");

        ImGuiMCP::Spacing();
        ImGuiMCP::SeparatorText("CRT effects");
        ImGuiMCP::Checkbox("Edge vignette", settings->pCrtVignette());
        ImGuiMCP::TextDisabled(
            "Optional fixed edge darkening. Off by default so background opacity is uniform across the screen.");
        ImGuiMCP::Checkbox("Phosphor breathing", settings->pCrtBreathe());
        ImGuiMCP::TextDisabled("Slow, subtle glow oscillation on the CRT overlay.");
        ImGuiMCP::Checkbox("Power-on open animation", settings->pOpenAnim());
        ImGuiMCP::TextDisabled("Short phosphor fade-in of the chrome + veil each time the Pip-Boy opens.");
        ImGuiMCP::SliderFloat("Open animation speed", settings->pOpenAnimSpeed(), 0.25F, 4.0F, "%.2fx");
        ImGuiMCP::TextDisabled("Speed multiplier for the power-on animation. 1.00x = default; higher = faster.");

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
            "Experimental and OFF by default. Renders a live capture of your equipped character in the "
            "inventory figure slot instead of the Vault Boy. Applies on the NEXT Pip-Boy open -- close and "
            "re-open the Pip-Boy after toggling (no game restart needed).");

        ImGuiMCP::Spacing();
        ImGuiMCP::SeparatorText("Figure placement (Live 3D)");
        ImGuiMCP::TextDisabled(
            "Character X/Y translate the model inside the fixed figure window. They do not resize the display "
            "quad, change its UVs, alter camera projection, or stretch the character. Changes apply live.");
        ImGuiMCP::SliderFloat("Character X", settings->pChar3dScreenX(), -100.0F, 100.0F, "%.1f");
        ImGuiMCP::SliderFloat("Character Y", settings->pChar3dScreenY(), -100.0F, 100.0F, "%.1f");
        if (ImGuiMCP::Button("Center character")) {
            *settings->pChar3dScreenX() = 0.0F;
            *settings->pChar3dScreenY() = 0.0F;
        }
        if (ImGuiMCP::CollapsingHeader("Advanced framing and aperture")) {
            ImGuiMCP::TextDisabled(
                "These controls intentionally change size, projection, rotation, or the compositor aperture. "
                "Use Character X/Y above for translation-only placement.");
            ImGuiMCP::SliderFloat("Window left", settings->pChar3dClipLeft(), 0.0F, 148.0F, "%.1f");
            ImGuiMCP::SliderFloat("Window top", settings->pChar3dClipTop(), 0.0F, 80.0F, "%.1f");
            ImGuiMCP::SliderFloat("Window right", settings->pChar3dClipRight(), 0.0F, 148.0F, "%.1f");
            ImGuiMCP::SliderFloat("Window bottom", settings->pChar3dClipBottom(), 0.0F, 80.0F, "%.1f");
            ImGuiMCP::SliderFloat("Model scale", settings->pChar3dScale(), 0.05F, 2.0F, "%.3f");
            ImGuiMCP::SliderFloat("Camera distance", settings->pChar3dDistance(), 50.0F, 600.0F, "%.0f");
            ImGuiMCP::SliderFloat("Camera FOV", settings->pChar3dFov(), 20.0F, 120.0F, "%.1f deg");
            ImGuiMCP::SliderFloat("Model yaw", settings->pChar3dYaw(), -180.0F, 180.0F, "%.1f deg");
            ImGuiMCP::SliderFloat("Model pitch", settings->pChar3dPitch(), -180.0F, 180.0F, "%.1f deg");
            ImGuiMCP::SliderFloat("Model roll", settings->pChar3dRoll(), -180.0F, 180.0F, "%.1f deg");
            static const char* const kTargets[] = { "Head", "Chest", "Pelvis", "Root" };
            ImGuiMCP::Combo("Framing target", settings->pChar3dTarget(), kTargets, 4);
        }

        if (ImGuiMCP::CollapsingHeader("Animation and state")) {
            ImGuiMCP::Checkbox("Run private animation graph", settings->pChar3dAnimate());
            static const char* const kIdleStates[] = { "Weapon ready", "Weapon sighted" };
            ImGuiMCP::Combo("Equipped-weapon idle", settings->pChar3dIdleState(), kIdleStates, 2);
            ImGuiMCP::TextDisabled(
                "When a weapon is equipped the preview is always drawn and uses this stationary pose. "
                "Unarmed previews use the relaxed state.");
            if (ImGuiMCP::CollapsingHeader("Mirrored event groups (no locomotion)")) {
                ImGuiMCP::Checkbox("Sneak", settings->pChar3dMirrorSneak());
                ImGuiMCP::SameLine();
                ImGuiMCP::Checkbox("Jump", settings->pChar3dMirrorJump());
                ImGuiMCP::Checkbox("Weapon fire", settings->pChar3dMirrorWeaponFire());
                ImGuiMCP::SameLine();
                ImGuiMCP::Checkbox("Weapon reload", settings->pChar3dMirrorWeaponReload());
                ImGuiMCP::Checkbox("Melee / block", settings->pChar3dMirrorMelee());
                ImGuiMCP::SameLine();
                ImGuiMCP::Checkbox("Grenades / mines", settings->pChar3dMirrorThrowable());
            }
            ImGuiMCP::TextDisabled("Locomotion mirroring is intentionally excluded; the preview remains stationary.");
        }

        if (ImGuiMCP::CollapsingHeader("Face, equipment, and cloth")) {
            ImGuiMCP::Checkbox("Live facial expressions and morphs", settings->pChar3dFaceMorphs());
            ImGuiMCP::Checkbox("Initialize preview cloth", settings->pChar3dCloth());
            ImGuiMCP::Checkbox("Hide preview in power armor", settings->pChar3dHidePowerArmor());
            if (ImGuiMCP::Button("Enable all equipment slots")) { *settings->pChar3dSlotMask() = 0xFFFF'FFFFu; }
            ImGuiMCP::SameLine();
            if (ImGuiMCP::Button("Disable all equipment slots")) { *settings->pChar3dSlotMask() = 0; }
            if (ImGuiMCP::CollapsingHeader("Equipment slot mask (30-61)")) {
                for (std::uint32_t slot = 0; slot < 32; ++slot) {
                    bool enabled = (*settings->pChar3dSlotMask() & (1u << slot)) != 0;
                    const auto label = std::format("Slot {}", slot + 30);
                    if (ImGuiMCP::Checkbox(label.c_str(), &enabled)) {
                        if (enabled) { *settings->pChar3dSlotMask() |= (1u << slot); }
                        else { *settings->pChar3dSlotMask() &= ~(1u << slot); }
                    }
                    if ((slot % 4) != 3) { ImGuiMCP::SameLine(); }
                }
            }
        }

        if (ImGuiMCP::CollapsingHeader("Target following")) {
            ImGuiMCP::Checkbox("Follow animated framing target", settings->pChar3dFollow());
            ImGuiMCP::Checkbox("Follow X", settings->pChar3dFollowX());
            ImGuiMCP::SameLine();
            ImGuiMCP::Checkbox("Follow Y", settings->pChar3dFollowY());
            ImGuiMCP::SameLine();
            ImGuiMCP::Checkbox("Follow Z", settings->pChar3dFollowZ());
        }

        if (ImGuiMCP::CollapsingHeader("Renderer and lighting")) {
            ImGuiMCP::Checkbox("Pip-green character rim", settings->pChar3dHologram());
            ImGuiMCP::TextDisabled(
                "Keeps the normal key/fill colors and strengthens only the green rear rim light. "
                "A character-masked scanline requires a dedicated compositor shader.");
            ImGuiMCP::Checkbox("Anti-aliasing", settings->pChar3dAntiAliasing());
            ImGuiMCP::SliderFloat("Key intensity", settings->pChar3dKeyIntensity(), 0.0F, 12.0F, "%.2f");
            ImGuiMCP::SliderFloat("Fill intensity", settings->pChar3dFillIntensity(), 0.0F, 12.0F, "%.2f");
            ImGuiMCP::SliderFloat("Rim intensity", settings->pChar3dRimIntensity(), 0.0F, 12.0F, "%.2f");
        }

        ImGuiMCP::Spacing();
        ImGuiMCP::Separator();
        ImGuiMCP::Spacing();

        if (ImGuiMCP::Button("Save")) {
            settings->SaveCustomization();
        }
        ImGuiMCP::SameLine();
        if (ImGuiMCP::Button("Reset to defaults")) {
            // Uniform-background defaults: veil 0.10, edge vignette off, breathing/open-anim/folders on.
            *settings->pVeilAlpha() = 0.10F;
            *settings->pCrtBreathe() = true;
            *settings->pCrtVignette() = false;
            *settings->pOpenAnim() = true;
            *settings->pOpenAnimSpeed() = 1.0F;
            *settings->pFolders() = true;
            *settings->pShowRPM() = false;
            *settings->pLive3D() = false;
            // Figure-slot placement estimate (matches the Settings ctor / Load defaults).
            *settings->pChar3dScale() = 0.45F;
            *settings->pChar3dFov() = 70.0F;
            *settings->pChar3dYaw() = 160.0F;
            *settings->pChar3dDistance() = 200.0F;
            *settings->pChar3dTarget() = 1;
            *settings->pChar3dClipLeft() = 46.0F;
            *settings->pChar3dClipTop() = 56.0F;
            *settings->pChar3dClipRight() = 52.0F;
            *settings->pChar3dClipBottom() = 30.0F;
            *settings->pChar3dScreenX() = 0.0F;
            *settings->pChar3dScreenY() = 0.0F;
            *settings->pChar3dAnimate() = true;
            *settings->pChar3dIdleState() = 0;
            *settings->pChar3dHideWeaponIdle() = false;
            *settings->pChar3dSheatheWeaponIdle() = false;
            *settings->pChar3dMirrorSneak() = true;
            *settings->pChar3dMirrorJump() = true;
            *settings->pChar3dMirrorWeaponFire() = true;
            *settings->pChar3dMirrorWeaponReload() = true;
            *settings->pChar3dMirrorMelee() = true;
            *settings->pChar3dMirrorThrowable() = true;
            *settings->pChar3dFaceMorphs() = true;
            *settings->pChar3dCloth() = true;
            *settings->pChar3dFollow() = true;
            *settings->pChar3dFollowX() = true;
            *settings->pChar3dFollowY() = true;
            *settings->pChar3dFollowZ() = true;
            *settings->pChar3dHidePowerArmor() = true;
            *settings->pChar3dAntiAliasing() = false;
            *settings->pChar3dHologram() = false;
            *settings->pChar3dSlotMask() = 0xFFFF'FFFFu;
            *settings->pChar3dKeyIntensity() = 3.4F;
            *settings->pChar3dFillIntensity() = 1.55F;
            *settings->pChar3dRimIntensity() = 2.15F;
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
