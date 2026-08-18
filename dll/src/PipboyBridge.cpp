#include "PCH.h"
#include "Scaleform/G/GFx_ASMovieRootBase.h"
#include "Scaleform/G/GFx_Viewport.h"
#include "PipboyBridge.h"
#include "Settings.h"

#include <cctype>
#include <cstdio>
#include <excpt.h>   // EXCEPTION_EXECUTE_HANDLER for the per-item SEH containment net
#include <string>
#include <unordered_map>
#include <vector>

namespace PipOS
{
    namespace
    {
        constexpr std::string_view kPipboyMenu = "PipboyMenu";

        // ROUND 22 - DLL CHROME ROUTE (shell stays BYTE-IDENTICAL vanilla).
        // The condemned patched shell exposed SetPageMode/a chrome loader; the DLL route keeps the vanilla
        // shell untouched, so those do NOT exist. Instead we (1) dim the vanilla Header_mc (removes the ghost
        // "WEAPONS APPAREL AID" category strip + the vanilla STAT/INV/DATA/MAP/RADIO page-tab row - round-20
        // diagnosis: both are rendered by the vanilla Pipboy_Header) and (2) load PIP-OS_Chrome.swf as a root
        // child of the Pip-Boy movie using the built-in flash.display.Loader + root.addChild - the exact
        // pattern S2 HUD Rework uses to inject a child SWF into a menu with no shell hook. The chrome then
        // self-acquires the menu via stage.getChildAt(0)["Menu_mc"] and drives page switching through the
        // vanilla-public PipboyMenu.TryToSetPage(uint). Task-deferred + readiness-guarded like the proven
        // page-mode push. Value-array marshalling only (never the "%fmt" varargs form).
        void AttachChromeNow(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            auto* movieRoot = a_view->asMovieRoot.get();
            if (!movieRoot) { logger::error("[PipOS] stage0-FAIL: asMovieRoot null"); return; }

            // Readiness: the vanilla shell instance Menu_mc must resolve before we touch it.
            Scaleform::GFx::Value menuObj;
            if (!a_view->GetVariable(std::addressof(menuObj), "root1.Menu_mc") ||
                !(menuObj.IsObject() || menuObj.IsDisplayObject())) {
                logger::info("[PipOS] Menu_mc not ready; skipping chrome attach this open");
                return;
            }
            // Idempotent: don't double-attach if the chrome loader is already a root member.
            Scaleform::GFx::Value existing;
            if (a_view->GetVariable(std::addressof(existing), "root1.PipOS_chrome_loader") && existing.IsObject()) {
                return;
            }

            // (1) dim the vanilla header (alpha 0 hides all its ghost TextFields; the header data path still
            //     runs and the PipboyTabs contract - Menu_mc.getChildAt(4)._TabNames - is unaffected).
            const bool dimOK = a_view->SetVariable("root1.Menu_mc.Header_mc.alpha", Scaleform::GFx::Value(0.0));
            logger::info("[PipOS] stage1: Header_mc.alpha=0 set ok={}", dimOK);
            if (!dimOK) { logger::error("[PipOS] stage1-FAIL: header dim SetVariable false (path unresolved); bailing"); return; }

            // P1 GATE: alpha=0 does NOT disable mouse in GFx - the invisible vanilla header still eats
            // MOUSE_DOWN and swallows our page sub-tab hits. Disable its mouse so clicks fall through to us.
            a_view->SetVariable("root1.Menu_mc.Header_mc.mouseEnabled", Scaleform::GFx::Value(false));
            a_view->SetVariable("root1.Menu_mc.Header_mc.mouseChildren", Scaleform::GFx::Value(false));
            // P2: dim + mouse-disable the vanilla bottom bar (weight/caps/HP) and the vanilla keybar.
            a_view->SetVariable("root1.Menu_mc.BottomBar_mc.alpha", Scaleform::GFx::Value(0.0));
            a_view->SetVariable("root1.Menu_mc.BottomBar_mc.mouseEnabled", Scaleform::GFx::Value(false));
            a_view->SetVariable("root1.Menu_mc.BottomBar_mc.mouseChildren", Scaleform::GFx::Value(false));
            a_view->SetVariable("root1.Menu_mc.ButtonHintBar_mc.alpha", Scaleform::GFx::Value(0.0));
            a_view->SetVariable("root1.Menu_mc.ButtonHintBar_mc.mouseEnabled", Scaleform::GFx::Value(false));
            logger::info("[PipOS] stage1b: header+bottombar mouse-disabled + bottombar dimmed");

            // (2) load PipOS_Chrome.swf as a root child (S2 pattern: Loader + URLRequest + root.addChild).
            // MOVIE-MANAGED string via CreateString (matches S2 exactly). CreateObject is void, so IsObject()
            // is the creation-success proxy - bail if a stage did not produce an object.
            Scaleform::GFx::Value loader;
            movieRoot->CreateObject(std::addressof(loader), "flash.display.Loader");
            if (!loader.IsObject()) { logger::error("[PipOS] stage2-FAIL: Loader not created"); return; }
            logger::info("[PipOS] stage2: Loader created");
            Scaleform::GFx::Value urlName;
            movieRoot->CreateString(std::addressof(urlName), "PipOS_Chrome.swf");
            Scaleform::GFx::Value request;
            movieRoot->CreateObject(std::addressof(request), "flash.net.URLRequest", std::addressof(urlName), 1);
            if (!request.IsObject()) { logger::error("[PipOS] stage2b-FAIL: URLRequest not created"); return; }

            Scaleform::GFx::Value root;
            if (!a_view->GetVariable(std::addressof(root), "root1")) { logger::error("[PipOS] stage2c-FAIL: root1 unresolved"); return; }
            root.SetMember("PipOS_chrome_loader", loader);
            const bool loadOK = a_view->Invoke("root1.PipOS_chrome_loader.load", nullptr, std::addressof(request), 1);
            logger::info("[PipOS] stage3: load() invoked ok={}", loadOK);
            if (!loadOK) { logger::error("[PipOS] stage3-FAIL: load() returned false; not addChilding"); return; }
            const bool addOK = a_view->Invoke("root1.addChild", nullptr, std::addressof(loader), 1);
            logger::info("[PipOS] stage4: root1.addChild invoked ok={}; chrome attached + header dimmed", addOK);
        }

