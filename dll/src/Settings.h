#pragma once

namespace PipOS
{
    // Per-tab page mode, mirroring the shell's PipboyMenu.PageModes / SetPageMode contract.
    enum class PageMode : std::uint32_t
    {
        kPipOS = 0,     // load PipOS_<Tab>Page.swf (default)
        kExternal = 1,  // load the external Pipboy_<Tab>Page.swf that wins the MO2 conflict
    };

    // Tab order matches Pipboy_DataObj page indices: 0=STAT 1=INV 2=DATA 3=MAP 4=RADIO.
    class Settings
    {
    public:
        static Settings* GetSingleton();

        // Reads Data\F4SE\Plugins\PipOSPipboy.ini [Pages]. Missing file => all kPipOS (graceful).
        void Load();

        // 0.0.38 CUSTOMIZATION (F4SE Menu Framework page). Rewrites ONLY the [Customization] keys in
        // PipOSPipboy.ini, preserving every other section/line (Pages / Character). Used by the in-game
        // ImGui settings page's Save button. Missing file => a fresh file with a [Customization] block.
        void SaveCustomization() const;

        PageMode Mode(std::size_t a_pageIndex) const;
        bool EnableCharacterCapture() const { return _enableCapture; }

        // 0.0.38 CUSTOMIZATION accessors. Const getters feed the menu-open push to root1.PipOS_settings
        // (defaults reproduce 0.0.37 exactly). Pointer accessors let the ImGui page bind sliders/checkboxes
        // directly to the live singleton fields (ImGui SliderFloat/Checkbox take T*), mirroring how S2 HUD
        // Rework's layout page edits its Settings struct in place.
        float VeilAlpha() const { return _veilAlpha; }
        bool  CrtBreathe() const { return _crtBreathe; }
        bool  CrtVignette() const { return _crtVignette; }
        bool  OpenAnim() const { return _openAnim; }
        float OpenAnimSpeed() const { return _openAnimSpeed; }   // 0.0.60
        bool  Folders() const { return _folders; }
        bool  ShowRPM() const { return _showRPM; }

        float* pVeilAlpha() { return &_veilAlpha; }
        bool*  pCrtBreathe() { return &_crtBreathe; }
        bool*  pCrtVignette() { return &_crtVignette; }
        bool*  pOpenAnim() { return &_openAnim; }
        float* pOpenAnimSpeed() { return &_openAnimSpeed; }      // 0.0.60
        bool*  pFolders() { return &_folders; }
        bool*  pShowRPM() { return &_showRPM; }
        bool*  pLive3D() { return &_live3D; }
        int*   pWidescreenSpike() { return &_wsSpike; }

        // Live-bound figure-slot placement fields (Menu Framework sliders write these directly).
        float* pChar3dScale() { return &_char3dScale; }
        float* pChar3dFov() { return &_char3dFov; }
        float* pChar3dYaw() { return &_char3dYaw; }
        float* pChar3dPitch() { return &_char3dPitch; }
        float* pChar3dRoll() { return &_char3dRoll; }
        float* pChar3dDistance() { return &_char3dDistance; }
        int*   pChar3dTarget() { return &_char3dTarget; }
        float* pChar3dClipLeft() { return &_char3dClipLeft; }
        float* pChar3dClipTop() { return &_char3dClipTop; }
        float* pChar3dClipRight() { return &_char3dClipRight; }
        float* pChar3dClipBottom() { return &_char3dClipBottom; }
        float* pChar3dScreenX() { return &_char3dScreenX; }
        float* pChar3dScreenY() { return &_char3dScreenY; }
        bool*  pChar3dAnimate() { return &_char3dAnimate; }
        int*   pChar3dIdleState() { return &_char3dIdleState; }
        bool*  pChar3dHideWeaponIdle() { return &_char3dHideWeaponIdle; }
        bool*  pChar3dSheatheWeaponIdle() { return &_char3dSheatheWeaponIdle; }
        bool*  pChar3dMirrorSneak() { return &_char3dMirrorSneak; }
        bool*  pChar3dMirrorJump() { return &_char3dMirrorJump; }
        bool*  pChar3dMirrorWeaponFire() { return &_char3dMirrorWeaponFire; }
        bool*  pChar3dMirrorWeaponReload() { return &_char3dMirrorWeaponReload; }
        bool*  pChar3dMirrorMelee() { return &_char3dMirrorMelee; }
        bool*  pChar3dMirrorThrowable() { return &_char3dMirrorThrowable; }
        bool*  pChar3dFaceMorphs() { return &_char3dFaceMorphs; }
        bool*  pChar3dCloth() { return &_char3dCloth; }
        bool*  pChar3dFollow() { return &_char3dFollow; }
        bool*  pChar3dFollowX() { return &_char3dFollowX; }
        bool*  pChar3dFollowY() { return &_char3dFollowY; }
        bool*  pChar3dFollowZ() { return &_char3dFollowZ; }
        bool*  pChar3dHidePowerArmor() { return &_char3dHidePowerArmor; }
        bool*  pChar3dAntiAliasing() { return &_char3dAntiAliasing; }
        bool*  pChar3dHologram() { return &_char3dHologram; }
        std::uint32_t* pChar3dSlotMask() { return &_char3dSlotMask; }
        float* pChar3dKeyIntensity() { return &_char3dKeyIntensity; }
        float* pChar3dFillIntensity() { return &_char3dFillIntensity; }
        float* pChar3dRimIntensity() { return &_char3dRimIntensity; }

