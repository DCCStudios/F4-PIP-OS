#include "PCH.h"
#include <spdlog/spdlog.h>   // 0.0.53: flush_on control (the REX logger shim is spdlog underneath)
#include "CharacterCapture.h"
#include "MenuUI.h"
#include "PipboyBridge.h"
#include "Settings.h"

namespace Plugin
{
    static constexpr auto NAME = "PipOSPipboy"sv;
    static constexpr auto VERSION = REL::Version{ 1, 0, 0 };
}

namespace
{
    void OnF4SEMessage(F4SE::MessagingInterface::Message* a_message)
    {
        if (!a_message) { return; }

        // kPostLoad: all plugins mapped (PipboyTabs, FallUI, F4SEMenuFramework, etc. now exist). F4SE maps
        // plugins in load order, so the Menu Framework DLL may not be resolvable during F4SEPlugin_Load;
        // registering here guarantees it is. Register() is a no-op if Menu Framework is absent.
        if (a_message->type == F4SE::MessagingInterface::kPostLoad) {
            PipOS::MenuUI::Register();
        }

        // kGameDataReady: forms and UI singletons are settled, safe to install the menu sink.
        if (a_message->type == F4SE::MessagingInterface::kGameDataReady) {
            PipOS::Settings::GetSingleton()->Load();
            PipOS::PipboyBridge::Install();
            // Self-gates on [Character] bLive3D (default OFF). When off, installs NO hooks and returns false,
            // exactly like the v1 stub -> figure slot uses the Vault Boy fallback. Only allocates a trampoline
            // + installs the frame hook when the user has opted in.
            PipOS::CharacterCapture::Install();
            logger::info("[PipOS] game data ready; bridge active");
        }
    }
}

extern "C" DLLEXPORT bool F4SEAPI F4SEPlugin_Query(
    const F4SE::QueryInterface* a_f4se, F4SE::PluginInfo* a_info)
{
    a_info->infoVersion = F4SE::PluginInfo::kVersion;
    a_info->name = Plugin::NAME.data();
    a_info->version = 0x010000;
    if (a_f4se->IsEditor()) { return false; }
    // OG-only per locked decision.
    return a_f4se->RuntimeVersion() == F4SE::RUNTIME_1_10_163;
}

extern "C" DLLEXPORT bool F4SEAPI F4SEPlugin_Load(const F4SE::LoadInterface* a_f4se)
{
    // 0.0.53 LOG FORENSICS: (1) PRESERVE the previous session's log as PipOSPipboy.prev.log before F4SE::Init
    // truncates it -- a crash + relaunch was destroying the diagnostic evidence from the crashed session.
    try {
        if (const char* prof = std::getenv("USERPROFILE")) {
            const auto dir = std::filesystem::path(prof) / "Documents" / "My Games" / "Fallout4" / "F4SE";
            const auto cur = dir / "PipOSPipboy.log";
            const auto prev = dir / "PipOSPipboy.prev.log";
            std::error_code ec;
            if (std::filesystem::exists(cur, ec)) {
                std::filesystem::remove(prev, ec);
                std::filesystem::rename(cur, prev, ec);
            }
        }
    } catch (...) {}

    F4SE::Init(a_f4se, {
        .log = true,
        .logName = Plugin::NAME.data(),
        .trampoline = false,
    });

    // (2) FLUSH every line to disk immediately -- crash-time buffered lines were being lost, which is fatal
    // for crash forensics (the MENUKIDS/life-trail diagnostics exist precisely to be read after a crash).
    if (auto log = spdlog::default_logger()) {
        log->flush_on(spdlog::level::trace);
    }

    logger::info("{} v{}.{}.{} loading on runtime {}",
        Plugin::NAME, Plugin::VERSION[0], Plugin::VERSION[1], Plugin::VERSION[2],
        a_f4se->RuntimeVersion().string());

    auto* messaging = F4SE::GetMessagingInterface();
    if (!messaging || !messaging->RegisterListener(OnF4SEMessage)) {
        logger::critical("[PipOS] F4SE messaging registration failed");
        return false;
    }
    logger::info("[PipOS] loaded; waiting for game data");
    return true;
}
