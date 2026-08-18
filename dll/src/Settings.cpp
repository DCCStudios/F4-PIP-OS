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
        // Figure-slot placement defaults (reset every Load so a removed key reverts to the estimate).
        _char3dDistance = 200.0f;
        _char3dTarget = 1;  // Chest
        _char3dClipLeft = 46.0f;
        _char3dClipTop = 56.0f;
        _char3dClipRight = 52.0f;
        _char3dClipBottom = 30.0f;
        // 0.0.38 customization defaults (reset every Load so a removed key reverts to shipping behavior).
        _veilAlpha = 0.10f;
        _crtBreathe = true;
        _openAnim = true;
        _folders = true;
        _showRPM = false;

        const auto path = std::filesystem::path("Data/F4SE/Plugins/PipOSPipboy.ini");
        std::ifstream in(path);
        if (!in) {
            logger::info("[PipOS] no PipOSPipboy.ini; defaulting all tabs to PipOS pages");
            return;
        }

        static constexpr std::array<std::string_view, 5> keys{ "STAT", "INV", "DATA", "MAP", "RADIO" };
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
            if (key == "CHAR3DFOV" || key == "CHAR3DSCALE" || key == "CHAR3DYAW") {
                try {
                    const float f = std::stof(val);
                    if (key == "CHAR3DFOV") { _char3dFov = f; }
                    else if (key == "CHAR3DSCALE") { _char3dScale = f; }
                    else { _char3dYaw = f; }
                } catch (...) {}
                continue;
            }
            // Figure-slot placement keys (all optional; a missing key keeps the estimate set above).
            if (key == "CHAR3DDISTANCE" || key == "CHAR3DCLIPLEFT" || key == "CHAR3DCLIPTOP" ||
                key == "CHAR3DCLIPRIGHT" || key == "CHAR3DCLIPBOTTOM") {
                try {
                    const float f = std::stof(val);
                    if (key == "CHAR3DDISTANCE") { _char3dDistance = f; }
                    else if (key == "CHAR3DCLIPLEFT") { _char3dClipLeft = f; }
                    else if (key == "CHAR3DCLIPTOP") { _char3dClipTop = f; }
                    else if (key == "CHAR3DCLIPRIGHT") { _char3dClipRight = f; }
                    else { _char3dClipBottom = f; }
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
            if (key == "WIDESCREENSPIKE") {
                std::string v = val;
                const auto f = v.find_first_of("0123456789");
                _wsSpike = (f == std::string::npos) ? 0 : (v[f] - '0');
                continue;
            }
            // 0.0.38 CUSTOMIZATION keys. All optional; a missing key keeps the shipping default set above.
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
        logger::info("[PipOS] settings loaded from PipOSPipboy.ini");
    }

    PageMode Settings::Mode(std::size_t a_pageIndex) const
    {
        return a_pageIndex < _pageModes.size() ? _pageModes[a_pageIndex] : PageMode::kPipOS;
    }

    void Settings::SaveCustomization() const
    {
        // Rewrite ONLY the [Customization] keys, preserving every other line (Pages / Character / comments)
        // verbatim. The flat Load() parser is section-insensitive (a line with no '=' is skipped), so the
        // [Customization] header is purely for humans; the keys are read wherever they sit. Best-effort:
        // any filesystem failure is logged and swallowed (never throws into the ImGui render thread).
        const auto path = std::filesystem::path("Data/F4SE/Plugins/PipOSPipboy.ini");

        auto fmtF = [](float a_v, const char* a_fmt = "%.2f") -> std::string {
            char b[32];
            std::snprintf(b, sizeof(b), a_fmt, static_cast<double>(a_v));
            return std::string(b);
        };

        // bLive3D is persisted too (the page toggles it), keyed on the SAME [Character] bLive3D the
        // CharacterCapture gate already reads. If a [Character] bLive3D line exists it is updated in place;
        // otherwise it lands in the appended [Customization] block (the flat parser reads it either way). The
        // figure-slot placement keys (Char3D*) round-trip the same way so in-game slider tuning survives a
        // restart; an existing [Character] line is updated in place, else appended.
        struct KV { const char* canon; const char* upper; std::string val; bool written; };
        std::vector<KV> entries{
            { "VeilAlpha",        "VEILALPHA",        fmtF(_veilAlpha),                       false },
            { "CrtBreathe",       "CRTBREATHE",       _crtBreathe ? "true" : "false",         false },
            { "OpenAnim",         "OPENANIM",         _openAnim   ? "true" : "false",         false },
            { "Folders",          "FOLDERS",          _folders    ? "true" : "false",         false },
            { "ShowRPM",          "SHOWRPM",          _showRPM    ? "true" : "false",         false },
            { "bLive3D",          "BLIVE3D",          _live3D     ? "true" : "false",         false },
            { "Char3DScale",      "CHAR3DSCALE",      fmtF(_char3dScale, "%.3f"),             false },
            { "Char3DDistance",   "CHAR3DDISTANCE",   fmtF(_char3dDistance, "%.1f"),          false },
            { "Char3DTarget",     "CHAR3DTARGET",     std::to_string(_char3dTarget),          false },
            { "Char3DClipLeft",   "CHAR3DCLIPLEFT",   fmtF(_char3dClipLeft, "%.1f"),          false },
            { "Char3DClipTop",    "CHAR3DCLIPTOP",    fmtF(_char3dClipTop, "%.1f"),           false },
            { "Char3DClipRight",  "CHAR3DCLIPRIGHT",  fmtF(_char3dClipRight, "%.1f"),         false },
            { "Char3DClipBottom", "CHAR3DCLIPBOTTOM", fmtF(_char3dClipBottom, "%.1f"),        false },
        };

        auto upperTrimKey = [](const std::string& a_line) -> std::string {
            const auto eq = a_line.find('=');
            if (eq == std::string::npos) { return {}; }
            std::string k = a_line.substr(0, eq);
            k.erase(0, k.find_first_not_of(" \t"));
            const auto last = k.find_last_not_of(" \t");
            if (last == std::string::npos) { return {}; }
            k.erase(last + 1);
            for (auto& c : k) { c = static_cast<char>(::toupper(c)); }
            return k;
        };

        std::vector<std::string> lines;
        bool hasCustomHeader = false;
        {
            std::ifstream in(path);
            if (in) {
                std::string line;
                while (std::getline(in, line)) {
                    if (!line.empty() && line.back() == '\r') { line.pop_back(); }
                    // Detect a [Customization] header (trimmed, case-insensitive) so we don't duplicate it.
                    std::string t = line;
                    t.erase(0, t.find_first_not_of(" \t"));
                    const auto te = t.find_last_not_of(" \t");
                    if (te != std::string::npos) { t.erase(te + 1); }
                    std::string tl = t; for (auto& c : tl) { c = static_cast<char>(::tolower(c)); }
                    if (tl == "[customization]") { hasCustomHeader = true; }

                    // Update an existing customization key in place (skip comment lines).
                    const auto firstNs = line.find_first_not_of(" \t");
                    const bool isComment = (firstNs != std::string::npos && (line[firstNs] == ';' || line[firstNs] == '#'));
                    if (!isComment) {
                        const std::string ukey = upperTrimKey(line);
                        for (auto& e : entries) {
                            if (!e.written && ukey == e.upper) {
                                line = std::string(e.canon) + "=" + e.val;
                                e.written = true;
                                break;
                            }
                        }
                    }
                    lines.push_back(std::move(line));
                }
            }
        }

        const bool anyMissing = std::any_of(entries.begin(), entries.end(),
            [](const KV& e) { return !e.written; });

        std::ofstream out(path, std::ios::trunc);
        if (!out) {
            logger::error("[PipOS] SaveCustomization: cannot open PipOSPipboy.ini for write");
            return;
        }
        for (const auto& l : lines) { out << l << "\n"; }
        if (anyMissing) {
            if (!lines.empty()) { out << "\n"; }
            if (!hasCustomHeader) { out << "[Customization]\n"; }
            for (const auto& e : entries) {
                if (!e.written) { out << e.canon << "=" << e.val << "\n"; }
            }
        }
        logger::info("[PipOS] SaveCustomization: veil={} breathe={} openAnim={} folders={} showRPM={} live3D={} "
                     "char3d(scale={} dist={} target={} clipL={} clipT={} clipR={} clipB={})",
            fmtF(_veilAlpha), _crtBreathe, _openAnim, _folders, _showRPM, _live3D,
            _char3dScale, _char3dDistance, _char3dTarget,
            _char3dClipLeft, _char3dClipTop, _char3dClipRight, _char3dClipBottom);
    }
}
