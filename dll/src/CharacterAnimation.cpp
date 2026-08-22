#include "PCH.h"
#include "CharacterAnimation.h"
#include "RE_Animation.h"
#include "Settings.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>

namespace PipOS::CharacterAnimation
{
    namespace
    {
        // -1 uses the persisted Menu Framework choice. Ready (0) and Sighted (1) are menu-session overrides.
        std::atomic<int> g_sessionIdleState{ -1 };

        constexpr std::size_t kGraphSize = 0x3D0;
        constexpr std::size_t kGraphAlignment = 0x10;

        bool g_privateWeaponBridgeLogged{ false };
        bool g_privateWeaponBridgeFailureLogged{ false };

        using Holder = RE::IAnimationGraphManagerHolder;
        using Graph = RE::BShkbAnimationGraph;
        using Manager = RE::BSAnimationGraphManager;
        using SubgraphArena = RE::BSTObjectArena<RE::BSFixedString, RE::BSTObjectArenaScrapAlloc, 32>;

        struct PrivateWeaponBridgeResult
        {
            RE::NiNode* wrapper{ nullptr };
            RE::NiNode* hand{ nullptr };
            RE::BSFlattenedBoneTree::FlattenedBone* weaponBone{ nullptr };
            RE::BSFlattenedBoneTree::FlattenedBone* handBone{ nullptr };
            RE::NiTransform wrapperBefore{};
            bool copiedGraphLocal{ false };
        };

        void ForEachPreviewObject(
            RE::NiAVObject* a_object,
            const std::function<void(RE::NiAVObject&)>& a_visitor)
        {
            if (!a_object) { return; }
            a_visitor(*a_object);
            if (auto* node = a_object->IsNode()) {
                for (auto& child : node->children) {
                    if (child) { ForEachPreviewObject(child.get(), a_visitor); }
                }
            }
        }

        RE::BSFlattenedBoneTree* FindPreviewFlattenedBoneTree(RE::NiAVObject* a_root)
        {
            if (!a_root) { return nullptr; }
            if (auto* flattened = netimmerse_cast<RE::BSFlattenedBoneTree*>(a_root)) { return flattened; }
            auto* node = a_root->IsNode();
            if (!node) { return nullptr; }
            for (auto& child : node->children) {
                if (child) {
                    if (auto* flattened = FindPreviewFlattenedBoneTree(child.get())) { return flattened; }
                }
            }
            return nullptr;
        }

        RE::BSFlattenedBoneTree::FlattenedBone* FindPreviewFlattenedBone(
            RE::BSFlattenedBoneTree& a_tree,
            const std::string_view a_name)
        {
            if (!a_tree.bone || a_tree.boneCount <= 0 || a_tree.boneCount > 1024) { return nullptr; }
            for (std::int32_t index = 0; index < a_tree.boneCount; ++index) {
                auto& bone = a_tree.bone[index];
                const char* name = bone.name.c_str();
                if (name && a_name == name) { return std::addressof(bone); }
            }
            return nullptr;
        }

        RE::NiNode* FindDirectPreviewChild(RE::NiNode& a_parent, const std::string_view a_name)
        {
            for (auto& child : a_parent.children) {
                if (!child) { continue; }
                const char* name = child->GetName().c_str();
                if (name && a_name == name) { return child->IsNode(); }
            }
            return nullptr;
        }

        bool IsFinitePrivateTransform(const RE::NiTransform& a_transform)
        {
            float pitch = 0.0f;
            float roll = 0.0f;
            float yaw = 0.0f;
            a_transform.rotate.ToEulerAnglesXYZ(pitch, roll, yaw);
            return std::isfinite(a_transform.translate.x) &&
                std::isfinite(a_transform.translate.y) &&
                std::isfinite(a_transform.translate.z) &&
                std::isfinite(a_transform.scale) && a_transform.scale > 0.0001f &&
                std::isfinite(pitch) && std::isfinite(roll) && std::isfinite(yaw);
        }

        void LogPrivateWeaponBridgeFailure(const std::string_view a_reason)
        {
            if (g_privateWeaponBridgeFailureLogged) { return; }
            g_privateWeaponBridgeFailureLogged = true;
            logger::error(std::format("[PipOS][3D][ANIM] private Weapon bridge unavailable: {}", a_reason));
        }

        PrivateWeaponBridgeResult ApplyPrivateWeaponTransformBridge(RE::NiAVObject& a_previewRoot)
        {
            PrivateWeaponBridgeResult result;
            auto* flattened = FindPreviewFlattenedBoneTree(std::addressof(a_previewRoot));
            if (!flattened) {
                LogPrivateWeaponBridgeFailure("preview flattened skeleton is missing");
                return result;
            }

            result.weaponBone = FindPreviewFlattenedBone(*flattened, "Weapon");
            if (!result.weaponBone) {
                LogPrivateWeaponBridgeFailure("flattened Weapon bone is missing");
                return result;
            }
            if (result.weaponBone->parent < 0 || result.weaponBone->parent >= flattened->boneCount) {
                LogPrivateWeaponBridgeFailure("flattened Weapon parent index is invalid");
                return result;
            }
            result.handBone = std::addressof(flattened->bone[result.weaponBone->parent]);
            const char* handBoneName = result.handBone->name.c_str();
            if (!handBoneName || std::string_view(handBoneName) != "RArm_Hand") {
                LogPrivateWeaponBridgeFailure("flattened Weapon parent is not RArm_Hand");
                return result;
            }

            result.hand = result.handBone->node ? result.handBone->node->IsNode() : nullptr;
            if (!result.hand) {
                auto* handObject = a_previewRoot.GetObjectByName(RE::BSFixedString("RArm_Hand"));
                result.hand = handObject ? handObject->IsNode() : nullptr;
            }
            if (!result.hand) {
                LogPrivateWeaponBridgeFailure("ordinary RArm_Hand node is missing");
                return result;
            }

            result.wrapper = FindDirectPreviewChild(*result.hand, "Weapon");
            if (!result.wrapper) {
                LogPrivateWeaponBridgeFailure("ordinary Weapon wrapper beneath RArm_Hand is missing");
                return result;
            }
            if (result.weaponBone->node && result.weaponBone->node.get() != result.wrapper) {
                LogPrivateWeaponBridgeFailure("flattened Weapon node points to a different object");
                result.wrapper = nullptr;
                return result;
            }
            if (!IsFinitePrivateTransform(result.weaponBone->local)) {
                LogPrivateWeaponBridgeFailure("private graph produced a non-finite Weapon local");
                result.wrapper = nullptr;
                return result;
            }

            result.wrapperBefore = result.wrapper->GetLocalTransform();
            // Both transforms are relative to RArm_Hand, so publish only the graph-owned local to the ordinary
            // wrapper. This assignment is also idempotent if a future skeleton maps the flattened bone directly
            // to the same wrapper. The complete weapon clone remains an unchanged child beneath this wrapper.
            result.wrapper->SetLocalTransform(result.weaponBone->local);
            result.copiedGraphLocal = true;
            return result;
        }

