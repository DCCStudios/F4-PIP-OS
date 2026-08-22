#include "PCH.h"
#include "CharacterAnimation.h"
#include "CharacterCapture.h"
#include "PipboyBridge.h"
#include "RE_BSSkin.h"   // 0.0.73: full BSSkin::Instance layout (TF3DHUD, offset-asserted) -- the fork only forward-declares it
#include "RE_Face.h"
#include "Settings.h"
#include "Scaleform/G/GFx_ASMovieRootBase.h"
#include "REL/ASM.h"
#include "RE/P/PowerArmor.h"
#include "RE/A/AIProcess.h"
#include "RE/T/TESEquipEvent.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <functional>
#include <limits>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
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
//   render-boundary commit hook (RenderPrepassesAndMenus) -> this fork's main-thread task commits the root before
//   draw instead. 0.0.79 DOES port TF3DHUD's two safe CALL-SITE hooks for RenderSceneDeferred and the composite-
//   pass ctor, with OG opcode guards, because kModMenu geometry otherwise selects unpopulated tiled-light lists.
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
        // 0.0.79: replace the field-proven 0.0.78 red clear with TF3DHUD's real character pass while preserving
        // the two facts 0.0.78 established in game: kMessage depth keeps the quad above PIP-OS, and releasing the
        // owned renderer on every close keeps that ordering stable across subsequent opens. This switch forces
        // the owned renderer, transparent kModMenu output, TF3DHUD's deferred-render fixes, and its fresh-race-
        // skeleton plus seeded equipment-clone construction path. The older whole-root clone remains a fallback.
        constexpr bool kTF3DHUDCharacterPass = true;
        constexpr auto kDisplayMeshPath = "Interface/GunModMenu/ModMenuRenderMesh.nif";
        // 0.0.70: BACK to the ModMenu display mesh. 0.0.69's switch to the vanilla preview's HUDGlassFlat:0
        // was OVER-mirroring: the engine auto-creates a display quad only for the ModMenu mesh name (0.0.66-68
        // field-proven -- the red RT composited through it and clipRect reshaping found it), while HUDGlassFlat
        // is a NIF the PIPBOY MACHINERY attaches to ITS renderer itself -- for ours it never appeared
        // ("clipRect skipped: display geometry not ready", nothing composited at all). The one config field that
        // actually mattered from the [3DDIAG] diff is the DEPTH (15/kMessage, kept in ConfigureRenderer).
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
        // Page visibility fallback: retain the live preview and its animation graph, but place the model far
        // outside the offscreen camera whenever Inventory is inactive. The configured X value is never mutated.
        constexpr float kNonInventoryModelOffsetX = 10000.0f;

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
        // Every open/close transition advances this token. All deferred menu work captures the token and must
        // not mutate scene/UI state after close or against a later reopen of the Pip-Boy.
        std::atomic<std::uint64_t> g_menuSessionToken{ 0 };
        std::atomic<bool> g_dirty{ true };          // rebuild requested (set on menu open / after release)
        std::atomic<bool> g_taskInFlight{ false };  // collapses worker-thread hook multiplicity -> 1 pass queued
        // F4SE drains its task list with while (!empty), so a delegate that calls AddTask can execute its own
        // replacement immediately in the same drain. Equipment settling must yield an engine/render frame before
        // polling again or an unpublished biped slot becomes an infinite main-thread loop.
        std::atomic<bool> g_captureTaskRunning{ false };
        std::atomic<bool> g_captureRetryRequested{ false };
        std::atomic<bool> g_captureTaskReentryLogged{ false };
        thread_local std::uint32_t g_renderHookDepth{ 0 };
        std::atomic<bool> g_failed{ false };        // hard-disable for the rest of the session on any failure
        std::atomic<bool> g_inventoryPageActive{ false }; // unknown pages start safely offscreen; never gates construction
        std::atomic<bool> g_pageProbeInFlight{ false };
        std::atomic<bool> g_rendererRecreateRequested{ false };
        std::atomic<bool> g_characterHovered{ false };
        std::atomic<float> g_sessionYawOffset{ 0.0f };
        std::atomic<std::uint32_t> g_poseToggleRequests{ 0 };

        // ---- MAIN-THREAD-ONLY scene state (only ever touched inside RunCaptureTask / teardown tasks, which
        //      F4SE drains serially on the game main thread -- so no lock is required) ----
        bool g_visible{ false };
        RE::Interface3D::Renderer* g_renderer{ nullptr };
        RE::NiPointer<RE::NiAVObject> g_previewRoot;
        RE::NiPointer<RE::BSFaceGenNiNode> g_previewFaceNode;
        RE::NiPointer<RE::NiAVObject> g_displayRoot;
        bool g_previewWeaponEquipped{ false };
        const RE::NiAVObject* g_sourceRoot{ nullptr };  // detect a player-3D swap -> rebuild
        std::uint64_t g_sourceBipedSignature{ 0 };      // diagnose Pip-Boy's temporary selected-item biped swaps
        std::uint64_t g_sourceVisualSignature{ 0 };
        enum class PendingEquipmentKind : std::uint8_t
        {
            kWeapon,
            kArmor
        };

        struct PendingEquipmentEvent
        {
            std::uint32_t formID{ 0 };
            std::uint32_t armorSlotMask{ 0 };
            std::uint64_t sequence{ 0 };
            PendingEquipmentKind kind{ PendingEquipmentKind::kArmor };
            bool equipped{ false };
        };

        struct PendingEquipmentSnapshot
        {
            std::vector<PendingEquipmentEvent> events;
            std::uint64_t lastSequence{ 0 };
        };

        // TESEquipEvent delivery is not assumed to share the capture task's main-thread affinity. The watcher
        // only mutates this queue while holding its lock; Tick copies a snapshot before inspecting BipedAnim.
        std::mutex g_pendingEquipmentLock;
        std::vector<PendingEquipmentEvent> g_pendingEquipmentEvents;
        std::uint64_t g_nextEquipmentEventSequence{ 0 };

        // These settle counters are main-thread-only. A sequence change invalidates all stability evidence from
        // the previous event batch, while the queue itself remains pending until BuildPreview succeeds.
        std::uint64_t g_equipmentCandidateSignature{ 0 };
        std::uint64_t g_equipmentCandidateSequence{ 0 };
        std::uint64_t g_equipmentWaitLoggedSequence{ 0 };
        std::uint64_t g_equipmentReadyLoggedSequence{ 0 };
        std::unordered_set<std::uint64_t> g_equipmentMaskMismatchLoggedSequences;
        std::uint32_t g_equipmentQuietPasses{ 0 };
        std::uint32_t g_equipmentStablePasses{ 0 };
        std::atomic_bool g_loggedTransientBipedPreview{ false };
        RE::NiTransform g_baseTransform;                // framed transform; breathing is added on top
        float g_idleTime{ 0.0f };
        std::recursive_mutex g_sceneLock;

        struct PlacementSnapshot
        {
            float scale{ -1.0f };
            float fov{ -1.0f };
            float yaw{ -999.0f };
            float pitch{ -999.0f };
            float roll{ -999.0f };
            float distance{ -1.0f };
            int target{ -1 };
            float clipLeft{ -1.0f };
            float clipTop{ -1.0f };
            float clipRight{ -1.0f };
            float clipBottom{ -1.0f };
            float screenX{ -999.0f };
            float screenY{ -999.0f };
            float keyIntensity{ -1.0f };
            float fillIntensity{ -1.0f };
            float rimIntensity{ -1.0f };
            std::uint32_t slotMask{ 0 };
            bool antiAliasing{ false };
            bool cloth{ false };
            bool hologram{ false };
            bool inventoryPageActive{ true };
        };
        PlacementSnapshot g_livePlacement;

        // Display-mesh clip-rect state (TF3DHUD Renderer.cpp). g_privateDisplayRendererData owns the rebuilt
        // BSGraphics::TriShape we substitute for the vanilla quad; g_appliedDisplayBounds caches the last
        // applied window so a no-change re-apply is a cheap early-out. Main-thread-only, like the rest.
        RE::BSGraphics::TriShape* g_privateDisplayRendererData{ nullptr };
        DisplayBounds g_appliedDisplayBounds{};
        bool g_displayClipApplied{ false };
        bool g_displayAttached{ false };

        using RunActorUpdates_t = void(void*, float, bool);
        RunActorUpdates_t* g_origRunActorUpdates{ nullptr };
        using Update3DModel_t = void(RE::AIProcess*, RE::Actor*, bool);
        Update3DModel_t* g_origUpdate3DModel{ nullptr };
        REL::Relocation<RE::BSTEventSource<RE::TESEquipEvent>*> g_equipEventSource{ REL::ID(485633) };

        using RenderSceneDeferred_t = void(
            RE::NiCamera*, RE::BSShaderAccumulator*, RE::BSCullingProcess*, RE::ShadowSceneNode*,
            std::int32_t, std::int32_t, bool, bool);
        using BSRenderPassCtor_t = void(void*, void*, void*, void*, std::uint32_t, std::uint8_t, void*);
        using RenderPrepassesAndMenus_t = void(RE::Interface3D::Renderer*);
        using ProcessGraphEvent_t = std::uint32_t(RE::BSAnimationGraphManager*, const RE::BSFixedString&);
        RenderSceneDeferred_t* g_origRenderSceneDeferred{ nullptr };
        BSRenderPassCtor_t* g_origBSRenderPassCtor{ nullptr };
        RenderPrepassesAndMenus_t* g_origRenderPrepassesAndMenus{ nullptr };
        ProcessGraphEvent_t* g_origProcessGraphEvent{ nullptr };
        thread_local bool g_inPipOSDeferredRender{ false };
        std::atomic<bool> g_loggedDeferredHook{ false };
        std::atomic<bool> g_loggedCompositeHook{ false };
        std::atomic<bool> g_loggedLivePoseSync{ false };

        // TF3DHUD Address.cpp, OG 1.10.163. These are invoked only after both measured call sites pass their
        // E8 opcode guards during Install, so an unexpected executable/runtime degrades to no character pass.
        REL::Relocation<bool (*)()> g_qTiledLighting{ REL::ID(1154650) };
        REL::Relocation<void (*)(bool)> g_setDoTiledLighting{ REL::ID(716351) };
        REL::Relocation<RE::NiAVObject* (*)(
            const RE::Actor*, RE::NiAVObject*, const RE::BGSBodyPartDefs::LIMB_ENUM*, bool)>
            g_getActorBodyPart3D{ REL::ID(157573) };
        REL::Relocation<RE::NiAVObject* (*)(RE::NiAVObject*)> g_convertNodeTree{ REL::ID(633230) };
        REL::Relocation<void (*)(void*, RE::NiAVObject*, bool)> g_fixFaceGenHeadSkinInstances{
            REL::ID(1131949)
        };
        REL::Relocation<void (*)(RE::TESNPC*, RE::NiColorA&, void*, bool, bool)> g_calculateBodyTintColor{
            REL::ID(134537)
        };
        REL::Relocation<void (*)(RE::NiAVObject*, const RE::NiColorA&)> g_updateBodyTintColorsOnScene{
            REL::ID(49935)
        };
        REL::Relocation<void (*)(void*, bool)> g_updateAllChildrenMorphData{ REL::ID(213436) };
        REL::Relocation<RE::NiExtraData* (*)(
            RE::NiAVObject&, const char*, const RE::NiTransform&, RE::NiAVObject*)>
            g_createClothFor3D{ REL::ID(1322043) };
        REL::Relocation<void (*)(RE::NiExtraData*, bool)> g_setClothSettle{ REL::ID(638869) };
        REL::Relocation<void (*)(RE::NiExtraData*, void*)> g_setClothWorld{ REL::ID(19064) };

        // Forward decls (definitions live further down, next to the contract push they wrap).
        void SchedulePushContract();
        void ScheduleInventoryPageProbe();
        void SanitizeClone(RE::NiAVObject& a_root, RE::NiAVObject* a_source);
        void RunCaptureTask(
            float a_delta, std::uint64_t a_sessionToken, bool a_afterRenderBoundary);

        void QueueCapturePass(float a_delta, bool a_afterRenderBoundary = false)
        {
            const bool captureTaskRunning = g_captureTaskRunning.load(std::memory_order_acquire);
            if (captureTaskRunning || g_renderHookDepth != 0) {
                g_captureRetryRequested.store(true, std::memory_order_release);
                if (captureTaskRunning &&
                    !g_captureTaskReentryLogged.exchange(true, std::memory_order_acq_rel)) {
                    logger::info(
                        "[PipOS][3D] capture retry deferred to the next render frame; avoided F4SE task-queue reentry");
                }
                return;
            }
            // Capturing the menu generation here closes the race where the menu-close event releases the
            // renderer while a capture pass queued by the previous frame is still waiting in F4SE's task list.
            // The task must validate this generation again on the main thread before it can recreate anything.
            const auto sessionToken = g_menuSessionToken.load(std::memory_order_acquire);
            bool expected = false;
            if (!g_taskInFlight.compare_exchange_strong(expected, true)) {
                // Preserve the wake if a task from an older menu generation is still queued. That task may reject
                // its stale token and clear the in-flight gate without doing this session's requested work.
                g_captureRetryRequested.store(true, std::memory_order_release);
                return;
            }
            auto* task = F4SE::GetTaskInterface();
            if (!task) { g_taskInFlight.store(false); return; }
            task->AddTask([a_delta, sessionToken, a_afterRenderBoundary]() {
                RunCaptureTask(a_delta, sessionToken, a_afterRenderBoundary);
            });
        }

        std::int32_t MakeRel32Displacement(std::uintptr_t a_sourceNext, std::uintptr_t a_destination)
        {
            const auto displacement = static_cast<std::int64_t>(a_destination) -
                                      static_cast<std::int64_t>(a_sourceNext);
            if (displacement < (std::numeric_limits<std::int32_t>::min)() ||
                displacement > (std::numeric_limits<std::int32_t>::max)()) {
                logger::error("[PipOS][3D] branch gateway rel32 displacement out of range");
                return 0;
            }
            return static_cast<std::int32_t>(displacement);
        }

        void WriteBranch5(std::uintptr_t a_source, std::uintptr_t a_destination)
        {
            auto& trampoline = REL::GetTrampoline();
            const auto branch = trampoline.allocate_branch5(a_destination);
            const REL::ASM::JMP5 assembly{
                MakeRel32Displacement(a_source + sizeof(REL::ASM::JMP5), branch)
            };
            REL::WriteSafeData(a_source, assembly);
        }

        bool ReadExistingBranchTarget(
            std::uintptr_t a_targetAddress, const std::byte* a_targetBytes, std::uintptr_t& a_branchTarget)
        {
            if (a_targetBytes[0] == std::byte{ 0xE9 }) {
                std::int32_t displacement = 0;
                std::memcpy(std::addressof(displacement), a_targetBytes + 1, sizeof(displacement));
                a_branchTarget = a_targetAddress + sizeof(REL::ASM::JMP5) + displacement;
                return a_branchTarget != 0;
            }
            if (a_targetBytes[0] == std::byte{ 0xFF } && a_targetBytes[1] == std::byte{ 0x25 }) {
                std::int32_t displacement = 0;
                std::memcpy(std::addressof(displacement), a_targetBytes + 2, sizeof(displacement));
                const auto indirectAddress = a_targetAddress + sizeof(REL::ASM::JMP6) + displacement;
                std::memcpy(std::addressof(a_branchTarget),
                    reinterpret_cast<const void*>(indirectAddress), sizeof(a_branchTarget));
                return a_branchTarget != 0;
            }
            return false;
        }

        template <class T>
        T CreateBranchGateway5(
            const char* a_name, REL::Relocation<std::uintptr_t>& a_target, void* a_hook)
        {
            constexpr std::size_t kPrologueSize = 5;
            const auto targetAddress = a_target.address();
            const auto* targetBytes = reinterpret_cast<const std::byte*>(targetAddress);
            auto& trampoline = REL::GetTrampoline();

            std::uintptr_t existingBranchTarget = 0;
            if (ReadExistingBranchTarget(targetAddress, targetBytes, existingBranchTarget)) {
                auto* gateway = trampoline.allocate<REL::ASM::JMP14>(existingBranchTarget);
                WriteBranch5(targetAddress, reinterpret_cast<std::uintptr_t>(a_hook));
                logger::info("[PipOS][3D] {} chained through existing branch {:X}", a_name, existingBranchTarget);
                return reinterpret_cast<T>(gateway);
            }
            if (targetBytes[0] == std::byte{ 0xE8 }) {
                logger::error(std::format("[PipOS][3D] {} gateway refused unexpected CALL prologue", a_name));
                return nullptr;
            }

            auto* gateway = static_cast<std::byte*>(
                trampoline.allocate(kPrologueSize + sizeof(REL::ASM::JMP14)));
            std::memcpy(gateway, targetBytes, kPrologueSize);
            const REL::ASM::JMP14 jumpBack{ targetAddress + kPrologueSize };
            std::memcpy(gateway + kPrologueSize, std::addressof(jumpBack), sizeof(jumpBack));
            WriteBranch5(targetAddress, reinterpret_cast<std::uintptr_t>(a_hook));
            logger::info("[PipOS][3D] {} branch gateway installed @ {:X}", a_name, targetAddress);
            return reinterpret_cast<T>(gateway);
        }

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

        bool IsPreviewNeckGoreGeometry(const std::string_view a_name)
        {
            return a_name == "FemaleNeckGore" || a_name == "MaleNeckGore" || a_name == "NeckGore";
        }

        bool HasPreviewShaderMaterial(RE::BSGeometry& a_geometry)
        {
            for (auto& property : a_geometry.properties) {
                if (auto* shader = netimmerse_cast<RE::BSShaderProperty*>(property.get());
                    shader && shader->material) {
                    return true;
                }
            }
            return false;
        }

        // Pip-Boy biped clones can inherit app-cull flags while their equipped source is being replaced.
        // TF3DHUD prepares every preview attachment as visible, then selectively suppresses only invalid
        // shader paths and neck-gore geometry. Apply the same rule to non-weapon attachments before they are
        // joined to the private preview skeleton so a newly equipped full outfit cannot leave only head/hands.
        std::uint32_t PrepareBipedAttachmentVisibility(RE::NiAVObject& a_root)
        {
            std::uint32_t restored = 0;
            ForEachAVObject(std::addressof(a_root), [&](RE::NiAVObject& a_object) {
                bool hide = false;
                if (auto* geometry = netimmerse_cast<RE::BSGeometry*>(std::addressof(a_object))) {
                    const char* name = geometry->GetName().c_str();
                    hide = IsPreviewNeckGoreGeometry(name ? std::string_view(name) : std::string_view{}) ||
                        !HasPreviewShaderMaterial(*geometry);
                }
                if (hide) {
                    a_object.SetAppCulled(true);
                    a_object.fadeAmount = 0.0f;
                } else {
                    if (a_object.GetAppCulled()) { ++restored; }
                    a_object.SetAppCulled(false);
                    a_object.fadeAmount = 1.0f;
                }
            });
            return restored;
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

        // ------------------------------------------------------------------ skin rebind (Previewer.cpp)
        // 0.0.73 THE SKINNED-CLONE FIX. Field-proven elimination: our clone in the ENABLED vanilla weapon-preview
        // renderer still drew nothing -- the fault is the clone. Cause: BSSkin::Instance holds RAW pointers
        // (bones[] NiAVObject*, worldTransforms[] NiTransform* INTO the skeleton, rootNode) that NiCloningProcess
        // cannot remap (same disease as the fixed shader fadeNode). So every cloned body mesh still skins against
        // the SOURCE player's live skeleton and renders at the PLAYER'S world position -- nowhere near the
        // offscreen camera -> empty picture with valid passes. TF3DHUD treats the rebind as REQUIRED-for-
        // correctness (Previewer::RebindSkinInstance): re-point each skin's bones/worldTransforms at the target
        // skeleton BY NAME, set rootNode, zero paletteStamp (forces the GPU skin palette rebuild). Our exact
        // full-root clone carries its OWN BSFlattenedBoneTree with matching bone names, so we rebind onto that.
        // Returns the rebound-geometry count (log: >0 = engaged; -1 = no flattened tree found in the clone).
        // Engine bone-map rebuild (TF3DHUD Address.cpp:102): re-resolves a flattened tree's internal
        // FlattenedBone::node pointers + its name->bone hash after cloning/structural change. OG 1.10.163 ID.
        void EngineCreateBoneMap(RE::NiAVObject* a_object)
        {
            static REL::Relocation<void (*)(RE::NiAVObject*)> func{ REL::ID(1131947) };
            func(a_object);
        }

        // ------------------------------------------------------- 0.0.75 CONSENSUS BATCH (4-agent TF3DHUD sweep)
        // Engine segment enabler (TF3DHUD Address.h:244/EnableAllSegments {246125}): FO4 body meshes carry
        // BSDismemberSkinInstance per-segment disable COUNTS the engine toggles constantly; a clone inherits
        // them, and a disabled segment renders NOTHING while node culling/fade all read clean. Force-enable all.
        void EngineEnableAllSegments(RE::BSGeometrySegmentData* a_data)
        {
            static REL::Relocation<void (*)(RE::BSGeometrySegmentData*)> func{ REL::ID(246125) };
            func(a_data);
        }

        // Shader-alpha restore (TF3DHUD PreviewRenderTree.cpp:169-183): a cloned BSShaderProperty with
        // alpha <= 0 renders FULLY TRANSPARENT with an otherwise perfect pipeline. Force back to 1.
        int RestoreShaderAlpha(RE::NiAVObject& a_root)
        {
            int fixed = 0;
            ForEachAVObject(std::addressof(a_root), [&](RE::NiAVObject& a_object) {
                auto* geometry = netimmerse_cast<RE::BSGeometry*>(std::addressof(a_object));
                if (!geometry) { return; }
                for (auto& property : geometry->properties) {
                    if (auto* shaderProperty = netimmerse_cast<RE::BSShaderProperty*>(property.get())) {
                        if (shaderProperty->alpha <= 0.0f) { shaderProperty->alpha = 1.0f; ++fixed; }
                    }
                }
            });
            return fixed;
        }

        // Pose copy (agents 3+4 consensus, the top zero-pixels suspect): an actor's POSE lives authoritatively
        // in BSFlattenedBoneTree::bone[].local (raw heap array the flattened update walks -- NODE locals are
        // ignored). TF3DHUD NEVER trusts a cloned flattened tree; if our clone's bone[] came through stale or
        // identity, every bone sits at the origin and the skinned body collapses to a sub-pixel speck = the
        // exact symptom. Copy the SOURCE tree's bone locals (the live captured pose) into the CLONE's array by
        // name, writing the ARRAY entries directly, then the flush Update recomputes bone worlds.
        int CopyFlattenedPose(RE::NiAVObject& a_root, RE::NiAVObject* a_source)
        {
            if (!a_source) { return -1; }
            auto* dst = FindFlattenedBoneTree(std::addressof(a_root));
            auto* src = FindFlattenedBoneTree(a_source);
            if (!dst || !src || !dst->bone || !src->bone) { return -1; }
            if (dst->boneCount <= 0 || dst->boneCount > 4096) { return -1; }
            int copied = 0;
            for (std::int32_t i = 0; i < dst->boneCount; ++i) {
                auto& db = dst->bone[i];
                const char* nm = db.name.c_str();
                if (!nm || nm[0] == '\0') { continue; }
                const std::string_view boneName(nm);
                // Equipment attachment bones belong to the private preview. Copying their live locals here would
                // reintroduce the drawn, holstered, and mid-equip dependency removed from the weapon path.
                if (boneName == "Weapon" || boneName == "WeaponLeft") { continue; }
                if (auto* sb = FindFlattenedBoneByName(*src, boneName)) {
                    db.local = sb->local;
                    db.world = sb->world;   // seed; the flush Update re-derives from local anyway
                    ++copied;
                }
            }
            return copied;
        }

        // One-shot pose probe: logs a known bone's world position after framing. If it is not near the framed
        // origin (|x|,|z| small, y ~ +distance), the flattened tree is not updating and the fresh-skeleton
        // rebuild (banked TF3DHUD recipe) is the required next step.
        void LogPoseProbe(RE::NiAVObject& a_root)
        {
            auto* flattened = FindFlattenedBoneTree(std::addressof(a_root));
            if (!flattened) { logger::info("[PipOS][3D] pose probe: no flattened tree"); return; }
            const char* probes[] = { "Chest", "Root", "COM" };
            for (const char* p : probes) {
                if (auto* fb = FindFlattenedBoneByName(*flattened, std::string_view(p))) {
                    logger::info("[PipOS][3D] pose probe: bone '{}' world=({:.1f},{:.1f},{:.1f}) node={}",
                        p, fb->world.translate.x, fb->world.translate.y, fb->world.translate.z, fb->node != nullptr);
                    return;
                }
            }
            logger::info("[PipOS][3D] pose probe: no probe bone found (Chest/Root/COM)");
        }

        // 0.0.74: whole-tree name search -- the FINAL bone-resolution fallback. 0.0.73's field counters
        // (102 rebound / 229 UNRESOLVED) proved most skin bones are NOT in the flattened tree: weapon nodes,
        // attach points and helper bones are ordinary NiNodes elsewhere in the skeleton. TF3DHUD resolves
        // against BOTH indexes (its CollectNamedNodes map covers the whole tree); this is our equivalent.
        RE::NiAVObject* FindNodeByNameRecursive(RE::NiAVObject* a_root, const RE::BSFixedString& a_name)
        {
            if (!a_root) { return nullptr; }
            if (a_root->name == a_name) { return a_root; }
            if (auto* node = netimmerse_cast<RE::NiNode*>(a_root)) {
                for (auto& child : node->children) {
                    if (child) {
                        if (auto* found = FindNodeByNameRecursive(child.get(), a_name)) { return found; }
                    }
                }
            }
            return nullptr;
        }

        int RebindClonedSkins(RE::NiAVObject& a_root, RE::NiAVObject* a_source)
        {
            // AUDIT F1 (required): the clone's flattened tree carries the SAME unremapped-pointer disease --
            // its FlattenedBone::node NiPointers (raw heap array) + boneMap hash still reference the SOURCE
            // skeleton after cloning, so a name lookup without a rebuild returns null or SOURCE bones. The
            // engine's CreateBoneMap re-resolves both; TF3DHUD calls it before EVERY rebind, in this exact
            // root -> flattened -> root order (RefreshPreviewBoneLookup, Previewer.cpp:1251-1263).
            EngineCreateBoneMap(std::addressof(a_root));
            auto* flattened = FindFlattenedBoneTree(std::addressof(a_root));   // the CLONE's own skeleton
            if (!flattened) { return -1; }
            EngineCreateBoneMap(flattened);
            EngineCreateBoneMap(std::addressof(a_root));

            // AUDIT F2 (required): NEVER mutate a skin instance the clone SHARES with the live player --
            // rebinding a shared skin would repoint the real character's body at the clone's skeleton and
            // dangle when the clone dies (TF3DHUD's sourceSkins guard, Previewer.cpp:1825-1840).
            std::unordered_set<const void*> sourceSkins;
            if (a_source) {
                ForEachAVObject(a_source, [&](RE::NiAVObject& a_object) {
                    if (auto* g = netimmerse_cast<RE::BSGeometry*>(std::addressof(a_object))) {
                        if (auto* s = g->skinInstance.get()) { sourceSkins.insert(s); }
                    }
                });
            }

            // 0.0.76: source flattened tree -- needed to recover NULL bone slots by pointer identity (below).
            auto* srcTree = a_source ? FindFlattenedBoneTree(a_source) : nullptr;

            int boundBones = 0, geoms = 0, sharedSkipped = 0, unresolved = 0, viaTree = 0;
            int nullFixedDest = 0, nullFixedSource = 0, nullDropped = 0;
            ForEachAVObject(std::addressof(a_root), [&](RE::NiAVObject& a_object) {
                auto* geometry = netimmerse_cast<RE::BSGeometry*>(std::addressof(a_object));
                if (!geometry) { return; }
                auto* skin = geometry->skinInstance.get();
                if (!skin) { return; }
                if (sourceSkins.find(skin) != sourceSkins.end()) { ++sharedSkipped; return; }   // F2 guard
                if (skin->bones.empty() || skin->bones.size() > RE::BSSkin::kMaxExpectedBones) { return; }
                if (!skin->worldTransforms.empty() && skin->worldTransforms.size() != skin->bones.size()) { return; }

                for (std::uint32_t i = 0; i < skin->bones.size(); ++i) {
                    auto* srcBone = skin->bones[i];
                    const char* nm = srcBone ? srcBone->GetName().c_str() : nullptr;
                    if (!nm || nm[0] == '\0') {
                        // 0.0.76 NULL/UNNAMED BONE SLOTS (the field-proven 229: whole-tree search found ZERO of
                        // them, so they are not elsewhere -- they are null). TF3DHUD's
                        // ResolveNullSkinBonesFromFlattenedTree (Previewer.cpp:1296-1348) recovers identity via
                        // POINTER IDENTITY: the slot's stale worldTransforms pointer still aims at a specific
                        // FlattenedBone::world in the SOURCE skeleton's array, which names the bone. Map that
                        // entry to the CLONE's same-index/same-name bone; unrecoverable slots get worldTransforms
                        // NULLED (TF3DHUD line 1341) instead of left sampling the source skeleton -- 70% of the
                        // palette pulling from the player's world position shredded the mesh across thousands of
                        // units = zero coherent pixels.
                        RE::NiTransform* stale = (!skin->worldTransforms.empty()) ? skin->worldTransforms[i] : nullptr;
                        RE::NiAVObject* nb = nullptr;
                        RE::NiTransform* nw = nullptr;
                        // TF3DHUD's seeded clone mapping makes skin->rootNode point at the FRESH skeleton before
                        // the clone is processed. Therefore a null bone's worldTransforms slot can already point
                        // into the DESTINATION flattened array. 0.0.79 searched only the live source array and
                        // dropped all 229 such slots. Match the destination first, exactly like TF3DHUD's
                        // ResolveNullSkinBonesFromFlattenedTree, then retain source matching for fallback clones.
                        if (stale && flattened->bone) {
                            for (std::int32_t k = 0; k < flattened->boneCount; ++k) {
                                if (stale == std::addressof(flattened->bone[k].world)) {
                                    nb = flattened->bone[k].node.get();
                                    nw = std::addressof(flattened->bone[k].world);
                                    ++nullFixedDest;
                                    break;
                                }
                            }
                        }
                        if (!nw && stale && srcTree && srcTree->bone && flattened->bone) {
                            for (std::int32_t k = 0; k < srcTree->boneCount; ++k) {
                                if (stale != std::addressof(srcTree->bone[k].world)) { continue; }
                                const char* bn = srcTree->bone[k].name.c_str();
                                if (bn && bn[0] != '\0') {
                                    if (auto* fb = FindFlattenedBoneByName(*flattened, std::string_view(bn))) {
                                        nb = fb->node.get();
                                        nw = std::addressof(fb->world);
                                    }
                                }
                                if (nw) { ++nullFixedSource; }
                                break;
                            }
                        }
                        if (nw) {
                            if (nb) { skin->bones[i] = nb; }
                            skin->worldTransforms[i] = nw;
                            ++boundBones;
                        } else {
                            if (!skin->worldTransforms.empty()) { skin->worldTransforms[i] = nullptr; }
                            ++nullDropped; ++unresolved;
                        }
                        continue;
                    }
                    // 0.0.75: resolution order changed -- FLATTENED-ARRAY entry FIRST. The engine maintains pose
                    // in FlattenedBone::world (the array the flattened update walks); node->world on a flattened
                    // skeleton may never be written. Bind the skin transform to the ARRAY's world when the bone
                    // is a flattened bone; node->world only for ordinary nodes found by the whole-tree search.
                    RE::NiAVObject* dstBone = nullptr;
                    RE::NiTransform* dstWorld = nullptr;
                    if (auto* fb = FindFlattenedBoneByName(*flattened, std::string_view(nm))) {
                        dstBone = fb->node.get();
                        dstWorld = std::addressof(fb->world);
                    } else if (auto* byName = flattened->GetObjectByName(srcBone->GetName())) {
                        dstBone = byName;
                        dstWorld = std::addressof(byName->world);
                    } else if (auto* wt = FindNodeByNameRecursive(std::addressof(a_root), srcBone->GetName())) {
                        // 0.0.74: whole-tree fallback -- ordinary nodes (weapon/attach/helper bones) outside the
                        // flattened tree; their node->world IS maintained by root.Update().
                        dstBone = wt;
                        dstWorld = std::addressof(wt->world);
                        ++viaTree;
                    }
                    if (dstBone || dstWorld) { if (dstBone) { skin->bones[i] = dstBone; } ++boundBones; }
                    else { ++unresolved; }
                    if (!skin->worldTransforms.empty()) {
                        if (dstWorld) { skin->worldTransforms[i] = dstWorld; }
                        else if (auto* t = skin->bones[i]) { skin->worldTransforms[i] = std::addressof(t->world); }
                        else { skin->worldTransforms[i] = nullptr; }
                    }
                }
                skin->rootNode = std::addressof(a_root);
                skin->paletteStamp = 0;   // force the skin-palette rebuild against the new transforms
                ++geoms;
            });
            // AUDIT F3: honest field signal -- bones actually rebound, not just geometries touched.
            logger::info("[PipOS][3D] skin rebind: {} bones rebound ({} via whole-tree, {} null-slots recovered from destination, {} from source, {} dropped) across {} geometries ({} shared skipped, {} unresolved)",
                boundBones, viaTree, nullFixedDest, nullFixedSource, nullDropped, geoms, sharedSkipped, unresolved);
            return boundBones;
        }

        // ------------------------------------------------------- 0.0.79 TF3DHUD fresh-skeleton construction
        // A whole live-player-root clone left hundreds of BSSkin palette entries unresolved. TF3DHUD avoids
        // that failure class: it loads the race skeleton fresh, flattens it through the engine, then clones each
        // biped part with NiCloningProcess mappings pre-seeded from source skin bones to the fresh skeleton.
        using PreviewNodeMap = std::unordered_map<std::string, RE::NiAVObject*>;

        void CollectPreviewNodes(RE::NiAVObject& a_root, PreviewNodeMap& a_nodes)
        {
            a_nodes.clear();
            if (auto* flattened = FindFlattenedBoneTree(std::addressof(a_root));
                flattened && flattened->bone && flattened->boneCount > 0 && flattened->boneCount <= 4096) {
                for (std::int32_t i = 0; i < flattened->boneCount; ++i) {
                    auto& entry = flattened->bone[i];
                    const char* name = entry.name.c_str();
                    if (name && name[0] != '\0' && entry.node) {
                        a_nodes.try_emplace(name, entry.node.get());
                    }
                }
            }
            ForEachAVObject(std::addressof(a_root), [&](RE::NiAVObject& a_object) {
                const char* name = a_object.GetName().c_str();
                if (name && name[0] != '\0') { a_nodes.try_emplace(name, std::addressof(a_object)); }
            });
        }

        RE::NiNode* FindPreviewNode(const PreviewNodeMap& a_nodes, std::string_view a_name)
        {
            const auto it = a_nodes.find(std::string(a_name));
            return it == a_nodes.end() || !it->second ? nullptr : netimmerse_cast<RE::NiNode*>(it->second);
        }

        RE::NiNode* FindRightHandWeaponNode(RE::NiAVObject& a_previewRoot, const PreviewNodeMap& a_nodes)
        {
            // BSFlattenedBoneTree does not represent its logical bone hierarchy through NiNode::children.
            // Resolve the authoritative skeleton entry directly, then verify its flattened parent chain reaches
            // RArm_Hand. This prevents an equipment clone's duplicate Weapon node from winning name lookup while
            // still honoring the hierarchy that the behavior graph actually animates.
            auto* flattened = FindFlattenedBoneTree(std::addressof(a_previewRoot));
            auto* weaponBone = flattened ? FindFlattenedBoneByName(*flattened, "Weapon") : nullptr;
            if (!flattened || !weaponBone || !weaponBone->node) { return nullptr; }

            auto parentIndex = weaponBone->parent;
            bool belowRightHand = false;
            const char* immediateParent = "<none>";
            for (std::int32_t depth = 0;
                 parentIndex >= 0 && parentIndex < flattened->boneCount && depth < flattened->boneCount;
                 ++depth) {
                auto& ancestor = flattened->bone[parentIndex];
                const char* ancestorName = ancestor.name.c_str();
                if (depth == 0 && ancestorName && ancestorName[0] != '\0') { immediateParent = ancestorName; }
                if (ancestorName && std::string_view(ancestorName) == "RArm_Hand") {
                    belowRightHand = true;
                    break;
                }
                parentIndex = ancestor.parent;
            }
            if (!belowRightHand) {
                logger::error(std::format(
                    "[PipOS][3D] flattened Weapon bone rejected: immediateParent='{}' does not descend from RArm_Hand",
                    immediateParent));
                return nullptr;
            }

            auto* weaponNode = weaponBone->node.get();
            if (!weaponNode || FindPreviewNode(a_nodes, "Weapon") != weaponNode) {
                logger::error("[PipOS][3D] flattened Weapon bone rejected: authoritative node-map mismatch");
                return nullptr;
            }
            logger::info(
                "[PipOS][3D] flattened Weapon bone resolved: bone='Weapon' immediateParent='{}' ancestor='RArm_Hand'",
                immediateParent);
            return weaponNode;
        }

        RE::NiNode* EnsureRightHandWeaponNode(RE::NiAVObject& a_previewRoot, PreviewNodeMap& a_nodes)
        {
            if (auto* existing = FindRightHandWeaponNode(a_previewRoot, a_nodes)) { return existing; }
            auto* rightHand = FindPreviewNode(a_nodes, "RArm_Hand");
            if (!rightHand) {
                logger::error("[PipOS][3D] synthetic Weapon node failed: RArm_Hand is missing");
                return nullptr;
            }
            if (auto* existing = FindPreviewNode(a_nodes, "Weapon");
                existing && existing->parent == rightHand) {
                return existing;
            }

            // The field race skeleton has RArm_Hand but no authored Weapon entry. Create one stable private
            // attachment node directly beneath that hand. Equipment clones remain ordinary children of this
            // node, so no live gameplay transform or weapon-specific clone root can become the animation bone.

            auto weaponNode = RE::make_nismart<RE::NiNode>(0);
            weaponNode->name = RE::BSFixedString("Weapon");
            weaponNode->SetLocalTransform(RE::NiTransform::IDENTITY);
            weaponNode->fadeAmount = 1.0f;
            rightHand->AttachChild(weaponNode.get(), false);
            auto* result = weaponNode.get();
            a_nodes.insert_or_assign("Weapon", result);

            RE::NiUpdateData updateData{};
            a_previewRoot.Update(updateData);
            logger::info(
                "[PipOS][3D] synthetic Weapon node created: parent='RArm_Hand' local=(0,0,0) scale=1");
            return result;
        }

        RE::NiStringExtraData* FindStringExtraDataInTree(RE::NiAVObject& a_root, const RE::BSFixedString& a_name)
        {
            RE::NiStringExtraData* result = nullptr;
            ForEachAVObject(std::addressof(a_root), [&](RE::NiAVObject& a_object) {
                if (!result) {
                    result = netimmerse_cast<RE::NiStringExtraData*>(a_object.GetExtraData(a_name));
                }
            });
            return result;
        }

        [[nodiscard]] bool IsEngineWeaponAttachSlot(const RE::BIPED_OBJECT a_slot)
        {
            // Fallout 4 assigns weapon models to runtime biped slots 32-39 and 41-43. Guns use slot 41,
            // which the earlier reduced port missed and consequently attached at the preview root.
            const auto slot = std::to_underlying(a_slot);
            return slot >= 32 && (slot <= 39 || (slot >= 41 && slot <= 43));
        }

        [[nodiscard]] bool BipedHasEquippedWeapon(const RE::BipedAnim& a_biped)
        {
            for (std::int32_t i = 0; i < std::to_underlying(RE::BIPED_OBJECT::kTotal); ++i) {
                const auto slot = static_cast<RE::BIPED_OBJECT>(i);
                if (!IsEngineWeaponAttachSlot(slot) && slot != RE::BIPED_OBJECT::kShield) { continue; }
                const auto& object = a_biped.object[i];
                if (object.partClone && object.parent.object &&
                    object.parent.object->Is(RE::ENUM_FORM_ID::kWEAP)) {
                    return true;
                }
            }
            return false;
        }

        void AttachChildLikeEngine(RE::NiAVObject& a_child, RE::NiNode& a_parent)
        {
            if (a_child.parent == std::addressof(a_parent)) { return; }
            RE::NiPointer<RE::NiAVObject> keepAlive(std::addressof(a_child));
            if (auto* oldParent = a_child.parent) { oldParent->DetachChild(std::addressof(a_child)); }
            a_parent.AttachChild(keepAlive.get(), true);
        }

        RE::NiPointer<RE::NiAVObject> CloneBipedPartToFreshSkeleton(
            RE::NiAVObject& a_source, RE::NiAVObject& a_previewRoot, const PreviewNodeMap& a_previewNodes)
        {
            RE::NiCloningProcess cloneProcess;
            cloneProcess.appendChar = '$';
            cloneProcess.copyType = RE::NiCloningProcess::CopyType::kCopyExact;
            cloneProcess.scale = { 1.0f, 1.0f, 1.0f };

            // TF3DHUD PreviewClone::SeedSkinCloneMappings, the essential difference from the failed whole-root
            // clone. Skin root and bone references are redirected during cloning, before stale raw pointers can
            // enter the new BSSkin::Instance.
            ForEachAVObject(std::addressof(a_source), [&](RE::NiAVObject& a_object) {
                auto* geometry = netimmerse_cast<RE::BSGeometry*>(std::addressof(a_object));
                auto* skin = geometry ? geometry->skinInstance.get() : nullptr;
                if (!skin || skin->bones.size() > RE::BSSkin::kMaxExpectedBones) { return; }
                if (skin->rootNode) { cloneProcess.cloneMap.emplace(skin->rootNode, std::addressof(a_previewRoot)); }
                for (auto* sourceBone : skin->bones) {
                    if (!sourceBone) { continue; }
                    const char* name = sourceBone->GetName().c_str();
                    if (!name || name[0] == '\0') { continue; }
                    const auto it = a_previewNodes.find(name);
                    if (it != a_previewNodes.end() && it->second) {
                        cloneProcess.cloneMap.emplace(sourceBone, it->second);
                    }
                }
            });

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

        RE::NiPointer<RE::NiAVObject> LoadFreshRaceSkeleton(RE::PlayerCharacter& a_player)
        {
            auto* race = a_player.GetVisualsRace();
            if (!race) {
                if (auto* base = a_player.GetObjectReference()) {
                    if (auto* npc = base->As<RE::TESNPC>()) { race = npc->GetFormRace(); }
                }
            }
            if (!race) { logger::error("[PipOS][3D] TF3DHUD fresh skeleton: player race unavailable"); return nullptr; }

            const auto sex = std::min<std::uint32_t>(static_cast<std::uint32_t>(a_player.GetSex()), 1);
            const char* skeletonPath = race->skeletonModel[sex].GetModel();
            if (!skeletonPath || skeletonPath[0] == '\0') { skeletonPath = race->skeletonModel[0].GetModel(); }
            if (!skeletonPath || skeletonPath[0] == '\0') { skeletonPath = race->skeletonModel[1].GetModel(); }
            if (!skeletonPath || skeletonPath[0] == '\0') {
                logger::error("[PipOS][3D] TF3DHUD fresh skeleton: race skeleton path unavailable");
                return nullptr;
            }

            RE::NiPointer<RE::NiNode> loadedRoot;
            RE::BSModelDB::DBTraits::ArgsType args{};
            args.loadLevel = 3;
            args.prepareAfterLoad = true;
            args.performProcess = true;
            args.createFadeNode = true;
            args.loadTextures = true;
            const auto result = RE::BSModelDB::Demand(skeletonPath, std::addressof(loadedRoot), args);
            if (result != RE::BSResource::ErrorCode::kNone || !loadedRoot) {
                logger::error(std::format(
                    "[PipOS][3D] TF3DHUD fresh skeleton: Demand('{}') failed ({})",
                    skeletonPath, std::to_underlying(result)));
                return nullptr;
            }

            auto previewRoot = CloneSubtree(*loadedRoot);
            if (!previewRoot) { return nullptr; }

            // The shipped human race skeleton exposes Weapon as a logical flattened bone but does not carry an
            // ordinary NiNode for equipment to parent beneath. Validate the stable hierarchy before
            // ConvertNodeTree so the logical Weapon entry is preserved. The field runtime can still optimize its
            // node pointer to null, so the ordinary wrapper receives the logical graph local through the private
            // transform bridge after flattening. No live actor transform participates in either step.
            auto* handObject = previewRoot->GetObjectByName(RE::BSFixedString("RArm_Hand"));
            auto* hand = handObject ? handObject->IsNode() : nullptr;
            if (!hand) {
                logger::error(
                    "[PipOS][3D] private Weapon node validation failed before skeleton flatten: RArm_Hand is missing");
                return nullptr;
            }

            bool privateWeaponNodeCreated = false;
            bool privateWeaponNodeReparented = false;
            auto* weaponObject = previewRoot->GetObjectByName(RE::BSFixedString("Weapon"));
            auto* privateWeaponNode = weaponObject ? weaponObject->IsNode() : nullptr;
            if (weaponObject && !privateWeaponNode) {
                logger::error(
                    "[PipOS][3D] private Weapon node validation failed before skeleton flatten: existing Weapon object is not a NiNode");
                return nullptr;
            }
            if (!privateWeaponNode) {
                auto weaponNode = RE::make_nismart<RE::NiNode>(0);
                weaponNode->name = RE::BSFixedString("Weapon");
                privateWeaponNode = weaponNode.get();
                hand->AttachChild(privateWeaponNode, false);
                privateWeaponNodeCreated = true;
            } else if (privateWeaponNode->parent != hand) {
                AttachChildLikeEngine(*privateWeaponNode, *hand);
                privateWeaponNodeReparented = true;
            }
            privateWeaponNode->SetLocalTransform(RE::NiTransform::IDENTITY);
            privateWeaponNode->SetAppCulled(false);
            privateWeaponNode->fadeAmount = 1.0f;
            const bool preFlattenPrivateWeaponNodeValidated = privateWeaponNode->parent == hand;
            if (!preFlattenPrivateWeaponNodeValidated) {
                logger::error(
                    "[PipOS][3D] private Weapon node validation failed before skeleton flatten: parent is not RArm_Hand");
                return nullptr;
            }
            logger::info(
                "[PipOS][3D] private identity Weapon node validated before skeleton flatten: created={} reparented={}",
                privateWeaponNodeCreated,
                privateWeaponNodeReparented);
            constexpr auto kRootPart = RE::BGSBodyPartDefs::LIMB_ENUM::kRoot;
            auto* convertTarget = g_getActorBodyPart3D(
                std::addressof(a_player), previewRoot.get(), std::addressof(kRootPart), false);
            if (!convertTarget) {
                logger::error("[PipOS][3D] TF3DHUD fresh skeleton: root body-part lookup failed");
                return nullptr;
            }
            if (convertTarget != previewRoot.get()) { g_convertNodeTree(convertTarget); }
            EngineCreateBoneMap(previewRoot.get());
            auto* flattened = FindFlattenedBoneTree(previewRoot.get());
            if (!flattened) {
                logger::error("[PipOS][3D] TF3DHUD fresh skeleton: flatten produced no BSFlattenedBoneTree");
                return nullptr;
            }
            EngineCreateBoneMap(flattened);
            EngineCreateBoneMap(previewRoot.get());
            if (auto* weaponBone = FindFlattenedBoneByName(*flattened, "Weapon")) {
                logger::info(
                    "[PipOS][3D] flattened Weapon bone published: node={} parentIndex={} preFlattenPrivateNodeValidated={}",
                    weaponBone->node != nullptr, weaponBone->parent, preFlattenPrivateWeaponNodeValidated);
            } else {
                logger::error("[PipOS][3D] pre-flatten Weapon node was not published into flattened bones");
            }
            logger::info("[PipOS][3D] TF3DHUD fresh skeleton loaded: '{}' ({} flattened bones)",
                skeletonPath, flattened->boneCount);
            return previewRoot;
        }

        void* GetPlayerClothWorld(RE::PlayerCharacter& a_player)
        {
            auto* cell = a_player.GetParentCell();
            auto* havokWorld = cell ? cell->GetbhkWorld() : nullptr;
            return havokWorld ?
                *reinterpret_cast<void**>(reinterpret_cast<std::byte*>(havokWorld) + 0x148) : nullptr;
        }

        std::uint32_t InitializePreviewCloth(
            RE::PlayerCharacter& a_player, RE::NiAVObject& a_object,
            RE::NiAVObject& a_previewRoot, const char* a_modelPath)
        {
            auto* settings = Settings::GetSingleton();
            if (!settings || !settings->Char3DCloth() || !a_modelPath || a_modelPath[0] == '\0') { return 0; }
            const RE::BSFixedString clothExtraName("CED");
            auto* clothWorld = GetPlayerClothWorld(a_player);
            std::uint32_t initialized = 0;
            ForEachAVObject(std::addressof(a_object), [&](RE::NiAVObject& candidate) {
                if (!candidate.GetExtraData(clothExtraName)) { return; }
                auto* runtime = g_createClothFor3D(
                    candidate, a_modelPath, a_previewRoot.GetWorldTransform(), std::addressof(a_previewRoot));
                if (!runtime) { return; }
                g_setClothSettle(runtime, true);
                if (clothWorld) { g_setClothWorld(runtime, clothWorld); }
                ++initialized;
            });
            return initialized;
        }

        struct BipedPopulationResult
        {
            int expected{ 0 };
            int attached{ 0 };
        };

        BipedPopulationResult PopulateFreshSkeletonFromBiped(
            RE::PlayerCharacter& a_player, RE::NiAVObject& a_previewRoot, const RE::BipedAnim& a_biped)
        {
            PreviewNodeMap previewNodes;
            CollectPreviewNodes(a_previewRoot, previewNodes);
            if (previewNodes.empty()) { return {}; }

            std::unordered_set<RE::NiAVObject*> seenSources;
            BipedPopulationResult result;
            for (std::int32_t i = 0; i < std::to_underlying(RE::BIPED_OBJECT::kTotal); ++i) {
                auto* settings = Settings::GetSingleton();
                if (i < 32 && settings && (settings->Char3DSlotMask() & (1u << i)) == 0) { continue; }
                const auto slot = static_cast<RE::BIPED_OBJECT>(i);
                const auto& sourceObject = a_biped.object[i];
                auto* sourcePart = sourceObject.partClone.get();
                if (!sourcePart || !seenSources.insert(sourcePart).second) { continue; }
                ++result.expected;

                auto clone = CloneBipedPartToFreshSkeleton(*sourcePart, a_previewRoot, previewNodes);
                if (!clone) { continue; }

                RE::NiNode* parent = nullptr;
                const auto* sourceForm = sourceObject.parent.object;
                const bool isWeaponForm = sourceForm && sourceForm->Is(RE::ENUM_FORM_ID::kWEAP);
                const bool isWeaponAttach = isWeaponForm &&
                    (IsEngineWeaponAttachSlot(slot) || slot == RE::BIPED_OBJECT::kShield);
                const bool isLightAttach = slot == RE::BIPED_OBJECT::kWeaponHand && sourceForm &&
                    sourceForm->Is(RE::ENUM_FORM_ID::kLIGH);
                const bool isStaffAttach = slot == RE::BIPED_OBJECT::kWeaponStaff;
                const bool usesStableWeaponParent = isWeaponAttach || isLightAttach || isStaffAttach;
                const bool hadInternalWeapon =
                    clone->GetObjectByName(RE::BSFixedString("Weapon")) != nullptr;
                const bool rootWasCulled = clone->GetAppCulled();
                if (isLightAttach) {
                    parent = EnsureRightHandWeaponNode(a_previewRoot, previewNodes);
                } else if (isStaffAttach) {
                    parent = EnsureRightHandWeaponNode(a_previewRoot, previewNodes);
                } else if (slot == RE::BIPED_OBJECT::kShield && isWeaponAttach) {
                    parent = FindPreviewNode(previewNodes, "WeaponLeft");
                } else if (isWeaponAttach) {
                    parent = EnsureRightHandWeaponNode(a_previewRoot, previewNodes);
                }
                std::string prnName;
                if (!parent && !usesStableWeaponParent) {
                    if (auto* prn = FindStringExtraDataInTree(*sourcePart, RE::BSFixedString("Prn"));
                        prn && !prn->GetValue().empty()) {
                        prnName = prn->GetValue().c_str();
                        parent = FindPreviewNode(previewNodes, prn->GetValue());
                    }
                }
                if (!parent && !usesStableWeaponParent) {
                    for (auto* sourceParent = sourcePart->parent; sourceParent && !parent;
                         sourceParent = sourceParent->parent) {
                        const char* name = sourceParent->GetName().c_str();
                        if (name && name[0] != '\0') { parent = FindPreviewNode(previewNodes, name); }
                    }
                }
                if (!parent && !usesStableWeaponParent) {
                    parent = netimmerse_cast<RE::NiNode*>(std::addressof(a_previewRoot));
                }
                if (!parent) { continue; }

                if (!isWeaponAttach) {
                    const auto restored = PrepareBipedAttachmentVisibility(*clone);
                    if (restored > 0) {
                        logger::info(
                            "[PipOS][3D] biped attachment visibility restored: slot={} form={:08X} objects={}",
                            i, sourceForm ? sourceForm->GetFormID() : 0, restored);
                    }
                } else if (rootWasCulled) {
                    // Weapon subtrees retain their NIF-authored visibility; only the attachment root must be
                    // available to the private skeleton.
                    clone->SetAppCulled(false);
                    clone->fadeAmount = 1.0f;
                }
                const auto cloneLocal = clone->GetLocalTransform();
                parent->AttachChild(clone.get(), false);
                bool scbReparented = false;
                if (usesStableWeaponParent) {
                    // Match BipedAnim::AttachToParent and TF3DHUD: after the complete clone is attached, move
                    // Scb beneath the same stable private weapon node without altering either object's local.
                    if (auto* scb = clone->GetObjectByName(RE::BSFixedString("Scb"));
                        scb && scb != clone.get()) {
                        const auto before = scb->GetLocalTransform();
                        AttachChildLikeEngine(*scb, *parent);
                        scbReparented = true;
                        logger::info(
                            "[PipOS][3D] weapon attach: slot={} form={:08X} parent='{}' boneParent='{}' Scb local=({:.2f},{:.2f},{:.2f}) scale={:.3f}",
                            i, sourceForm ? sourceForm->GetFormID() : 0,
                            parent->GetName().c_str() ? parent->GetName().c_str() : "<unnamed>",
                            parent->parent && parent->parent->GetName().c_str() ?
                                parent->parent->GetName().c_str() : "<none>",
                            before.translate.x, before.translate.y, before.translate.z, before.scale);
                    }
                }
                if (isWeaponAttach) {
                    float pitch = 0.0f;
                    float roll = 0.0f;
                    float yaw = 0.0f;
                    cloneLocal.rotate.ToEulerAnglesXYZ(pitch, roll, yaw);
                    logger::info(
                        "[PipOS][3D] weapon attach: slot={} form={:08X} parent='{}' boneParent='{}' Prn='{}' internalWeapon={} stablePrivateParent=true cloneLocalPreserved=true rootWasCulled={} ScbReparented={}; clone local=({:.2f},{:.2f},{:.2f}) rotDeg=({:.1f},{:.1f},{:.1f}) scale={:.3f}",
                        i, sourceForm ? sourceForm->GetFormID() : 0,
                        parent->GetName().c_str() ? parent->GetName().c_str() : "<unnamed>",
                        parent->parent && parent->parent->GetName().c_str() ?
                            parent->parent->GetName().c_str() : "<none>",
                        prnName.empty() ? "<none>" : prnName,
                        hadInternalWeapon,
                        rootWasCulled,
                        scbReparented,
                        cloneLocal.translate.x, cloneLocal.translate.y, cloneLocal.translate.z,
                        pitch * 180.0f / kPi, roll * 180.0f / kPi, yaw * 180.0f / kPi,
                        cloneLocal.scale);
                }
                RE::bhkWorld::RemoveObjects(clone.get(), true, true);
                ForEachAVObject(clone.get(), [](RE::NiAVObject& a_object) { a_object.controllers.reset(); });
                // TF3DHUD extends its lookup after every attachment. Preserve existing skeleton entries as
                // authoritative, but expose newly cloned helper/weapon nodes to later biped parts.
                ForEachAVObject(clone.get(), [&](RE::NiAVObject& a_object) {
                    const char* name = a_object.GetName().c_str();
                    if (name && name[0] != '\0') {
                        previewNodes.try_emplace(name, std::addressof(a_object));
                    }
                });
                const char* modelPath = sourceObject.part ? sourceObject.part->GetModel() : nullptr;
                (void)InitializePreviewCloth(a_player, *clone, a_previewRoot, modelPath);
                ++result.attached;
            }

            EngineCreateBoneMap(std::addressof(a_previewRoot));
            if (auto* flattened = FindFlattenedBoneTree(std::addressof(a_previewRoot))) {
                EngineCreateBoneMap(flattened);
            }
            EngineCreateBoneMap(std::addressof(a_previewRoot));
            logger::info(
                "[PipOS][3D] TF3DHUD equipment construction: {}/{} unique biped parts attached",
                result.attached,
                result.expected);
            return result;
        }

        std::uint64_t BuildBipedSignature(const RE::BipedAnim& a_biped)
        {
            // TF3DHUD maintains a richer audited signature. These ownership pointers are sufficient for PIP-OS's
            // rebuild-on-change model: every equipped part replacement changes at least partClone, parent form,
            // armor addon, or model. FNV-1a keeps the comparison deterministic and allocation-free per pass.
            std::uint64_t hash = 1469598103934665603ull;
            auto mix = [&](const void* a_value) {
                hash ^= reinterpret_cast<std::uintptr_t>(a_value);
                hash *= 1099511628211ull;
            };
            for (std::int32_t i = 0; i < std::to_underlying(RE::BIPED_OBJECT::kTotal); ++i) {
                const auto& object = a_biped.object[i];
                mix(object.partClone.get());
                mix(object.parent.object);
                mix(object.armorAddon);
                mix(object.part);
            }
            return hash;
        }

        [[nodiscard]] bool HasPendingBipedModelHandles(
            const RE::BipedAnim& a_biped, std::int32_t& a_pendingSlot)
        {
            // A populated handle with no clone, or any populated buffered object, means LoadBipedParts is
            // between ownership states. Cloning at this point produces the familiar missing-head/limb build.
            for (std::int32_t i = 0; i < std::to_underlying(RE::BIPED_OBJECT::kTotal); ++i) {
                const auto& object = a_biped.object[i];
                if (object.handleList.head && !object.partClone) {
                    a_pendingSlot = i;
                    return true;
                }
                const auto& buffered = a_biped.bufferedObjects[i];
                if (buffered.parent.object || buffered.parent.instanceData || buffered.modExtra ||
                    buffered.armorAddon || buffered.part || buffered.partClone ||
                    buffered.objectGraphManager || buffered.hitEffect) {
                    a_pendingSlot = i;
                    return true;
                }
            }
            a_pendingSlot = -1;
            return false;
        }

        const char* PendingEquipmentKindName(const PendingEquipmentKind a_kind)
        {
            return a_kind == PendingEquipmentKind::kWeapon ? "weapon" : "armor";
        }

        void ResetEquipmentSettleCandidate()
        {
            g_equipmentCandidateSignature = 0;
            g_equipmentCandidateSequence = 0;
            g_equipmentStablePasses = 0;
            g_equipmentQuietPasses = 0;
            g_equipmentWaitLoggedSequence = 0;
            g_equipmentReadyLoggedSequence = 0;
            g_equipmentMaskMismatchLoggedSequences.clear();
        }

        void ClearPendingEquipmentEvents()
        {
            std::scoped_lock lock(g_pendingEquipmentLock);
            g_pendingEquipmentEvents.clear();
        }

        void EnqueuePendingEquipmentEvent(
            const std::uint32_t a_formID,
            const std::uint32_t a_armorSlotMask,
            const bool a_equipped,
            const PendingEquipmentKind a_kind)
        {
            PendingEquipmentEvent pending;
            {
                std::scoped_lock lock(g_pendingEquipmentLock);
                // A form's latest state supersedes its earlier state. A newly equipped right-hand weapon also
                // supersedes older equipped-weapon targets because only one can own that attachment at a time.
                std::erase_if(g_pendingEquipmentEvents, [&](const PendingEquipmentEvent& a_existing) {
                    if (a_existing.kind != a_kind) { return false; }
                    if (a_existing.formID == a_formID) { return true; }
                    if (a_kind == PendingEquipmentKind::kWeapon) {
                        return a_equipped && a_existing.equipped;
                    }
                    // Two equipped armor forms cannot simultaneously own the same advertised biped slot. The
                    // latest overlapping equip is the only reachable target; retaining the older one would
                    // deadlock the batch while waiting for mutually exclusive ownership.
                    return a_equipped && a_existing.equipped && a_armorSlotMask != 0 &&
                        (a_existing.armorSlotMask & a_armorSlotMask) != 0;
                });
                pending = {
                    .formID = a_formID,
                    .armorSlotMask = a_armorSlotMask,
                    .sequence = ++g_nextEquipmentEventSequence,
                    .kind = a_kind,
                    .equipped = a_equipped,
                };
                g_pendingEquipmentEvents.push_back(pending);
            }

            logger::info(
                "[PipOS][3D] equipment event queued: seq={} type={} form={:08X} equipped={} armorMask={:08X}",
                pending.sequence,
                PendingEquipmentKindName(pending.kind),
                pending.formID,
                pending.equipped,
                pending.armorSlotMask);
            if (g_pipboyOpen.load(std::memory_order_acquire)) {
                QueueCapturePass(1.0f / 60.0f);
            }
        }

        PendingEquipmentSnapshot SnapshotPendingEquipmentEvents()
        {
            std::scoped_lock lock(g_pendingEquipmentLock);
            PendingEquipmentSnapshot snapshot;
            snapshot.events = g_pendingEquipmentEvents;
            for (const auto& event : snapshot.events) {
                snapshot.lastSequence = (std::max)(snapshot.lastSequence, event.sequence);
            }
            return snapshot;
        }

        bool ClearPendingEquipmentEventsThrough(const std::uint64_t a_sequence)
        {
            std::scoped_lock lock(g_pendingEquipmentLock);
            std::erase_if(g_pendingEquipmentEvents, [&](const PendingEquipmentEvent& a_event) {
                return a_event.sequence <= a_sequence;
            });
            return !g_pendingEquipmentEvents.empty();
        }

        [[nodiscard]] bool BipedObjectHasForm(
            const RE::BIPOBJECT& a_object, const std::uint32_t a_formID)
        {
            return a_object.parent.object && a_object.parent.object->GetFormID() == a_formID;
        }

        [[nodiscard]] bool PendingEquipmentEventReflected(
            const RE::BipedAnim& a_biped,
            const PendingEquipmentEvent& a_event,
            std::int32_t& a_blockedSlot,
            const char*& a_reason)
        {
            if (a_event.kind == PendingEquipmentKind::kWeapon) {
                for (std::int32_t i = 0; i < std::to_underlying(RE::BIPED_OBJECT::kTotal); ++i) {
                    const auto slot = static_cast<RE::BIPED_OBJECT>(i);
                    if (!IsEngineWeaponAttachSlot(slot) && slot != RE::BIPED_OBJECT::kShield) { continue; }
                    const auto& object = a_biped.object[i];
                    if (!BipedObjectHasForm(object, a_event.formID)) { continue; }
                    if (!a_event.equipped) {
                        a_blockedSlot = i;
                        a_reason = "unequipped weapon is still present";
                        return false;
                    }
                    if (!object.partClone) {
                        a_blockedSlot = i;
                        a_reason = "equipped weapon partClone is not published";
                        return false;
                    }
                    return true;
                }
                if (a_event.equipped) {
                    a_reason = "matching equipped weapon is not present";
                    return false;
                }
                return true;
            }

            if (!a_event.equipped) {
                for (std::int32_t i = 0; i < std::to_underlying(RE::BIPED_OBJECT::kTotal); ++i) {
                    if (BipedObjectHasForm(a_biped.object[i], a_event.formID)) {
                        a_blockedSlot = i;
                        a_reason = "unequipped armor is still present";
                        return false;
                    }
                }
                return true;
            }

            // Armor with no advertised biped slots cannot replace visible preview geometry. Treat the event as
            // reflected once the global pending-handle gate is clear instead of waiting forever on no slots.
            if (a_event.armorSlotMask == 0) { return true; }

            // ARMO slots describe occupancy/conflicts, while the runtime BipedAnim entries are produced by the
            // applicable ARMA add-ons for this race and sex. Multi-slot and modded armor can therefore publish one
            // complete partClone instead of duplicating that clone into every ARMO bit. Require at least one
            // matching visible runtime part, then let the global pending-handle gate, quiet interval, and stable
            // whole-biped signature prove that all participating add-ons have converged.
            std::uint32_t matchingFormMask = 0;
            std::uint32_t matchingCloneMask = 0;
            for (std::int32_t i = 0; i < 32; ++i) {
                const auto& object = a_biped.object[i];
                if (!BipedObjectHasForm(object, a_event.formID)) { continue; }
                matchingFormMask |= 1u << i;
                if (object.partClone) { matchingCloneMask |= 1u << i; }
            }
            if ((matchingCloneMask & a_event.armorSlotMask) != 0) { return true; }
            if (matchingCloneMask != 0) {
                if (g_equipmentMaskMismatchLoggedSequences.insert(a_event.sequence).second) {
                    logger::info(
                        "[PipOS][3D] armor runtime-slot mismatch accepted: seq={} form={:08X} advertisedMask={:08X} matchingFormMask={:08X} matchingCloneMask={:08X}",
                        a_event.sequence,
                        a_event.formID,
                        a_event.armorSlotMask,
                        matchingFormMask,
                        matchingCloneMask);
                }
                return true;
            }

            for (std::int32_t i = 0; i < 32; ++i) {
                if ((a_event.armorSlotMask & (1u << i)) != 0) {
                    a_blockedSlot = i;
                    break;
                }
            }
            a_reason = matchingFormMask != 0 ?
                "matching equipped armor has no published visual partClone" :
                "matching equipped armor is not published in an advertised runtime slot";
            return false;
        }

        [[nodiscard]] bool PendingEquipmentEventsReflected(
            const RE::BipedAnim& a_biped,
            const PendingEquipmentSnapshot& a_snapshot,
            PendingEquipmentEvent& a_blockedEvent,
            std::int32_t& a_blockedSlot,
            const char*& a_reason)
        {
            for (const auto& event : a_snapshot.events) {
                if (!PendingEquipmentEventReflected(a_biped, event, a_blockedSlot, a_reason)) {
                    a_blockedEvent = event;
                    return false;
                }
            }
            return true;
        }

        std::uint64_t BuildVisualSignature(RE::PlayerCharacter& a_player)
        {
            std::uint64_t hash = 1469598103934665603ull;
            const auto mix = [&](std::uintptr_t value) {
                hash ^= value;
                hash *= 1099511628211ull;
            };
            mix(reinterpret_cast<std::uintptr_t>(a_player.GetVisualsRace()));
            mix(static_cast<std::uintptr_t>(a_player.GetSex()));
            mix(reinterpret_cast<std::uintptr_t>(a_player.GetFaceNodeSkinned()));
            // Do not fold BipedAnim into this signature. While Pip-Boy inventory is open, the engine reuses
            // the player's third-person biped for the selected-item preview. That temporary model is not the
            // equipped loadout and must never replace the character captured at menu-open time.
            // The live third-person root owns the same BipedAnim geometry. Traversing every geometry here would
            // reintroduce the selected-item preview through rendererData/skinInstance pointer changes even though
            // the explicit biped signature above is excluded. Race, sex, face node, and NPC head/morph state are
            // the stable appearance signals; equipment changes arrive through TESEquipEvent.
            auto* base = a_player.GetObjectReference();
            auto* npc = base ? base->As<RE::TESNPC>() : nullptr;
            if (npc) {
                mix(reinterpret_cast<std::uintptr_t>(npc->GetRootFaceNPC()));
                mix(reinterpret_cast<std::uintptr_t>(npc->headParts));
                mix(static_cast<std::uintptr_t>(npc->numHeadParts));
                for (std::int32_t i = 0; npc->headParts && i < npc->numHeadParts; ++i) {
                    mix(reinterpret_cast<std::uintptr_t>(npc->headParts[i]));
                }
                std::uint32_t bits = 0;
                std::memcpy(std::addressof(bits), std::addressof(npc->morphWeight.x), sizeof(bits)); mix(bits);
                std::memcpy(std::addressof(bits), std::addressof(npc->morphWeight.y), sizeof(bits)); mix(bits);
                std::memcpy(std::addressof(bits), std::addressof(npc->morphWeight.z), sizeof(bits)); mix(bits);
            }
            return hash;
        }

        bool AttachFreshFaceGenHead(RE::PlayerCharacter& a_player, RE::NiAVObject& a_previewRoot)
        {
            // TF3DHUD does not expect FaceGen to arrive through BipedAnim. It clones the live skinned face node
            // separately, seeds its skin mappings to the fresh skeleton, then invokes the same engine skin-fix
            // helper used by AttachHeadHelper. 0.0.79 omitted this entire path, matching the missing head in game.
            auto* liveFaceOpaque = a_player.GetFaceNodeSkinned();
            auto* liveFace = reinterpret_cast<RE::NiAVObject*>(liveFaceOpaque);
            if (!liveFace) {
                if (auto* liveRoot = a_player.Get3D(false)) {
                    liveFace = liveRoot->GetObjectByName(RE::BSFixedString("BSFaceGenNiNodeSkinned"));
                }
            }
            if (!liveFace) {
                logger::error("[PipOS][3D] TF3DHUD head construction: live FaceGen node unavailable");
                return false;
            }

            PreviewNodeMap previewNodes;
            CollectPreviewNodes(a_previewRoot, previewNodes);
            auto faceClone = CloneBipedPartToFreshSkeleton(*liveFace, a_previewRoot, previewNodes);
            if (!faceClone) {
                logger::error("[PipOS][3D] TF3DHUD head construction: FaceGen clone failed");
                return false;
            }
            auto* actorRoot = netimmerse_cast<RE::NiNode*>(std::addressof(a_previewRoot));
            if (!actorRoot) {
                logger::error("[PipOS][3D] TF3DHUD head construction: preview root is not a NiNode");
                return false;
            }

            RE::bhkWorld::RemoveObjects(faceClone.get(), true, true);
            ForEachAVObject(faceClone.get(), [](RE::NiAVObject& a_object) { a_object.controllers.reset(); });
            actorRoot->AttachChild(faceClone.get(), false);
            g_fixFaceGenHeadSkinInstances(faceClone.get(), std::addressof(a_previewRoot), true);
            g_previewFaceNode = static_cast<RE::BSFaceGenNiNode*>(faceClone.get());
            logger::info("[PipOS][3D] TF3DHUD head construction: live FaceGen clone attached + skins fixed");
            return true;
        }

        RE::BSFaceGenAnimationData* GetLiveFaceAnimationData(RE::PlayerCharacter& a_player)
        {
            auto* liveFace = reinterpret_cast<RE::BSFaceGenNiNode*>(a_player.GetFaceNodeSkinned());
            if (liveFace && liveFace->animationData) { return liveFace->animationData; }
            auto* middleHigh = a_player.currentProcess ? a_player.currentProcess->middleHigh : nullptr;
            return middleHigh ? reinterpret_cast<RE::BSFaceGenAnimationData*>(middleHigh->faceAnimationData) : nullptr;
        }

        void SyncPreviewFacialExpression(RE::PlayerCharacter& a_player)
        {
            auto* settings = Settings::GetSingleton();
            if (!settings || !settings->Char3DFaceMorphs() || !g_previewFaceNode) { return; }
            auto* liveData = GetLiveFaceAnimationData(a_player);
            auto* previewData = g_previewFaceNode->animationData;
            if (liveData && previewData && liveData != previewData) {
                previewData->currentExpression = liveData->currentExpression;
                previewData->modifierExpression = liveData->modifierExpression;
                previewData->baseExpression = liveData->baseExpression;
                previewData->morphsDirty = true;
                previewData->forceMorphUpdate = true;
            }
            g_previewFaceNode->faceGenFlags &= static_cast<std::uint16_t>(~0x4u);
            g_updateAllChildrenMorphData(g_previewFaceNode.get(), true);
        }

        void InitializePreviewHairCloth(RE::PlayerCharacter& a_player, RE::NiAVObject& a_previewRoot)
        {
            auto* settings = Settings::GetSingleton();
            auto* base = a_player.GetObjectReference();
            auto* npc = base ? base->As<RE::TESNPC>() : nullptr;
            if (!settings || !settings->Char3DCloth() || !npc || !g_previewFaceNode ||
                !npc->headParts || npc->numHeadParts <= 0) {
                return;
            }
            std::uint32_t initialized = 0;
            std::function<void(RE::BGSHeadPart*)> visit = [&](RE::BGSHeadPart* part) {
                if (!part) { return; }
                if (*part->type == RE::BGSHeadPart::HeadPartType::kHair && !part->formEditorID.empty()) {
                    if (auto* object = g_previewFaceNode->GetObjectByName(part->formEditorID)) {
                        initialized += InitializePreviewCloth(
                            a_player, *object, a_previewRoot, part->GetModel());
                    }
                }
                for (auto* extra : part->extraParts) { visit(extra); }
            };
            for (std::int32_t i = 0; i < npc->numHeadParts; ++i) { visit(npc->headParts[i]); }
            logger::info("[PipOS][3D] preview hair cloth initialized: {} objects", initialized);
        }

        void ApplyFreshBodyTint(RE::PlayerCharacter& a_player, RE::NiAVObject& a_previewRoot)
        {
            auto* playerBase = a_player.GetObjectReference();
            auto* npc = playerBase ? playerBase->As<RE::TESNPC>() : nullptr;
            if (!npc) { return; }
            RE::NiColorA bodyTint{ 0.0f, 0.0f, 0.0f, 0.0f };
            g_calculateBodyTintColor(npc, bodyTint, nullptr, true, false);
            bodyTint.a = 1.0f;
            g_updateBodyTintColorsOnScene(std::addressof(a_previewRoot), bodyTint);
            RestoreShaderAlpha(a_previewRoot);
            logger::info("[PipOS][3D] TF3DHUD body tint applied");
        }

        RE::NiPointer<RE::NiAVObject> BuildFreshTF3DHUDCharacter(
            RE::PlayerCharacter& a_player, RE::NiAVObject& a_liveSource)
        {
            const auto& biped = a_player.GetBiped(false);
            if (!biped) {
                logger::error("[PipOS][3D] TF3DHUD fresh character: third-person biped unavailable");
                return nullptr;
            }
            auto previewRoot = LoadFreshRaceSkeleton(a_player);
            if (!previewRoot) { return nullptr; }
            const auto population = PopulateFreshSkeletonFromBiped(a_player, *previewRoot, *biped);
            if (population.attached == 0 || population.attached != population.expected) {
                logger::error(std::format(
                    "[PipOS][3D] TF3DHUD fresh character: incomplete biped candidate ({}/{} parts attached)",
                    population.attached,
                    population.expected));
                return nullptr;
            }
            if (!AttachFreshFaceGenHead(a_player, *previewRoot)) {
                logger::error(
                    "[PipOS][3D] TF3DHUD fresh character: mandatory FaceGen head attachment failed");
                return nullptr;
            }
            InitializePreviewHairCloth(a_player, *previewRoot);
            SanitizeClone(*previewRoot, std::addressof(a_liveSource));
            ApplyFreshBodyTint(a_player, *previewRoot);
            return previewRoot;
        }

        // ------------------------------------------------------------------ sanitise (PreviewRenderTree.cpp)
        // 0.0.73: a_source = the LIVE tree the clone came from (for the shared-skin guard); may be null.
        void SanitizeClone(RE::NiAVObject& a_root, RE::NiAVObject* a_source)
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

            // 0.0.75 consensus batch (4-agent TF3DHUD sweep), each independently logged:
            // (1) detach live havok/cloth references TF3DHUD strips at every level (robustness);
            try { RE::bhkWorld::RemoveObjects(std::addressof(a_root), true, true); } catch (...) {}
            // (2) POSE COPY -- source flattened bone[].local -> clone's array by name (top zero-pixels suspect:
            //     stale/identity clone pose collapses the skinned body to a sub-pixel speck);
            const int posed = CopyFlattenedPose(a_root, a_source);
            logger::info("[PipOS][3D] pose copy: {} flattened bone locals copied from the source", posed);
            // (3) shader-alpha restore (alpha<=0 clone materials render fully transparent);
            const int alphaFixed = RestoreShaderAlpha(a_root);
            logger::info("[PipOS][3D] shader alpha: {} properties restored from <=0 to 1", alphaFixed);
            // (4) dismember segments: force-enable all (inherited disable counts hide segments invisibly).
            int segData = 0;
            ForEachAVObject(std::addressof(a_root), [&](RE::NiAVObject& a_object) {
                if (auto* geometry = netimmerse_cast<RE::BSGeometry*>(std::addressof(a_object))) {
                    if (auto* segments = geometry->GetSegmentData()) { EngineEnableAllSegments(segments); ++segData; }
                }
            });
            logger::info("[PipOS][3D] segments: EnableAllSegments on {} geometries", segData);

            // 0.0.73: rebind skinned geometry to the clone's own skeleton, also before the flush Update (matching
            // TF3DHUD's order: RebindPreviewSkinInstances precedes the final Update). Logs its own counts.
            const int rebound = RebindClonedSkins(a_root, a_source);
            if (rebound < 0) { logger::info("[PipOS][3D] skin rebind: NO flattened bone tree found in the clone"); }

            RE::NiUpdateData updateData{};
            a_root.Update(updateData);
        }

        // ------------------------------------------------------------------ framing (PreviewFraming.cpp)
        // a_distanceCap > 0 clamps the camera distance (0.0.72: the borrowed item-preview camera is short-range;
        // the own-renderer long-range path passes no cap).
        void FrameClone(RE::NiAVObject& a_root, float a_distanceCap = 0.0f)
        {
            auto* settings = Settings::GetSingleton();
            const float scale = settings ? settings->Char3DScale() : 0.45f;
            const float yaw = (settings ? settings->Char3DYaw() : 160.0f) + g_sessionYawOffset.load();
            const float pitch = settings ? settings->Char3DPitch() : 0.0f;
            const float roll = settings ? settings->Char3DRoll() : 0.0f;
            float distance = settings ? settings->Char3DDistance() : 200.0f;
            if (a_distanceCap > 0.0f && distance > a_distanceCap) { distance = a_distanceCap; }
            const int target = settings ? settings->Char3DTarget() : 1;

            RE::NiTransform transform = RE::NiTransform::IDENTITY;
            transform.scale = scale;
            transform.rotate.FromEulerAnglesXYZ(
                pitch * kPi / 180.0f, roll * kPi / 180.0f, yaw * kPi / 180.0f);
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
            // Translation-only placement lives in model space. Unlike moving/resizing the compositor quad,
            // this cannot change UV scale or stretch the rendered character.
            centered.translate.x += settings ? settings->Char3DScreenX() : 0.0f;
            if (!g_inventoryPageActive.load()) { centered.translate.x += kNonInventoryModelOffsetX; }
            centered.translate.z += settings ? settings->Char3DScreenY() : 0.0f;
            a_root.SetLocalTransform(centered);
            a_root.Update(updateData);

            g_baseTransform = centered;
        }

        // TF3DHUD PreviewFraming parity: after the private graph moves the selected bone, translate the
        // preview root back toward the configured screen anchor. Axis switches allow deliberate partial follow.
        void ApplyTargetFollow(RE::NiAVObject& a_root)
        {
            auto* settings = Settings::GetSingleton();
            if (!settings || !settings->Char3DFollow() ||
                (!settings->Char3DFollowX() && !settings->Char3DFollowY() && !settings->Char3DFollowZ())) {
                return;
            }

            RE::NiPoint3 targetWorld;
            if (!TryGetFramingTargetWorld(a_root, settings->Char3DTarget(), targetWorld)) { return; }

            auto transform = a_root.GetLocalTransform();
            if (settings->Char3DFollowX()) {
                const float pageOffset = g_inventoryPageActive.load() ? 0.0f : kNonInventoryModelOffsetX;
                transform.translate.x += settings->Char3DScreenX() + pageOffset - targetWorld.x;
            }
            if (settings->Char3DFollowY()) { transform.translate.y += settings->Char3DDistance() - targetWorld.y; }
            if (settings->Char3DFollowZ()) {
                transform.translate.z += settings->Char3DScreenY() - targetWorld.z;
            }
            a_root.SetLocalTransform(transform);
            RE::NiUpdateData updateData{};
            a_root.Update(updateData);
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

        void SynchronizeLivePose(RE::NiAVObject& a_previewRoot, RE::NiAVObject& a_liveSource)
        {
            // Full TF3DHUD owns a private animation graph. PIP-OS already has the live player's authoritative
            // third-person flattened pose available each frame, so mirror those locals into the independent
            // preview skeleton before its Update. This provides live body animation without sharing graph or
            // skeleton ownership, and preserves the fresh-skeleton skin bindings established at construction.
            const int copied = CopyFlattenedPose(a_previewRoot, std::addressof(a_liveSource));
            if (copied > 0 && !g_loggedLivePoseSync.exchange(true)) {
                logger::info("[PipOS][3D] live pose synchronization active: {} flattened bone locals per pass", copied);
            }
            if (g_previewFaceNode) { g_updateAllChildrenMorphData(g_previewFaceNode.get(), true); }
        }

        // ------------------------------------------------------------------ renderer (Renderer.cpp)
        bool ConfigureRenderer()
        {
            if (g_renderer) { return true; }
            g_displayAttached = false;

            auto* settings = Settings::GetSingleton();
            const float fov = settings ? settings->Char3DFov() : 70.0f;
            const RE::BSFixedString name(kRendererName);

            // 0.0.67 COMPOSITING FIX (vanilla-item-preview trace): the 0.0.60 kTerminal(0x9) depth experiment is
            // REVERTED -- the engine's Interface3D composite loop does not draw that depth while the Pip-Boy is
            // the active menu (renderer enabled, never composited = the exact symptom; the original invisibility
            // it tried to fix was actually the fade-node bug, fixed in 0.0.64). Back to kStandard3DModel(0x7),
            // the engine's DOCUMENTED "3D model over a menu" depth (Container3D / WorkbenchItem3D -- the same
            // layer family the provably-working vanilla Pip-Boy item preview composites in), and
            // alwaysRenderWhenEnabled=true so the renderer composites every frame while enabled instead of
            // waiting for a menu owner to claim its depth (none does over the fullscreen Scaleform Pip-Boy).
            // Depth is fixed at Create, so RELEASE any renderer persisted under the old depth and recreate --
            // makes the fix deterministic without requiring a fresh game launch.
            g_renderer = RE::Interface3D::Renderer::GetByName(name);
            if (g_renderer) {
                logger::info("[PipOS][3D] releasing persisted renderer (depth may be stale); recreating");
                g_renderer->Release();
                g_renderer = nullptr;
            }
            // 0.0.69: depth = kMessage (0xF) -- [3DDIAG] ground truth: the vanilla item preview's
            // 'PipboyScreenModel' composites at depth 15, ABOVE the fullscreen Scaleform menu (that is why the
            // weapon preview floats OVER the Pip-Boy UI while our depth-7 red block rendered UNDER it, visible
            // only through transparent regions). Matching it puts the character over our UI as requested.
            g_renderer = RE::Interface3D::Renderer::Create(
                name, RE::UI_DEPTH_PRIORITY::kMessage, fov, true);
            if (!g_renderer) {
                logger::error("[PipOS][3D] Interface3D renderer creation returned null");
                return false;
            }
            g_renderer->alwaysRenderWhenEnabled = true;   // belt: member @055, in case Create's arg is advisory

            // 0.0.69: config mirrored onto the [3DDIAG]-dumped VANILLA item-preview renderer ('PipboyScreenModel')
            // -- the one setup PROVEN to composite over this exact menu: HUDGlassFlat quad + its BGEM material +
            // HUDShadowFlat mask, PostEffect kHUDGlass(2) (was kModMenu 4), fullPremultAlpha=false (vanilla),
            // hideScreenWhenDisabled=true (vanilla). Deliberate deviation: useLongRangeCamera stays TRUE (our
            // character sits at Char3DDistance~200 game units; the item preview's short-range camera could clip it).
            // 0.0.78's red clear proved this quad and depth in game. 0.0.79 retains the same renderer family but
            // restores a transparent target and ports TF3DHUD's deferred hooks so character geometry can replace
            // the proof color without sacrificing the confirmed above-PIP-OS ordering.
            // 0.0.70: the WORKING COMBINATION -- the 0.0.66-68 quad pipeline (ModMenuRenderMesh + kModMenu +
            // TF3DHUD alpha flags: FIELD-PROVEN to composite, it carried the red block) at the 0.0.69 depth
            // (kMessage 15, [3DDIAG]-proven to layer ABOVE the fullscreen menu). 0.0.69's extra mirroring of the
            // vanilla quad/material/mask is reverted -- it killed the engine-auto-created display quad entirely.
            g_renderer->MainScreen_SetBackgroundMode(RE::Interface3D::BackgroundMode::kLive);
            // Interface3D's setter takes the engine's disable-AA policy, matching TF3DHUD's inversion.
            g_renderer->MainScreen_SetPostAA(!(settings && settings->Char3DAntiAliasing()));
            g_renderer->Offscreen_Enable3D(true);
            g_renderer->Offscreen_SetUseLongRangeCamera(true);
            g_renderer->Offscreen_SetRenderTargetSize(RE::Interface3D::OffscreenMenuSize::kFullFrame);
            g_renderer->Offscreen_SetDisplayMode(
                RE::Interface3D::ScreenMode::kScreenAttached, kDisplayMeshGeometry, nullptr);
            g_renderer->MainScreen_EnableScreenAttached3DMasking(nullptr, nullptr);
            if constexpr (kTF3DHUDCharacterPass) {
                // Exact TF3DHUD renderer path. Its deferred-render hooks installed below suppress tiled lighting
                // only for this renderer and correct the BSDF composite flags, allowing geometry into the RT.
                g_renderer->Offscreen_SetPostEffect(RE::Interface3D::PostEffect::kModMenu);
                g_renderer->useFullPremultAlpha = true;
            } else {
                // 0.0.71 THE MODEL-INTO-RT FIX (item-preview-path investigation): kHUDGlass, NOT kModMenu. Under
                // tiled lighting the kModMenu DEFERRED composite (BSDFCompositeShader) samples per-tile light
                // lists that are never populated during an offscreen menu render, so geometry contributes no
                // pixels. The vanilla item preview avoids that dependency by rendering forward via kHUDGlass.
                g_renderer->Offscreen_SetPostEffect(RE::Interface3D::PostEffect::kHUDGlass);
                g_renderer->useFullPremultAlpha = false;
                g_renderer->hideScreenWhenDisabled = true;
            }
            g_renderer->customRenderTarget = -1;
            g_renderer->customSwapTarget = -1;
            g_renderer->Offscreen_SetClearRenderTarget(true);
            if constexpr (kTF3DHUDCharacterPass) {
                // Replace 0.0.78's opaque proof color with TF3DHUD's transparent character target.
                g_renderer->Offscreen_SetBackgroundColor(RE::NiColorA{ 0.0f, 0.0f, 0.0f, 0.0f });
                logger::info(
                    "[PipOS][3D] 0.0.123 FRAME-BOUND EQUIPMENT SETTLE active: Interface3D accumulation is lifetime-locked and every queued capture/probe/close operation is session-token guarded; each right-hand weapon clone keeps its NIF local beneath the ordinary private Weapon wrapper under RArm_Hand, the preview graph's flattened Weapon local is published to that wrapper after each private graph update, Scb is replayed beneath the same wrapper, and no live gameplay Weapon transform or animation-refresh request is used; equipment polls requested from inside an F4SE capture task are deferred to the next render frame, require matching published runtime ownership, then 15 quiet render frames and three identical whole-biped signatures, and remain pending until a complete preview publishes; newly equipped biped attachments use TF3DHUD selective visibility, cursor-matched session yaw drag, Ready/Sighted right-click toggle, "
                    "three-point lighting, transparent kModMenu RT, fresh "
                    "race skeleton, seeded biped clones, depth 15, recreate-on-open");
            } else {
                g_renderer->Offscreen_SetBackgroundColor(RE::NiColorA{ 0.0f, 0.0f, 0.0f, 0.0f });
            }

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

        void AttachClippedDisplayRoot()
        {
            if (!g_renderer || !g_displayRoot || !g_displayClipApplied || g_displayAttached) { return; }
            g_renderer->MainScreen_SetScreenAttached3D(g_displayRoot.get());
            g_renderer->MainScreen_RegisterGeometryRequiringFullViewport(g_displayRoot.get());
            g_displayAttached = true;
            logger::info("[PipOS][3D] clipped display root attached");
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

        void ConfigureThreePointLights(RE::Interface3D::Renderer& a_renderer)
        {
            auto* settings = Settings::GetSingleton();
            const float keyIntensity = settings ? settings->Char3DKeyIntensity() : 3.4f;
            const float fillIntensity = settings ? settings->Char3DFillIntensity() : 1.55f;
            const float rimIntensity = settings ? settings->Char3DRimIntensity() : 2.15f;
            const bool hologram = settings && settings->Char3DHologram();
            a_renderer.offscreenLights.clear();
            a_renderer.needsLightSetupOffscreen = true;

            // Key: warm, strong, high/front-left. Fill: cooler and softer from the opposite side.
            // Rim: pale green from behind/above to separate the silhouette from PIP-OS's dark background.
            a_renderer.Offscreen_AddLight(
                RE::NiPoint3{ 80.0f, -45.0f, 105.0f },
                RE::NiColor{ 1.00f, 0.82f, 0.68f },
                RE::NiColor{ 1200.0f, 0.0f, 0.0f },
                keyIntensity);
            a_renderer.Offscreen_AddLight(
                RE::NiPoint3{ -75.0f, -20.0f, 45.0f },
                RE::NiColor{ 0.48f, 0.66f, 1.00f },
                RE::NiColor{ 1000.0f, 0.0f, 0.0f },
                fillIntensity);
            a_renderer.Offscreen_AddLight(
                RE::NiPoint3{ 20.0f, 100.0f, 115.0f },
                hologram ? RE::NiColor{ 0.25f, 1.00f, 0.38f } : RE::NiColor{ 0.58f, 1.00f, 0.76f },
                RE::NiColor{ 1400.0f, 0.0f, 0.0f },
                hologram ? std::max(rimIntensity, 5.5f) : rimIntensity);
            logger::info("[PipOS][3D] three-point lighting configured: key={} fill={} rim={} hologram={}",
                keyIntensity, fillIntensity, hologram ? std::max(rimIntensity, 5.5f) : rimIntensity, hologram);
        }

        void RefreshLivePlacement()
        {
            auto* settings = Settings::GetSingleton();
            if (!settings || !g_previewRoot) { return; }

            const PlacementSnapshot current{
                settings->Char3DScale(), settings->Char3DFov(),
                settings->Char3DYaw() + g_sessionYawOffset.load(),
                settings->Char3DPitch(), settings->Char3DRoll(),
                settings->Char3DDistance(), settings->Char3DTarget(),
                settings->Char3DClipLeft(), settings->Char3DClipTop(),
                settings->Char3DClipRight(), settings->Char3DClipBottom(),
                settings->Char3DScreenX(), settings->Char3DScreenY(),
                settings->Char3DKeyIntensity(), settings->Char3DFillIntensity(),
                settings->Char3DRimIntensity(), settings->Char3DSlotMask(),
                settings->Char3DAntiAliasing(), settings->Char3DCloth(), settings->Char3DHologram(),
                g_inventoryPageActive.load()
            };
            const bool framingChanged = current.scale != g_livePlacement.scale ||
                current.yaw != g_livePlacement.yaw || current.pitch != g_livePlacement.pitch ||
                current.roll != g_livePlacement.roll || current.distance != g_livePlacement.distance ||
                current.target != g_livePlacement.target || current.screenX != g_livePlacement.screenX ||
                current.screenY != g_livePlacement.screenY ||
                current.inventoryPageActive != g_livePlacement.inventoryPageActive;
            const bool clipChanged = current.clipLeft != g_livePlacement.clipLeft ||
                current.clipTop != g_livePlacement.clipTop || current.clipRight != g_livePlacement.clipRight ||
                current.clipBottom != g_livePlacement.clipBottom;
            const bool lightingChanged = current.keyIntensity != g_livePlacement.keyIntensity ||
                current.fillIntensity != g_livePlacement.fillIntensity ||
                current.rimIntensity != g_livePlacement.rimIntensity ||
                current.hologram != g_livePlacement.hologram;
            const bool rebuildChanged = current.slotMask != g_livePlacement.slotMask ||
                current.cloth != g_livePlacement.cloth;
            const bool fovChanged = current.fov != g_livePlacement.fov;
            const bool aaChanged = current.antiAliasing != g_livePlacement.antiAliasing;

            if (framingChanged) {
                FrameClone(*g_previewRoot);
                logger::info("[PipOS][3D] live framing applied: scale={} yaw={} pitch={} roll={} distance={} target={}",
                    current.scale, current.yaw, current.pitch, current.roll, current.distance, current.target);
                if (current.inventoryPageActive != g_livePlacement.inventoryPageActive) {
                    logger::info("[PipOS][3D] inventory page placement: inventory={} modelOffsetX={}",
                        current.inventoryPageActive,
                        current.inventoryPageActive ? 0.0f : kNonInventoryModelOffsetX);
                }
            }
            if (clipChanged && g_displayRoot && !DisplayClipRectCopyPending()) {
                ApplyDisplayClipRect();
            }
            if (lightingChanged && g_renderer) { ConfigureThreePointLights(*g_renderer); }
            if (aaChanged && g_renderer) { g_renderer->MainScreen_SetPostAA(!current.antiAliasing); }
            // The camera FOV is immutable after Interface3D::Create. Request a main-thread renderer recreation,
            // but only after the initial snapshot has been populated.
            if (fovChanged && g_livePlacement.fov >= 0.0f) {
                g_rendererRecreateRequested.store(true);
                QueueCapturePass(1.0f / 60.0f);
            }
            if (rebuildChanged && g_livePlacement.scale >= 0.0f) {
                g_dirty.store(true);
                QueueCapturePass(1.0f / 60.0f);
            }
            g_livePlacement = current;
        }

        bool AttachToRenderer(RE::NiAVObject& a_previewRoot)
        {
            if (!g_renderer) { return false; }

            EnsureDisplayRoot();
            if (g_displayRoot) {
                // Never expose the stock full-frame quad. Its GPU buffers can still be uploading on first load;
                // attaching before clipping succeeds made the first open larger than every retained-root reopen.
                if (!DisplayClipRectCopyPending()) { ApplyDisplayClipRect(); }
                AttachClippedDisplayRoot();
            }

            g_forceUpgradeTextures(std::addressof(a_previewRoot), false, false);
            g_renderer->Offscreen_Set3D(std::addressof(a_previewRoot));

            ConfigureThreePointLights(*g_renderer);
            return g_renderer->offscreenElement.get() == std::addressof(a_previewRoot);
        }

        bool BuildPreview(
            RE::PlayerCharacter& a_player,
            RE::NiAVObject& a_source,
            const bool a_allowWholeRootFallback)
        {
            // Build the replacement off to the side. A failed equipment candidate must not disturb the last
            // complete preview's face metadata, private graph, or renderer attachment.
            auto previousFaceNode = g_previewFaceNode;
            auto previousRoot = g_previewRoot;
            bool candidateWeaponEquipped = false;
            if (const auto& biped = a_player.GetBiped(false); biped) {
                candidateWeaponEquipped = BipedHasEquippedWeapon(*biped);
            }
            g_previewFaceNode.reset();
            auto clone = kTF3DHUDCharacterPass ? BuildFreshTF3DHUDCharacter(a_player, a_source) : nullptr;
            if (!clone && a_allowWholeRootFallback && !previousRoot) {
                logger::info("[PipOS][3D] TF3DHUD fresh construction unavailable; falling back to whole-root clone");
                clone = CloneSubtree(a_source);
                if (clone) { SanitizeClone(*clone, std::addressof(a_source)); }
            }
            if (!clone) {
                g_previewFaceNode = std::move(previousFaceNode);
                logger::error(
                    "[PipOS][3D] complete player biped candidate failed; previous preview retained");
                return false;
            }
            if (!g_renderer) {
                g_previewFaceNode = std::move(previousFaceNode);
                logger::error("[PipOS][3D] preview candidate completed without an available renderer");
                return false;
            }
            FrameClone(*clone);
            if (!AttachToRenderer(*clone)) {
                if (previousRoot && !AttachToRenderer(*previousRoot)) {
                    logger::error(
                        "[PipOS][3D] renderer rejected both the replacement and retained preview roots");
                }
                g_previewFaceNode = std::move(previousFaceNode);
                logger::error(
                    "[PipOS][3D] renderer rejected complete player biped candidate; previous preview retained");
                return false;
            }
            CharacterAnimation::Reset();
            g_livePlacement = {};
            g_previewRoot = clone;
            g_previewWeaponEquipped = candidateWeaponEquipped;
            g_sourceRoot = std::addressof(a_source);
            if (const auto& biped = a_player.GetBiped(false); biped) {
                g_sourceBipedSignature = BuildBipedSignature(*biped);
            }
            g_sourceVisualSignature = BuildVisualSignature(a_player);
            logger::info("[PipOS][3D] preview built + attached to offscreen renderer");
            return true;
        }

        // ---------------------------------------------------------- 0.0.72 PLAN A.2: the VANILLA renderer
        // Primary path per the item-preview investigation: borrow the Pip-Boy's OWN 'PipboyScreenModel'
        // renderer (PipboyManager->inv3DModelManager.str3DRendererName) -- the one object FIELD-PROVEN to draw
        // 3D models over this exact fullscreen menu (engine-wired HUDGlass quad, forward kHUDGlass composite,
        // right depth, engine-managed lifecycle). We only borrow its OFFSCREEN SLOT:
        //   - Offscreen_Set3D(ourClone), but ONLY while the slot is empty or already ours -- a live item
        //     preview owns the slot and is never fought (we resume when it clears);
        //   - NEVER Enable/Disable/Release/End3D the vanilla renderer (the manager owns it);
        //   - one guarded Begin3D() per Pip-Boy open stands the renderer up before any item is selected
        //     (Begin3D with no queued item is unverified engine-internal -- if it no-ops we retry next pass).
        bool g_usingVanilla{ false };
        bool g_weEnabledVanilla{ false };

        RE::Interface3D::Renderer* AcquireVanillaRenderer()
        {
            // AUDIT H3: the Begin3D()-on-idle-manager stand-up was REMOVED (engine-internal body could deref the
            // null itemBase/tempRef of an idle manager = main-thread AV). The renderer therefore only exists
            // after the user inspects an item once per Pip-Boy session; until then we simply return null and the
            // caller retries next pass. Documented UX cost, zero crash risk.
            auto* pm = RE::PipboyManager::GetSingleton();
            if (!pm) { return nullptr; }
            const auto& nm = pm->inv3DModelManager.str3DRendererName;
            if (!nm.c_str() || nm.c_str()[0] == '\0') { return nullptr; }
            return RE::Interface3D::Renderer::GetByName(nm);
        }

        void HideAndRelease()
        {
            std::scoped_lock lock(g_sceneLock);
            CharacterAnimation::Reset();
            if (g_usingVanilla) {
                // Give the borrowed slot back iff it still holds OUR clone, and restore the disabled state we
                // found it in (tracked symmetric enable, audit H1). Never Release/End3D -- the manager owns it.
                auto* pm = RE::PipboyManager::GetSingleton();
                auto* vr = pm ? RE::Interface3D::Renderer::GetByName(pm->inv3DModelManager.str3DRendererName) : nullptr;
                if (vr && g_previewRoot && vr->offscreenElement.get() == g_previewRoot.get()) {
                    vr->Offscreen_Set3D(nullptr);
                    // 0.0.75: also clear the light list we injected so the manager rebuilds its own state.
                    vr->offscreenLights.clear();
                    vr->needsLightSetupOffscreen = true;
                    if (g_weEnabledVanilla && vr->enabled) { vr->Disable(); }
                    logger::info("[PipOS][3D] vanilla renderer slot returned (enable restored={})", g_weEnabledVanilla);
                }
                g_usingVanilla = false;
                g_weEnabledVanilla = false;
            }
            if (g_renderer) {
                g_renderer->Offscreen_Set3D(nullptr);
                if (g_visible || g_renderer->enabled) { g_renderer->Disable(); }
                if constexpr (kTF3DHUDCharacterPass) {
                    // Preserve the 0.0.78 field-proven ordering fix: a reused renderer moved under Scaleform after
                    // the first close. Recreate it at depth 15 each open while retaining the clipped display root.
                    g_renderer->MainScreen_SetScreenAttached3D(nullptr);
                    g_displayAttached = false;
                    g_renderer->Release();
                    g_renderer = nullptr;
                    logger::info("[PipOS][3D] 0.0.84 character renderer released; next open recreates depth 15");
                }
            }
            g_visible = false;
            g_available.store(false);
            g_previewRoot.reset();
            g_previewFaceNode.reset();
            g_previewWeaponEquipped = false;
            g_sourceRoot = nullptr;
            g_sourceBipedSignature = 0;
            g_sourceVisualSignature = 0;
            ClearPendingEquipmentEvents();
            ResetEquipmentSettleCandidate();
            g_captureRetryRequested.store(false, std::memory_order_release);
            g_livePlacement = {};
            g_dirty = true;
        }

        [[nodiscard]] bool PipboyOpen()
        {
            auto* ui = RE::UI::GetSingleton();
            if (!ui) { return false; }
            auto menu = ui->GetMenu(RE::BSFixedString(kPipboyMenu.data()));
            return menu.get() != nullptr;
        }

        [[nodiscard]] bool ShouldDrawCharacter(RE::PlayerCharacter& a_player)
        {
            auto* settings = Settings::GetSingleton();
            return !(settings && settings->Char3DHidePowerArmor() &&
                RE::PowerArmor::ActorInPowerArmor(a_player));
        }

        // Frame tick -- runs ONLY on the game main thread, inside RunCaptureTask (an F4SE task). All scene-graph
        // and D3D mutation happens here; the worker-thread hook never reaches this.
        void Tick(float a_delta, bool a_afterRenderBoundary)
        {
            std::scoped_lock lock(g_sceneLock);
            if (g_failed.load()) { return; }

            auto* settings = Settings::GetSingleton();
            const bool menuOpen = PipboyOpen();
            const bool live3DEnabled = settings && settings->Live3D();
            // 0.0.82 recovery: do not make character startup depend on asynchronous Scaleform page state.
            // RunActorUpdates can yield only one capture pass while the paused Pip-Boy is open; both 0.0.80 and
            // 0.0.81 consumed that pass before CurrentPage was ready and remained available:false forever.
            // Restore the field-proven 0.0.79 gate first. Page-specific visibility needs an event-driven main-
            // thread wakeup and must never again be allowed to block initial character construction.
            const bool wantShow = live3DEnabled && menuOpen;
            if (!wantShow) {
                if (g_available.load() || g_visible || g_previewRoot) { HideAndRelease(); }
                return;
            }

            auto* player = RE::PlayerCharacter::GetSingleton();
            if (!player) { HideAndRelease(); return; }

            // UI input only increments an atomic request count. Consume it here, on the same main-thread path
            // that owns the private behavior graph and renderer scene.
            const auto poseRequests = g_poseToggleRequests.exchange(0);
            for (std::uint32_t i = 0; i < poseRequests; ++i) {
                CharacterAnimation::ToggleReadySighted();
            }

            auto* source = player->Get3D(false);  // third-person root (carries worn armor + weapon)
            if (!source) { HideAndRelease(); return; }

            const auto& biped = player->GetBiped(false);
            const auto pendingEquipment = SnapshotPendingEquipmentEvents();
            std::uint64_t settledEquipmentSequence = 0;
            if (biped) {
                std::int32_t pendingSlot = -1;
                if (HasPendingBipedModelHandles(*biped, pendingSlot)) {
                    // Keep the last complete preview alive while the engine finishes the replacement. The
                    // render-boundary signature audit queues another pass, so this does not strand the update.
                    static std::int32_t s_lastPendingSlot = -1;
                    if (s_lastPendingSlot != pendingSlot) {
                        s_lastPendingSlot = pendingSlot;
                        logger::info("[PipOS][3D] deferred preview rebuild: biped slot {} is still loading", pendingSlot);
                    }
                    if (!pendingEquipment.events.empty()) {
                        g_equipmentCandidateSignature = 0;
                        g_equipmentCandidateSequence = 0;
                        g_equipmentQuietPasses = 0;
                        g_equipmentStablePasses = 0;
                    }
                    QueueCapturePass(a_delta);
                    return;
                }
            }

            // TESEquipEvent arrives before all participating biped clones are guaranteed to be published. Wait
            // for matching runtime ownership first, including ARMA-driven armor visuals that need not duplicate
            // every ARMO occupancy bit, then require 15 quiet render frames and three identical whole-biped
            // signatures. No timeout can convert a stable but incomplete outfit into a publishable preview.
            if (!pendingEquipment.events.empty()) {
                if (!biped) {
                    g_equipmentCandidateSignature = 0;
                    g_equipmentCandidateSequence = 0;
                    g_equipmentQuietPasses = 0;
                    g_equipmentStablePasses = 0;
                    QueueCapturePass(a_delta);
                    return;
                }
                PendingEquipmentEvent blockedEvent;
                std::int32_t blockedSlot = -1;
                const char* blockedReason = "requested equipment state is not reflected";
                if (!PendingEquipmentEventsReflected(
                        *biped, pendingEquipment, blockedEvent, blockedSlot, blockedReason)) {
                    g_equipmentCandidateSignature = 0;
                    g_equipmentCandidateSequence = 0;
                    g_equipmentQuietPasses = 0;
                    g_equipmentStablePasses = 0;
                    if (g_equipmentWaitLoggedSequence != pendingEquipment.lastSequence) {
                        g_equipmentWaitLoggedSequence = pendingEquipment.lastSequence;
                        logger::info(
                            "[PipOS][3D] equipment event waiting: seq={} type={} form={:08X} equipped={} slot={} reason='{}'",
                            blockedEvent.sequence,
                            PendingEquipmentKindName(blockedEvent.kind),
                            blockedEvent.formID,
                            blockedEvent.equipped,
                            blockedSlot,
                            blockedReason);
                    }
                    QueueCapturePass(a_delta);
                    return;
                }

                const bool newEquipmentCandidate =
                    g_equipmentCandidateSequence != pendingEquipment.lastSequence;
                if (newEquipmentCandidate) {
                    g_equipmentCandidateSequence = pendingEquipment.lastSequence;
                    g_equipmentCandidateSignature = 0;
                    g_equipmentQuietPasses = 0;
                    g_equipmentStablePasses = 0;
                }
                constexpr std::uint32_t kRequiredQuietEquipmentPasses = 15;
                if (g_equipmentReadyLoggedSequence != pendingEquipment.lastSequence) {
                    g_equipmentReadyLoggedSequence = pendingEquipment.lastSequence;
                    logger::info(
                        "[PipOS][3D] equipment ownership reflected through seq={}; waiting {} quiet render frames",
                        pendingEquipment.lastSequence,
                        kRequiredQuietEquipmentPasses);
                }
                // Actor, equipment, and UI wakeups can enqueue capture work more than once per rendered frame.
                // They may observe readiness, but only a task emitted by the outer render-boundary retry pump can
                // advance the quiet/stable evidence. This keeps all settle counts separated by engine rendering.
                // A boundary task queued before a newer event may observe that event only when it executes, so
                // the first observation establishes the candidate but never counts as its first quiet boundary.
                if (newEquipmentCandidate || !a_afterRenderBoundary) {
                    QueueCapturePass(a_delta);
                    return;
                }
                if (g_equipmentQuietPasses < kRequiredQuietEquipmentPasses) {
                    ++g_equipmentQuietPasses;
                    QueueCapturePass(a_delta);
                    return;
                }

                const auto signature = BuildBipedSignature(*biped);
                if (signature != g_equipmentCandidateSignature) {
                    g_equipmentCandidateSignature = signature;
                    g_equipmentStablePasses = 1;
                } else {
                    ++g_equipmentStablePasses;
                }
                constexpr std::uint32_t kRequiredStableEquipmentPasses = 3;
                if (g_equipmentStablePasses < kRequiredStableEquipmentPasses) {
                    QueueCapturePass(a_delta);
                    return;
                }
                settledEquipmentSequence = pendingEquipment.lastSequence;
                g_dirty.store(true);
                logger::info(
                    "[PipOS][3D] equipment state complete: throughSeq={} events={} signature={:016X} stablePasses={}; rebuilding preview",
                    settledEquipmentSequence,
                    pendingEquipment.events.size(),
                    signature,
                    g_equipmentStablePasses);
            }

            if (biped && g_previewRoot) {
                const auto currentSignature = BuildBipedSignature(*biped);
                if (currentSignature != g_sourceBipedSignature) {
                    if (!g_loggedTransientBipedPreview.exchange(true)) {
                        logger::info(
                            "[PipOS][3D] ignored transient Pip-Boy biped preview change; retaining the "
                            "menu-open equipped loadout");
                    }
                }
            }

            if (g_rendererRecreateRequested.exchange(false) && g_renderer) {
                // Interface3D stores FOV at construction. Recreate only the renderer, retaining the complete
                // preview tree and display mesh so the FOV slider remains live without a menu reopen.
                g_renderer->Offscreen_Set3D(nullptr);
                g_renderer->MainScreen_SetScreenAttached3D(nullptr);
                g_displayAttached = false;
                if (g_renderer->enabled) { g_renderer->Disable(); }
                g_renderer->Release();
                g_renderer = nullptr;
                g_visible = false;
                if (!ConfigureRenderer()) {
                    logger::error("[PipOS][3D] live FOV renderer recreation failed");
                    HideAndRelease();
                    return;
                }
                if (g_previewRoot && !AttachToRenderer(*g_previewRoot)) {
                    logger::error("[PipOS][3D] live FOV renderer recreation rejected the retained preview");
                    HideAndRelease();
                    return;
                }
                logger::info("[PipOS][3D] renderer recreated for live FOV={}", settings->Char3DFov());
            }

            // 0.0.72 VANILLA-FIRST: borrow the PipboyScreenModel offscreen slot (see AcquireVanillaRenderer
            // note). Our own renderer path below remains the fallback when the vanilla one can't be resolved
            // (i.e. until the user has inspected one item this Pip-Boy session -- Begin3D stand-up removed per
            // audit H3).
            if (auto* vr = kTF3DHUDCharacterPass ? nullptr : AcquireVanillaRenderer()) {
                // AUDIT H2: if the fallback path ran earlier this session, its renderer is still enabled with
                // its own offscreen 3D -- tear that down before borrowing, or both composite at once.
                if (g_renderer && (g_renderer->enabled || g_visible)) {
                    g_renderer->Offscreen_Set3D(nullptr);
                    g_renderer->Disable();
                    g_visible = false;
                    logger::info("[PipOS][3D] own renderer parked; handing off to the vanilla renderer");
                }
                if (!g_previewRoot || g_dirty || g_sourceRoot != source) {
                    auto clone = CloneSubtree(*source);
                    if (!clone) { logger::error("[PipOS][3D] player biped clone failed"); HideAndRelease(); return; }
                    SanitizeClone(*clone, source);
                    // AUDIT M1: the item preview's camera is SHORT-RANGE (items sit close); our default 200-unit
                    // distance is likely past its far plane. Cap the framing distance on this path; the in-game
                    // Camera-distance slider still applies below the cap.
                    FrameClone(*clone, 80.0f);
                    g_forceUpgradeTextures(clone.get(), false, false);
                    g_previewRoot = clone;
                    g_sourceRoot = source;
                    g_dirty = false;
                    logger::info("[PipOS][3D] preview built for the VANILLA renderer path");
                }
                auto* cur = vr->offscreenElement.get();
                if (cur == nullptr && g_previewRoot) {
                    vr->Offscreen_Set3D(g_previewRoot.get());
                    // 0.0.75 (agent-2 gap): TF3DHUD configures offscreen lights on EVERY attach; our vanilla
                    // path never lit the scene -- an unlit model over a transparent background is invisible.
                    // Same fixed fill the own-renderer path uses; cleared again when the slot is returned.
                    ConfigureThreePointLights(*vr);
                    if (!g_usingVanilla) { logger::info("[PipOS][3D] clone attached to vanilla renderer '{}' (enabled={}) + three-point lighting", vr->name.c_str(), vr->enabled); }
                    LogPoseProbe(*g_previewRoot);   // 0.0.75: decisive framing/pose telemetry (once per attach)
                    g_usingVanilla = true;
                }
                const bool slotIsOurs = g_previewRoot && vr->offscreenElement.get() == g_previewRoot.get();
                if (slotIsOurs) {
                    // AUDIT H1: the manager leaves the renderer DISABLED at idle -- a borrowed slot on a disabled
                    // renderer composites nothing. TRACKED SYMMETRIC ENABLE: we enable only while the slot holds
                    // OUR clone, remember that we did, and restore disabled state when handing the slot back
                    // (HideAndRelease). While a real item preview owns the slot we never touch enable state.
                    if (!vr->enabled) {
                        vr->Enable(false);
                        g_weEnabledVanilla = true;
                        logger::info("[PipOS][3D] vanilla renderer enabled for the character (will restore on close)");
                    }
                    RefreshLivePlacement();
                    const bool shouldDraw = ShouldDrawCharacter(*player);
                    g_previewRoot->SetAppCulled(!shouldDraw);
                    if (shouldDraw) {
                        CharacterAnimation::Update(
                            *player, *g_previewRoot, g_previewWeaponEquipped, a_delta);
                        ApplyTargetFollow(*g_previewRoot);
                        SyncPreviewFacialExpression(*player);
                    }
                    g_visible = true; // renderer ownership state; app-cull controls the power-armor option
                    g_available.store(shouldDraw && g_inventoryPageActive.load());
                    // AS hides Vault Boy only while our figure is actually on the Inventory page.
                } else {
                    // AUDIT M2: while yielding to a live item preview, do NOT report available (the AS side keeps
                    // the Vault Boy) and skip idle work on the detached clone.
                    static bool s_yieldLogged = false;
                    if (cur != nullptr && !s_yieldLogged) { s_yieldLogged = true; logger::info("[PipOS][3D] vanilla slot busy with an item preview; yielding until it clears"); }
                    g_visible = false;
                    g_available.store(false);
                }
                return;
            }

            if (!ConfigureRenderer() || !g_renderer) {
                logger::error("[PipOS][3D] renderer unavailable; disabling live 3D for this session");
                g_failed = true;
                HideAndRelease();
                return;
            }

            if (!g_previewRoot || g_dirty || g_sourceRoot != source) {
                const bool equipmentReplacement = settledEquipmentSequence != 0;
                if (!BuildPreview(*player, *source, !equipmentReplacement)) {
                    if (equipmentReplacement) {
                        // Keep both the previous complete preview and the event batch. Another three stable
                        // passes will retry construction; a failed candidate is never published or timed out.
                        g_dirty.store(false);
                        ResetEquipmentSettleCandidate();
                        logger::error(std::format(
                            "[PipOS][3D] equipment preview rebuild failed through seq={}; retaining previous preview and pending events",
                            settledEquipmentSequence));
                        QueueCapturePass(a_delta);
                        return;
                    }
                    HideAndRelease();
                    return;
                }
                g_dirty = false;
                if (equipmentReplacement) {
                    const bool moreEventsPending =
                        ClearPendingEquipmentEventsThrough(settledEquipmentSequence);
                    ResetEquipmentSettleCandidate();
                    logger::info(
                        "[PipOS][3D] equipment preview published through seq={}; newerEventsPending={}",
                        settledEquipmentSequence,
                        moreEventsPending);
                    if (moreEventsPending) { QueueCapturePass(a_delta); }
                }
            }

            if (g_previewRoot) { RefreshLivePlacement(); }

            // Re-apply the figure-slot window each pass (main-thread task). SameDisplayBounds makes an
            // unchanged window a no-op, so this only rebuilds the quad when (a) the initial build deferred it
            // because the buffers were still uploading, or (b) the user retuned a clipRect slider -- letting a
            // reopened Pip-Boy pick up new placement values without a game restart.
            if (g_displayRoot && !DisplayClipRectCopyPending()) { ApplyDisplayClipRect(); }
            AttachClippedDisplayRoot();

            if (!g_visible) {
                g_renderer->Enable(false);
                g_visible = true;
                logger::info("[PipOS][3D] offscreen renderer enabled");
            }
            const bool shouldDraw = ShouldDrawCharacter(*player);
            g_previewRoot->SetAppCulled(!shouldDraw);
            // Do not hide the fallback Vault Boy until the compositor surface is actually attached. On the first
            // menu open the fresh display mesh can still be uploading even though the character RT is ready.
            g_available.store(shouldDraw && g_inventoryPageActive.load() && g_displayAttached);
        }

        // 0.0.68 GROUND-TRUTH RENDERER DIFF. The red-RT test proved our fully-configured renderer NEVER
        // composites inside the Pip-Boy (no red block even at kStandard3DModel + alwaysRenderWhenEnabled),
        // while the VANILLA item preview provably composites in the same menu. Its Inventory3DManager names
        // its renderer (PipboyManager->inv3DModelManager.str3DRendererName); dump that live renderer's full
        // config next to ours ONCE each so the next log carries the exact working-vs-broken field diff --
        // no more hypothesis-driven probing. Main-thread only (called from RunCaptureTask).
        void DumpOneRenderer(const char* a_tag, RE::Interface3D::Renderer* a_r)
        {
            if (!a_r) { return; }
            logger::info(
                "[PipOS][3DDIAG] {}: name='{}' depth={} enabled={} offscr3D={} alwaysRender={} defRenderMain={} "
                "screenmode={} omsize={} postfx={} bgmode={} menuBlend={} postAA={} fullPremult={} usePremult={} "
                "clearRT={} hideWhenDisabled={} longRange={} enableAO={} geom='{}' mat='{}' maskGeom='{}' "
                "customRT={} customSwap={} opacity={} mainLights={} offLights={} offscreenElement={} screenRoot={} "
                "displayGeom={}",
                a_tag, a_r->name.c_str(),
                static_cast<int>(a_r->depth.get()), a_r->enabled, a_r->offscreen3DEnabled,
                a_r->alwaysRenderWhenEnabled, a_r->defRenderMainScreen,
                static_cast<int>(a_r->screenmode.get()), static_cast<int>(a_r->omsize.get()),
                static_cast<int>(a_r->postfx.get()), static_cast<int>(a_r->bgmode.get()),
                static_cast<int>(a_r->menuBlend.get()), a_r->postAA, a_r->useFullPremultAlpha,
                a_r->usePremultAlpha, a_r->clearRenderTarget, a_r->hideScreenWhenDisabled,
                a_r->useLongRangeCamera, a_r->enableAO,
                a_r->screenGeomName.c_str() ? a_r->screenGeomName.c_str() : "",
                a_r->screenMaterialName.c_str() ? a_r->screenMaterialName.c_str() : "",
                a_r->maskedGeomName.c_str() ? a_r->maskedGeomName.c_str() : "",
                a_r->customRenderTarget, a_r->customSwapTarget, a_r->opacityAlpha,
                a_r->mainLights.size(), a_r->offscreenLights.size(),
                a_r->offscreenElement != nullptr, a_r->screenAttachedElementRoot != nullptr,
                a_r->displayGeometry.size());
        }

        void DumpRendererDiag()
        {
            static bool s_oursDumped = false;
            static bool s_vanillaDumped = false;
            if (s_oursDumped && s_vanillaDumped) { return; }
            if (!s_oursDumped && g_renderer) {
                s_oursDumped = true;
                DumpOneRenderer("OURS(PipOS_Char3D)", g_renderer);
            }
            if (!s_vanillaDumped) {
                // The vanilla preview renderer exists only after the user selects an item (updateItem3D ->
                // Begin3D); keep checking until it appears, then dump once. NOTE the name itself is also gold.
                if (auto* pm = RE::PipboyManager::GetSingleton()) {
                    const auto& nm = pm->inv3DModelManager.str3DRendererName;
                    if (nm.c_str() && nm.c_str()[0] != '\0') {
                        if (auto* vr = RE::Interface3D::Renderer::GetByName(nm)) {
                            s_vanillaDumped = true;
                            logger::info("[PipOS][3DDIAG] vanilla item-preview renderer name='{}'", nm.c_str());
                            DumpOneRenderer("VANILLA(item-preview)", vr);
                        }
                    }
                }
            }
        }

        // MAIN-THREAD task body: the entire build/attach/idle/teardown pass. Scheduled from the hook via
        // AddTask; F4SE drains it serially on the game main thread. Re-pushes the AS3 contract whenever the
        // "clone is live" availability flips, so the AS3 side learns when the capture actually goes live.
        void RunCaptureTask(
            float a_delta, std::uint64_t a_sessionToken, bool a_afterRenderBoundary)
        {
            struct CaptureTaskExecutionScope
            {
                CaptureTaskExecutionScope()
                {
                    g_captureTaskRunning.store(true, std::memory_order_release);
                }

                ~CaptureTaskExecutionScope()
                {
                    g_taskInFlight.store(false, std::memory_order_release);
                    g_captureTaskRunning.store(false, std::memory_order_release);
                }
            } executionScope;

            // Keep the in-flight gate set through the complete delegate. QueueCapturePass detects this active
            // task and records a render-frame retry instead of appending another task to F4SE's current
            // while-not-empty drain. The scope clears both gates on every return path.
            if (g_failed.load()) { return; }

            const auto currentToken = g_menuSessionToken.load(std::memory_order_acquire);
            if (!g_pipboyOpen.load(std::memory_order_acquire) || currentToken != a_sessionToken) {
                logger::info(
                    "[PipOS][3D] skipped stale capture pass: taskToken={} currentToken={} open={}",
                    a_sessionToken,
                    currentToken,
                    g_pipboyOpen.load(std::memory_order_relaxed));
                return;
            }

            const bool wasAvailable = g_available.load();
            Tick(a_delta, a_afterRenderBoundary);
            if (g_available.load() != wasAvailable) {
                SchedulePushContract();  // clone went live / was released -> tell AS3 (available:true/false)
            }
            // 0.0.60: piggyback the equipment live-refresh on this main-thread pass (runs while the Pip-Boy is
            // open regardless of bLive3D -- Tick() early-outs but this line still fires). Rate-limited inside.
            // 0.0.68: right-click moved to the UI input-receiver vfunc hook (GetAsyncKeyState was blind to it).
            if (g_pipboyOpen.load()) { RepushEquipmentPeriodic(); ReadDropLog(); DumpRendererDiag(); }
        }

        // ------------------------------------------------------ TF3DHUD deferred character-render hook pair
        // kModMenu renders geometry through BSShaderUtil::RenderSceneDeferred. TF3DHUD proved that Interface3D's
        // offscreen pass must temporarily disable tiled lighting and clear bit 0x20 from the composite pass flags;
        // otherwise the shader selects a tiled variant whose t11/t12 light lists were never populated for this RT.
        bool IsOurOffscreenRender(RE::ShadowSceneNode* a_shadowSceneNode)
        {
            return g_renderer && a_shadowSceneNode && a_shadowSceneNode == g_renderer->offscreenSSN.get();
        }

        void HookedRenderSceneDeferred(
            RE::NiCamera* a_camera,
            RE::BSShaderAccumulator* a_accumulator,
            RE::BSCullingProcess* a_cullingProcess,
            RE::ShadowSceneNode* a_shadowSceneNode,
            std::int32_t a_target,
            std::int32_t a_depth,
            bool a_arg7,
            bool a_arg8)
        {
            if (!g_origRenderSceneDeferred) { return; }
            if (!IsOurOffscreenRender(a_shadowSceneNode)) {
                g_origRenderSceneDeferred(
                    a_camera, a_accumulator, a_cullingProcess, a_shadowSceneNode,
                    a_target, a_depth, a_arg7, a_arg8);
                return;
            }

            const bool oldTiledLighting = g_qTiledLighting();
            const bool oldDeferredFlag = g_inPipOSDeferredRender;
            g_inPipOSDeferredRender = true;
            g_setDoTiledLighting(false);
            if (!g_loggedDeferredHook.exchange(true)) {
                logger::info("[PipOS][3D] TF3DHUD deferred hook engaged for PipOS_Char3D");
            }
            g_origRenderSceneDeferred(
                a_camera, a_accumulator, a_cullingProcess, a_shadowSceneNode,
                a_target, a_depth, a_arg7, a_arg8);
            g_setDoTiledLighting(oldTiledLighting);
            g_inPipOSDeferredRender = oldDeferredFlag;
        }

        void HookedCompositePassCtor(
            void* a_renderPass,
            void* a_shader,
            void* a_property,
            void* a_geometry,
            std::uint32_t a_flags,
            std::uint8_t a_pass,
            void* a_lights)
        {
            if (!g_origBSRenderPassCtor) { return; }
            if (g_inPipOSDeferredRender && a_flags == 0x68) {
                a_flags = 0x48;
                if (!g_loggedCompositeHook.exchange(true)) {
                    logger::info("[PipOS][3D] TF3DHUD composite hook changed flags 0x68 -> 0x48");
                }
            }
            g_origBSRenderPassCtor(
                a_renderPass, a_shader, a_property, a_geometry, a_flags, a_pass, a_lights);
        }

        void HookedRenderPrepassesAndMenus(RE::Interface3D::Renderer* a_renderer)
        {
            ++g_renderHookDepth;
            {
                // Interface3D's original body performs deferred accumulation before it returns. Keep the scene
                // mutex for that complete interval, not merely for our pre-pass updates: otherwise the main-thread
                // close task can clear Offscreen_Set3D, release ModMenuRenderMesh, and drop the last NiPointer while
                // BSBatchRenderer worker tasks still hold raw geometry/pass pointers. The recursive mutex is needed
                // because this same thread can re-enter PIP-OS helpers during the original renderer call.
                std::scoped_lock renderLifetimeLock(g_sceneLock);
                if (a_renderer && g_pipboyOpen.load() && !g_failed.load()) {
                    // UI state is read only by a queued UI task. The renderer path consumes the resulting atomic,
                    // so character construction never waits for Scaleform's asynchronous CurrentPage property.
                    ScheduleInventoryPageProbe();
                    if (a_renderer == g_renderer && g_previewRoot &&
                        a_renderer->offscreenElement.get() == g_previewRoot.get()) {
                        // A paused Pip-Boy may not run the actor-update hook again after the first deferred clip
                        // attempt. Queue a main-thread retry from each render boundary until the display quad attaches.
                        if (!g_displayAttached) { QueueCapturePass(1.0f / 60.0f); }
                        RefreshLivePlacement();
                        if (auto* player = RE::PlayerCharacter::GetSingleton()) {
                            const auto visualSignature = BuildVisualSignature(*player);
                            if (visualSignature != g_sourceVisualSignature) {
                                g_dirty.store(true);
                                QueueCapturePass(1.0f / 60.0f);
                            }
                            const bool shouldDraw = ShouldDrawCharacter(*player);
                            g_previewRoot->SetAppCulled(!shouldDraw);
                            const bool renderAvailable = shouldDraw && g_inventoryPageActive.load() && g_displayAttached;
                            const bool wasAvailable = g_available.exchange(renderAvailable);
                            if (wasAvailable != renderAvailable) { SchedulePushContract(); }

                            const auto* timer = RE::BSTimer::GetSingleton();
                            if (shouldDraw) {
                                CharacterAnimation::Update(
                                    *player,
                                    *g_previewRoot,
                                    g_previewWeaponEquipped,
                                    timer ? timer->delta : (1.0f / 60.0f));
                                ApplyTargetFollow(*g_previewRoot);
                                SyncPreviewFacialExpression(*player);
                            }
                        }
                    }
                }

                if (g_origRenderPrepassesAndMenus) { g_origRenderPrepassesAndMenus(a_renderer); }
            }
            --g_renderHookDepth;

            // Convert a retry requested inside RunCaptureTask or while g_sceneLock was held into one future task
            // only after the renderer has advanced and released the scene. This avoids both same-drain reentry
            // and the F4SE-task-lock versus scene-lock inversion.
            if (g_renderHookDepth == 0 &&
                g_captureRetryRequested.exchange(false, std::memory_order_acq_rel) &&
                g_pipboyOpen.load(std::memory_order_acquire) && !g_failed.load(std::memory_order_acquire)) {
                QueueCapturePass(1.0f / 60.0f, true);
            }
        }

        std::uint32_t HookedProcessGraphEvent(
            RE::BSAnimationGraphManager* a_manager, const RE::BSFixedString& a_eventName)
        {
            const auto result = g_origProcessGraphEvent ? g_origProcessGraphEvent(a_manager, a_eventName) : 0;
            CharacterAnimation::ObserveGraphRequest(a_manager, a_eventName.c_str(), result);
            return result;
        }

        bool InstallTF3DHUDRenderHooks(REL::Trampoline& a_trampoline)
        {
            if constexpr (!kTF3DHUDCharacterPass) { return true; }

            REL::Relocation<std::uintptr_t> drawModel{ REL::ID(917134) };
            REL::Relocation<std::uintptr_t> renderSceneDeferred{ REL::ID(73644) };
            const auto deferredCall = drawModel.address() + 0x51A;
            const auto compositeCtorCall = renderSceneDeferred.address() + 0x158B;

            // Both sites are measured OG CALL rel32 instructions. Validate all bytes before changing either site
            // so a wrong executable cannot leave a half-installed render path.
            const auto deferredOpcode = *reinterpret_cast<const std::uint8_t*>(deferredCall);
            const auto compositeOpcode = *reinterpret_cast<const std::uint8_t*>(compositeCtorCall);
            if (deferredOpcode != 0xE8 || compositeOpcode != 0xE8) {
                logger::error(std::format(
                    "[PipOS][3D] TF3DHUD render hooks refused: expected E8 calls, got {:02X}/{:02X}",
                    deferredOpcode, compositeOpcode));
                return false;
            }

            g_origRenderSceneDeferred = reinterpret_cast<RenderSceneDeferred_t*>(
                a_trampoline.write_call<5>(deferredCall, &HookedRenderSceneDeferred));
            g_origBSRenderPassCtor = reinterpret_cast<BSRenderPassCtor_t*>(
                a_trampoline.write_call<5>(compositeCtorCall, &HookedCompositePassCtor));
            REL::Relocation<std::uintptr_t> renderPrepassesAndMenus{ REL::ID(1189309) };
            g_origRenderPrepassesAndMenus = CreateBranchGateway5<RenderPrepassesAndMenus_t*>(
                "Interface3D::Renderer::RenderPrepassesAndMenus", renderPrepassesAndMenus,
                reinterpret_cast<void*>(&HookedRenderPrepassesAndMenus));
            REL::Relocation<std::uintptr_t> processGraphEvent{ REL::ID(1199489) };
            g_origProcessGraphEvent = CreateBranchGateway5<ProcessGraphEvent_t*>(
                "BSAnimationGraphManager::ProcessGraphEvent", processGraphEvent,
                reinterpret_cast<void*>(&HookedProcessGraphEvent));
            logger::info(
                "[PipOS][3D] TF3DHUD deferred hooks installed @ REL::ID(917134)+0x51A and "
                "REL::ID(73644)+0x158B; graph hooks @ REL::ID(1189309)/REL::ID(1199489)");
            return g_origRenderSceneDeferred && g_origBSRenderPassCtor && g_origRenderPrepassesAndMenus &&
                g_origProcessGraphEvent;
        }

        void RequestVisualRebuild()
        {
            g_dirty.store(true);
            if (g_pipboyOpen.load()) { QueueCapturePass(1.0f / 60.0f); }
        }

        void HookedUpdate3DModel(RE::AIProcess* a_process, RE::Actor* a_actor, bool a_queued)
        {
            if (g_origUpdate3DModel) { g_origUpdate3DModel(a_process, a_actor, a_queued); }
            // Pip-Boy item inspection calls Update3DModel on the player after replacing biped slot 41 with the
            // selected list item's preview model. Treating that as equipment is what put a Cryolator-shaped model
            // into a 10mm ready pose. Real loadout changes have their own TESEquipEvent watcher below.
            if (a_actor && a_actor->IsPlayerRef() && !g_pipboyOpen.load()) { RequestVisualRebuild(); }
        }

        class EquipWatcher final : public RE::BSTEventSink<RE::TESEquipEvent>
        {
        public:
            RE::BSEventNotifyControl ProcessEvent(
                const RE::TESEquipEvent& a_event,
                RE::BSTEventSource<RE::TESEquipEvent>*) override
            {
                auto* player = RE::PlayerCharacter::GetSingleton();
                if (!player || a_event.actor.get() != player) { return RE::BSEventNotifyControl::kContinue; }
                auto* form = RE::TESForm::GetFormByID(a_event.baseObject);
                if (form && form->Is(RE::ENUM_FORM_ID::kWEAP)) {
                    EnqueuePendingEquipmentEvent(
                        a_event.baseObject,
                        0,
                        a_event.equipped,
                        PendingEquipmentKind::kWeapon);
                } else if (auto* armor = form ? form->As<RE::TESObjectARMO>() : nullptr) {
                    EnqueuePendingEquipmentEvent(
                        a_event.baseObject,
                        armor->bipedModelData.bipedObjectSlots,
                        a_event.equipped,
                        PendingEquipmentKind::kArmor);
                }
                return RE::BSEventNotifyControl::kContinue;
            }
        };

        void RegisterEquipWatcher()
        {
            static EquipWatcher watcher;
            if (auto* source = g_equipEventSource.get()) {
                source->RegisterSink(std::addressof(watcher));
                logger::info("[PipOS][3D] equipment event watcher registered");
            } else {
                logger::info("[PipOS][3D] equipment event watcher unavailable");
            }
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

            QueueCapturePass(a_delta);
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

        void ScheduleInventoryPageProbe()
        {
            const auto sessionToken = g_menuSessionToken.load(std::memory_order_acquire);
            bool expected = false;
            if (!g_pageProbeInFlight.compare_exchange_strong(expected, true)) { return; }
            auto* task = F4SE::GetTaskInterface();
            if (!task) { g_pageProbeInFlight.store(false); return; }
            task->AddUITask([sessionToken]() {
                g_pageProbeInFlight.store(false);
                if (!g_pipboyOpen.load(std::memory_order_acquire) ||
                    g_menuSessionToken.load(std::memory_order_acquire) != sessionToken) {
                    return;
                }
                auto* ui = RE::UI::GetSingleton();
                auto menu = ui ? ui->GetMenu(RE::BSFixedString(kPipboyMenu.data())) : nullptr;
                auto* view = menu ? menu->uiMovie.get() : nullptr;
                if (!view) { return; }

                bool inventory = false;
                const char* source = nullptr;
                double pageNumber = -1.0;

                // The custom Inventory page publishes its real ADDED_TO_STAGE / REMOVED_FROM_STAGE lifecycle on
                // root1. This is authoritative: the stock shell's DataObj is private/unreadable on this setup.
                Scaleform::GFx::Value explicitPage;
                if (view->GetVariable(
                        std::addressof(explicitPage), "root1.PipOS_inventoryPageActive") &&
                    explicitPage.IsBoolean()) {
                    inventory = explicitPage.GetBoolean();
                    source = "inventory-page-lifecycle";
                } else {
                    Scaleform::GFx::Value page;
                    if (!view->GetVariable(std::addressof(page), "root1.Menu_mc.DataObj.CurrentPage") ||
                        !page.IsNumber()) {
                        return;
                    }
                    pageNumber = page.GetNumber();
                    inventory = static_cast<std::int32_t>(pageNumber) == 1;
                    source = "shell-dataobj";
                }

                Scaleform::GFx::Value hoverValue;
                const bool hovered = view->GetVariable(
                    std::addressof(hoverValue), "root1.PipOS_charHover") && hoverValue.IsBoolean() &&
                    hoverValue.GetBoolean();
                g_characterHovered.store(inventory && hovered);

                Scaleform::GFx::Value yawValue;
                if (view->GetVariable(std::addressof(yawValue), "root1.PipOS_charYawOffset") &&
                    yawValue.IsNumber()) {
                    const float newYaw = std::clamp(static_cast<float>(yawValue.GetNumber()), -720.0f, 720.0f);
                    const float oldYaw = g_sessionYawOffset.exchange(newYaw);
                    if (oldYaw != newYaw) { QueueCapturePass(1.0f / 60.0f); }
                }
                const bool previous = g_inventoryPageActive.exchange(inventory);
                if (previous != inventory) {
                    logger::info("[PipOS][3D] page visibility changed: source={} CurrentPage={} inventory={}",
                        source, pageNumber, inventory);
                    QueueCapturePass(1.0f / 60.0f);
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
                        g_menuSessionToken.fetch_add(1, std::memory_order_acq_rel);
                        g_pipboyOpen.store(true);
                        g_loggedTransientBipedPreview.store(false);
                        // Page state can be asynchronous, but it no longer gates preview construction. Start the
                        // live model offscreen until Scaleform positively identifies Inventory, avoiding a flash
                        // of the character when PIP-OS opens on STATUS, DATA, MAP, or RADIO.
                        g_inventoryPageActive.store(false);
                        g_characterHovered.store(false);
                        g_sessionYawOffset.store(0.0f);
                        g_poseToggleRequests.store(0);
                        g_captureRetryRequested.store(false, std::memory_order_release);
                        g_captureTaskReentryLogged.store(false, std::memory_order_release);
                        // Preserve equipment events that occurred after the prior close. They describe the live
                        // gameplay transition that this open may be interrupting, and their exact-form gate keeps
                        // an open-mid-equip snapshot from publishing before the requested biped state is complete.
                        // The prior menu session's events were already cleared synchronously on its close.
                        ResetEquipmentSettleCandidate();
                        CharacterAnimation::ResetSessionPose();
                        g_dirty.store(true);  // rebuild with the equipment worn at this open
                        // Initial push (available:false until the clone actually builds in RunCaptureTask,
                        // which re-pushes available:true on the transition). Keeps absent-member -> fallback.
                        SchedulePushContract();
                        ScheduleInventoryPageProbe();
                    } else {
                        const auto closeToken = g_menuSessionToken.fetch_add(1, std::memory_order_acq_rel) + 1;
                        g_pipboyOpen.store(false);
                        g_inventoryPageActive.store(false);
                        g_characterHovered.store(false);
                        g_sessionYawOffset.store(0.0f);
                        g_poseToggleRequests.store(0);
                        g_captureRetryRequested.store(false, std::memory_order_release);
                        // Cancel every rebuild intent before the queued teardown. A capture task already queued
                        // by the old session is generation-guarded above; these clears prevent a later reopen
                        // from inheriting an obsolete FOV or equipment request.
                        g_rendererRecreateRequested.store(false);
                        ClearPendingEquipmentEvents();
                        ResetEquipmentSettleCandidate();
                        g_dirty.store(false);
                        CharacterAnimation::ResetSessionPose();
                        // Teardown must be single-threaded like the build: run HideAndRelease on the main
                        // thread via AddTask (renderer Disable / Offscreen_Set3D(nullptr) / NiPointer release
                        // are all D3D/scene lifecycle). Then re-push the contract (now available:false).
                        if (auto* task = F4SE::GetTaskInterface()) {
                            task->AddTask([closeToken]() {
                                // A new open can be delivered before F4SE drains this task. In that case all
                                // scene state now belongs to the newer session and this close is stale.
                                if (g_pipboyOpen.load(std::memory_order_acquire) ||
                                    g_menuSessionToken.load(std::memory_order_acquire) != closeToken) {
                                    logger::info(
                                        "[PipOS][3D] skipped stale menu-close teardown: closeToken={} currentToken={} open={}",
                                        closeToken,
                                        g_menuSessionToken.load(std::memory_order_relaxed),
                                        g_pipboyOpen.load(std::memory_order_relaxed));
                                    return;
                                }
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
        F4SE::AllocTrampoline(512);  // frame/call-site hooks plus render/update branch gateways and islands.
#pragma warning(pop)
        auto& trampoline = REL::GetTrampoline();

        if (!InstallTF3DHUDRenderHooks(trampoline)) {
            logger::error("[PipOS][3D] TF3DHUD character pass disabled because its render hooks were not safe to install");
            g_failed.store(true);
            return false;
        }

        REL::Relocation<std::uintptr_t> update3DModel{ REL::ID(986782) };
        g_origUpdate3DModel = CreateBranchGateway5<Update3DModel_t*>(
            "AIProcess::Update3DModel", update3DModel,
            reinterpret_cast<void*>(&HookedUpdate3DModel));
        if (!g_origUpdate3DModel) {
            logger::error("[PipOS][3D] Update3DModel hook could not be installed safely");
            g_failed.store(true);
            return false;
        }

        // RunActorUpdates call site (OG 1.10.163): REL::ID(556439)+0x17 -- the same frame hook Full Body
        // Awareness uses with this fork; write_call<5> is battle-tested here (no hand-rolled branch gateway).
        REL::Relocation<std::uintptr_t> call{ REL::ID(556439) };
        const auto target = call.address() + 0x17;
        g_origRunActorUpdates = reinterpret_cast<RunActorUpdates_t*>(
            trampoline.write_call<5>(target, &HookedRunActorUpdates));
        logger::info("[PipOS][3D] RunActorUpdates frame hook installed @ REL::ID(556439)+0x17 (target {:X})",
            target);

        RegisterContractSink();
        RegisterEquipWatcher();
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

    bool CharacterCapture::TryHandleCharacterRightClick()
    {
        if (!g_pipboyOpen.load() || !g_inventoryPageActive.load() || !g_characterHovered.load()) {
            return false;
        }
        g_poseToggleRequests.fetch_add(1);
        QueueCapturePass(1.0f / 60.0f);
        logger::info("[PipOS][3D] character right-click accepted; queued Ready/Sighted session toggle");
        return true;
    }
}
