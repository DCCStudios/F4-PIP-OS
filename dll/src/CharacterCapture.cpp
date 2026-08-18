#include "PCH.h"
#include "CharacterCapture.h"
#include "PipboyBridge.h"
#include "Settings.h"
#include "Scaleform/G/GFx_ASMovieRootBase.h"

#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <functional>
#include <vector>

// =====================================================================================================
// PIP-OS live 3D character capture -- ARCHITECTURE PORT of PluginTemplate/TF3DHUD-master.
//
// TF3DHUD renders a live clone of the equipped third-person player into the game's own
// RE::Interface3D::Renderer (the workbench / container 3D-preview subsystem), frames + lights it, and
// composites its offscreen render target to screen through a screen-attached display mesh. This file ports
// that CORE pipeline into PipOS against the FOV-Slider CommonLibF4 fork.
//
// PORTED (this round):  Interface3D offscreen renderer configuration (Renderer.cpp), exact biped-root clone
//   with source-controller detach (PreviewClone.cpp), render-tree sanitisation / fade-node repair
//   (PreviewRenderTree.cpp), bounds-centered framing (PreviewFraming.cpp), a single front light
//   (Lights.cpp), the RunActorUpdates frame-tick driver (Previewer.cpp), and a subtle procedural breathing
//   idle. The equipped weapon rides along because it is a biped object on the cloned root.
//
// DEFERRED (documented in docs/Character3DContract.md + the report):  the 127 KB live animation-graph clone
//   + idle state machine (Animations.cpp) -> replaced by the procedural breathing idle; the FaceGen
//   morph / head-part / cloth high-detail head reconstruction (Morph/PreviewHeadParts/PreviewCloth) -> the
//   exact clone already carries the live baked body morphs + current head at third-person LOD; the
//   frame-audit signature state machine (PreviewRebuilder.cpp) -> rebuild-on-open instead; the
//   render-boundary commit + tiled-lighting deferred hooks (RenderPrepassesAndMenus / RenderSceneDeferred /
//   composite-pass ctor) -> this fork ships no REL::ASM branch-gateway, so those function-entry hooks are
//   not portable here. Possible consequence when enabled: under ENB tiled-lighting the offscreen composite
//   may be mis-lit -- a VISUAL issue, never a crash.
//
// THREADING MODEL (audit FIX-FIRST): the write_call<5> RunActorUpdates hook (REL::ID(556439)+0x17) is NOT
// reliably the main thread on this fork -- it fires >1x/frame on BSMTAManager / HighFPSPhysics worker
// threads. Running scene-graph + D3D mutation there is this project's worst crash class (see
// rainsplashes-surface-detection-state). So the hook body does ONLY cheap flag reads and SCHEDULES the
// whole build/attach/idle/teardown pass onto the MAIN thread via F4SE::GetTaskInterface()->AddTask. F4SE
// tasks are drained serially on the game main thread, so exactly one capture pass runs at a time and every
// CloneSubtree / Interface3D / NiAVObject::Update / D3D lifecycle op is single-threaded. A "task in flight"
// atomic collapses the worker-thread multiplicity so N hook fires never queue N clones. Menu-close teardown
// (HideAndRelease) is scheduled the same way, so renderer/D3D lifecycle is main-thread only.
//
// SAFETY: config-gated default-off; every step null-guarded; any failure sets g_failed and the figure slot
// falls back to the placeholder. No try/catch is relied upon for AV safety -- correctness is null-guards +
// main-thread-task affinity (all scene/renderer mutation happens inside RunCaptureTask on the main thread).
// =====================================================================================================

namespace PipOS
{
    namespace
    {
        constexpr auto kRendererName = "PipOS_Char3D";
        constexpr auto kDisplayMeshPath = "Interface/GunModMenu/ModMenuRenderMesh.nif";
        constexpr auto kDisplayMeshGeometry = "ModMenuRenderMesh:0";
        constexpr float kDisplayRootY = 375.0f;
        constexpr float kPi = 3.14159265358979323846f;
        constexpr std::string_view kPipboyMenu = "PipboyMenu"sv;

        // Display-mesh clip-rect port (TF3DHUD Renderer.cpp). The ModMenuRenderMesh quad lives on a plane at
        // local Y=375; kDisplayMeshPlaneY is its vanilla near-zero plane offset. The kVanilla* values are the
        // full-frame display extents used only when no placement camera frustum is available at apply time.
        constexpr float kDisplayMeshPlaneY = -0.0000013113022f;
        constexpr float kVanillaDisplayLeft = -148.125f;
        constexpr float kVanillaDisplayTop = 79.875f;
        constexpr float kVanillaDisplayRight = 148.125f;
        constexpr float kVanillaDisplayBottom = -79.875f;

        // Centered display-plane sub-rect (left<=0, right>=0, top>=0, bottom<=0). Used for both the full-frame
        // extents and the clipped figure-slot window.
        struct DisplayBounds
        {
            float left;
            float top;
            float right;
            float bottom;
        };

        // BSFadeNode / NiAVObject flag bit forcing a fade node to render fully opaque (IDA: BSFadeNode
        // fast-paths visible nodes when 0x8000 + fade fields are all set). Ported from PreviewRenderTree.
        constexpr std::uint64_t kNiAVObjectFadeDone = 0x8000;
        constexpr std::uint64_t kNiAVObjectTopFadeNode = 0x4000;   // 0.0.64: distance-faded-LOD-root flag; cleared on the clone

        // ForceUpgradeTextures(NiAVObject*, bool, bool) -- OG 1.10.163, TF3DHUD Address.cpp REL::ID{1417022}.
        REL::Relocation<void (*)(RE::NiAVObject*, bool, bool)> g_forceUpgradeTextures{ REL::ID(1417022) };

        // ---- cross-thread flags (touched from the worker-thread hook + the menu sink) ----
        // These are the ONLY fields the off-main-thread code touches. Everything else is main-thread-only.
        std::atomic<bool> g_installed{ false };
        std::atomic<bool> g_available{ false };    // an offscreen player clone is currently live
        std::atomic<bool> g_pipboyOpen{ false };   // set by the menu sink; read cheaply in the hook
        std::atomic<bool> g_dirty{ true };          // rebuild requested (set on menu open / after release)
        std::atomic<bool> g_taskInFlight{ false };  // collapses worker-thread hook multiplicity -> 1 pass queued
        std::atomic<bool> g_failed{ false };        // hard-disable for the rest of the session on any failure