        // ROUND 25 (0.0.20) - NATIVE EQUIPMENT-PER-SLOT PUSH (P3(b)).
        // The AS inventory list rows carry no stable key, so per-row WT/VAL/AMMO stays blocked; but the
        // EQUIPMENT panel is a FIXED set of biped slots (not list rows), so no row-key is needed. We read the
        // player's worn armor natively and push a 10-element name array (panel-row order == InvPage SLOTS[])
        // onto root1 as a dynamic member "PipOS_equip". The InvPage reads it (update-text-only) on stage.
        // CRASH-SAFETY (#1 risk): every native handle is null-guarded; any null skips that row to "" (=> "-"),
        // never derefs. Reads run on the UI-task thread (same proven path as the chrome attach); the whole
        // native section is wrapped in try/catch so a failed read degrades to a blank panel, never a CTD.
        // bit i of TESObjectARMO::bipedModelData.bipedObjectSlots == RE::BIPED_OBJECT index i == CK slot 30+i.
        void PushEquipmentNow(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            auto* movieRoot = a_view->asMovieRoot.get();
            if (!movieRoot) { return; }

            // Readiness: root1 must resolve (same guard family as the chrome attach). Idempotent by design:
            // each open overwrites the member, so re-running is harmless.
            Scaleform::GFx::Value root;
            if (!a_view->GetVariable(std::addressof(root), "root1") || !root.IsObject()) {
                logger::info("[PipOS] equip: root1 not ready; skipping push");
                return;
            }

            // Panel row -> the biped-slot bit(s) that fill it. Row order MUST match InvPage SLOTS[]:
            // HEAD,TORSO,L.ARM,R.ARM,L.LEG,R.LEG,UNDER ARMOR,OUTFIT,BACKPACK,PIP-BOY.
            static constexpr std::uint32_t kRowMask[10] = {
                (1u << 0) | (1u << 16),  // 0 HEAD        : HairTop(30) / Headband(46) - headgear/masks/helmets
                (1u << 11),              // 1 TORSO       : [A] Torso(41) - over-armor chest piece
                (1u << 12),              // 2 L.ARM       : [A] Left Arm(42)
                (1u << 13),              // 3 R.ARM       : [A] Right Arm(43)
                (1u << 14),              // 4 L.LEG       : [A] Left Leg(44)
                (1u << 15),              // 5 R.LEG       : [A] Right Leg(45)
                (1u << 6),               // 6 UNDER ARMOR : [U] Torso(36) - undergarment torso layer
                (1u << 3),               // 7 OUTFIT      : Body(33) - full-body outfit
                (0x1Fu << 24),           // 8 BACKPACK    : Unnamed1..5(54..58) - common modded backpack slots
                (1u << 30),              // 9 PIP-BOY     : Pipboy(60)
            };
            std::array<std::string, 10> names{};  // empty string => AS renders "-"

            try {
                auto* pc = RE::PlayerCharacter::GetSingleton();
                if (pc && pc->inventoryList) {
                    pc->inventoryList->ForEachStack(
                        [](RE::BGSInventoryItem& a_item) -> bool {
                            // iterate stacks only for armor base objects
                            return a_item.object && a_item.object->As<RE::TESObjectARMO>() != nullptr;
                        },
                        [&](RE::BGSInventoryItem& a_item, RE::BGSInventoryItem::Stack& a_stack) -> bool {
                            if (!a_stack.IsEquipped()) { return true; }
                            auto* armo = a_item.object ? a_item.object->As<RE::TESObjectARMO>() : nullptr;
                            if (!armo) { return true; }
                            const std::uint32_t slots = armo->bipedModelData.bipedObjectSlots;
                            if (slots == 0u) { return true; }
                            const char* nm = a_item.GetDisplayFullName(a_stack.extra.get());
                            if (!nm || nm[0] == '\0') { nm = armo->GetFullName(); }
                            if (!nm || nm[0] == '\0') { return true; }
                            for (std::size_t r = 0; r < names.size(); ++r) {
                                if ((slots & kRowMask[r]) != 0u && names[r].empty()) {
                                    names[r] = nm;  // copy immediately (engine buffer may be reused)
                                }
                            }
                            return true;  // keep iterating all equipped armor
                        });
                } else {
                    logger::info("[PipOS] equip: player/inventoryList null; pushing empty panel");
                }
            } catch (...) {
                logger::error("[PipOS] equip: native read threw; degrading to gathered/blank panel");
            }

            // Marshal -> AS3 string array; set as a dynamic member on root1 (== stage.getChildAt(0) the page
            // reads). Value-array / CreateString marshalling only (never %fmt varargs).
            try {
                Scaleform::GFx::Value arr;
                movieRoot->CreateArray(std::addressof(arr));
                if (!arr.IsArray()) { logger::error("[PipOS] equip: CreateArray failed; skipping"); return; }
                for (std::size_t r = 0; r < names.size(); ++r) {
                    Scaleform::GFx::Value s;
                    movieRoot->CreateString(std::addressof(s), names[r].c_str());
                    arr.PushBack(s);
                }
                root.SetMember("PipOS_equip", arr);
                logger::info("[PipOS] equip: pushed 10 rows (HEAD='{}' TORSO='{}' PIPBOY='{}')",
                    names[0], names[1], names[9]);
            } catch (...) {
                logger::error("[PipOS] equip: marshalling threw; skipped (panel stays blank)");
            }
        }

        // ROUND 28 (0.0.23) - NATIVE PER-ITEM WT/VAL/AMMO PUSH (P1-D).
        // The AS inventory rows carry no formID and no weight/value, so the WT/VAL/AMMO columns were blank.
        // Main-inventory rows DO carry a (non-unique) display name (.text). We build a native lookup map keyed
        // by that same display name: root1.PipOS_iteminfo[<fullName>] = { w:"<weight,1dp>", v:"<goldValue>",
        // a:"<ammo full name or ''>" } for every inventory object. The InvPage itemAdapter looks up
        // String(e.text) and fills the columns; a miss renders blank (never throws).
        // Weight/value come from the engine's own generic accessors (TESWeightForm::GetFormWeight /
        // TESValueForm::GetFormValue with null instance data == base per-unit) so they work for every item
        // type (weapons/armor store these on instance data, not as inherited base-form members). Ammo is the
        // weapon's ammo form full name (weapons only). Read-only; null-guarded; same UI-task thread affinity
        // as the equipment push; try/catch degrades a failed read to a partial/empty map (never a CTD).
        void PushItemInfoNow(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            auto* movieRoot = a_view->asMovieRoot.get();
            if (!movieRoot) { return; }

            Scaleform::GFx::Value root;
            if (!a_view->GetVariable(std::addressof(root), "root1") || !root.IsObject()) {
                logger::info("[PipOS] iteminfo: root1 not ready; skipping push");
                return;
            }

            Scaleform::GFx::Value map;
            movieRoot->CreateObject(std::addressof(map));   // plain AS3 Object (map)
            if (!map.IsObject()) { logger::error("[PipOS] iteminfo: CreateObject failed; skipping"); return; }

            int nEntries = 0;
            try {
                auto* pc = RE::PlayerCharacter::GetSingleton();
                if (pc && pc->inventoryList) {
                    pc->inventoryList->ForEachStack(
                        [](RE::BGSInventoryItem& a_item) -> bool {
                            return a_item.object != nullptr;
                        },
                        [&](RE::BGSInventoryItem& a_item, RE::BGSInventoryItem::Stack& a_stack) -> bool {
                            RE::TESBoundObject* obj = a_item.object;
                            if (!obj) { return true; }
                            const char* nm = a_item.GetDisplayFullName(a_stack.extra.get());
                            if (!nm || nm[0] == '\0') {
                                const auto sv = RE::TESFullName::GetFullName(*obj);
                                if (!sv.empty()) { nm = sv.data(); }
                            }
                            if (!nm || nm[0] == '\0') { return true; }

                            // Base per-unit weight/value via the engine's generic accessors (work for all
                            // item types; null instance data == base). Ammo full name for weapons only.
                            float wt = 0.0f;
                            std::int32_t val = 0;
                            try {
                                wt = RE::TESWeightForm::GetFormWeight(obj, nullptr);
                                val = static_cast<std::int32_t>(RE::TESValueForm::GetFormValue(obj, nullptr));
                            } catch (...) {}
                            std::string ammoName;
                            if (auto* weap = obj->As<RE::TESObjectWEAP>()) {
                                if (auto* am = weap->weaponData.ammo) {
                                    const char* an = am->GetFullName();
                                    if (an && an[0] != '\0') { ammoName = an; }
                                }
                            }

                            char wbuf[32]; std::snprintf(wbuf, sizeof(wbuf), "%.1f", wt);
                            char vbuf[32]; std::snprintf(vbuf, sizeof(vbuf), "%d", static_cast<int>(val));

                            Scaleform::GFx::Value entry;
                            movieRoot->CreateObject(std::addressof(entry));
                            if (!entry.IsObject()) { return true; }
                            Scaleform::GFx::Value sw, sv, sa;
                            movieRoot->CreateString(std::addressof(sw), wbuf);
                            movieRoot->CreateString(std::addressof(sv), vbuf);
                            movieRoot->CreateString(std::addressof(sa), ammoName.c_str());
                            entry.SetMember("w", sw);
                            entry.SetMember("v", sv);
                            entry.SetMember("a", sa);
                            map.SetMember(nm, entry);
                            ++nEntries;
                            return true;   // keep iterating; duplicate names overwrite (harmless)
                        });
                } else {
                    logger::info("[PipOS] iteminfo: player/inventoryList null; pushing empty map");
                }
            } catch (...) {
                logger::error("[PipOS] iteminfo: native read threw; degrading to partial/empty map");
            }

            root.SetMember("PipOS_iteminfo", map);
            logger::info("[PipOS] iteminfo: pushed {} entries", nEntries);
        }