        void LogPrivateWeaponBridgeAudit(const PrivateWeaponBridgeResult& a_result)
        {
            if (g_privateWeaponBridgeLogged || !a_result.wrapper || !a_result.hand ||
                !a_result.weaponBone || !a_result.handBone) {
                return;
            }
            g_privateWeaponBridgeLogged = true;

            std::uint32_t objectCount = 0;
            std::uint32_t geometryCount = 0;
            std::uint32_t culledObjectCount = 0;
            std::uint32_t culledGeometryCount = 0;
            std::uint32_t zeroFadeCount = 0;
            std::uint32_t transparentShaderCount = 0;
            ForEachPreviewObject(a_result.wrapper, [&](RE::NiAVObject& a_object) {
                ++objectCount;
                if (a_object.GetAppCulled()) { ++culledObjectCount; }
                if (a_object.fadeAmount <= 0.0f) { ++zeroFadeCount; }
                auto* geometry = a_object.IsGeometry();
                if (!geometry) { return; }
                ++geometryCount;
                if (geometry->GetAppCulled()) { ++culledGeometryCount; }
                for (auto& property : geometry->properties) {
                    if (auto* shader = netimmerse_cast<RE::BSShaderProperty*>(property.get());
                        shader && shader->alpha <= 0.0f) {
                        ++transparentShaderCount;
                    }
                }
            });

            const auto wrapperAfter = a_result.wrapper->GetLocalTransform();
            float beforePitch = 0.0f;
            float beforeRoll = 0.0f;
            float beforeYaw = 0.0f;
            float graphPitch = 0.0f;
            float graphRoll = 0.0f;
            float graphYaw = 0.0f;
            a_result.wrapperBefore.rotate.ToEulerAnglesXYZ(beforePitch, beforeRoll, beforeYaw);
            a_result.weaponBone->local.rotate.ToEulerAnglesXYZ(graphPitch, graphRoll, graphYaw);
            constexpr float kRadiansToDegrees = 57.2957795f;
            logger::info(
                "[PipOS][3D][ANIM] private Weapon bridge active: flattenedNode={} handNodeMatches={} copiedGraphLocal={} before=({:.2f},{:.2f},{:.2f}; {:.1f},{:.1f},{:.1f}; s={:.3f}) graphLocal=({:.2f},{:.2f},{:.2f}; {:.1f},{:.1f},{:.1f}; s={:.3f}) after=({:.2f},{:.2f},{:.2f})",
                a_result.weaponBone->node != nullptr,
                a_result.handBone->node.get() == a_result.hand,
                a_result.copiedGraphLocal,
                a_result.wrapperBefore.translate.x,
                a_result.wrapperBefore.translate.y,
                a_result.wrapperBefore.translate.z,
                beforePitch * kRadiansToDegrees,
                beforeRoll * kRadiansToDegrees,
                beforeYaw * kRadiansToDegrees,
                a_result.wrapperBefore.scale,
                a_result.weaponBone->local.translate.x,
                a_result.weaponBone->local.translate.y,
                a_result.weaponBone->local.translate.z,
                graphPitch * kRadiansToDegrees,
                graphRoll * kRadiansToDegrees,
                graphYaw * kRadiansToDegrees,
                a_result.weaponBone->local.scale,
                wrapperAfter.translate.x,
                wrapperAfter.translate.y,
                wrapperAfter.translate.z);

            const auto& wrapperWorld = a_result.wrapper->GetWorldTransform();
            const auto& handWorld = a_result.hand->GetWorldTransform();
            auto* settings = Settings::GetSingleton();
            logger::info(
                "[PipOS][3D][ANIM] private Weapon draw audit: objects={} geometries={} culledObjects={} culledGeometries={} zeroFade={} transparentShaders={} wrapperCulled={} hideSetting={} sheatheSetting={} graphHandWorld=({:.2f},{:.2f},{:.2f}) ordinaryHandWorld=({:.2f},{:.2f},{:.2f}) graphWeaponWorld=({:.2f},{:.2f},{:.2f}) wrapperWorld=({:.2f},{:.2f},{:.2f}) bound=({:.2f},{:.2f},{:.2f}; r={:.2f})",
                objectCount,
                geometryCount,
                culledObjectCount,
                culledGeometryCount,
                zeroFadeCount,
                transparentShaderCount,
                a_result.wrapper->GetAppCulled(),
                settings ? settings->Char3DHideWeaponIdle() : false,
                settings ? settings->Char3DSheatheWeaponIdle() : false,
                a_result.handBone->world.translate.x,
                a_result.handBone->world.translate.y,
                a_result.handBone->world.translate.z,
                handWorld.translate.x,
                handWorld.translate.y,
                handWorld.translate.z,
                a_result.weaponBone->world.translate.x,
                a_result.weaponBone->world.translate.y,
                a_result.weaponBone->world.translate.z,
                wrapperWorld.translate.x,
                wrapperWorld.translate.y,
                wrapperWorld.translate.z,
                a_result.wrapper->worldBound.center.x,
                a_result.wrapper->worldBound.center.y,
                a_result.wrapper->worldBound.center.z,
                a_result.wrapper->worldBound.fRadius);
        }