        // ---- MAIN-THREAD-ONLY scene state (only ever touched inside RunCaptureTask / teardown tasks, which
        //      F4SE drains serially on the game main thread -- so no lock is required) ----
        bool g_visible{ false };
        RE::Interface3D::Renderer* g_renderer{ nullptr };
        RE::NiPointer<RE::NiAVObject> g_previewRoot;
        RE::NiPointer<RE::NiAVObject> g_displayRoot;
        const RE::NiAVObject* g_sourceRoot{ nullptr };  // detect a player-3D swap -> rebuild
        RE::NiTransform g_baseTransform;                // framed transform; breathing is added on top
        float g_idleTime{ 0.0f };

        // Display-mesh clip-rect state (TF3DHUD Renderer.cpp). g_privateDisplayRendererData owns the rebuilt
        // BSGraphics::TriShape we substitute for the vanilla quad; g_appliedDisplayBounds caches the last
        // applied window so a no-change re-apply is a cheap early-out. Main-thread-only, like the rest.
        RE::BSGraphics::TriShape* g_privateDisplayRendererData{ nullptr };
        DisplayBounds g_appliedDisplayBounds{};
        bool g_displayClipApplied{ false };

        using RunActorUpdates_t = void(void*, float, bool);
        RunActorUpdates_t* g_origRunActorUpdates{ nullptr };

        // Forward decls (definitions live further down, next to the contract push they wrap).
        void SchedulePushContract();

        // ------------------------------------------------------------------ traversal helpers
        void ForEachAVObject(RE::NiAVObject* a_object, const std::function<void(RE::NiAVObject&)>& a_fn)
        {
            if (!a_object) { return; }
            a_fn(*a_object);
            if (auto* node = netimmerse_cast<RE::NiNode*>(a_object)) {
                for (auto& child : node->children) {
                    if (child) { ForEachAVObject(child.get(), a_fn); }
                }
            }
        }

        // ------------------------------------------------------------------ framing target (PreviewFraming.cpp)
        // FO4 biped bones live in a BSFlattenedBoneTree, so a plain GetObjectByName on the root won't reach
        // them. These two helpers (ported from TF3DHUD Utils.cpp, adapted to netimmerse_cast since this fork
        // exposes no NiAVObject::IsNode) locate the flattened tree and a named bone within it.
        RE::BSFlattenedBoneTree* FindFlattenedBoneTree(RE::NiAVObject* a_root)
        {
            if (!a_root) { return nullptr; }
            if (auto* flattened = netimmerse_cast<RE::BSFlattenedBoneTree*>(a_root)) { return flattened; }
            auto* node = netimmerse_cast<RE::NiNode*>(a_root);
            if (!node) { return nullptr; }
            for (auto& child : node->children) {
                if (child) {
                    if (auto* flattened = FindFlattenedBoneTree(child.get())) { return flattened; }
                }
            }
            return nullptr;
        }

        RE::BSFlattenedBoneTree::FlattenedBone* FindFlattenedBoneByName(
            RE::BSFlattenedBoneTree& a_tree, std::string_view a_name)
        {
            if (!a_tree.bone || a_tree.boneCount <= 0 || a_tree.boneCount > 1024) { return nullptr; }
            for (std::int32_t i = 0; i < a_tree.boneCount; ++i) {
                auto& bone = a_tree.bone[i];
                const char* name = bone.name.c_str();
                if (name && a_name == name) { return std::addressof(bone); }
            }
            return nullptr;
        }

        // Resolve the world position of the configured framing target (0=Head 1=Chest 2=Pelvis 3=Root).
        // Returns false if the named bone can't be found, so the caller can fall back to the bounds center.
        bool TryGetFramingTargetWorld(RE::NiAVObject& a_root, int a_target, RE::NiPoint3& a_out)
        {
            if (a_target == 3) {  // Root -> the preview root's own world origin
                a_out = a_root.world.translate;
                return true;
            }
            const char* name = (a_target == 0) ? "Head" : (a_target == 1) ? "Chest" : "Pelvis";
            const RE::BSFixedString boneName(name);

            if (auto* flattened = FindFlattenedBoneTree(std::addressof(a_root))) {
                if (auto* object = flattened->GetObjectByName(boneName)) {
                    a_out = object->world.translate;
                    return true;
                }
                if (auto* bone = FindFlattenedBoneByName(*flattened, name)) {
                    a_out = bone->node ? bone->node->world.translate : bone->world.translate;
                    return true;
                }
            }
            if (auto* object = a_root.GetObjectByName(boneName)) {
                a_out = object->world.translate;
                return true;
            }
            return false;
        }

        // ------------------------------------------------------------------ clone (PreviewClone.cpp)
        // Exact clone of the source subtree. Source controllers are detached during the clone so per-frame
        // animation controllers are not deep-copied/driven on the offscreen copy, then restored on the live
        // model. We deliberately do NOT seed skin-bone remaps (TF3DHUD's shared-skeleton optimisation): an
        // exact clone yields a fully self-contained skinned copy, which needs far less of the RE surface.
        RE::NiPointer<RE::NiAVObject> CloneSubtree(RE::NiAVObject& a_source)
        {
            RE::NiCloningProcess cloneProcess;
            cloneProcess.appendChar = '$';
            cloneProcess.copyType = RE::NiCloningProcess::CopyType::kCopyExact;
            cloneProcess.scale = { 1.0f, 1.0f, 1.0f };

            std::vector<std::pair<RE::NiAVObject*, RE::NiPointer<RE::NiTimeController>>> detached;
            ForEachAVObject(std::addressof(a_source), [&](RE::NiAVObject& a_object) {
                if (a_object.controllers) {
                    detached.emplace_back(std::addressof(a_object), a_object.controllers);
                    a_object.controllers.reset();
                }
            });

            RE::NiObject* clone = a_source.CreateClone(cloneProcess);
            a_source.ProcessClone(cloneProcess);

            for (auto& [object, controller] : detached) {
                if (object) { object->controllers = controller; }
            }

            return clone ? RE::NiPointer<RE::NiAVObject>(static_cast<RE::NiAVObject*>(clone)) : nullptr;
        }

