#pragma once

namespace RE
{
    class BSAnimationGraphManager;
    class NiAVObject;
    class PlayerCharacter;
}

namespace PipOS::CharacterAnimation
{
    // Owns a TF3DHUD-style private third-person behavior graph whose target is
    // the independent preview skeleton. All calls are made from PIP-OS's
    // Interface3D render-boundary hook while the preview renderer is active.
    void Update(RE::PlayerCharacter& a_player, RE::NiAVObject& a_previewRoot, float a_deltaTime);
    void ObserveGraphRequest(RE::BSAnimationGraphManager* a_manager, const char* a_eventName, std::uint32_t a_result);
    void Reset();
}