        struct HkbBehaviorGraphDiagnostic
        {
            std::byte pad000[0x1AA];
            bool isActive;
        };
        static_assert(offsetof(HkbBehaviorGraphDiagnostic, isActive) == 0x1AA);

        REL::Relocation<const char* (*)(RE::Actor*, RE::NiAVObject*)> g_getProjectForActor{ REL::ID(804224) };
        REL::Relocation<bool (*)(Holder*, const char*)> g_createManager{ REL::ID(532453) };
        REL::Relocation<Graph* (*)(Graph*, RE::Actor*, bool)> g_constructGraph{ REL::ID(1074981) };
        REL::Relocation<bool (*)(Holder*, RE::NiAVObject*, bool)> g_setTarget{ REL::ID(1340816) };
        REL::Relocation<bool (*)(Manager*)> g_activateManager{ REL::ID(950096) };
        REL::Relocation<bool (*)(Holder*, float)> g_updateManager{ REL::ID(973903) };
        REL::Relocation<bool (*)(Holder*, const RE::BSFixedString&)> g_notifyGraph{ REL::ID(1379025) };
        REL::Relocation<void (*)(Holder*, const RE::BSTSmartPointer<Manager>&)> g_actorPreUpdate{ REL::ID(442032) };
        REL::Relocation<void (*)(Holder*, const RE::BSTSmartPointer<Manager>&)> g_actorPreLoad{ REL::ID(1053762) };
        REL::Relocation<void (*)(Holder*, const RE::BSTSmartPointer<Manager>&)> g_actorPostLoad{ REL::ID(348865) };
        REL::Relocation<std::int32_t (*)(RE::TES*, RE::TESObjectCELL*, void*)> g_getCellPriority{ REL::ID(665767) };
        REL::Relocation<bool (*)(
            const RE::TESRace&, const RE::TESObjectREFR&, const RE::SubgraphIdentifier&, RE::SEX, bool,
            SubgraphArena&)> g_gatherPreload{ REL::ID(1492580) };
        REL::Relocation<bool (*)(
            void*, std::uint32_t, const RE::SubgraphIdentifier*, RE::BSFixedString*, SubgraphArena*)>
            g_retrieveSubgraph{ REL::ID(1291992) };
        REL::Relocation<bool (*)(
            void*, Graph*, const RE::BSFixedString*, SubgraphArena*, SubgraphArena*, const std::int32_t*,
            RE::SubgraphHandle*)> g_initializeSubgraph{ REL::ID(649876) };
        REL::Relocation<std::uint32_t (*)(
            void*, Graph*, const RE::SubgraphHandle*, const std::int32_t*)> g_isSubgraphLoaded{ REL::ID(10120) };
        REL::Relocation<RE::SEX (*)(const RE::Actor*)> g_getAnimationSex{ REL::ID(511244) };
        REL::Relocation<void**> g_subgraphDataSingleton{ REL::ID(1363506) };
        REL::Relocation<void**> g_graphSwapSingleton{ REL::ID(153510) };

        constexpr auto kSuppressedChannels = std::to_array<std::string_view>({
            "Speed", "Direction", "DirectionSmoothed", "Pitch", "Roll", "TurnDelta", "PitchDelta",
            "PitchDeltaSmoothed", "TurnDeltaSmoothed", "DirectionDegrees", "fControllerXSum", "fControllerYSum",
            "bEquipOk", "iSyncReadyAlertRelaxed", "iSyncWeaponDrawState"
        });
        constexpr auto kPreviewNeutralBoolVariables = std::to_array<std::string_view>({
            "bAimActive", "bAimEnabled", "bAimCaptureEnabled", "bShouldAimHeadTrack", "bSyncDirection",
            "m_bEnablePitchTwistModifier"
        });
        constexpr auto kPreviewEnabledBoolVariables = std::to_array<std::string_view>({
            "DisableCharacterPitch", "bFreezeRotationUpdate"
        });
        constexpr auto kPreviewNeutralIntVariables = std::to_array<std::string_view>({ "iSyncRunDirection" });
        constexpr auto kPreviewReadyIntVariables = std::to_array<std::string_view>({ "iSyncTurnState" });
        constexpr auto kPreviewNeutralFloatVariables = std::to_array<std::string_view>({
            "AimHeadingCurrent", "AimPitchCurrent", "BowAimOffsetHeading", "BowAimOffsetPitch", "CamPitch",
            "CamPitchDamped", "Direction", "DirectionDamped", "DirectionDegrees", "DirectionSmoothed",
            "PitchDelta", "PitchDeltaDamped", "PitchDeltaSmoothed", "PitchDeltaSmoothedDamped", "PitchOffset",
            "TurnDelta", "TurnDeltaDamped", "TurnDeltaSmoothed", "TurnDeltaSmoothedDamped",
            "TurnDeltaSpeedLimitedDampened", "fControllerXSum", "fControllerYSum", "speedDamped", "pitch"
        });
        constexpr auto kIntVariables = std::to_array<std::string_view>({
            "iSyncWeaponDrawState", "iSyncSightedState", "iSyncGunDown", "iSyncChargeState",
            "iWeaponChargeMode", "iAttackState", "iSyncJumpState", "iIsInSneak", "iSyncReadyAlertRelaxed"
        });
        constexpr auto kBoolVariables = std::to_array<std::string_view>({
            "isAttacking", "IsAttackReady", "isAttackNotReady", "bEquipOk", "isJumping",
            "bInJumpState", "IsSneaking", "bIsSneaking", "isReloading"
        });
        constexpr auto kFloatVariables = std::to_array<std::string_view>({
            "weaponSpeedMult", "reloadSpeedMult", "sightedSpeedMult"
        });
        constexpr auto kMirroredEvents = std::to_array<std::string_view>({
            "sneakStart", "sneakStop", "sneakStateEnter", "sneakStateExit",
            "jumpStart", "jumpStartFromWalk", "jumpFall", "jumpLand", "jumpLandSoft", "jumpLandToWalk",
            "jumpLandToRun", "jumpEnd", "jumpEndToRun", "attackStart", "attackStartAuto", "attackRelease",
            "attackStop", "attackStateEnter", "attackStateExit", "attackInterrupt", "AttackEnd",
            "reloadStart", "reloadStateEnter", "reloadStateExit", "reloadReserveStart", "meleeattackStart",
            "meleeattackSprintStart", "meleeAttackGun", "blockStart", "grenadeThrowStart", "mineThrowStart",
            "SyncLeft", "SyncRight", "SyncCycleEnd"
        });