        // ------------------------------------------------------------------ fade-node repair (PreviewRenderTree.cpp)
        // 0.0.64 THE LIVE-3D FIX. Re-own each cloned geometry's shader-property fadeNode to the nearest enclosing
        // BSFadeNode IN THE CLONE. BSShaderProperty::fadeNode (0x48) is a NON-OWNING back-pointer that
        // NiCloningProcess does not remap, so after CloneSubtree every cloned geometry's fadeNode still points at
        // the SOURCE player's fade node. The offscreen deferred path (Offscreen_SetPostEffect(kModMenu)) clears a
        // geometry's draw passes when its fadeNode lacks kNiAVObjectFadeDone / has currentFade<=0 -- so with the
        // stale source pointer the clone contributes NO geometry to the offscreen RT and the figure slot is an
        // empty black hole (renderer/RT/quad all fine -> "reports success but nothing renders"). Pointing each
        // property at the clone's own sanitised fade node (currentFade=1, FadeDone-flagged) restores the passes.
        // Ported from TF3DHUD PreviewRenderTree::RepairShaderFadeNodes. Returns the count of properties whose
        // pointer was actually changed (diagnostic: >0 confirms the stale-back-pointer diagnosis in the field).
        int RepairShaderFadeNodes(RE::NiAVObject& a_object, RE::BSFadeNode* a_currentFadeNode)
        {
            int repaired = 0;
            if (auto* fade = netimmerse_cast<RE::BSFadeNode*>(std::addressof(a_object))) {
                a_currentFadeNode = fade;
            }
            if (a_currentFadeNode) {
                if (auto* geometry = netimmerse_cast<RE::BSGeometry*>(std::addressof(a_object))) {
                    for (auto& property : geometry->properties) {
                        if (auto* shaderProperty = netimmerse_cast<RE::BSShaderProperty*>(property.get())) {
                            if (shaderProperty->fadeNode != a_currentFadeNode) { ++repaired; }
                            shaderProperty->fadeNode = a_currentFadeNode;
                        }
                    }
                }
            }
            if (auto* node = netimmerse_cast<RE::NiNode*>(std::addressof(a_object))) {
                for (auto& child : node->children) {
                    if (child) { repaired += RepairShaderFadeNodes(*child, a_currentFadeNode); }
                }
            }
            return repaired;
        }

        // ------------------------------------------------------------------ sanitise (PreviewRenderTree.cpp)
        void SanitizeClone(RE::NiAVObject& a_root)
        {
            ForEachAVObject(std::addressof(a_root), [&](RE::NiAVObject& a_object) {
                a_object.controllers.reset();  // no cloned controllers should drive the offscreen copy
                a_object.fadeAmount = 1.0f;
                if (auto* fade = netimmerse_cast<RE::BSFadeNode*>(std::addressof(a_object))) {
                    a_object.flags.flags |= kNiAVObjectFadeDone;
                    a_object.flags.flags &= ~kNiAVObjectTopFadeNode;   // 0.0.64: fade-node-scoped (matches TF3DHUD; not every node) -- stop treating the clone as a distance-faded LOD root
                    fade->currentFade = 1.0f;
                    fade->currentDecalFade = 1.0f;
                    fade->previousMaxA = 1.0f;
                }
                // 0.0.64: DELIBERATELY no blanket SetAppCulled(false). TF3DHUD renders the same cloned player
                // subtree without un-culling (the offscreen renderer draws the attached tree on its own pass), and
                // a blanket un-cull risks revealing neck-gore / intentionally-hidden parts. If a future test shows
                // an app-culled-invisible model, port TF3DHUD's SELECTIVE cull (gore + missing-material) instead.
            });

            // Re-own the shader fadeNode back-pointers to the clone BEFORE the flush Update below, so the single
            // Update() propagates the corrected tree (matches TF3DHUD's order).
            const int repaired = RepairShaderFadeNodes(a_root, nullptr);
            logger::info("[PipOS][3D] fade-node repair: re-owned {} shader properties to the clone", repaired);

            RE::NiUpdateData updateData{};
            a_root.Update(updateData);
        }

        // ------------------------------------------------------------------ framing (PreviewFraming.cpp)
        void FrameClone(RE::NiAVObject& a_root)
        {
            auto* settings = Settings::GetSingleton();
            const float scale = settings ? settings->Char3DScale() : 0.45f;
            const float yaw = settings ? settings->Char3DYaw() : 160.0f;
            const float distance = settings ? settings->Char3DDistance() : 200.0f;
            const int target = settings ? settings->Char3DTarget() : 1;

            RE::NiTransform transform = RE::NiTransform::IDENTITY;
            transform.scale = scale;
            transform.rotate.FromEulerAnglesXYZ(0.0f, 0.0f, yaw * kPi / 180.0f);
            a_root.SetLocalTransform(transform);

            RE::NiUpdateData updateData{};
            a_root.Update(updateData);

            // Center the configured framing target (Head/Chest/Pelvis/Root) at the offscreen frame origin; the
            // camera looks down +Y, so the target lands at screen-center. Fall back to the whole-body bounds
            // center (the pre-port behavior) if the named bone can't be resolved.
            RE::NiPoint3 targetWorld;
            if (!TryGetFramingTargetWorld(a_root, target, targetWorld)) {
                targetWorld = a_root.worldBound.center;
            }
            auto centered = a_root.GetLocalTransform();
            centered.translate = { -targetWorld.x, -targetWorld.y + distance, -targetWorld.z };
            a_root.SetLocalTransform(centered);
            a_root.Update(updateData);

            g_baseTransform = centered;
        }