        // M5 LIVE 3D CHARACTER (default OFF). Gates the TF3DHUD-style live equipped-player capture in
        // CharacterCapture. When false, CharacterCapture::Install() returns immediately and installs NO
        // engine hooks (byte-identical to the v1 stub). Read from [Character] bLive3D in PipOSPipboy.ini.
        bool Live3D() const { return _live3D; }
        float Char3DFov() const { return _char3dFov; }
        float Char3DScale() const { return _char3dScale; }
        float Char3DYaw() const { return _char3dYaw; }
        float Char3DPitch() const { return _char3dPitch; }
        float Char3DRoll() const { return _char3dRoll; }
        bool Char3DAnimate() const { return _char3dAnimate; }
        int Char3DIdleState() const { return _char3dIdleState; }
        bool Char3DHideWeaponIdle() const { return _char3dHideWeaponIdle; }
        bool Char3DSheatheWeaponIdle() const { return _char3dSheatheWeaponIdle; }
        bool Char3DMirrorSneak() const { return _char3dMirrorSneak; }
        bool Char3DMirrorJump() const { return _char3dMirrorJump; }
        bool Char3DMirrorWeaponFire() const { return _char3dMirrorWeaponFire; }
        bool Char3DMirrorWeaponReload() const { return _char3dMirrorWeaponReload; }
        bool Char3DMirrorMelee() const { return _char3dMirrorMelee; }
        bool Char3DMirrorThrowable() const { return _char3dMirrorThrowable; }
        bool Char3DFaceMorphs() const { return _char3dFaceMorphs; }
        bool Char3DCloth() const { return _char3dCloth; }
        bool Char3DFollow() const { return _char3dFollow; }
        bool Char3DFollowX() const { return _char3dFollowX; }
        bool Char3DFollowY() const { return _char3dFollowY; }
        bool Char3DFollowZ() const { return _char3dFollowZ; }
        bool Char3DHidePowerArmor() const { return _char3dHidePowerArmor; }
        bool Char3DAntiAliasing() const { return _char3dAntiAliasing; }
        bool Char3DHologram() const { return _char3dHologram; }
        std::uint32_t Char3DSlotMask() const { return _char3dSlotMask; }
        float Char3DKeyIntensity() const { return _char3dKeyIntensity; }
        float Char3DFillIntensity() const { return _char3dFillIntensity; }
        float Char3DRimIntensity() const { return _char3dRimIntensity; }

        // FIGURE-SLOT PLACEMENT (ported from TF3DHUD Renderer.cpp clipRect + PreviewFraming.cpp). All are
        // live-tunable via the Menu Framework page and persisted by SaveCustomization; the render-boundary hook
        // applies clip and framing edits while the renderer is active. Defaults estimate the center-column
        // figure box of the PIP-OS INV/STAT layout.
        //   clipRect L/T/R/B = POSITIVE centered extents (display-plane world units, ~±148 horiz / ±80 vert)
        //     of the on-screen window; a 0/0 pair on an axis means "use the full screen extent on that axis".
        //   cameraDistance   = camera pull-back along +Y in the offscreen frame (bigger = smaller figure).
        //   target           = framing bone the offscreen frame centers on (0=Head 1=Chest 2=Pelvis 3=Root).
        float Char3DDistance() const { return _char3dDistance; }
        int   Char3DTarget() const { return _char3dTarget; }
        float Char3DClipLeft() const { return _char3dClipLeft; }
        float Char3DClipTop() const { return _char3dClipTop; }
        float Char3DClipRight() const { return _char3dClipRight; }
        float Char3DClipBottom() const { return _char3dClipBottom; }
        float Char3DScreenX() const { return _char3dScreenX; }
        float Char3DScreenY() const { return _char3dScreenY; }