        template <std::size_t N>
        bool Contains(const RE::BSFixedString& a_value, const std::array<std::string_view, N>& a_values)
        {
            return std::any_of(a_values.begin(), a_values.end(), [&](auto a_candidate) {
                return a_value == a_candidate;
            });
        }

        [[nodiscard]] bool MirroredEventEnabled(std::string_view a_event)
        {
            auto* settings = Settings::GetSingleton();
            if (!settings) { return true; }
            std::string lower(a_event);
            std::ranges::transform(lower, lower.begin(), [](unsigned char c) {
                return static_cast<char>(std::tolower(c));
            });
            if (lower.find("sneak") != std::string::npos) { return settings->Char3DMirrorSneak(); }
            if (lower.find("jump") != std::string::npos || lower.find("land") != std::string::npos) {
                return settings->Char3DMirrorJump();
            }
            if (lower.find("reload") != std::string::npos) { return settings->Char3DMirrorWeaponReload(); }
            if (lower.find("melee") != std::string::npos || lower.find("block") != std::string::npos) {
                return settings->Char3DMirrorMelee();
            }
            if (lower.find("grenade") != std::string::npos || lower.find("mine") != std::string::npos ||
                lower.find("throw") != std::string::npos) {
                return settings->Char3DMirrorThrowable();
            }
            if (lower.find("attack") != std::string::npos) { return settings->Char3DMirrorWeaponFire(); }
            return true; // remaining private-graph synchronization events
        }

        class PreviewHolder final : public Holder
        {
        public:
            PreviewHolder(
                RE::PlayerCharacter& a_player,
                RE::NiAVObject& a_target,
                const bool a_weaponEquipped) :
                sourceActor_(std::addressof(a_player)),
                sourceHolder_(static_cast<Holder*>(std::addressof(a_player))),
                target_(std::addressof(a_target)),
                weaponEquipped_(a_weaponEquipped)
            {}

            ~PreviewHolder() override { manager_.reset(); }

            bool NotifyAnimationGraphImpl(const RE::BSFixedString& a_event) override
            {
                return g_notifyGraph(this, a_event);
            }

            bool GetAnimationGraphManagerImpl(RE::BSTSmartPointer<Manager>& a_out) const override
            {
                a_out = manager_;
                return static_cast<bool>(a_out);
            }

            bool SetAnimationGraphManagerImpl(const RE::BSTSmartPointer<Manager>& a_manager) override
            {
                manager_ = a_manager;
                return true;
            }

            bool PopulateGraphNodesToTarget(RE::BSScrapArray<RE::NiAVObject*>& a_nodes) const override
            {
                if (!target_) { return false; }
                a_nodes.push_back(target_);
                return true;
            }

            bool ConstructAnimationGraph(RE::BSTSmartPointer<Graph>& a_out) override
            {
                if (!sourceActor_) { return false; }
                auto* memory = static_cast<Graph*>(RE::aligned_alloc(kGraphAlignment, kGraphSize));
                if (!memory) { return false; }
                auto* graph = g_constructGraph(memory, sourceActor_, false);
                if (!graph) {
                    RE::aligned_free(memory);
                    return false;
                }
                a_out.reset(graph);
                return true;
            }

            bool InitializeAnimationGraphVariables(const RE::BSTSmartPointer<Graph>& a_graph) const override
            {
                return sourceHolder_ && sourceHolder_->InitializeAnimationGraphVariables(a_graph);
            }

            bool SetupAnimEventSinks(const RE::BSTSmartPointer<Graph>&) override
            {
                // The isolated preview must not register the actor's movement or transform event sinks.
                return true;
            }

            bool CreateAnimationChannels(
                RE::BSScrapArray<RE::BSTSmartPointer<RE::BSAnimationGraphChannel>>& a_channels) override
            {
                if (!sourceHolder_) { return false; }
                RE::BSScrapArray<RE::BSTSmartPointer<RE::BSAnimationGraphChannel>> sourceChannels;
                if (!sourceHolder_->CreateAnimationChannels(sourceChannels)) { return false; }
                for (const auto& channel : sourceChannels) {
                    if (channel && !Contains(channel->variableName, kSuppressedChannels)) {
                        a_channels.push_back(channel);
                    }
                }
                return true;
            }