        // ------------------------------------------------------------------ procedural idle (breathing)
        // Placeholder for TF3DHUD's live animation-graph idle. Gently modulates the framed root each frame so
        // the figure reads as breathing rather than a frozen mannequin. Operates on already-attached nodes
        // only (writing a transform to an existing node is what TF3DHUD's framing-follow does per frame).
        void ApplyIdle(RE::NiAVObject& a_root, float a_delta)
        {
            g_idleTime += (a_delta > 0.0f && a_delta < 1.0f) ? a_delta : (1.0f / 30.0f);
            const float breath = std::sin(g_idleTime * 1.6f);

            RE::NiTransform transform = g_baseTransform;
            transform.translate.z += breath * 0.4f;
            transform.scale = g_baseTransform.scale * (1.0f + breath * 0.004f);
            a_root.SetLocalTransform(transform);

            RE::NiUpdateData updateData{};
            a_root.Update(updateData);
        }

        // ------------------------------------------------------------------ renderer (Renderer.cpp)
        bool ConfigureRenderer()
        {
            if (g_renderer) { return true; }

            auto* settings = Settings::GetSingleton();
            const float fov = settings ? settings->Char3DFov() : 70.0f;
            const RE::BSFixedString name(kRendererName);

            g_renderer = RE::Interface3D::Renderer::GetByName(name);
            if (!g_renderer) {
                // 0.0.60: kTerminal (0x9), not kStandard3DModel (0x7). PipboyMenu draws at kStandard (0x6) but
                // the pipboy layer family reaches kPipboy (0x8); at 0x7 the screen-attached quad could composite
                // UNDER the (Baka-fullscreened) menu -- the "renderer enabled but no figure visible" symptom.
                // kTerminal sits above both, below game messages/cursor, and only exists while the Pip-Boy is open.
                g_renderer = RE::Interface3D::Renderer::Create(
                    name, RE::UI_DEPTH_PRIORITY::kTerminal, fov, false);
            }
            if (!g_renderer) {
                logger::error("[PipOS][3D] Interface3D renderer creation returned null");
                return false;
            }

            g_renderer->MainScreen_SetBackgroundMode(RE::Interface3D::BackgroundMode::kLive);
            g_renderer->useFullPremultAlpha = true;
            g_renderer->MainScreen_SetPostAA(true);
            g_renderer->Offscreen_Enable3D(true);
            g_renderer->Offscreen_SetUseLongRangeCamera(true);
            g_renderer->Offscreen_SetRenderTargetSize(RE::Interface3D::OffscreenMenuSize::kFullFrame);
            g_renderer->Offscreen_SetDisplayMode(
                RE::Interface3D::ScreenMode::kScreenAttached, kDisplayMeshGeometry, nullptr);
            g_renderer->MainScreen_EnableScreenAttached3DMasking(nullptr, nullptr);
            g_renderer->Offscreen_SetPostEffect(RE::Interface3D::PostEffect::kModMenu);
            g_renderer->customRenderTarget = -1;
            g_renderer->customSwapTarget = -1;

            logger::info("[PipOS][3D] Interface3D renderer '{}' configured (offscreen RT={}x{})",
                kRendererName,
                g_renderer->Offscreen_GetRenderTargetWidth(),
                g_renderer->Offscreen_GetRenderTargetHeight());
            return true;
        }

        // ============================================================ display-mesh clip rect (Renderer.cpp)
        // Reshapes the screen-attached ModMenuRenderMesh:0 quad from the vanilla full-frame rectangle to an
        // arbitrary SCREEN sub-rectangle (the figure slot), rebuilding its vertex/index buffers so the
        // offscreen render composites into exactly that window. This is D3D resource creation and therefore
        // runs ONLY inside the F4SE main-thread task (via Tick/BuildPreview), never the worker-thread hook.

        [[nodiscard]] std::uint16_t FloatToHalf(const float a_value)
        {
            std::uint32_t bits;
            std::memcpy(std::addressof(bits), std::addressof(a_value), sizeof(bits));
            const auto sign = static_cast<std::uint16_t>((bits >> 16) & 0x8000);
            auto exponent = static_cast<std::int32_t>((bits >> 23) & 0xFF);
            auto mantissa = bits & 0x7FFFFF;
            if (exponent == 0xFF) {
                if (mantissa != 0) { return static_cast<std::uint16_t>(sign | 0x7E00); }
                return static_cast<std::uint16_t>(sign | 0x7C00);
            }
            exponent = exponent - 127 + 15;
            if (exponent >= 0x1F) { return static_cast<std::uint16_t>(sign | 0x7C00); }
            if (exponent <= 0) {
                if (exponent < -10) { return sign; }
                mantissa |= 0x800000;
                const auto shift = static_cast<std::uint32_t>(14 - exponent);
                auto halfMantissa = static_cast<std::uint16_t>(mantissa >> shift);
                if ((mantissa >> (shift - 1)) & 1) { ++halfMantissa; }
                return static_cast<std::uint16_t>(sign | halfMantissa);
            }
            auto half = static_cast<std::uint16_t>(
                sign | (static_cast<std::uint16_t>(exponent) << 10) | (mantissa >> 13));
            if (mantissa & 0x1000) { ++half; }
            return half;
        }

        void WriteHalf(std::byte* a_target, const float a_value)
        {
            const auto half = FloatToHalf(a_value);
            std::memcpy(a_target, std::addressof(half), sizeof(half));
        }

        [[nodiscard]] bool SameDisplayBounds(const DisplayBounds& a_lhs, const DisplayBounds& a_rhs)
        {
            constexpr float epsilon = 0.0001f;
            return std::abs(a_lhs.left - a_rhs.left) <= epsilon &&
                   std::abs(a_lhs.top - a_rhs.top) <= epsilon &&
                   std::abs(a_lhs.right - a_rhs.right) <= epsilon &&
                   std::abs(a_lhs.bottom - a_rhs.bottom) <= epsilon;
        }

        [[nodiscard]] RE::NiCamera* GetDisplayPlacementCamera()
        {
            if (!g_renderer) { return nullptr; }
            if (g_renderer->nativeAspect) { return g_renderer->nativeAspect.get(); }
            if (g_renderer->nativeAspectLongRange) { return g_renderer->nativeAspectLongRange.get(); }
            return g_renderer->pipboyAspect.get();
        }