        // ROUND 30 (0.0.25) - NATIVE ITEM-STATS / WEAPON-MODS / FAVORITES PUSH (P1 card+inspect+quick-access).
        // The AS item card / inspect / quick-access boxes were sparse because the engine _cardInfo callback
        // fills nothing. This adds three NEW dynamic members on root1, keyed by the row's decimal formID so
        // AS3 can join on String(row.formId):
        //   root1.PipOS_itemstats[<formID>] = { type, ...per-type stats }   (see docs/ItemDataContract.md)
        //   root1.PipOS_itemmods [<formID>] = [ "<mod full name>", ... ]    (installed object mods, weapons+armor)
        //   root1.PipOS_favorites          = [ { slot, formID, name, count, type }, ... ]  (12 quick-key slots)
        // ADDITIVE ONLY: the existing equip / iteminfo pushes are untouched. Same UI-task thread affinity, all
        // reads null-guarded (catch(...) does NOT catch an AV -> the null guards are what keep us safe), hard
        // caps on every array/map, degrade to omitted fields on any miss. One inventory pass builds the stats +
        // mods maps and an aux formID->count / ammoFormID->weaponName table (for ammo "used by" + favorite counts).
        //
        // HONEST SCOPE / gaps (documented, chosen over AV risk):
        //   * Stats come from the item's BASE form instance data (weaponData / armorData) -- these are plain
        //     member reads, no engine calls. They are the UNMODDED authored values; per-instance modded stat
        //     deltas are NOT applied (safely building fully-modded TBO_InstanceData needs engine instantiation
        //     calls that risk an AV in this untestable auto-install). The installed mod NAMES are still listed
        //     via PipOS_itemmods so the inspect "Current Mods" panel is correct.
        //   * Weapon accuracy is a DLL-derived proxy from the aim-model min cone (lower cone -> higher acc), not
        //     the engine's exact 0-150 derived accuracy stat (that lives behind an engine call).
        constexpr std::size_t kMaxStatEntries = 1024;   // inventory objects processed for stats/mods
        constexpr std::size_t kMaxModsPerItem = 16;     // installed mods listed per item
        constexpr std::size_t kMaxFavorites   = 12;     // Pip-Boy quick-key slots (engine array size)

        [[nodiscard]] const char* CategoryFor(RE::ENUM_FORM_ID a_type)
        {
            using F = RE::ENUM_FORM_ID;
            switch (a_type) {
                case F::kWEAP: return "weapon";
                case F::kARMO: return "apparel";
                case F::kALCH: return "aid";
                case F::kAMMO: return "ammo";
                case F::kBOOK: case F::kNOTE: return "note";
                default:       return "misc";
            }
        }

        // ---- CRASH FIX (Complex Sorter / FIS modded inventory) ----------------------------------------
        // POD carrier for one item's native reads. Trivially destructible (scalars + fixed char buffers,
        // no std:: containers / Scaleform values), so the SEH leaf helper that fills it needs no C++ object
        // unwinding -- that is what lets it host __try/__except without tripping MSVC C2712. Everything that
        // constructs a std::string / std::vector / Scaleform::GFx::Value is built by the CALLER from this POD,
        // strictly OUTSIDE the SEH.
        struct ItemRawPOD
        {
            bool          ok{ false };
            const char*   type{ "misc" };  // -> CategoryFor() string literal (safe, static storage)

            // installed OMOD object form IDs (disabled entries already dropped, capped)
            std::uint32_t modIDs[kMaxModsPerItem]{};
            std::uint32_t modCount{ 0 };

            bool isWeap{ false }, isArmo{ false }, isAlch{ false };

            // weapon
            double        dmg{ 0.0 }, firerate{ 0.0 }, rpm{ 0.0 }, range{ 0.0 };
            bool          haveAcc{ false };  double acc{ 0.0 };
            bool          haveAmmo{ false }; std::uint32_t ammoFormID{ 0 };
            char          ammoName[128]{};
            char          weapName[128]{};

            // armor
            double        dr{ 0.0 };
            bool          haveEr{ false };   double er{ 0.0 };
            bool          haveRr{ false };   double rr{ 0.0 };

            // aid
            bool          haveMagDur{ false };
            double        magnitude{ 0.0 }, duration{ 0.0 }, addiction{ 0.0 };

            // shared effect string (armor enchantment name / aid magic-effect name)
            bool          haveEffect{ false };
            char          effect[128]{};
        };

        // POD-only C-string copy (no std::string) so it is safe to call from inside the SEH leaf.
        inline void CopyCStr(char* a_dst, std::size_t a_cap, const char* a_src) noexcept
        {
            if (!a_dst || a_cap == 0) { return; }
            a_dst[0] = '\0';
            if (!a_src) { return; }
            std::size_t i = 0;
            for (; i + 1 < a_cap && a_src[i] != '\0'; ++i) { a_dst[i] = a_src[i]; }
            a_dst[i] = '\0';
        }

        // POD-only string_view copy (magic-effect / favorite names arrive as a string_view).
        inline void CopySV(char* a_dst, std::size_t a_cap, std::string_view a_src) noexcept
        {
            if (!a_dst || a_cap == 0) { return; }
            std::size_t n = a_src.size();
            if (n >= a_cap) { n = a_cap - 1; }
            for (std::size_t i = 0; i < n; ++i) { a_dst[i] = a_src[i]; }
            a_dst[n] = '\0';
        }

        // POD-only case-insensitive substring test (replaces the std::string lowercase+find, which would
        // pull an unwinding object into the SEH leaf).
        inline bool ContainsCI(const char* a_hay, const char* a_needle) noexcept
        {
            if (!a_hay || !a_needle) { return false; }
            for (std::size_t i = 0; a_hay[i] != '\0'; ++i) {
                std::size_t j = 0;
                while (a_needle[j] != '\0' &&
                       std::tolower(static_cast<unsigned char>(a_hay[i + j])) ==
                       std::tolower(static_cast<unsigned char>(a_needle[j]))) {
                    ++j;
                }
                if (a_needle[j] == '\0') { return true; }
            }
            return false;
        }

        // Rate-limited (first few only) note when the SEH net swallows a bad item, so the trip is visible in
        // the log without spamming. Lives OUTSIDE any __try (it constructs a formatted string).
        void LogItemGuardFired(std::uint32_t a_formID)
        {
            static int s_fired = 0;
            if (s_fired < 4) {
                ++s_fired;
                logger::info("[PipOS] itemstats: SEH net skipped a malformed modded item (formID {:08X}); menu stays up", a_formID);
            }
        }

        // 0.0.59 INSTANCE-DATA RESOLUTION (the "every gun says DAMAGE 17 / ACC 0" fix). The base weapon record
        // carries only AUTHORED values -- the real damage/fire-rate/aim-cone of a modded gun lives in the OMOD
        // deltas (receivers especially), which the engine resolves via TESBoundObject::ApplyMods into a fresh
        // per-instance data block. Both helpers are SEH leaves (POD/reference params only, no unwinding locals)
        // so a malformed modded item degrades to base values instead of crashing the menu.
        [[nodiscard]] RE::BGSObjectInstanceExtra* GetInstanceExtraSEH(RE::BGSInventoryItem::Stack* a_stack) noexcept
        {
            __try {
                if (a_stack) {
                    if (auto* extra = a_stack->extra.get()) {
                        return extra->GetByType<RE::BGSObjectInstanceExtra>();
                    }
                }
            } __except (EXCEPTION_EXECUTE_HANDLER) {}
            return nullptr;
        }

        void ResolveInstanceSEH(RE::TESBoundObject*                          a_obj,
                                const RE::BGSObjectInstanceExtra*            a_oie,
                                RE::BSTSmartPointer<RE::TBO_InstanceData>&   a_inst) noexcept
        {
            __try {
                a_obj->ApplyMods(a_inst, a_oie);
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                // leave a_inst as delivered (typically null) -> caller falls back to the base record
            }
        }