            bool ShouldUpdateAnimation() override { return true; }
            std::uint32_t GetGraphVariableCacheSize() const override
            {
                return sourceHolder_ ? sourceHolder_->GetGraphVariableCacheSize() : 0;
            }
            bool GetGraphVariableImpl(std::uint32_t a_id, float& a_out) const override
            {
                return sourceHolder_ && sourceHolder_->GetGraphVariableImpl(a_id, a_out);
            }
            bool GetGraphVariableImpl(std::uint32_t a_id, bool& a_out) const override
            {
                return sourceHolder_ && sourceHolder_->GetGraphVariableImpl(a_id, a_out);
            }
            bool GetGraphVariableImpl(std::uint32_t a_id, std::int32_t& a_out) const override
            {
                return sourceHolder_ && sourceHolder_->GetGraphVariableImpl(a_id, a_out);
            }
            bool GetGraphVariableImplFloat(const RE::BSFixedString& a_name, float& a_out) const override
            {
                return sourceHolder_ && sourceHolder_->GetGraphVariableImplFloat(a_name, a_out);
            }
            bool GetGraphVariableImplInt(const RE::BSFixedString& a_name, std::int32_t& a_out) const override
            {
                return sourceHolder_ && sourceHolder_->GetGraphVariableImplInt(a_name, a_out);
            }
            bool GetGraphVariableImplBool(const RE::BSFixedString& a_name, bool& a_out) const override
            {
                return sourceHolder_ && sourceHolder_->GetGraphVariableImplBool(a_name, a_out);
            }
            void PreUpdateAnimationGraphManager(const RE::BSTSmartPointer<Manager>& a_manager) const override
            {
                if (sourceHolder_) { g_actorPreUpdate(sourceHolder_, a_manager); }
            }
            void PreLoadAnimationGraphManager(const RE::BSTSmartPointer<Manager>& a_manager) override
            {
                if (sourceHolder_) { g_actorPreLoad(sourceHolder_, a_manager); }
            }
            void PostLoadAnimationGraphManager(const RE::BSTSmartPointer<Manager>& a_manager) override
            {
                if (sourceHolder_) { g_actorPostLoad(sourceHolder_, a_manager); }
            }

            Graph* ActiveGraph() const
            {
                if (!manager_ || manager_->graph.empty() || manager_->activeGraph >= manager_->graph.size()) {
                    return nullptr;
                }
                return manager_->graph[manager_->activeGraph].get();
            }

            bool IsLiveSourceManager(const Manager* a_manager) const
            {
                RE::BSTSmartPointer<Manager> source;
                return sourceHolder_ && sourceHolder_->GetAnimationGraphManagerImpl(source) &&
                    source.get() == a_manager;
            }

            void MirrorEvent(const RE::BSFixedString& a_event)
            {
                if (a_event.empty()) { return; }
                // Seed the private graph with the source's current action variables before dispatching the
                // event, then perform the same tiny immediate update used by InitializeActorInstant. This makes
                // the state machine consume the request now instead of showing a one-frame old state first.
                if (initialized_) {
                    SyncVariables();
                    ApplyPreviewGraphVariableOverrides();
                    ApplyWeaponIdleVisibility();
                }
                const bool accepted = NotifyAnimationGraphImpl(a_event);
                if (accepted && initialized_) {
                    (void)AdvanceGraphPreservingRoot(0.0001f);
                    ApplyPreviewGraphVariableOverrides();
                    ApplyWeaponIdleVisibility();
                    if (!loggedInstantEventConsumption_) {
                        loggedInstantEventConsumption_ = true;
                        logger::info("[PipOS][3D][ANIM] mirrored state transitions consume immediately");
                    }
                }
            }

            bool Create(const char* a_project)
            {
                if (!a_project || !g_createManager(this, a_project) || !manager_) {
                    logger::error("[PipOS][3D][ANIM] CreateAnimationGraphManager failed");
                    return false;
                }
                if (!Target()) {
                    logger::error("[PipOS][3D][ANIM] SetAnimationGraphTargets failed");
                    return false;
                }
                PreLoadAnimationGraphManager(manager_);
                PostLoadAnimationGraphManager(manager_);
                LoadThirdPersonSubgraphs();
                PreLoadAnimationGraphManager(manager_);
                PostLoadAnimationGraphManager(manager_);
                // ActivateImpl reports false when the Havok behavior is already active. TF3DHUD treats that
                // state as success; rejecting it here was the runtime-confirmed reason every preview stayed in
                // its bind pose while the log retried manager construction every frame.
                auto* graph = ActiveGraph();
                auto* behavior = graph ? *reinterpret_cast<HkbBehaviorGraphDiagnostic* const*>(
                    reinterpret_cast<const std::byte*>(graph) + 0x378) : nullptr;
                if (!(behavior && behavior->isActive) && !g_activateManager(manager_.get())) {
                    logger::error("[PipOS][3D][ANIM] ActivateAnimationGraphManager failed");
                    return false;
                }
                return true;
            }

            bool Target() { return target_ && g_setTarget(this, target_, true); }

            void LoadThirdPersonSubgraphs()
            {
                auto* middleHigh = sourceActor_ && sourceActor_->currentProcess ?
                    sourceActor_->currentProcess->middleHigh : nullptr;
                auto* race = sourceActor_ ? sourceActor_->GetVisualsRace() : nullptr;
                auto* tes = RE::TES::GetSingleton();
                auto* cell = sourceActor_ ? sourceActor_->GetParentCell() : nullptr;
                auto* data = *g_subgraphDataSingleton;
                auto* swap = *g_graphSwapSingleton;
                auto* graph = ActiveGraph();
                if (!middleHigh || !race || !tes || !cell || !data || !swap || !graph) { return; }

                subgraphPriority_ = g_getCellPriority(tes, cell, nullptr);
                std::vector<RE::SubgraphIdentifier> requested;
                const auto appendIntent = [&](const auto& a_intent) {
                    for (const auto& root : middleHigh->subGraphIdleManagerRoots) {
                        if (root.forFirstPerson || root.subGraphID.identifier == 0) { continue; }
                        const bool wanted = std::any_of(a_intent.begin(), a_intent.end(), [&](const auto& id) {
                            return id.identifier == root.subGraphID.identifier;
                        });
                        const bool duplicate = std::any_of(requested.begin(), requested.end(), [&](const auto& id) {
                            return id.identifier == root.subGraphID.identifier;
                        });
                        if (wanted && !duplicate) { requested.push_back(root.subGraphID); }
                    }
                };
                appendIntent(middleHigh->requestedDefaultSubGraphID.empty() ?
                    middleHigh->currentDefaultSubGraphID : middleHigh->requestedDefaultSubGraphID);
                appendIntent(middleHigh->requestedWeaponSubGraphID.empty() ?
                    middleHigh->currentWeaponSubGraphID : middleHigh->requestedWeaponSubGraphID);

                for (const auto& id : requested) {
                    RE::BSFixedString rootName;
                    SubgraphArena preload;
                    if (!g_retrieveSubgraph(data, race->formID, std::addressof(id), std::addressof(rootName),
                            std::addressof(preload)) || rootName.empty()) {
                        continue;
                    }
                    SubgraphArena lowPriority;
                    (void)g_gatherPreload(*race, *sourceActor_, id, g_getAnimationSex(sourceActor_), false,
                        lowPriority);
                    RE::SubgraphHandle handle;
                    if (g_initializeSubgraph(swap, graph, std::addressof(rootName), std::addressof(preload),
                            std::addressof(lowPriority), std::addressof(subgraphPriority_),
                            std::addressof(handle)) && handle.handle != 0) {
                        subgraphHandles_.push_back(handle);
                    }
                }
                logger::info("[PipOS][3D][ANIM] requested {} third-person behavior subgraphs", subgraphHandles_.size());
            }