        [[nodiscard]] DisplayBounds GetScreenPlaneBounds()
        {
            constexpr float displayPlaneY = kDisplayRootY + kDisplayMeshPlaneY;
            if (const auto* camera = GetDisplayPlacementCamera()) {
                return {
                    camera->viewFrustum.left * displayPlaneY,
                    camera->viewFrustum.top * displayPlaneY,
                    camera->viewFrustum.right * displayPlaneY,
                    camera->viewFrustum.bottom * displayPlaneY
                };
            }
            return { kVanillaDisplayLeft, kVanillaDisplayTop, kVanillaDisplayRight, kVanillaDisplayBottom };
        }

        // Map the configured positive centered extents onto a display-plane sub-rect. A 0/0 pair on an axis
        // means "use the full screen extent on that axis" (so left=right=0 spans the whole width).
        [[nodiscard]] DisplayBounds GetDisplayBounds(const DisplayBounds& a_full)
        {
            auto* settings = Settings::GetSingleton();
            const float cl = settings ? settings->Char3DClipLeft() : 0.0f;
            const float ct = settings ? settings->Char3DClipTop() : 0.0f;
            const float cr = settings ? settings->Char3DClipRight() : 0.0f;
            const float cb = settings ? settings->Char3DClipBottom() : 0.0f;
            const bool hasCustomHorizontal = cl != 0.0f || cr != 0.0f;
            const bool hasCustomVertical = ct != 0.0f || cb != 0.0f;
            const DisplayBounds bounds{
                hasCustomHorizontal ? -std::max(cl, 0.0f) : a_full.left,
                hasCustomVertical ? std::max(ct, 0.0f) : a_full.top,
                hasCustomHorizontal ? std::max(cr, 0.0f) : a_full.right,
                hasCustomVertical ? -std::max(cb, 0.0f) : a_full.bottom
            };
            if (bounds.right > bounds.left && bounds.top > bounds.bottom) { return bounds; }
            logger::info("[PipOS][3D] ignored invalid clipRect extents (L={} T={} R={} B={}); using full frame",
                cl, ct, cr, cb);
            return a_full;
        }

        [[nodiscard]] float NormalizeDisplayX(const float a_x, const DisplayBounds& a_full)
        {
            return (a_x - a_full.left) / (a_full.right - a_full.left);
        }

        [[nodiscard]] float NormalizeDisplayZ(const float a_z, const DisplayBounds& a_full)
        {
            return (a_z - a_full.top) / (a_full.bottom - a_full.top);
        }

        [[nodiscard]] RE::BSGraphics::TriShape* GetDisplayRendererData()
        {
            if (!g_displayRoot) { return nullptr; }
            auto* object = g_displayRoot->GetObjectByName(RE::BSFixedString(kDisplayMeshGeometry));
            auto* triShape = object ? object->IsTriShape() : nullptr;
            auto* geometry = triShape ? static_cast<RE::BSGeometry*>(triShape) : nullptr;
            return geometry ? static_cast<RE::BSGraphics::TriShape*>(geometry->rendererData) : nullptr;
        }

        // True while the quad's GPU buffers are mid-upload; reshaping then would race the copy, so we defer to
        // a later frame (Tick re-checks). Mirrors TF3DHUD's CanApplyDisplayClipRect gate.
        [[nodiscard]] bool DisplayClipRectCopyPending()
        {
            auto* rendererData = GetDisplayRendererData();
            auto* vertexBuffer = rendererData ? rendererData->vertexBuffer : nullptr;
            auto* indexBuffer = rendererData ? rendererData->indexBuffer : nullptr;
            return (vertexBuffer && vertexBuffer->pendingCopy) || (indexBuffer && indexBuffer->pendingCopy);
        }

