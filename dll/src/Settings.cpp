#include "PCH.h"
#include "Settings.h"

#include <algorithm>
#include <cstdio>
#include <vector>

namespace PipOS
{
    Settings* Settings::GetSingleton()
    {
        static Settings s;
        return &s;
    }

    namespace
    {
        // Minimal INI value reader: trim surrounding whitespace, lower-case, map to PageMode.
        PageMode ParseMode(std::string_view a_value)
        {
            std::string v{ a_value };
            const auto first = v.find_first_not_of(" \t\r\n");
            if (first == std::string::npos) { return PageMode::kPipOS; }
            v.erase(0, first);
            v.erase(v.find_last_not_of(" \t\r\n") + 1);
            for (auto& c : v) { c = static_cast<char>(::tolower(c)); }
            return (v == "external") ? PageMode::kExternal : PageMode::kPipOS;
        }
    }

    void Settings::Load()
    {
        _pageModes = { PageMode::kPipOS, PageMode::kPipOS, PageMode::kPipOS,
                       PageMode::kPipOS, PageMode::kPipOS };
        _enableCapture = true;
        // Live 3D defaults (OFF). Reset every Load so a removed key reverts to shipping behavior.
        _live3D = false;
        _char3dFov = 70.0f;
        _char3dScale = 0.45f;
        _char3dYaw = 160.0f;
        _char3dPitch = 0.0f;
        _char3dRoll = 0.0f;
        _char3dAnimate = true;
        _char3dIdleState = 0;
        _char3dHideWeaponIdle = false;
        _char3dSheatheWeaponIdle = false;
        _char3dMirrorSneak = true;
        _char3dMirrorJump = true;
        _char3dMirrorWeaponFire = true;
        _char3dMirrorWeaponReload = true;
        _char3dMirrorMelee = true;
        _char3dMirrorThrowable = true;
        _char3dFaceMorphs = true;
        _char3dCloth = true;
        _char3dFollow = true;
        _char3dFollowX = true;
        _char3dFollowY = true;
        _char3dFollowZ = true;
        _char3dHidePowerArmor = true;
        _char3dAntiAliasing = false;
        _char3dHologram = false;
        _char3dSlotMask = 0xFFFF'FFFFu;
        _char3dKeyIntensity = 3.4f;
        _char3dFillIntensity = 1.55f;
        _char3dRimIntensity = 2.15f;
        // Figure-slot placement defaults (reset every Load so a removed key reverts to the estimate).
        _char3dDistance = 200.0f;
        _char3dTarget = 1;  // Chest
        _char3dClipLeft = 46.0f;
        _char3dClipTop = 56.0f;
        _char3dClipRight = 52.0f;
        _char3dClipBottom = 30.0f;
        _char3dScreenX = 0.0f;
        _char3dScreenY = 0.0f;
        // 0.0.38 customization defaults (reset every Load so a removed key reverts to shipping behavior).
        _veilAlpha = 0.10f;
        _crtBreathe = true;
        _crtVignette = false;
        _openAnim = true;
        _openAnimSpeed = 1.0f;
        _folders = true;
        _showRPM = false;

        // 0.0.59 TWO-FILE SETTINGS: the shipped PipOSPipboy.ini is REPLACED by every build install (the FOMOD
        // zip carries it), which silently wiped all in-game customization saves (field-observed: live3D/showRPM
        // saved true in one session loaded false the next -- the 0.0.58 install had overwritten the ini).
        // In-game saves therefore go to PipOSPipboy_User.ini, which is NEVER shipped in the package; it is
        // parsed AFTER the main ini so its values override the shipped defaults.
        static constexpr std::array<std::string_view, 5> keys{ "STAT", "INV", "DATA", "MAP", "RADIO" };
        const auto parseStream = [&](std::istream& in) {
        std::string line;
        while (std::getline(in, line)) {
            const auto hash = line.find_first_of(";#");
            if (hash != std::string::npos) { line.erase(hash); }
            const auto eq = line.find('=');
            if (eq == std::string::npos) { continue; }
            std::string key = line.substr(0, eq);
            key.erase(0, key.find_first_not_of(" \t"));
            key.erase(key.find_last_not_of(" \t") + 1);
            for (auto& c : key) { c = static_cast<char>(::toupper(c)); }
            const std::string val = line.substr(eq + 1);

            if (key == "CHARACTERCAPTURE") {
                std::string v = val; for (auto& c : v) { c = static_cast<char>(::tolower(c)); }
                _enableCapture = (v.find("false") == std::string::npos && v.find('0') == std::string::npos);
                continue;
            }
            if (key == "BLIVE3D") {
                std::string v = val; for (auto& c : v) { c = static_cast<char>(::tolower(c)); }
                _live3D = (v.find("true") != std::string::npos) || (v.find('1') != std::string::npos);
                continue;
            }
            if (key == "CHAR3DFOV" || key == "CHAR3DSCALE" || key == "CHAR3DYAW" ||
                key == "CHAR3DPITCH" || key == "CHAR3DROLL") {
                try {
                    const float f = std::stof(val);
                    if (key == "CHAR3DFOV") { _char3dFov = f; }
                    else if (key == "CHAR3DSCALE") { _char3dScale = f; }
                    else if (key == "CHAR3DYAW") { _char3dYaw = f; }
                    else if (key == "CHAR3DPITCH") { _char3dPitch = f; }
                    else { _char3dRoll = f; }
                } catch (...) {}
                continue;
            }
            // Figure-slot placement keys (all optional; a missing key keeps the estimate set above).
            if (key == "CHAR3DDISTANCE" || key == "CHAR3DCLIPLEFT" || key == "CHAR3DCLIPTOP" ||
                key == "CHAR3DCLIPRIGHT" || key == "CHAR3DCLIPBOTTOM" ||
                key == "CHAR3DSCREENX" || key == "CHAR3DSCREENY") {
                try {
                    const float f = std::stof(val);
                    if (key == "CHAR3DDISTANCE") { _char3dDistance = f; }
                    else if (key == "CHAR3DCLIPLEFT") { _char3dClipLeft = f; }
                    else if (key == "CHAR3DCLIPTOP") { _char3dClipTop = f; }
                    else if (key == "CHAR3DCLIPRIGHT") { _char3dClipRight = f; }
                    else if (key == "CHAR3DCLIPBOTTOM") { _char3dClipBottom = f; }
                    else if (key == "CHAR3DSCREENX") { _char3dScreenX = f; }
                    else { _char3dScreenY = f; }
                } catch (...) {}
                continue;
            }
            if (key == "CHAR3DTARGET") {
                try {
                    int t = std::stoi(val);
                    if (t < 0) { t = 0; } else if (t > 3) { t = 3; }
                    _char3dTarget = t;
                } catch (...) {}
                continue;
            }
            if (key == "CHAR3DIDLESTATE") {
                try { _char3dIdleState = std::clamp(std::stoi(val), 0, 1); } catch (...) {}
                continue;
            }
            if (key == "CHAR3DSLOTMASK") {
                try { _char3dSlotMask = static_cast<std::uint32_t>(std::stoul(val, nullptr, 0)); } catch (...) {}
                continue;
            }
            if (key == "CHAR3DKEYINTENSITY" || key == "CHAR3DFILLINTENSITY" || key == "CHAR3DRIMINTENSITY") {
                try {
                    const float f = std::clamp(std::stof(val), 0.0f, 12.0f);
                    if (key == "CHAR3DKEYINTENSITY") { _char3dKeyIntensity = f; }
                    else if (key == "CHAR3DFILLINTENSITY") { _char3dFillIntensity = f; }
                    else { _char3dRimIntensity = f; }
                } catch (...) {}
                continue;
            }
            if (key == "CHAR3DANIMATE" || key == "CHAR3DHIDEWEAPONIDLE" ||
                key == "CHAR3DSHEATHEWEAPONIDLE" || key == "CHAR3DFACEMORPHS" || key == "CHAR3DCLOTH" ||
                key == "CHAR3DFOLLOW" || key == "CHAR3DFOLLOWX" || key == "CHAR3DFOLLOWY" ||
                key == "CHAR3DFOLLOWZ" || key == "CHAR3DHIDEPOWERARMOR" || key == "CHAR3DANTIALIASING" ||
                key == "CHAR3DHOLOGRAM" ||
                key == "CHAR3DMIRRORSNEAK" || key == "CHAR3DMIRRORJUMP" ||
                key == "CHAR3DMIRRORWEAPONFIRE" || key == "CHAR3DMIRRORWEAPONRELOAD" ||
                key == "CHAR3DMIRRORMELEE" || key == "CHAR3DMIRRORTHROWABLE") {
                std::string v = val; for (auto& c : v) { c = static_cast<char>(::tolower(c)); }
                const bool on = (v.find("false") == std::string::npos && v.find('0') == std::string::npos);
                if (key == "CHAR3DANIMATE") { _char3dAnimate = on; }
                else if (key == "CHAR3DHIDEWEAPONIDLE") { _char3dHideWeaponIdle = on; }
                else if (key == "CHAR3DSHEATHEWEAPONIDLE") { _char3dSheatheWeaponIdle = on; }
                else if (key == "CHAR3DMIRRORSNEAK") { _char3dMirrorSneak = on; }
                else if (key == "CHAR3DMIRRORJUMP") { _char3dMirrorJump = on; }
                else if (key == "CHAR3DMIRRORWEAPONFIRE") { _char3dMirrorWeaponFire = on; }
                else if (key == "CHAR3DMIRRORWEAPONRELOAD") { _char3dMirrorWeaponReload = on; }
                else if (key == "CHAR3DMIRRORMELEE") { _char3dMirrorMelee = on; }
                else if (key == "CHAR3DMIRRORTHROWABLE") { _char3dMirrorThrowable = on; }
                else if (key == "CHAR3DFACEMORPHS") { _char3dFaceMorphs = on; }
                else if (key == "CHAR3DCLOTH") { _char3dCloth = on; }
                else if (key == "CHAR3DFOLLOW") { _char3dFollow = on; }
                else if (key == "CHAR3DFOLLOWX") { _char3dFollowX = on; }
                else if (key == "CHAR3DFOLLOWY") { _char3dFollowY = on; }
                else if (key == "CHAR3DFOLLOWZ") { _char3dFollowZ = on; }
                else if (key == "CHAR3DHIDEPOWERARMOR") { _char3dHidePowerArmor = on; }
                else if (key == "CHAR3DANTIALIASING") { _char3dAntiAliasing = on; }
                else { _char3dHologram = on; }
                continue;
            }
            if (key == "WIDESCREENSPIKE") {
                std::string v = val;
                const auto f = v.find_first_of("0123456789");
                _wsSpike = (f == std::string::npos) ? 0 : (v[f] - '0');
                continue;
            }
            // 0.0.38 CUSTOMIZATION keys. All optional; a missing key keeps the shipping default set above.
            if (key == "OPENANIMSPEED") {   // 0.0.60: power-on speed multiplier
                try {
                    float f = std::stof(val);
                    if (f < 0.25f) { f = 0.25f; } else if (f > 4.0f) { f = 4.0f; }
                    _openAnimSpeed = f;
                } catch (...) {}
                continue;
            }
            if (key == "VEILALPHA") {
                try {
                    float f = std::stof(val);
                    if (f < 0.0f) { f = 0.0f; } else if (f > 1.0f) { f = 1.0f; }
                    _veilAlpha = f;
                } catch (...) {}
                continue;
            }
            if (key == "CRTBREATHE" || key == "OPENANIM" || key == "FOLDERS") {
                std::string v = val; for (auto& c : v) { c = static_cast<char>(::tolower(c)); }
                // Interpret like the other bool keys: explicit false/0 turns it off; anything else keeps on.
                const bool on = (v.find("false") == std::string::npos && v.find('0') == std::string::npos);
                if (key == "CRTBREATHE") { _crtBreathe = on; }
                else if (key == "OPENANIM") { _openAnim = on; }
                else { _folders = on; }
                continue;
            }
            if (key == "CRTVIGNETTE") {
                // Default-off option: only an explicit true/1 enables the fixed edge-darkening bands.
                std::string v = val; for (auto& c : v) { c = static_cast<char>(::tolower(c)); }
                _crtVignette = (v.find("true") != std::string::npos) || (v.find('1') != std::string::npos);
                continue;
            }
            if (key == "SHOWRPM") {
                // Default-OFF bool (opposite sense to the on-by-default keys above): explicit true/1 turns it on,
                // anything else (incl. a missing key) leaves the vanilla FIRE RATE default.
                std::string v = val; for (auto& c : v) { c = static_cast<char>(::tolower(c)); }
                _showRPM = (v.find("true") != std::string::npos) || (v.find('1') != std::string::npos);
                continue;
            }
            for (std::size_t i = 0; i < keys.size(); ++i) {
                if (key == keys[i]) { _pageModes[i] = ParseMode(val); }
            }
        }
        };  // parseStream

        {
            std::ifstream in(std::filesystem::path("Data/F4SE/Plugins/PipOSPipboy.ini"));
            if (in) {
                parseStream(in);
            } else {
                logger::info("[PipOS] no PipOSPipboy.ini; defaulting all tabs to PipOS pages");
            }
        }
        bool userIni = false;
        {
            std::ifstream in(std::filesystem::path("Data/F4SE/Plugins/PipOSPipboy_User.ini"));
            if (in) {
                parseStream(in);
                userIni = true;
            }
        }
        logger::info("[PipOS] settings loaded from PipOSPipboy.ini{}", userIni ? " + PipOSPipboy_User.ini overrides" : " (no user override file yet)");
    }