            bool SubgraphsReady() const
            {
                if (subgraphHandles_.empty()) { return true; }
                auto* swap = *g_graphSwapSingleton;
                auto* graph = ActiveGraph();
                if (!swap || !graph) { return false; }
                return std::all_of(subgraphHandles_.begin(), subgraphHandles_.end(), [&](const auto& handle) {
                    return g_isSubgraphLoaded(swap, graph, std::addressof(handle),
                        std::addressof(subgraphPriority_)) == 2;
                });
            }

            void SyncVariables()
            {
                for (auto name : kIntVariables) {
                    std::int32_t value = 0;
                    if (sourceHolder_->GetGraphVariableImplInt(RE::BSFixedString(name), value)) {
                        SetGraphVariableInt(RE::BSFixedString(name), value);
                    }
                }
                for (auto name : kBoolVariables) {
                    bool value = false;
                    if (sourceHolder_->GetGraphVariableImplBool(RE::BSFixedString(name), value)) {
                        SetGraphVariableBool(RE::BSFixedString(name), value);
                    }
                }
                for (auto name : kFloatVariables) {
                    float value = 0.0f;
                    if (sourceHolder_->GetGraphVariableImplFloat(RE::BSFixedString(name), value)) {
                        SetGraphVariableFloat(RE::BSFixedString(name), value);
                    }
                }
                SetGraphVariableFloat(RE::BSFixedString("Speed"), 0.0f);
                SetGraphVariableBool(RE::BSFixedString("bAimActive"), false);
                SetGraphVariableBool(RE::BSFixedString("bAimEnabled"), false);
                SetGraphVariableBool(RE::BSFixedString("DisableCharacterPitch"), true);
                SetGraphVariableBool(RE::BSFixedString("bFreezeRotationUpdate"), true);
            }

            void ApplyPreviewGraphVariableOverrides()
            {
                for (auto name : kPreviewNeutralBoolVariables) {
                    SetGraphVariableBool(RE::BSFixedString(name), false);
                }
                for (auto name : kPreviewEnabledBoolVariables) {
                    SetGraphVariableBool(RE::BSFixedString(name), true);
                }
                for (auto name : kPreviewNeutralIntVariables) {
                    SetGraphVariableInt(RE::BSFixedString(name), 0);
                }
                for (auto name : kPreviewReadyIntVariables) {
                    SetGraphVariableInt(RE::BSFixedString(name), 1);
                }
                for (auto name : kPreviewNeutralFloatVariables) {
                    SetGraphVariableFloat(RE::BSFixedString(name), 0.0f);
                }
            }

            [[nodiscard]] int EffectiveIdleState() const
            {
                const int sessionState = g_sessionIdleState.load();
                if (sessionState >= 0) { return sessionState; }
                auto* settings = Settings::GetSingleton();
                return settings ? settings->Char3DIdleState() : 0;
            }

            void Update(float a_delta)
            {
                if (!manager_) { return; }
                auto* settings = Settings::GetSingleton();
                if (!settings || !settings->Char3DAnimate()) { return; }
                if (!initialized_ && SubgraphsReady()) {
                    (void)Target();
                    SyncVariables();
                    ApplyPreviewGraphVariableOverrides();
                    ApplyConfiguredIdleState(true);
                    ApplyWeaponIdleVisibility();
                    FastForwardConfiguredStateTransition();
                    initialized_ = true;
                    logger::info("[PipOS][3D][ANIM] private state machine pre-rolled into idleState={}",
                        settings->Char3DIdleState());
                }
                if (initialized_ && (EffectiveIdleState() != appliedIdleState_ ||
                                         HasEquippedWeapon() != appliedWeaponEquipped_)) {
                    // Use the instant base-state entry and fully settle Ready/Sighted before the next visible
                    // renderer pass. The target idle clip then continues normally from its settled loop.
                    ApplyConfiguredIdleState(true);
                    FastForwardConfiguredStateTransition();
                    logger::info("[PipOS][3D][ANIM] configured state transition fast-forwarded into idleState={}",
                        settings->Char3DIdleState());
                }
                SyncVariables();
                ApplyPreviewGraphVariableOverrides();
                // Apply preview-only weapon policy after mirroring the live graph. Otherwise the live
                // iSync values immediately overwrite the menu's sheathed-state request every frame.
                ApplyWeaponIdleVisibility();
                const bool updated = AdvanceGraphPreservingRoot(std::clamp(a_delta, 0.0001f, 0.05f));
                if (!loggedUpdate_) {
                    loggedUpdate_ = true;
                    logger::info("[PipOS][3D][ANIM] private graph update active: updated={} subgraphsReady={}",
                        updated, SubgraphsReady());
                }
            }