        void ApplyDisplayClipRect()
        {
            if (!g_displayRoot) { return; }

            const auto fullBounds = GetScreenPlaneBounds();
            const auto bounds = GetDisplayBounds(fullBounds);
            if (g_displayClipApplied && SameDisplayBounds(g_appliedDisplayBounds, bounds)) { return; }

            auto* object = g_displayRoot->GetObjectByName(RE::BSFixedString(kDisplayMeshGeometry));
            auto* triShape = object ? object->IsTriShape() : nullptr;
            auto* geometry = triShape ? static_cast<RE::BSGeometry*>(triShape) : nullptr;
            auto* rendererData = geometry ? static_cast<RE::BSGraphics::TriShape*>(geometry->rendererData) : nullptr;
            auto* vertexBuffer = rendererData ? rendererData->vertexBuffer : nullptr;
            auto* indexBuffer = rendererData ? rendererData->indexBuffer : nullptr;
            if (!triShape || !rendererData || !vertexBuffer || !vertexBuffer->data || !indexBuffer || !indexBuffer->data) {
                logger::info("[PipOS][3D] clipRect skipped: display geometry not ready");
                return;
            }

            // ModMenuRenderMesh:0 is a 4-vertex, 20-byte-stride, half-precision quad (pos@0, uv@8). If the
            // asset layout ever differs, bail and let it composite full-frame rather than corrupt the buffer.
            const auto desc = rendererData->vertexDesc.desc;
            const auto stride = static_cast<std::uint32_t>((desc & 0xF) * 4);
            const auto positionOffset = static_cast<std::uint32_t>((desc >> 2) & 0x3C);
            const auto uvOffset = static_cast<std::uint32_t>((desc >> 6) & 0x3C);
            const auto fullPrecision = ((desc >> 44) & RE::BSGraphics::Vertex::VF_FULLPREC) != 0;
            if (triShape->numVertices != 4 || stride != 20 || positionOffset != 0 || uvOffset != 8 || fullPrecision) {
                logger::info("[PipOS][3D] clipRect skipped: unsupported '{}' layout (verts={}, stride={}, desc={:X})",
                    kDisplayMeshGeometry, triShape->numVertices, stride, desc);
                return;
            }

            const auto vertexBytes = static_cast<std::size_t>(triShape->numVertices) * stride;
            std::array<std::byte, 128> vertexDataCopy{};
            if (vertexBytes > vertexDataCopy.size()) { return; }
            std::memcpy(vertexDataCopy.data(), vertexBuffer->data, vertexBytes);

            const std::array<std::array<float, 3>, 4> positions{ {
                { bounds.left, kDisplayMeshPlaneY, bounds.bottom },
                { bounds.right, kDisplayMeshPlaneY, bounds.bottom },
                { bounds.right, kDisplayMeshPlaneY, bounds.top },
                { bounds.left, kDisplayMeshPlaneY, bounds.top }
            } };
            const auto uvLeft = std::clamp(NormalizeDisplayX(bounds.left, fullBounds), 0.0f, 1.0f);
            const auto uvTop = std::clamp(NormalizeDisplayZ(bounds.top, fullBounds), 0.0f, 1.0f);
            const auto uvRight = std::clamp(NormalizeDisplayX(bounds.right, fullBounds), 0.0f, 1.0f);
            const auto uvBottom = std::clamp(NormalizeDisplayZ(bounds.bottom, fullBounds), 0.0f, 1.0f);
            const std::array<std::array<float, 2>, 4> uvs{ {
                { uvLeft, uvBottom },
                { uvRight, uvBottom },
                { uvRight, uvTop },
                { uvLeft, uvTop }
            } };

            auto* vertexData = vertexDataCopy.data();
            for (std::uint16_t i = 0; i < triShape->numVertices; ++i) {
                auto* position = vertexData + (static_cast<std::size_t>(i) * stride) + positionOffset;
                WriteHalf(position, positions[i][0]);
                WriteHalf(position + 2, positions[i][1]);
                WriteHalf(position + 4, positions[i][2]);
                WriteHalf(position + 6, 1.0f);
                auto* uv = vertexData + (static_cast<std::size_t>(i) * stride) + uvOffset;
                WriteHalf(uv, uvs[i][0]);
                WriteHalf(uv + 2, uvs[i][1]);
            }

            auto* resourceManager = RE::BSShaderResourceManager::GetSingleton();
            if (!resourceManager) { return; }

            auto dataSize = static_cast<std::uint32_t>(vertexBytes);
            auto* newVertexBuffer = static_cast<RE::BSGraphics::VertexBuffer*>(
                resourceManager->CreateVertexBuffer(std::addressof(dataSize), vertexDataCopy.data(), stride, 0));
            if (!newVertexBuffer) {
                logger::info("[PipOS][3D] clipRect skipped: CreateVertexBuffer failed");
                return;
            }

            const auto indexCount = triShape->numTriangles * 3U;
            if (indexCount == 0 || indexBuffer->dataSize < indexCount * sizeof(std::uint16_t)) {
                resourceManager->DecRefVertexBuffer(newVertexBuffer);
                return;
            }

            auto* newRendererData = static_cast<RE::BSGraphics::TriShape*>(
                resourceManager->CreateTriShapeRendererData(
                    newVertexBuffer, desc, static_cast<std::uint16_t*>(indexBuffer->data), indexCount));
            resourceManager->DecRefVertexBuffer(newVertexBuffer);
            if (!newRendererData) {
                logger::info("[PipOS][3D] clipRect skipped: CreateTriShapeRendererData failed");
                return;
            }

            auto* oldPrivateRendererData = g_privateDisplayRendererData;
            geometry->rendererData = newRendererData;
            g_privateDisplayRendererData = newRendererData;
            if (oldPrivateRendererData && oldPrivateRendererData != newRendererData) {
                resourceManager->DecRefTriShape(oldPrivateRendererData);
            }

            const auto centerX = (bounds.left + bounds.right) * 0.5f;
            const auto centerZ = (bounds.top + bounds.bottom) * 0.5f;
            const auto halfX = (bounds.right - bounds.left) * 0.5f;
            const auto halfZ = std::abs(bounds.top - bounds.bottom) * 0.5f;
            geometry->modelBound.center = { centerX, kDisplayMeshPlaneY, centerZ };
            geometry->modelBound.fRadius = std::sqrt((halfX * halfX) + (halfZ * halfZ));

            RE::NiUpdateData updateData{};
            g_displayRoot->Update(updateData);
            g_appliedDisplayBounds = bounds;
            g_displayClipApplied = true;
            logger::info("[PipOS][3D] clipRect applied: window L={} T={} R={} B={}",
                bounds.left, bounds.top, bounds.right, bounds.bottom);
        }

        void EnsureDisplayRoot()
        {
            if (g_displayRoot) { return; }
            // Fresh display root -> its rebuilt-quad state is stale; force the next ApplyDisplayClipRect.
            g_privateDisplayRendererData = nullptr;
            g_displayClipApplied = false;

            RE::NiPointer<RE::NiNode> loaded;
            RE::BSModelDB::DBTraits::ArgsType args{};
            args.prepareAfterLoad = true;
            args.useErrorMarker = true;
            args.performProcess = true;
            args.createFadeNode = true;
            args.loadTextures = true;
            RE::BSModelDB::Demand(kDisplayMeshPath, std::addressof(loaded), args);
            if (!loaded) {
                logger::info("[PipOS][3D] failed to load display mesh '{}'", kDisplayMeshPath);
                return;
            }

            auto clone = CloneSubtree(*loaded);
            RE::NiAVObject* display = clone ? clone.get() : static_cast<RE::NiAVObject*>(loaded.get());
            // IDA: WorkbenchMenuBase::UpdateMenu writes local translate {0, 375, 0} before Update.
            display->SetLocalTranslate({ 0.0f, kDisplayRootY, 0.0f });
            RE::NiUpdateData updateData{};
            display->Update(updateData);
            g_displayRoot = display;
        }