    PageMode Settings::Mode(std::size_t a_pageIndex) const
    {
        return a_pageIndex < _pageModes.size() ? _pageModes[a_pageIndex] : PageMode::kPipOS;
    }

    void Settings::SaveCustomization() const
    {
        // 0.0.59: all in-game saves go to PipOSPipboy_User.ini -- a file the FOMOD package NEVER ships, so a
        // build install can no longer wipe them (0.0.58's in-place rewrite of the shipped ini was correct, but
        // the next zip install replaced the whole file and every saved value reverted; field-observed twice).
        // We own this file outright, so a plain full rewrite of the known keys is enough. Best-effort: any
        // filesystem failure is logged and swallowed (never throws into the ImGui render thread).
        const auto path = std::filesystem::path("Data/F4SE/Plugins/PipOSPipboy_User.ini");

        auto fmtF = [](float a_v, const char* a_fmt = "%.2f") -> std::string {
            char b[32];
            std::snprintf(b, sizeof(b), a_fmt, static_cast<double>(a_v));
            return std::string(b);
        };

        std::ofstream out(path, std::ios::trunc);
        if (!out) {
            logger::error("[PipOS] SaveCustomization: cannot open PipOSPipboy_User.ini for write");
            return;
        }
        out << "; PIP-OS in-game customization saves. Written by the mod; NOT shipped in the package,\n"
               "; so build updates never overwrite it. Values here override PipOSPipboy.ini.\n"
               "[Customization]\n";
        out << "VeilAlpha=" << fmtF(_veilAlpha) << "\n";
        out << "CrtBreathe=" << (_crtBreathe ? "true" : "false") << "\n";
        out << "CrtVignette=" << (_crtVignette ? "true" : "false") << "\n";
        out << "OpenAnim=" << (_openAnim ? "true" : "false") << "\n";
        out << "OpenAnimSpeed=" << fmtF(_openAnimSpeed) << "\n";
        out << "Folders=" << (_folders ? "true" : "false") << "\n";
        out << "ShowRPM=" << (_showRPM ? "true" : "false") << "\n";
        out << "bLive3D=" << (_live3D ? "true" : "false") << "\n";
        out << "Char3DScale=" << fmtF(_char3dScale, "%.3f") << "\n";
        out << "Char3DFov=" << fmtF(_char3dFov, "%.1f") << "\n";
        out << "Char3DYaw=" << fmtF(_char3dYaw, "%.1f") << "\n";
        out << "Char3DPitch=" << fmtF(_char3dPitch, "%.1f") << "\n";
        out << "Char3DRoll=" << fmtF(_char3dRoll, "%.1f") << "\n";
        out << "Char3DDistance=" << fmtF(_char3dDistance, "%.1f") << "\n";
        out << "Char3DTarget=" << _char3dTarget << "\n";
        out << "Char3DClipLeft=" << fmtF(_char3dClipLeft, "%.1f") << "\n";
        out << "Char3DClipTop=" << fmtF(_char3dClipTop, "%.1f") << "\n";
        out << "Char3DClipRight=" << fmtF(_char3dClipRight, "%.1f") << "\n";
        out << "Char3DClipBottom=" << fmtF(_char3dClipBottom, "%.1f") << "\n";
        out << "Char3DScreenX=" << fmtF(_char3dScreenX, "%.1f") << "\n";
        out << "Char3DScreenY=" << fmtF(_char3dScreenY, "%.1f") << "\n";
        out << "Char3DAnimate=" << (_char3dAnimate ? "true" : "false") << "\n";
        out << "Char3DIdleState=" << _char3dIdleState << "\n";
        out << "Char3DHideWeaponIdle=" << (_char3dHideWeaponIdle ? "true" : "false") << "\n";
        out << "Char3DSheatheWeaponIdle=" << (_char3dSheatheWeaponIdle ? "true" : "false") << "\n";
        out << "Char3DMirrorSneak=" << (_char3dMirrorSneak ? "true" : "false") << "\n";
        out << "Char3DMirrorJump=" << (_char3dMirrorJump ? "true" : "false") << "\n";
        out << "Char3DMirrorWeaponFire=" << (_char3dMirrorWeaponFire ? "true" : "false") << "\n";
        out << "Char3DMirrorWeaponReload=" << (_char3dMirrorWeaponReload ? "true" : "false") << "\n";
        out << "Char3DMirrorMelee=" << (_char3dMirrorMelee ? "true" : "false") << "\n";
        out << "Char3DMirrorThrowable=" << (_char3dMirrorThrowable ? "true" : "false") << "\n";
        out << "Char3DFaceMorphs=" << (_char3dFaceMorphs ? "true" : "false") << "\n";
        out << "Char3DCloth=" << (_char3dCloth ? "true" : "false") << "\n";
        out << "Char3DFollow=" << (_char3dFollow ? "true" : "false") << "\n";
        out << "Char3DFollowX=" << (_char3dFollowX ? "true" : "false") << "\n";
        out << "Char3DFollowY=" << (_char3dFollowY ? "true" : "false") << "\n";
        out << "Char3DFollowZ=" << (_char3dFollowZ ? "true" : "false") << "\n";
        out << "Char3DHidePowerArmor=" << (_char3dHidePowerArmor ? "true" : "false") << "\n";
        out << "Char3DAntiAliasing=" << (_char3dAntiAliasing ? "true" : "false") << "\n";
        out << "Char3DHologram=" << (_char3dHologram ? "true" : "false") << "\n";
        out << "Char3DSlotMask=0x" << std::hex << std::uppercase << _char3dSlotMask << std::dec << "\n";
        out << "Char3DKeyIntensity=" << fmtF(_char3dKeyIntensity) << "\n";
        out << "Char3DFillIntensity=" << fmtF(_char3dFillIntensity) << "\n";
        out << "Char3DRimIntensity=" << fmtF(_char3dRimIntensity) << "\n";

        logger::info("[PipOS] SaveCustomization -> PipOSPipboy_User.ini: veil={} breathe={} vignette={} openAnim={} folders={} showRPM={} live3D={} "
                     "char3d(scale={} dist={} target={} clipL={} clipT={} clipR={} clipB={})",
            fmtF(_veilAlpha), _crtBreathe, _crtVignette, _openAnim, _folders, _showRPM, _live3D,
            _char3dScale, _char3dDistance, _char3dTarget,
            _char3dClipLeft, _char3dClipTop, _char3dClipRight, _char3dClipBottom);
    }
}