            bool AdvanceGraphPreservingRoot(float a_delta)
            {
                if (!target_) { return false; }
                const auto rootTransform = target_->GetLocalTransform();
                const bool updated = g_updateManager(this, a_delta);
                target_->SetLocalTransform(rootTransform);
                return updated;
            }

            void FastForwardConfiguredStateTransition()
            {
                // Tiny tick consumes the instant base-state event. The settle tick skips only the configured
                // preview's Ready/Sighted/Relaxed blend, matching the existing first-open pre-roll. Mirrored
                // attack/reload/melee clips use only the tiny consumption tick above and are never skipped.
                (void)AdvanceGraphPreservingRoot(0.0001f);
                ApplyConfiguredWeaponPoseEvents();
                (void)AdvanceGraphPreservingRoot(2.0f);
                ApplyPreviewGraphVariableOverrides();
                ApplyWeaponIdleVisibility();
            }

            void ApplyConfiguredIdleState(bool a_instant)
            {
                auto* settings = Settings::GetSingleton();
                if (!settings) { return; }
                const int state = EffectiveIdleState();
                const bool weaponEquipped = HasEquippedWeapon();
                if (!a_instant && appliedIdleState_ == state &&
                    appliedWeaponEquipped_ == weaponEquipped) {
                    return;
                }
                // Weapon previews always initialize through the drawn base state. The user then chooses
                // stationary ready or sighted. Relaxed is reserved for genuinely unarmed previews.
                const char* eventName = weaponEquipped ?
                    (a_instant ? "g_archetypeBaseStateStartInstant" : "g_archetypeBaseStateStart") :
                    (a_instant ? "g_archetypeRelaxedStateStartInstant" : "g_archetypeRelaxedStateStart");
                bool accepted = NotifyAnimationGraphImpl(RE::BSFixedString(eventName));
                if (!accepted && a_instant) {
                    accepted = NotifyAnimationGraphImpl(RE::BSFixedString(
                        weaponEquipped ? "g_archetypeBaseStateStart" : "g_archetypeRelaxedStateStart"));
                }
                if (weaponEquipped) {
                    ApplyConfiguredWeaponPoseEvents();
                }
                appliedIdleState_ = state;
                resolvedIdleState_ = state;
                appliedWeaponEquipped_ = weaponEquipped;
                logger::info("[PipOS][3D][ANIM] idle state applied: configured={} weaponEquipped={} pose='{}' accepted={}",
                    appliedIdleState_, weaponEquipped,
                    weaponEquipped ? (state == 1 ? "sighted" : "ready") : "relaxed", accepted);
            }

