#include "PCH.h"
#include "CharacterAnimation.h"
#include "RE_Animation.h"
#include "Settings.h"

#include <algorithm>
#include <memory>
#include <mutex>
#include <vector>

namespace PipOS::CharacterAnimation
{
    namespace
    {
        constexpr std::size_t kGraphSize = 0x3D0;
        constexpr std::size_t kGraphAlignment = 0x10;

        using Holder = RE::IAnimationGraphManagerHolder;
        using Graph = RE::BShkbAnimationGraph;
        using Manager = RE::BSAnimationGraphManager;
        using SubgraphArena = RE::BSTObjectArena<RE::BSFixedString, RE::BSTObjectArenaScrapAlloc, 32>;

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
            "weapEquip", "weapUnequip", "Unequip", "weaponDraw", "weaponSheathe", "BeginWeaponDraw",
            "BeginWeaponSheathe", "weaponAttach", "weaponDetach", "rifleSightedStart", "rifleSightedEnd",
            "rifleSightedStartOver", "sightedStateEnter", "sightedStateExit", "UpdateSighted", "SyncLeft",
            "SyncRight", "SyncCycleEnd", "syncIdleStart", "syncIdleStop"
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
            return true; // draw/sheathe, ready-state, sighted, and synchronization lifecycle events
        }

        class PreviewHolder final : public Holder
        {
        public:
            PreviewHolder(RE::PlayerCharacter& a_player, RE::NiAVObject& a_target) :
                sourceActor_(std::addressof(a_player)),
                sourceHolder_(static_cast<Holder*>(std::addressof(a_player))),
                target_(std::addressof(a_target))
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

            std::uint64_t SourceIntentSignature() const
            {
                auto* middleHigh = sourceActor_ && sourceActor_->currentProcess ?
                    sourceActor_->currentProcess->middleHigh : nullptr;
                if (!middleHigh) { return 0; }
                std::uint64_t hash = 1469598103934665603ull;
                const auto mix = [&](const auto& ids) {
                    for (const auto& id : ids) {
                        hash ^= id.identifier;
                        hash *= 1099511628211ull;
                    }
                };
                const auto& defaults = middleHigh->requestedDefaultSubGraphID.empty() ?
                    middleHigh->currentDefaultSubGraphID : middleHigh->requestedDefaultSubGraphID;
                const auto& weapons = middleHigh->requestedWeaponSubGraphID.empty() ?
                    middleHigh->currentWeaponSubGraphID : middleHigh->requestedWeaponSubGraphID;
                mix(defaults);
                mix(weapons);
                return hash;
            }

            bool NeedsSubgraphReconcile() const
            {
                const auto current = SourceIntentSignature();
                return current != 0 && sourceIntentSignature_ != 0 && current != sourceIntentSignature_;
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
                sourceIntentSignature_ = SourceIntentSignature();
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
                if (initialized_ && (settings->Char3DIdleState() != appliedIdleState_ ||
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
                const int state = settings->Char3DIdleState();
                const bool weaponEquipped = HasEquippedWeapon();
                if (!a_instant && appliedIdleState_ == settings->Char3DIdleState() &&
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
                appliedIdleState_ = settings->Char3DIdleState();
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
                if (settings->Char3DIdleState() == 1) {
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("rifleSightedStart"));
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("sightedStateEnter"));
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("UpdateSighted"));
                } else {
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("rifleSightedEnd"));
                    (void)NotifyAnimationGraphImpl(RE::BSFixedString("sightedStateExit"));
                }
            }

            [[nodiscard]] bool HasEquippedWeapon() const
            {
                const auto& biped = sourceActor_ ? sourceActor_->GetBiped(false) : nullptr;
                if (!biped) { return false; }
                for (std::int32_t slot = 32; slot <= 43; ++slot) {
                    if (slot == 40) { continue; }
                    const auto* form = biped->object[slot].parent.object;
                    if (form && form->Is(RE::ENUM_FORM_ID::kWEAP)) { return true; }
                }
                return false;
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
                    const bool sighted = settings->Char3DIdleState() == 1;
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
            RE::BSTSmartPointer<Manager> manager_;
            std::vector<RE::SubgraphHandle> subgraphHandles_;
            std::int32_t subgraphPriority_{ 0 };
            std::uint64_t sourceIntentSignature_{ 0 };
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

        bool Ensure(RE::PlayerCharacter& a_player, RE::NiAVObject& a_target)
        {
            if (g_holder && g_source == std::addressof(a_player) && g_target == std::addressof(a_target)) {
                if (!g_holder->NeedsSubgraphReconcile()) { return true; }
                logger::info("[PipOS][3D][ANIM] source subgraph intent changed; rebuilding private manager");
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
            auto holder = std::make_unique<PreviewHolder>(a_player, a_target);
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

    void Update(RE::PlayerCharacter& a_player, RE::NiAVObject& a_previewRoot, float a_deltaTime)
    {
        std::scoped_lock lock(g_lock);
        if (!Ensure(a_player, a_previewRoot) || !g_holder) { return; }
        DrainPendingRequests();
        g_holder->Update(a_deltaTime);
        RE::NiUpdateData updateData;
        a_previewRoot.Update(updateData);
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

    void Reset()
    {
        std::scoped_lock lock(g_lock);
        g_holder.reset();
        g_target = nullptr;
        g_source = nullptr;
        g_failedTarget = nullptr;
        g_retryAfter = {};
        std::scoped_lock pendingLock(g_pendingLock);
        g_pendingRequests.clear();
    }
}