        // SEH CONTAINMENT NET (defense-in-depth). Reads ONE inventory item's raw native data into the POD
        // out-param. An access violation on any single unusual modded item (Complex Sorter / FIS instance
        // data) is caught here and reported via out.ok=false, so the caller skips that one item instead of
        // the whole Pip-Boy menu crashing. NOTHING with a non-trivial destructor may be declared in this
        // function body (std::string / std::vector / Scaleform value) -- that would trip C2712. std::span
        // and std::string_view are trivially destructible and therefore allowed. a_inst (may be null) is the
        // caller-owned OMOD-resolved instance data; when present it REPLACES the base record's numbers.
        [[nodiscard]] bool ExtractItemRaw(RE::TESBoundObject* a_obj, RE::BGSInventoryItem::Stack* a_stack, const RE::TBO_InstanceData* a_inst, ItemRawPOD& a_out) noexcept
        {
            __try {
                a_out.type = CategoryFor(a_obj->GetFormType());

                // ---- installed OMOD ids (THE reported crash site) ----------------------------------------
                // GetIndexData() unconditionally does `return values->GetBuffer<...>(0)`; GetBuffer -> GetBlock
                // reads values->buffer at [values+0x00]. A Complex Sorter OMOD can leave `values`
                // (BSTDataBuffer<1>* @0x18) null -> `mov r11,[rax]` with rax=0 -> EXCEPTION_ACCESS_VIOLATION.
                // Guard the exact pointer GetIndexData derefs, then guard the returned span's data.
                if (a_stack) {
                    if (auto* extra = a_stack->extra.get()) {
                        if (auto* oie = extra->GetByType<RE::BGSObjectInstanceExtra>()) {
                            if (oie->values) {                            // guard 1: null index-data buffer ptr
                                const auto idx = oie->GetIndexData();
                                if (idx.data() != nullptr) {              // guard 2: null span data
                                    for (const auto& d : idx) {
                                        if (a_out.modCount >= kMaxModsPerItem) { break; }
                                        if (d.disabled != 0) { continue; }
                                        a_out.modIDs[a_out.modCount++] = d.objectID;
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- per-type stat numbers / strings -----------------------------------------------------
                if (auto* weap = a_obj->As<RE::TESObjectWEAP>()) {
                    a_out.isWeap = true;
                    // 0.0.59: prefer the OMOD-resolved instance data (real modded damage / fire rate / aim cone /
                    // ammo); the base record is the fallback for stacks with no instance extra.
                    const auto& wd = (a_inst != nullptr)
                        ? *static_cast<const RE::TESObjectWEAP::InstanceData*>(a_inst)
                        : weap->weaponData;
                    // WEAPON STAT MAPPING (all plain member reads off TESObjectWEAP::Data, no engine calls;
                    // these are the UNMODDED authored base values -- per-instance mod deltas are intentionally
                    // NOT applied, see "HONEST SCOPE" above -- and the AS card rounds each to an integer):
                    //   dmg  = attackDamage (0x132) -- authored base ballistic damage per shot. The vanilla
                    //          card's headline DAMAGE; InvPage presents ENERGY as 0.35x of this.
                    //   firerate = 10 * speed / attackDelaySec -- the vanilla Pip-Boy "FIRE RATE" derived stat,
                    //          i.e. shots-per-10-seconds. The engine's own formula is
                    //          secondsPerShot = attackDelaySec / speed, then rate = 10 / secondsPerShot. A fast
                    //          SMG (e.g. FN P90: short attackDelaySec, speed >= 1) now reads a HIGH number
                    //          instead of the old bogus "2". The old value pushed `speed` ALONE (the attack-anim
                    //          speed multiplier, ~1-2), which is NOT a fire rate. Divide is guarded: a 0/negative
                    //          authored delay (rare; a few weapons are pure animation-driven) falls back to
                    //          `speed` so we never divide by zero, matching the engine's own "nonsensical for a
                    //          handful of records" behaviour rather than emitting a wilder number.
                    //   range = maxRange (0x0D4) -- authored max range in game units (bigger = longer reach).
                    //          Directional proxy: the vanilla card applies an internal scale we do not replicate
                    //          without an engine call, so this is the raw authored ceiling, not the 0-100 card value.
                    //   acc   = aim-cone proxy (below) -- 100 - minConeDegrees*40, clamped 0-100. Lower cone =>
                    //          tighter => higher acc. A DLL-derived stand-in for the engine's exact accuracy stat.
                    a_out.dmg = static_cast<double>(wd.attackDamage);
                    {
                        const float delay = wd.attackDelaySec;
                        const float spd   = wd.speed;
                        a_out.firerate = (delay > 0.001f)
                            ? static_cast<double>(10.0f * spd / delay)
                            : static_cast<double>(spd);
                        // rpm = rounds-per-minute = 60 * speed / attackDelaySec == 6 * firerate. SAME guarded
                        // divide (0/negative authored delay falls back to 6*speed, i.e. 6x the firerate fallback)
                        // so we never divide by zero. POD double; the AS card rounds it to an int like firerate.
                        a_out.rpm = (delay > 0.001f)
                            ? static_cast<double>(60.0f * spd / delay)
                            : static_cast<double>(6.0f * spd);
                    }
                    a_out.range = static_cast<double>(wd.maxRange);
                    if (wd.aimModel) {
                        const float cone = wd.aimModel->aimModelData.aimModelMinConeDegrees;
                        float acc = 100.0f - cone * 40.0f;
                        if (acc < 0.0f) { acc = 0.0f; } else if (acc > 100.0f) { acc = 100.0f; }
                        a_out.acc = static_cast<double>(acc);
                        a_out.haveAcc = true;
                    }
                    if (auto* am = wd.ammo) {
                        const char* an = am->GetFullName();
                        if (an && an[0] != '\0') {
                            CopyCStr(a_out.ammoName, sizeof(a_out.ammoName), an);
                            a_out.haveAmmo = true;
                            a_out.ammoFormID = am->GetFormID();
                            const char* wn = weap->GetFullName();
                            CopyCStr(a_out.weapName, sizeof(a_out.weapName), wn);
                        }
                    }
                } else if (auto* armo = a_obj->As<RE::TESObjectARMO>()) {
                    a_out.isArmo = true;
                    // 0.0.59: same instance-data preference for armor (misc-mod DR deltas, lining enchantments).
                    const auto& ad = (a_inst != nullptr)
                        ? *static_cast<const RE::TESObjectARMO::InstanceData*>(a_inst)
                        : armo->armorData;
                    a_out.dr = static_cast<double>(ad.rating);
                    if (ad.damageTypes) {
                        for (const auto& dt : *ad.damageTypes) {
                            auto* dmgType = dt.first ? dt.first->As<RE::BGSDamageType>() : nullptr;
                            if (!dmgType || !dmgType->data.resistance) { continue; }
                            const char* eid = dmgType->data.resistance->formEditorID.c_str();
                            if (!eid) { continue; }
                            const double v = static_cast<double>(dt.second.f);
                            if (ContainsCI(eid, "energy")) { a_out.er = v; a_out.haveEr = true; }
                            else if (ContainsCI(eid, "rad")) { a_out.rr = v; a_out.haveRr = true; }
                        }
                    }
                    if (ad.enchantments && !ad.enchantments->empty()) {
                        auto* ench = ad.enchantments->front();
                        const char* en = ench ? ench->GetFullName() : nullptr;
                        if (en && en[0] != '\0') {
                            CopyCStr(a_out.effect, sizeof(a_out.effect), en);
                            a_out.haveEffect = true;
                        }
                    }
                } else if (auto* alch = a_obj->As<RE::AlchemyItem>()) {
                    a_out.isAlch = true;
                    if (!alch->listOfEffects.empty()) {
                        auto* ei = alch->listOfEffects.front();
                        if (ei) {
                            if (ei->effectSetting) {
                                const auto sv = RE::TESFullName::GetFullName(*ei->effectSetting);
                                if (!sv.empty()) {
                                    CopySV(a_out.effect, sizeof(a_out.effect), sv);
                                    a_out.haveEffect = true;
                                }
                            }
                            a_out.magnitude = static_cast<double>(ei->data.magnitude);
                            a_out.duration = static_cast<double>(ei->data.duration);
                            a_out.haveMagDur = true;
                        }
                    }
                    a_out.addiction = static_cast<double>(alch->data.addictionChance * 100.0f);
                }

                a_out.ok = true;
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                a_out.ok = false;
            }
            return a_out.ok;
        }

        // POD carrier + SEH leaf for one favorite slot. storedFavTypes[i] can be a stale/dangling pointer
        // (non-null but pointing at a freed form) after Complex Sorter reshuffles, so even reading GetFormID()
        // off it can AV -- contain it the same way.
        struct FavRawPOD
        {
            bool          ok{ false };
            bool          filled{ false };
            std::uint32_t formID{ 0 };
            const char*   type{ "misc" };
            char          name[128]{};
        };

        [[nodiscard]] bool ReadFavoriteRaw(RE::FavoritesManager* a_fm, std::size_t a_slot, FavRawPOD& a_out) noexcept
        {
            __try {
                RE::TESBoundObject* obj = a_fm ? a_fm->storedFavTypes[a_slot] : nullptr;
                if (obj) {
                    a_out.formID = obj->GetFormID();
                    a_out.type = CategoryFor(obj->GetFormType());
                    const auto sv = RE::TESFullName::GetFullName(*obj);
                    CopySV(a_out.name, sizeof(a_out.name), sv);
                    a_out.filled = true;
                }
                a_out.ok = true;
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                a_out.ok = false;
            }
            return a_out.ok;
        }

        void PushItemStatsNow(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            auto* movieRoot = a_view->asMovieRoot.get();
            if (!movieRoot) { return; }

            Scaleform::GFx::Value root;
            if (!a_view->GetVariable(std::addressof(root), "root1") || !root.IsObject()) {
                logger::info("[PipOS] itemstats: root1 not ready; skipping push");
                return;
            }

            Scaleform::GFx::Value statsMap, modsMap;
            movieRoot->CreateObject(std::addressof(statsMap));
            movieRoot->CreateObject(std::addressof(modsMap));
            if (!statsMap.IsObject() || !modsMap.IsObject()) {
                logger::error("[PipOS] itemstats: CreateObject failed; skipping");
                return;
            }

            // Aux tables from the single inventory pass (used for ammo "used by" + favorite counts).
            std::unordered_map<std::uint32_t, std::string> ammoUsedBy;  // ammo formID -> a weapon name
            std::unordered_map<std::uint32_t, std::uint32_t> countByForm;  // base formID -> total count
            int nStats = 0, nMods = 0;

            auto keyOf = [](std::uint32_t a_id) {
                char b[16]; std::snprintf(b, sizeof(b), "%u", a_id); return std::string(b);
            };

            try {
                auto* pc = RE::PlayerCharacter::GetSingleton();
                if (pc && pc->inventoryList) {
                    pc->inventoryList->ForEachStack(
                        [](RE::BGSInventoryItem& a_item) -> bool { return a_item.object != nullptr; },
                        [&](RE::BGSInventoryItem& a_item, RE::BGSInventoryItem::Stack& a_stack) -> bool {
                            RE::TESBoundObject* obj = a_item.object;
                            if (!obj) { return true; }
                            const std::uint32_t id = obj->GetFormID();
                            countByForm[id] += a_stack.GetCount();
                            if (static_cast<std::size_t>(nStats) >= kMaxStatEntries) { return true; }

                            const std::string key = keyOf(id);

                            const bool needMods  = (modsMap.HasMember(key.c_str()) == false);
                            const bool needStats = (statsMap.HasMember(key.c_str()) == false);
                            if (!needMods && !needStats) { return true; }  // first stack per formID wins

                            // SEH-contained raw read: any AV on this one (Complex Sorter / FIS) modded item is
                            // swallowed and the item skipped, instead of crashing the whole Pip-Boy menu. POD
                            // out only; every std::string / std::vector / Scaleform value below is built OUTSIDE
                            // the SEH from this POD.
                            ItemRawPOD pod{};
                            // 0.0.59: resolve the stack's OMOD instance data first (SEH-leaf helpers; smart
                            // pointer owned HERE, outside any __try) so the raw read reports the REAL modded
                            // numbers instead of the base record's (the "every gun is DAMAGE 17" bug).
                            RE::BSTSmartPointer<RE::TBO_InstanceData> inst;
                            if (auto* oie = GetInstanceExtraSEH(std::addressof(a_stack))) {
                                ResolveInstanceSEH(obj, oie, inst);
                            }
                            if (!ExtractItemRaw(obj, std::addressof(a_stack), inst.get(), pod)) {
                                LogItemGuardFired(id);
                                return true;
                            }

                            // ---- installed mods (weapons + armor) -> modsMap[key] = [names...] ----
                            if (needMods && pod.modCount > 0) {
                                std::vector<std::string> mods;
                                mods.reserve(pod.modCount);
                                for (std::uint32_t i = 0; i < pod.modCount; ++i) {
                                    auto* mod = RE::TESForm::GetFormByID<RE::BGSMod::Attachment::Mod>(pod.modIDs[i]);
                                    if (!mod) { continue; }
                                    const char* mn = mod->GetFullName();
                                    if (mn && mn[0] != '\0') { mods.emplace_back(mn); }
                                }
                                if (!mods.empty()) {
                                    Scaleform::GFx::Value arr;
                                    movieRoot->CreateArray(std::addressof(arr));
                                    if (arr.IsArray()) {
                                        for (auto& m : mods) {
                                            Scaleform::GFx::Value s;
                                            movieRoot->CreateString(std::addressof(s), m.c_str());
                                            arr.PushBack(s);
                                        }
                                        modsMap.SetMember(key.c_str(), arr);
                                        ++nMods;
                                    }
                                }
                            }

                            // ---- per-type stats -> statsMap[key] ----
                            if (!needStats) { return true; }
                            Scaleform::GFx::Value entry;
                            movieRoot->CreateObject(std::addressof(entry));
                            if (!entry.IsObject()) { return true; }
                            Scaleform::GFx::Value stype;
                            movieRoot->CreateString(std::addressof(stype), pod.type);
                            entry.SetMember("type", stype);

                            if (pod.isWeap) {
                                entry.SetMember("dmg", Scaleform::GFx::Value(pod.dmg));
                                entry.SetMember("firerate", Scaleform::GFx::Value(pod.firerate));
                                entry.SetMember("rpm", Scaleform::GFx::Value(pod.rpm));
                                entry.SetMember("range", Scaleform::GFx::Value(pod.range));
                                if (pod.haveAcc) { entry.SetMember("acc", Scaleform::GFx::Value(pod.acc)); }
                                if (pod.haveAmmo) {
                                    Scaleform::GFx::Value sa;
                                    movieRoot->CreateString(std::addressof(sa), pod.ammoName);
                                    entry.SetMember("ammo", sa);
                                    if (ammoUsedBy.find(pod.ammoFormID) == ammoUsedBy.end() && pod.weapName[0] != '\0') {
                                        ammoUsedBy[pod.ammoFormID] = pod.weapName;
                                    }
                                }
                            } else if (pod.isArmo) {
                                entry.SetMember("dr", Scaleform::GFx::Value(pod.dr));
                                if (pod.haveEr) { entry.SetMember("er", Scaleform::GFx::Value(pod.er)); }
                                if (pod.haveRr) { entry.SetMember("rr", Scaleform::GFx::Value(pod.rr)); }
                                if (pod.haveEffect) {
                                    Scaleform::GFx::Value se;
                                    movieRoot->CreateString(std::addressof(se), pod.effect);
                                    entry.SetMember("effect", se);
                                }
                            } else if (pod.isAlch) {
                                if (pod.haveEffect) {
                                    Scaleform::GFx::Value se;
                                    movieRoot->CreateString(std::addressof(se), pod.effect);
                                    entry.SetMember("effect", se);
                                }
                                if (pod.haveMagDur) {
                                    entry.SetMember("magnitude", Scaleform::GFx::Value(pod.magnitude));
                                    entry.SetMember("duration", Scaleform::GFx::Value(pod.duration));
                                }
                                entry.SetMember("addiction", Scaleform::GFx::Value(pod.addiction));
                            }
                            // ammo "used by" is resolved in a second sweep below (needs the full weapon table).

                            statsMap.SetMember(key.c_str(), entry);
                            ++nStats;
                            return true;
                        });
                } else {
                    logger::info("[PipOS] itemstats: player/inventoryList null; pushing empty maps");
                }
            } catch (...) {
                logger::error("[PipOS] itemstats: native read threw; degrading to partial maps");
            }

            // Second sweep: fill ammo "used by" now that the weapon->ammo table is complete.
            try {
                if (auto* pc = RE::PlayerCharacter::GetSingleton(); pc && pc->inventoryList) {
                    for (auto& kv : ammoUsedBy) {
                        const std::string key = keyOf(kv.first);
                        if (!statsMap.HasMember(key.c_str())) { continue; }
                        Scaleform::GFx::Value entry;
                        if (!statsMap.GetMember(key.c_str(), std::addressof(entry)) || !entry.IsObject()) { continue; }
                        Scaleform::GFx::Value su;
                        movieRoot->CreateString(std::addressof(su), kv.second.c_str());
                        entry.SetMember("usedby", su);
                    }
                }
            } catch (...) {
                logger::error("[PipOS] itemstats: ammo used-by sweep threw; skipped");
            }

            root.SetMember("PipOS_itemstats", statsMap);
            root.SetMember("PipOS_itemmods", modsMap);
            logger::info("[PipOS] itemstats: pushed {} stat entries, {} mod lists", nStats, nMods);

            // ---- favorites (12 Pip-Boy quick-key slots) -> root1.PipOS_favorites ----
            try {
                Scaleform::GFx::Value favArr;
                movieRoot->CreateArray(std::addressof(favArr));
                if (favArr.IsArray()) {
                    auto* fm = RE::FavoritesManager::GetSingleton();
                    int nFav = 0;
                    for (std::size_t i = 0; i < kMaxFavorites; ++i) {
                        Scaleform::GFx::Value fe;
                        movieRoot->CreateObject(std::addressof(fe));
                        if (!fe.IsObject()) { continue; }
                        fe.SetMember("slot", Scaleform::GFx::Value(static_cast<double>(i)));
                        // SEH-contained slot read: storedFavTypes[i] can be a stale/dangling pointer after a
                        // Complex Sorter reshuffle, so even reading GetFormID() off it can AV. Contain it; POD
                        // out only, the Scaleform values are built OUTSIDE the SEH from the POD.
                        FavRawPOD fav{};
                        const bool favOK = ReadFavoriteRaw(fm, i, fav);
                        if (favOK && fav.filled) {
                            const std::uint32_t id = fav.formID;
                            Scaleform::GFx::Value sid, snm, stp;
                            movieRoot->CreateString(std::addressof(sid), keyOf(id).c_str());
                            movieRoot->CreateString(std::addressof(snm), fav.name);
                            movieRoot->CreateString(std::addressof(stp), fav.type);
                            fe.SetMember("formID", sid);
                            fe.SetMember("name", snm);
                            fe.SetMember("type", stp);
                            const auto it = countByForm.find(id);
                            fe.SetMember("count", Scaleform::GFx::Value(static_cast<double>(it != countByForm.end() ? it->second : 0u)));
                            ++nFav;
                        } else {
                            if (!favOK) { LogItemGuardFired(0u); }
                            Scaleform::GFx::Value empty;
                            movieRoot->CreateString(std::addressof(empty), "");
                            fe.SetMember("formID", Scaleform::GFx::Value(0.0));
                            fe.SetMember("name", empty);
                            fe.SetMember("type", empty);
                            fe.SetMember("count", Scaleform::GFx::Value(0.0));
                        }
                        favArr.PushBack(fe);
                    }
                    root.SetMember("PipOS_favorites", favArr);
                    logger::info("[PipOS] favorites: pushed {} filled of {} slots", nFav, kMaxFavorites);
                }
            } catch (...) {
                logger::error("[PipOS] favorites: native read threw; skipped");
            }
        }

        // 0.0.38 - NATIVE CUSTOMIZATION PUSH. Writes the F4SE-Menu-Framework-editable settings onto root1 as
        // a plain AS3 object root1.PipOS_settings = { veil:<Number>, breathe:<Boolean>, openAnim:<Boolean>,
        // folders:<Boolean>, showRPM:<Boolean> }. ADDITIVE ONLY: the equip / iteminfo / itemstats / favorites pushes and the
        // chrome attach are untouched. The AS3 (Chrome.as, PipOS_InvPage.as) reads these with FALLBACK to its
        // own const defaults whenever the object or a member is absent, so an old shell / a missing DLL / a
        // marshalling failure all degrade to EXACTLY 0.0.37 behavior. Same UI-task thread + root1 readiness
        // guard as the other pushes; try/catch degrades a failed push to the AS fallbacks (never a CTD).
        // NOTE (scope): bLive3D is NOT pushed here -- the live-3D gate is evaluated ONCE at load in
        // CharacterCapture::Install() (that AV-audited gate is deliberately left byte-for-byte), so pushing it
        // to the running movie would have no effect. The menu page still edits + persists it for next launch.
        void PushSettingsNow(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            auto* movieRoot = a_view->asMovieRoot.get();
            if (!movieRoot) { return; }

            Scaleform::GFx::Value root;
            if (!a_view->GetVariable(std::addressof(root), "root1") || !root.IsObject()) {
                logger::info("[PipOS] settings: root1 not ready; skipping push");
                return;
            }

            auto* s = Settings::GetSingleton();
            if (!s) { return; }

            try {
                Scaleform::GFx::Value obj;
                movieRoot->CreateObject(std::addressof(obj));
                if (!obj.IsObject()) { logger::error("[PipOS] settings: CreateObject failed; skipping"); return; }
                obj.SetMember("veil", Scaleform::GFx::Value(static_cast<double>(s->VeilAlpha())));
                obj.SetMember("breathe", Scaleform::GFx::Value(s->CrtBreathe()));
                obj.SetMember("openAnim", Scaleform::GFx::Value(s->OpenAnim()));
                obj.SetMember("folders", Scaleform::GFx::Value(s->Folders()));
                obj.SetMember("showRPM", Scaleform::GFx::Value(s->ShowRPM()));
                root.SetMember("PipOS_settings", obj);
                logger::info("[PipOS] settings: pushed veil={} breathe={} openAnim={} folders={} showRPM={}",
                    s->VeilAlpha(), s->CrtBreathe(), s->OpenAnim(), s->Folders(), s->ShowRPM());
            } catch (...) {
                logger::error("[PipOS] settings: marshalling threw; skipped (AS uses const fallbacks)");
            }
        }

        // 16:9 FEASIBILITY SPIKE (round 27, throwaway, opt-in via [Widescreen] WidescreenSpike; default 0 =
        // never called => shipping behavior byte-unchanged at runtime). Measures what actually governs the
        // Pip-Boy render aspect, IN-GAME: the render-target/viewport dims, the Scaleform scale mode, the
        // movie's visible frame rect (the true usable coordinate space the pages author against), and Baka's
        // root1 transform (its ~0.92 scale / x=35 fullscreen fit). All reads null/try-guarded. Level 2 also
        // runs a reversible experiment (switch scale mode to reveal whether a wider authoring frame exists).
        void DiagnoseViewport(Scaleform::GFx::Movie* a_view, int a_level)
        {
            if (!a_view || a_level <= 0) { return; }
            try {
                Scaleform::GFx::Viewport vp{};
                a_view->GetViewport(std::addressof(vp));
                const auto sm = a_view->GetViewScaleMode();
                const auto fr = a_view->GetVisibleFrameRect();
                logger::info("[PipOS][WSSPIKE] RTT buffer={}x{}  viewRect=({},{} {}x{})  gfxScale={}  aspect={}",
                    vp.bufferWidth, vp.bufferHeight, vp.left, vp.top, vp.width, vp.height, vp.scale, vp.aspectRatio);
                logger::info("[PipOS][WSSPIKE] scaleMode={} (0=NoScale 1=ShowAll 2=ExactFit 3=NoBorder)  visibleFrameRect=({},{} .. {},{})  usable={}x{} movie-units",
                    static_cast<int>(sm), fr.x1, fr.y1, fr.x2, fr.y2, (fr.x2 - fr.x1), (fr.y2 - fr.y1));
                Scaleform::GFx::Value rx, ry, rsx, rsy;
                double vx = 0, vy = 0, vsx = 0, vsy = 0;
                if (a_view->GetVariable(std::addressof(rx), "root1.x")) { vx = rx.GetNumber(); }
                if (a_view->GetVariable(std::addressof(ry), "root1.y")) { vy = ry.GetNumber(); }
                if (a_view->GetVariable(std::addressof(rsx), "root1.scaleX")) { vsx = rsx.GetNumber(); }
                if (a_view->GetVariable(std::addressof(rsy), "root1.scaleY")) { vsy = rsy.GetNumber(); }
                logger::info("[PipOS][WSSPIKE] root1 transform: x={} y={} scaleX={} scaleY={} (Baka fullscreen fit lives here)", vx, vy, vsx, vsy);

                if (a_level >= 2) {
                    // Reversible probe: does a border-filling scale mode reveal a wider usable frame? If the
                    // viewport is already 16:9 (Baka's 16:9 background) but the frame is ShowAll-pillarboxed to
                    // 5:4, NoBorder should widen visibleFrameRect. Baka may re-assert its transform next frame.
                    const auto prev = static_cast<int>(sm);
                    a_view->SetViewScaleMode(Scaleform::GFx::Movie::ScaleModeType::kNoBorder);
                    a_view->SetViewAlignment(Scaleform::GFx::Movie::AlignType::kCenter);
                    const auto fr2 = a_view->GetVisibleFrameRect();
                    logger::info("[PipOS][WSSPIKE][EXP] scaleMode {}->NoBorder: visibleFrameRect now ({},{} .. {},{}) usable={}x{}",
                        prev, fr2.x1, fr2.y1, fr2.x2, fr2.y2, (fr2.x2 - fr2.x1), (fr2.y2 - fr2.y1));
                }
            } catch (...) {
                logger::error("[PipOS][WSSPIKE] viewport diagnostic threw; skipped");
            }
        }

        // 16:9 RE-AUTHOR (0.0.24) - UNCONDITIONAL transform-chain log on every Pip-Boy open (INFO level, NOT
        // behind the spike flag). The pages author in root1-local coordinates but actually render under
        // root1.Menu_mc; this logs BOTH transforms (root1 AND root1.Menu_mc) plus the visible frame rect so
        // the first widescreen screenshot + this log line pin down any origin correction to a single Theme
        // knob (FX/FY/MS). All reads null/try-guarded, read-only. The WidescreenSpike diagnostic is untouched.
        void LogTransformChain(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            try {
                Scaleform::GFx::Value v;
                double rx = 0, ry = 0, rsx = 0, rsy = 0, mmx = 0, mmy = 0, msx = 0, msy = 0;
                if (a_view->GetVariable(std::addressof(v), "root1.x")) { rx = v.GetNumber(); }
                if (a_view->GetVariable(std::addressof(v), "root1.y")) { ry = v.GetNumber(); }
                if (a_view->GetVariable(std::addressof(v), "root1.scaleX")) { rsx = v.GetNumber(); }
                if (a_view->GetVariable(std::addressof(v), "root1.scaleY")) { rsy = v.GetNumber(); }
                const bool haveMenu = a_view->GetVariable(std::addressof(v), "root1.Menu_mc.x");
                if (haveMenu) { mmx = v.GetNumber(); }
                if (a_view->GetVariable(std::addressof(v), "root1.Menu_mc.y")) { mmy = v.GetNumber(); }
                if (a_view->GetVariable(std::addressof(v), "root1.Menu_mc.scaleX")) { msx = v.GetNumber(); }
                if (a_view->GetVariable(std::addressof(v), "root1.Menu_mc.scaleY")) { msy = v.GetNumber(); }
                const auto fr = a_view->GetVisibleFrameRect();
                logger::info("[PipOS][XFORM] root1: x={} y={} scaleX={} scaleY={} | Menu_mc(present={}): x={} y={} scaleX={} scaleY={} | visibleFrameRect=({},{} .. {},{}) usable={}x{} movie-units",
                    rx, ry, rsx, rsy, haveMenu, mmx, mmy, msx, msy, fr.x1, fr.y1, fr.x2, fr.y2, (fr.x2 - fr.x1), (fr.y2 - fr.y1));
            } catch (...) {
                logger::error("[PipOS][XFORM] transform-chain log threw; skipped");
            }
        }

        // 0.0.51 STAT-INSTALL DIAGNOSTIC. The custom Stats page renders in preview but never appears in game, and
        // PipboyTabs' contract (Menu_mc.getChildAt(4)._TabNames) wedges when the current-page slot is not a live
        // page. This logs GROUND TRUTH on every open: each Menu_mc child's class (toString), whether it exposes
        // _TabNames (a live PipboyPage) and its length, whether it exposes debugRects (OUR page marker), plus
        // CurrentPage/CurrentTab. Read-only, fully guarded; one log block per open decides the diagnosis.
        void LogMenuChildren(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            try {
                Scaleform::GFx::Value v;
                double nc = -1.0;
                if (a_view->GetVariable(std::addressof(v), "root1.Menu_mc.numChildren") && v.IsNumber()) { nc = v.GetNumber(); }
                double curPage = -1.0, curTab = -1.0;
                if (a_view->GetVariable(std::addressof(v), "root1.Menu_mc.DataObj.CurrentPage") && v.IsNumber()) { curPage = v.GetNumber(); }
                if (a_view->GetVariable(std::addressof(v), "root1.Menu_mc.DataObj.CurrentTab") && v.IsNumber()) { curTab = v.GetNumber(); }
                logger::info("[PipOS][MENUKIDS] Menu_mc numChildren={} CurrentPage={} CurrentTab={}", nc, curPage, curTab);
                Scaleform::GFx::Value menu;
                if (!a_view->GetVariable(std::addressof(menu), "root1.Menu_mc") || !menu.IsObject()) { return; }
                const int count = (nc >= 0.0 && nc < 12.0) ? static_cast<int>(nc) : 8;
                for (int i = 0; i < count; ++i) {
                    Scaleform::GFx::Value child;
                    Scaleform::GFx::Value idx(static_cast<double>(i));
                    if (!menu.Invoke("getChildAt", std::addressof(child), std::addressof(idx), 1) || !child.IsObject()) {
                        logger::info("[PipOS][MENUKIDS]   [{}] <getChildAt failed>", i);
                        continue;
                    }
                    const char* cls = "?";
                    Scaleform::GFx::Value str;
                    if (child.Invoke("toString", std::addressof(str), nullptr, 0) && str.IsString()) { cls = str.GetString(); }
                    const char* nm = "?";
                    Scaleform::GFx::Value nmv;
                    if (child.GetMember("name", std::addressof(nmv)) && nmv.IsString()) { nm = nmv.GetString(); }
                    bool hasTabs = false; double tabLen = -1.0;
                    Scaleform::GFx::Value tabs;
                    if (child.GetMember("_TabNames", std::addressof(tabs)) && tabs.IsArray()) { hasTabs = true; tabLen = static_cast<double>(tabs.GetArraySize()); }
                    const bool ours = child.HasMember("debugRects");
                    logger::info("[PipOS][MENUKIDS]   [{}] class={} name={} _TabNames={} (len={}) pipos-page={}",
                        i, cls, nm, hasTabs, tabLen, ours);
                }
                // 0.0.52: shell page-machine state. CurrentPage is the shell's PUBLIC getter (PageA[cur].content
                // as PipboyPage) -- null here while a child slot claims a page pins the CAST-NULL failure mode.
                // _IsLoadingPage is the wedge flag: the vanilla shell registers NO error handler and its
                // onPageLoadComplete calls InitCodeObj on the cast result with NO null check, so a failed page
                // load/cast leaves _IsLoadingPage stuck true and InvalidatePartialData dead menu-wide (the lockup).
                Scaleform::GFx::Value pg;
                if (a_view->GetVariable(std::addressof(pg), "root1.Menu_mc.CurrentPage")) {
                    const char* pcls = "?";
                    Scaleform::GFx::Value pstr;
                    if (pg.IsObject() && pg.Invoke("toString", std::addressof(pstr), nullptr, 0) && pstr.IsString()) { pcls = pstr.GetString(); }
                    const bool pgNull = (pg.GetType() == Scaleform::GFx::Value::ValueType::kNull);
                    logger::info("[PipOS][MENUKIDS] shell CurrentPage getter: object={} null={} undefined={} class={}",
                        pg.IsObject(), pgNull, pg.IsUndefined(), pcls);
                } else {
                    logger::info("[PipOS][MENUKIDS] shell CurrentPage getter: <unreadable>");
                }
                Scaleform::GFx::Value ldg;
                if (a_view->GetVariable(std::addressof(ldg), "root1.Menu_mc._IsLoadingPage") && ldg.IsBoolean()) {
                    logger::info("[PipOS][MENUKIDS] shell _IsLoadingPage={}", ldg.GetBoolean());
                } else {
                    logger::info("[PipOS][MENUKIDS] shell _IsLoadingPage=<unreadable (private)>");
                }
                // 0.0.52: lifecycle-breadcrumb trail (pipos.Theme.LIFE, mirrored by the chrome each tick). Shows
                // exactly how far each page class got: ST.c/p0/p1/p2/c1/s/t0/t1/eN for Stats, IV/DA/RA/CH controls.
                // NO "ST." marks after visiting STAT == our SWF was never instantiated (GFx load/parse failure);
                // marks present but page absent from the child list == the shell-side cast/handler failure.
                Scaleform::GFx::Value life;
                if (a_view->GetVariable(std::addressof(life), "root1.PipOS_chrome_loader.content.PipOS_life") && life.IsString()) {
                    logger::info("[PipOS][MENUKIDS] life-trail: {}", life.GetString());
                } else {
                    logger::info("[PipOS][MENUKIDS] life-trail: <unavailable (chrome not attached yet?)>");
                }
                // 0.0.59: ROOT1-LEVEL child sweep. If a button-hint bar (or anything else) survives at a level the
                // Menu_mc sweep can't see -- e.g. a bar cloned to root by another mod -- this names it: class, name,
                // y and visible per child. Cheap, read-only, runs in the same snapshots.
                Scaleform::GFx::Value r1;
                if (a_view->GetVariable(std::addressof(r1), "root1") && r1.IsObject()) {
                    double rnc = -1.0;
                    Scaleform::GFx::Value rn;
                    if (r1.GetMember("numChildren", std::addressof(rn)) && rn.IsNumber()) { rnc = rn.GetNumber(); }
                    const int rcount = (rnc >= 0.0 && rnc < 12.0) ? static_cast<int>(rnc) : 8;
                    logger::info("[PipOS][MENUKIDS] root1 numChildren={}", rnc);
                    for (int ri = 0; ri < rcount; ++ri) {
                        Scaleform::GFx::Value rchild;
                        Scaleform::GFx::Value ridx(static_cast<double>(ri));
                        if (!r1.Invoke("getChildAt", std::addressof(rchild), std::addressof(ridx), 1) || !rchild.IsObject()) {
                            logger::info("[PipOS][MENUKIDS]   root1[{}] <getChildAt failed>", ri);
                            continue;
                        }
                        const char* rcls = "?";
                        Scaleform::GFx::Value rstr;
                        if (rchild.Invoke("toString", std::addressof(rstr), nullptr, 0) && rstr.IsString()) { rcls = rstr.GetString(); }
                        const char* rnm = "?";
                        Scaleform::GFx::Value rnmv;
                        if (rchild.GetMember("name", std::addressof(rnmv)) && rnmv.IsString()) { rnm = rnmv.GetString(); }
                        double cy = 0.0; bool cvis = false;
                        Scaleform::GFx::Value cyv, cvv;
                        if (rchild.GetMember("y", std::addressof(cyv)) && cyv.IsNumber()) { cy = cyv.GetNumber(); }
                        if (rchild.GetMember("visible", std::addressof(cvv)) && cvv.IsBoolean()) { cvis = cvv.GetBoolean(); }
                        logger::info("[PipOS][MENUKIDS]   root1[{}] class={} name={} y={} visible={}", ri, rcls, rnm, cy, cvis);
                    }
                }
            } catch (...) {
                logger::error("[PipOS][MENUKIDS] diagnostic threw; skipped");
            }
        }

        // 0.0.59 SESSION FOLDER MEMORY. The Inv page mirrors its opened-folder state into root1.PipOS_folderMem
        // ("tab:KEY|KEY;tab:KEY"); the page (and root1) die with the menu, so we bank the string here at close
        // and re-seed it onto the fresh root1 at the next open. Session-scoped by design (not saved to disk).
        std::string s_folderMem{};

        void CaptureFolderMemNow(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view) { return; }
            try {
                Scaleform::GFx::Value v;
                if (a_view->GetVariable(std::addressof(v), "root1.PipOS_folderMem") && v.IsString()) {
                    s_folderMem = v.GetString();
                    logger::info("[PipOS] folderMem: captured '{}' at close", s_folderMem);
                }
            } catch (...) {}
        }

        void SeedFolderMemNow(Scaleform::GFx::Movie* a_view)
        {
            if (!a_view || s_folderMem.empty()) { return; }
            try {
                Scaleform::GFx::Value v(s_folderMem.c_str());
                if (a_view->SetVariable("root1.PipOS_folderMem", v)) {
                    logger::info("[PipOS] folderMem: re-seeded '{}' at open", s_folderMem);
                }
            } catch (...) {}
        }

        // 0.0.53: periodic life-trail capture while the Pip-Boy is open (~every 1.5-3s). With flush-on-write,
        // the last [LIFE] line before a crash brackets the crashing code path via the page breadcrumbs.
        bool g_lifeLogActive = false;
        void PeriodicLifeLog(int a_hops)
        {
            if (auto* task = F4SE::GetTaskInterface()) {
                task->AddUITask([a_hops]() {
                    if (a_hops > 0) { PeriodicLifeLog(a_hops - 1); return; }
                    if (auto* ui = RE::UI::GetSingleton()) {
                        if (auto menu = ui->GetMenu(kPipboyMenu)) {
                            if (auto* view = menu->uiMovie.get()) {
                                Scaleform::GFx::Value life;
                                if (view->GetVariable(std::addressof(life), "root1.PipOS_chrome_loader.content.PipOS_life") && life.IsString()) {
                                    logger::info("[PipOS][LIFE] {}", life.GetString());
                                }
                            }
                            PeriodicLifeLog(90);   // requeue while the Pip-Boy stays open
                            return;
                        }
                    }
                    g_lifeLogActive = false;   // Pip-Boy closed; stop the chain
                });
            }
        }

        // 0.0.52: re-log the MENUKIDS snapshot after a delay (page loads resolve a few frames after open; a late
        // snapshot separates "not loaded YET" from "never loads"). Chains UI tasks as a frame counter.
        void DelayedMenuSnapshot(int a_hops)
        {
            if (auto* task = F4SE::GetTaskInterface()) {
                task->AddUITask([a_hops]() {
                    if (a_hops > 0) { DelayedMenuSnapshot(a_hops - 1); return; }
                    if (auto* ui = RE::UI::GetSingleton()) {
                        if (auto menu = ui->GetMenu(kPipboyMenu)) {
                            logger::info("[PipOS][MENUKIDS] ---- delayed snapshot ----");
                            LogMenuChildren(menu->uiMovie.get());
                        }
                    }
                });
            }
        }

        class MenuSink : public RE::BSTEventSink<RE::MenuOpenCloseEvent>
        {
        public:
            RE::BSEventNotifyControl ProcessEvent(
                const RE::MenuOpenCloseEvent& a_event,
                RE::BSTEventSource<RE::MenuOpenCloseEvent>*) override
            {
                if (!a_event.opening && a_event.menuName == kPipboyMenu.data()) {
                    // 0.0.52: CLOSE-TIME snapshot -- captures the state that was actually on screen when the user
                    // closed the Pip-Boy (post-navigation), incl. the final life-trail. Synchronous but read-only
                    // and fully guarded; if the movie is already torn down every read fails harmlessly.
                    if (auto* ui = RE::UI::GetSingleton()) {
                        if (auto menu = ui->GetMenu(kPipboyMenu)) {
                            logger::info("[PipOS][MENUKIDS] ---- close snapshot ----");
                            LogMenuChildren(menu->uiMovie.get());
                            CaptureFolderMemNow(menu->uiMovie.get());   // 0.0.59: bank opened-folder state for the next open
                        }
                    }
                }
                if (a_event.opening && a_event.menuName == kPipboyMenu.data()) {
                    // Defer off the synchronous open dispatch (the movie is still being constructed on the
                    // UI thread during "opening"); run the attach on the next UI task, guarded, once loaded.
                    if (auto* task = F4SE::GetTaskInterface()) {
                        task->AddUITask([]() {
                            if (auto* ui = RE::UI::GetSingleton()) {
                                if (auto menu = ui->GetMenu(kPipboyMenu)) {
                                    auto* view = menu->uiMovie.get();
                                    LogTransformChain(view); // 0.0.24: unconditional root1/Menu_mc transform log
                                    LogMenuChildren(view);   // 0.0.51: STAT-install ground-truth diagnostic
                                    DelayedMenuSnapshot(45);  // 0.0.52: ~1s later (page loads resolved)
                                    DelayedMenuSnapshot(300); // 0.0.52: ~5-10s later (post-navigation)
                                    // 0.0.54: PeriodicLifeLog chain RETIRED -- it never produced a line in the
                                    // field (task-pump timing) and the open/close snapshots carry the trail
                                    // reliably. Left compiled but unstarted to avoid any pump-recursion risk.
                                    AttachChromeNow(view);
                                    PushEquipmentNow(view);  // 0.0.20: native worn-armor -> root1.PipOS_equip
                                    PushItemInfoNow(view);   // 0.0.23 P1-D: per-item WT/VAL/AMMO -> root1.PipOS_iteminfo
                                    PushItemStatsNow(view);  // 0.0.25: per-item stats + mods + favorites (formID-keyed)
                                    PushSettingsNow(view);   // 0.0.38: customization -> root1.PipOS_settings (veil/breathe/openAnim/folders)
                                    SeedFolderMemNow(view);  // 0.0.59: session folder memory -> root1.PipOS_folderMem
                                    if (auto* s = Settings::GetSingleton()) {
                                        DiagnoseViewport(view, s->WidescreenSpike());  // spike: default 0 = no-op
                                    }
                                }
                            }
                        });
                    }
                }
                return RE::BSEventNotifyControl::kContinue;
            }
        };
    }

    bool PipboyBridge::Install()
    {
        static MenuSink sink;
        auto* ui = RE::UI::GetSingleton();
        if (!ui) {
            logger::error("[PipOS] UI singleton unavailable; chrome bridge not installed");
            return false;
        }
        ui->RegisterSink(&sink);
        logger::info("[PipOS] Pip-Boy chrome bridge installed (DLL route; shell byte-identical)");
        return true;
    }
}