            void ApplyConfiguredWeaponPoseEvents()
            {
                auto* settings = Settings::GetSingleton();
                if (!settings || !HasEquippedWeapon()) { return; }
                (void)NotifyAnimationGraphImpl(RE::BSFixedString("weapEquip"));
                if (EffectiveIdleState() == 1) {
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("rifleSightedStart"));
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("sightedStateEnter"));
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("UpdateSighted"));
                } else {
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("rifleSightedEnd"));
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("sightedStateExit"));
                }
            }

            void ApplySessionPoseTransition()
            {
                if (!initialized_ || !HasEquippedWeapon()) { return; }
                // Session right-clicks intentionally retain the ordinary Ready/Sighted behavior blend.
                // Persisted setting changes continue to use the separate fast-forward path in Update().
                ApplyConfiguredWeaponPoseEvents();
                appliedIdleState_ = EffectiveIdleState();
                appliedWeaponEquipped_ = true;
                ApplyWeaponIdleVisibility();
                logger::info("[PipOS][3D][ANIM] session pose transition requested: pose='{}'",
                    appliedIdleState_ == 1 ? "sighted" : "ready");
            }

            [[nodiscard]] bool HasEquippedWeapon() const
            {
                // Equipment ownership is captured with the private preview generation. Do not let a gameplay
                // draw/holster/equip transition change the menu graph before that generation is rebuilt.
                return weaponEquipped_;
            }

            void ApplyWeaponIdleVisibility()
            {
                auto* settings = Settings::GetSingleton();
                if (!settings || !target_) { return; }
                const bool weaponEquipped = HasEquippedWeapon();
                const bool hide = !weaponEquipped || settings->Char3DHideWeaponIdle();
                for (const char* name : { "Weapon", "WeaponLeft" }) {
                    if (auto* weapon = target_->GetObjectByName(RE::BSFixedString(name))) {
                        weapon->SetAppCulled(hide);
                    }
                }
                if (weaponEquipped && !settings->Char3DSheatheWeaponIdle()) {
                    // Match TF3DHUD's settled preview state. iSyncWeaponDrawState=2 is an initialization pulse,
                    // not a value to hold every frame; holding it can leave the hand pose and Weapon bone in
                    // different transition states. The base-state event above performs that pulse, so settle it
                    // back to zero and keep the equipped weapon subgraph in its preview-owned state 2.
                    SetGraphVariableBool(RE::BSFixedString("bEquipOk"), true);
                    SetGraphVariableInt(RE::BSFixedString("iSyncWeaponDrawState"), 0);
                    SetGraphVariableInt(RE::BSFixedString("iSyncGunDown"), 0);
                    SetGraphVariableInt(RE::BSFixedString("iSyncReadyAlertRelaxed"), 2);
                    const bool sighted = EffectiveIdleState() == 1;
                    SetGraphVariableInt(RE::BSFixedString("iSyncSightedState"), sighted ? 1 : 0);
                    // TF3DHUD keeps aim IK disabled in a stationary preview and selects the sighted branch via
                    // iSyncSightedState/events. Enabling live aim without an aim target can pull the hands away
                    // from the weapon independently of its Weapon-bone attachment.
                    SetGraphVariableBool(RE::BSFixedString("bAimActive"), false);
                    SetGraphVariableBool(RE::BSFixedString("bAimEnabled"), false);
                } else if (settings->Char3DSheatheWeaponIdle()) {
                    SetGraphVariableInt(RE::BSFixedString("iSyncWeaponDrawState"), 0);
                    SetGraphVariableInt(RE::BSFixedString("iSyncGunDown"), 1);
                }
            }

            RE::PlayerCharacter* sourceActor_{ nullptr };
            Holder* sourceHolder_{ nullptr };
            RE::NiAVObject* target_{ nullptr };
            bool weaponEquipped_{ false };
            RE::BSTSmartPointer<Manager> manager_;
            std::vector<RE::SubgraphHandle> subgraphHandles_;
            std::int32_t subgraphPriority_{ 0 };
            int appliedIdleState_{ -1 };
            int resolvedIdleState_{ -1 };
            bool appliedWeaponEquipped_{ false };
            bool initialized_{ false };
            bool loggedUpdate_{ false };
            bool loggedInstantEventConsumption_{ false };
        };

        std::unique_ptr<PreviewHolder> g_holder;
        RE::NiAVObject* g_target{ nullptr };
        RE::PlayerCharacter* g_source{ nullptr };
        std::recursive_mutex g_lock;
        struct PendingRequest
        {
            Manager* manager;
            RE::BSFixedString eventName;
            std::uint32_t result;
        };
        std::mutex g_pendingLock;
        std::vector<PendingRequest> g_pendingRequests;
        RE::NiAVObject* g_failedTarget{ nullptr };
        std::chrono::steady_clock::time_point g_retryAfter{};

        void DrainPendingRequests()
        {
            std::vector<PendingRequest> requests;
            {
                std::scoped_lock lock(g_pendingLock);
                requests.swap(g_pendingRequests);
            }
            if (!g_holder) { return; }
            for (const auto& request : requests) {
                if (g_holder->IsLiveSourceManager(request.manager)) {
                    (void)request.result;
                    g_holder->MirrorEvent(request.eventName);
                }
            }
        }

        bool Ensure(
            RE::PlayerCharacter& a_player,
            RE::NiAVObject& a_target,
            const bool a_weaponEquipped)
        {
            if (g_holder && g_source == std::addressof(a_player) && g_target == std::addressof(a_target)) {
                return true;
            }
            g_holder.reset();
            g_source = nullptr;
            g_target = nullptr;
            const auto now = std::chrono::steady_clock::now();
            if (g_failedTarget == std::addressof(a_target) && now < g_retryAfter) { return false; }
            auto* sourceRoot = a_player.Get3D(false);
            if (!sourceRoot) { sourceRoot = a_player.Get3D(); }
            const char* project = g_getProjectForActor(std::addressof(a_player), sourceRoot);
            if (!project || project[0] == '\0') {
                logger::error("[PipOS][3D][ANIM] live actor behavior project unavailable");
                return false;
            }
            auto holder = std::make_unique<PreviewHolder>(a_player, a_target, a_weaponEquipped);
            if (!holder->Create(project)) {
                logger::error(std::format("[PipOS][3D][ANIM] private graph creation failed for '{}'", project));
                g_failedTarget = std::addressof(a_target);
                g_retryAfter = now + std::chrono::seconds(1);
                return false;
            }
            g_source = std::addressof(a_player);
            g_target = std::addressof(a_target);
            g_holder = std::move(holder);
            g_failedTarget = nullptr;
            g_retryAfter = {};
            logger::info("[PipOS][3D][ANIM] private graph created for '{}'", project);
            return true;
        }
    }

    void Update(
        RE::PlayerCharacter& a_player,
        RE::NiAVObject& a_previewRoot,
        const bool a_weaponEquipped,
        float a_deltaTime)
    {
        std::scoped_lock lock(g_lock);
        if (!Ensure(a_player, a_previewRoot, a_weaponEquipped) || !g_holder) { return; }
        DrainPendingRequests();
        g_holder->Update(a_deltaTime);
        const auto weaponBridge = a_weaponEquipped ?
            ApplyPrivateWeaponTransformBridge(a_previewRoot) : PrivateWeaponBridgeResult{};
        RE::NiUpdateData updateData;
        a_previewRoot.Update(updateData);
        if (a_weaponEquipped) { LogPrivateWeaponBridgeAudit(weaponBridge); }
    }

    void ObserveGraphRequest(
        RE::BSAnimationGraphManager* a_manager, const char* a_eventName, std::uint32_t a_result)
    {
        if (!a_manager || !a_eventName || a_eventName[0] == '\0') { return; }
        const std::string_view eventName(a_eventName);
        if (std::find(kMirroredEvents.begin(), kMirroredEvents.end(), eventName) == kMirroredEvents.end()) {
            return;
        }
        if (!MirroredEventEnabled(eventName)) { return; }
        std::scoped_lock lock(g_pendingLock);
        g_pendingRequests.push_back({ a_manager, RE::BSFixedString(a_eventName), a_result });
    }

    void ToggleReadySighted()
    {
        std::scoped_lock lock(g_lock);
        const int sessionState = g_sessionIdleState.load();
        auto* settings = Settings::GetSingleton();
        const int current = sessionState >= 0 ? sessionState : (settings ? settings->Char3DIdleState() : 0);
        g_sessionIdleState.store(current == 1 ? 0 : 1);
        if (g_holder) { g_holder->ApplySessionPoseTransition(); }
    }

    void ResetSessionPose()
    {
        g_sessionIdleState.store(-1);
    }

    void Reset()
    {
        std::scoped_lock lock(g_lock);
        g_holder.reset();
        g_target = nullptr;
        g_source = nullptr;
        g_failedTarget = nullptr;
        g_retryAfter = {};
        g_privateWeaponBridgeLogged = false;
        g_privateWeaponBridgeFailureLogged = false;
        std::scoped_lock pendingLock(g_pendingLock);
        g_pendingRequests.clear();
    }
}