        void AttachToRenderer(RE::NiAVObject& a_previewRoot)
        {
            if (!g_renderer) { return; }

            EnsureDisplayRoot();
            if (g_displayRoot) {
                // Reshape the quad into the figure-slot window before attaching (deferred a frame by Tick if
                // the buffers are still uploading). D3D resource creation -> main-thread task only, which is
                // where this whole call chain runs.
                if (!DisplayClipRectCopyPending()) { ApplyDisplayClipRect(); }
                g_renderer->MainScreen_SetScreenAttached3D(g_displayRoot.get());
                g_renderer->MainScreen_RegisterGeometryRequiringFullViewport(g_displayRoot.get());
            }

            g_forceUpgradeTextures(std::addressof(a_previewRoot), false, false);
            g_renderer->Offscreen_Set3D(std::addressof(a_previewRoot));

            // Single front directional-ish fill (Lights.cpp DefaultLights). 3rd NiColor.r encodes distance.
            g_renderer->offscreenLights.clear();
            g_renderer->needsLightSetupOffscreen = true;
            g_renderer->Offscreen_AddLight(
                RE::NiPoint3{ 50.0f, 0.0f, 50.0f },
                RE::NiColor{ 0.841f, 0.758f, 0.785f },
                RE::NiColor{ 1000.0f, 0.0f, 0.0f },
                3.0f);
        }

        bool BuildPreview(RE::NiAVObject& a_source)
        {
            auto clone = CloneSubtree(a_source);
            if (!clone) {
                logger::error("[PipOS][3D] player biped clone failed");
                return false;
            }
            SanitizeClone(*clone);
            FrameClone(*clone);
            AttachToRenderer(*clone);
            g_previewRoot = clone;
            g_sourceRoot = std::addressof(a_source);
            logger::info("[PipOS][3D] preview built + attached to offscreen renderer");
            return true;
        }

        void HideAndRelease()
        {
            if (g_renderer) {
                g_renderer->Offscreen_Set3D(nullptr);
                if (g_visible || g_renderer->enabled) { g_renderer->Disable(); }
            }
            g_visible = false;
            g_available.store(false);
            g_previewRoot.reset();
            g_sourceRoot = nullptr;
            g_dirty = true;
        }

        [[nodiscard]] bool PipboyOpen()
        {
            auto* ui = RE::UI::GetSingleton();
            if (!ui) { return false; }
            auto menu = ui->GetMenu(RE::BSFixedString(kPipboyMenu.data()));
            return menu.get() != nullptr;
        }

        // Frame tick -- runs ONLY on the game main thread, inside RunCaptureTask (an F4SE task). All scene-graph
        // and D3D mutation happens here; the worker-thread hook never reaches this.
        void Tick(float a_delta)
        {
            if (g_failed.load()) { return; }

            auto* settings = Settings::GetSingleton();
            const bool wantShow = settings && settings->Live3D() && PipboyOpen();
            if (!wantShow) {
                if (g_available.load() || g_visible || g_previewRoot) { HideAndRelease(); }
                return;
            }

            auto* player = RE::PlayerCharacter::GetSingleton();
            if (!player) { HideAndRelease(); return; }

            if (!ConfigureRenderer() || !g_renderer) {
                logger::error("[PipOS][3D] renderer unavailable; disabling live 3D for this session");
                g_failed = true;
                HideAndRelease();
                return;
            }

            auto* source = player->Get3D(false);  // third-person root (carries worn armor + weapon)
            if (!source) { HideAndRelease(); return; }

            if (!g_previewRoot || g_dirty || g_sourceRoot != source) {
                if (!BuildPreview(*source)) { HideAndRelease(); return; }
                g_dirty = false;
            }

            if (g_previewRoot) { ApplyIdle(*g_previewRoot, a_delta); }

            // Re-apply the figure-slot window each pass (main-thread task). SameDisplayBounds makes an
            // unchanged window a no-op, so this only rebuilds the quad when (a) the initial build deferred it
            // because the buffers were still uploading, or (b) the user retuned a clipRect slider -- letting a
            // reopened Pip-Boy pick up new placement values without a game restart.
            if (g_displayRoot && !DisplayClipRectCopyPending()) { ApplyDisplayClipRect(); }

            if (!g_visible) {
                g_renderer->Enable(false);
                g_visible = true;
                logger::info("[PipOS][3D] offscreen renderer enabled");
            }
            g_available.store(true);
        }

        // MAIN-THREAD task body: the entire build/attach/idle/teardown pass. Scheduled from the hook via
        // AddTask; F4SE drains it serially on the game main thread. Re-pushes the AS3 contract whenever the
        // "clone is live" availability flips, so the AS3 side learns when the capture actually goes live.
        void RunCaptureTask(float a_delta)
        {
            // Reset the in-flight gate FIRST so the next frame's hook can queue the following pass. F4SE tasks
            // never run concurrently, so at most one pass executes + one is queued -- never N clones.
            g_taskInFlight.store(false);
            if (g_failed.load()) { return; }

            const bool wasAvailable = g_available.load();
            Tick(a_delta);
            if (g_available.load() != wasAvailable) {
                SchedulePushContract();  // clone went live / was released -> tell AS3 (available:true/false)
            }
            // 0.0.60: piggyback the equipment live-refresh on this main-thread pass (runs while the Pip-Boy is
            // open regardless of bLive3D -- Tick() early-outs but this line still fires). Rate-limited inside.
            // 0.0.62: also poll the right mouse button here (forwards right-click to the AS context menu).
            if (g_pipboyOpen.load()) { RepushEquipmentPeriodic(); PollRightClick(); }
        }

        // WORKER-THREAD-SAFE hook body: on this fork RunActorUpdates fires on BSMTAManager / HighFPSPhysics
        // worker threads >1x/frame. Do ONLY cheap atomic reads here and SCHEDULE the real pass onto the main
        // thread. No scene graph / D3D / UI-map access on this thread. g_pipboyOpen is maintained by the menu
        // sink (fires on the UI/main thread), so we avoid touching the UI menu map off-thread.
        void HookedRunActorUpdates(void* a_processLists, float a_delta, bool a_instant)
        {
            if (g_origRunActorUpdates) {
                g_origRunActorUpdates(a_processLists, a_delta, a_instant);
            }
            if (g_failed.load()) { return; }

            // Only bother scheduling when there is something to do: the Pip-Boy is open, or a clone is still
            // live and may need teardown. Avoids queuing a perpetual no-op task while the menu is closed.
            if (!g_pipboyOpen.load() && !g_available.load()) { return; }

            bool expected = false;
            if (!g_taskInFlight.compare_exchange_strong(expected, true)) {
                return;  // a pass is already queued/running -- collapse this worker-thread fire
            }
            auto* task = F4SE::GetTaskInterface();
            if (!task) { g_taskInFlight.store(false); return; }
            const float delta = a_delta;
            task->AddTask([delta]() { RunCaptureTask(delta); });
        }