        // 16:9 feasibility spike (throwaway, default OFF => shipping behavior unchanged).
        //   0 = off; 1 = read-only diagnostic log (viewport/scale-mode/visible-frame-rect/root transform);
        //   2 = also apply the experimental widescreen scale-mode change + re-log (may fight Baka).
        int WidescreenSpike() const { return _wsSpike; }

    private:
        Settings() = default;
        std::array<PageMode, 5> _pageModes{};  // value-initialised to kPipOS (0)
        bool _enableCapture{ true };
        int _wsSpike{ 0 };

        // Live 3D character (M5). DEFAULT OFF -- shipping behavior is byte-identical until opted in.
        bool _live3D{ false };
        float _char3dFov{ 70.0f };
        float _char3dScale{ 0.45f };
        float _char3dYaw{ 160.0f };
        float _char3dPitch{ 0.0f };
        float _char3dRoll{ 0.0f };
        bool _char3dAnimate{ true };
        int _char3dIdleState{ 0 };  // 0 weapon-ready, 1 weapon-sighted; unarmed previews remain relaxed
        bool _char3dHideWeaponIdle{ false };
        bool _char3dSheatheWeaponIdle{ false };
        // TF3DHUD mirror-event groups. Locomotion is deliberately absent by user request.
        bool _char3dMirrorSneak{ true };
        bool _char3dMirrorJump{ true };
        bool _char3dMirrorWeaponFire{ true };
        bool _char3dMirrorWeaponReload{ true };
        bool _char3dMirrorMelee{ true };
        bool _char3dMirrorThrowable{ true };
        bool _char3dFaceMorphs{ true };
        bool _char3dCloth{ true };
        bool _char3dFollow{ true };
        bool _char3dFollowX{ true };
        bool _char3dFollowY{ true };
        bool _char3dFollowZ{ true };
        bool _char3dHidePowerArmor{ true };
        bool _char3dAntiAliasing{ false };
        bool _char3dHologram{ false };
        std::uint32_t _char3dSlotMask{ 0xFFFF'FFFFu };
        float _char3dKeyIntensity{ 3.4f };
        float _char3dFillIntensity{ 1.55f };
        float _char3dRimIntensity{ 2.15f };

        // Figure-slot placement (M5.1). Defaults estimate the center-column figure box of the INV/STAT layout
        // (see the port report): a window straddling screen-center, biased slightly right + above center, that
        // frames a chest-centered standing figure. All live-tunable + persisted; a rebuild is NOT required.
        float _char3dDistance{ 200.0f };
        int   _char3dTarget{ 1 };          // 0=Head 1=Chest 2=Pelvis 3=Root
        float _char3dClipLeft{ 46.0f };    // POSITIVE centered extents in display-plane world units
        float _char3dClipTop{ 56.0f };
        float _char3dClipRight{ 52.0f };
        float _char3dClipBottom{ 30.0f };
        float _char3dScreenX{ 0.0f };      // model-space X/Z translation; never modifies compositor geometry
        float _char3dScreenY{ 0.0f };

        // 0.0.38 CUSTOMIZATION. EVERY default reproduces 0.0.37 behavior exactly, so with NO ini keys (or no
        // ini file, or no Menu Framework installed) the menu uses a uniform veil at 0.10, with breathing and
        // open animation on. The old fixed edge vignette is now optional and defaults off so VeilAlpha is the
        // only background-darkening layer. These map INI([Customization]) -> DLL -> root1.PipOS_settings -> AS3.
        float _veilAlpha{ 0.10f };  // PIP-OS world-dim veil alpha (what WE own; NOT Baka's fPipboyEffectColorRGB)
        bool _crtBreathe{ true };   // Chrome CRT_BREATHE runtime override
        bool _crtVignette{ false }; // optional fixed edge darkening; off keeps background opacity spatially uniform
        bool _openAnim{ true };     // Chrome OPEN_ANIM runtime override
        float _openAnimSpeed{ 1.0f };  // 0.0.60: power-on speed multiplier (0.25-4.0; 1 = shipped timing)
        bool _folders{ true };      // Theme.FOLDERS runtime override (FIS/Complex-Sorter folder grouping)
        bool _showRPM{ false };     // Weapon card stat: false = vanilla FIRE RATE (default), true = RPM (rounds/min)
    };
}