        // ------------------------------------------------------------------ DLL<->AS3 contract push
        // Mirrors PipboyBridge's proven idiom: on PipboyMenu open, defer to a UI task and set a dynamic
        // member on root1 the AS3 side can read. See docs/Character3DContract.md.
        void PushContract(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            auto* movieRoot = a_view->asMovieRoot.get();
            if (!movieRoot) { return; }

            Scaleform::GFx::Value root;
            if (!a_view->GetVariable(std::addressof(root), "root1") || !root.IsObject()) {
                logger::info("[PipOS][3D] root1 not ready; skipping contract push");
                return;
            }

            Scaleform::GFx::Value obj;
            movieRoot->CreateObject(std::addressof(obj));
            if (!obj.IsObject()) { return; }

            Scaleform::GFx::Value active(true);
            Scaleform::GFx::Value avail(g_available.load());
            Scaleform::GFx::Value rendererName;
            movieRoot->CreateString(std::addressof(rendererName), kRendererName);

            obj.SetMember("active", active);          // DLL live-3D path installed this session
            obj.SetMember("available", avail);        // an offscreen clone is currently live
            obj.SetMember("renderer", rendererName);  // Interface3D renderer name (AS3 wiring key)
            root.SetMember("PipOS_char3d", obj);
            logger::info("[PipOS][3D] contract pushed: root1.PipOS_char3d = {{active:true, available:{}, renderer:'{}'}}",
                g_available.load(), kRendererName);
        }

        // Push the contract on the UI task (the movie is only safe to touch there). Called on open, and again
        // from RunCaptureTask when availability flips, so AS3 learns the exact frame the clone goes live.
        void SchedulePushContract()
        {
            auto* task = F4SE::GetTaskInterface();
            if (!task) { return; }
            task->AddUITask([]() {
                if (auto* ui = RE::UI::GetSingleton()) {
                    if (auto menu = ui->GetMenu(RE::BSFixedString(kPipboyMenu.data()))) {
                        PushContract(menu->uiMovie.get());
                    }
                }
            });
        }

        class Char3DMenuSink : public RE::BSTEventSink<RE::MenuOpenCloseEvent>
        {
        public:
            RE::BSEventNotifyControl ProcessEvent(
                const RE::MenuOpenCloseEvent& a_event,
                RE::BSTEventSource<RE::MenuOpenCloseEvent>*) override
            {
                if (a_event.menuName == kPipboyMenu.data()) {
                    if (a_event.opening) {
                        g_pipboyOpen.store(true);
                        g_dirty.store(true);  // rebuild with the equipment worn at this open
                        // Initial push (available:false until the clone actually builds in RunCaptureTask,
                        // which re-pushes available:true on the transition). Keeps absent-member -> fallback.
                        SchedulePushContract();
                    } else {
                        g_pipboyOpen.store(false);
                        // Teardown must be single-threaded like the build: run HideAndRelease on the main
                        // thread via AddTask (renderer Disable / Offscreen_Set3D(nullptr) / NiPointer release
                        // are all D3D/scene lifecycle). Then re-push the contract (now available:false).
                        if (auto* task = F4SE::GetTaskInterface()) {
                            task->AddTask([]() {
                                HideAndRelease();
                                SchedulePushContract();
                            });
                        }
                    }
                }
                return RE::BSEventNotifyControl::kContinue;
            }
        };

        void RegisterContractSink()
        {
            static Char3DMenuSink sink;
            if (auto* ui = RE::UI::GetSingleton()) {
                ui->RegisterSink(std::addressof(sink));
                logger::info("[PipOS][3D] contract menu sink registered");
            }
        }
    }

    bool CharacterCapture::Install()
    {
        // 0.0.58 (user request): the hook installs UNCONDITIONALLY; bLive3D is now a pure RUNTIME toggle -- the
        // frame hook's wantShow gate (settings->Live3D() && PipboyOpen()) reads the live setting every frame, so
        // flipping it in the Menu Framework page switches 3D character <-> Vault Boy on the next Pip-Boy open,
        // no game restart needed.
        logger::info("[PipOS][3D] installing capture hook unconditionally; bLive3D={} gates at runtime (toggle "
                     "applies on next Pip-Boy open)",
            Settings::GetSingleton() ? Settings::GetSingleton()->Live3D() : false);

        bool expected = false;
        if (!g_installed.compare_exchange_strong(expected, true)) { return true; }

        // PipOS's F4SE::Init requests no trampoline (main.cpp .trampoline=false), so allocate one lazily now
        // -- only ever reached when the user has opted in.
#pragma warning(push)
#pragma warning(disable: 4996)  // AllocTrampoline is deprecated in favor of F4SE::Init({.trampoline=true}),
        F4SE::AllocTrampoline(64);  // but PipOS's Init requests none; allocate lazily only when opted in.
#pragma warning(pop)
        auto& trampoline = REL::GetTrampoline();

        // RunActorUpdates call site (OG 1.10.163): REL::ID(556439)+0x17 -- the same frame hook Full Body
        // Awareness uses with this fork; write_call<5> is battle-tested here (no hand-rolled branch gateway).
        REL::Relocation<std::uintptr_t> call{ REL::ID(556439) };
        const auto target = call.address() + 0x17;
        g_origRunActorUpdates = reinterpret_cast<RunActorUpdates_t*>(
            trampoline.write_call<5>(target, &HookedRunActorUpdates));
        logger::info("[PipOS][3D] RunActorUpdates frame hook installed @ REL::ID(556439)+0x17 (target {:X})",
            target);

        RegisterContractSink();
        if (auto* settings = Settings::GetSingleton()) {
            logger::info("[PipOS][3D] capture hook armed (renderer='{}', fov={}, scale={}, yaw={}); bLive3D toggles at runtime",
                kRendererName, settings->Char3DFov(), settings->Char3DScale(), settings->Char3DYaw());
        }
        return true;
    }

    bool CharacterCapture::IsCaptureAvailable()
    {
        return g_available.load();
    }
}
