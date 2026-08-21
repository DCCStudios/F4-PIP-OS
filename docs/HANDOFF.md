# PIP-OS Pip-Boy — Engineering Handoff

**Last updated:** 2026-08-21, during the **0.0.109** weapon attachment, STATUS radiation, sidebar artifact, and vanilla map restoration pass. Primary runtime checks are first-open and post-swap weapon alignment, actual radiation values on STATUS, artifact-free STATUS/MAP/RADIO selection, and the restored live vanilla world/local map inside the green frame.

This doc is written for another agent/developer picking up mid-stream. Read this top-to-bottom once, then keep the **[Decision tree for the next test](#live-3d--decision-tree-for-the-next-test)** and **[Things NOT to do](#things-not-to-do-hard-won)** sections open while you work.

The single richest source of running history is the project memory index at
`C:\Users\rober\.claude\projects\e--Fallout-4-Modding-F4SE\memory\pipos-pipboy-state.md`
(read the top entries first — newest is authoritative over older). This handoff distills and organizes what matters; the memory file has the blow-by-blow.

## Current status, 0.0.109 supersedes the older 0.0.76 live-3D snapshot below

**0.0.109 weapon hierarchy correction:** the 0.0.108 field log reports `flattened Weapon bone published: node=false`, but the attachment path still labeled its identity transform as `flattened-weapon-bone`. The promoted weapon clone also had its `Scb` geometry reparented directly to `RArm_Hand`, bypassing the promoted clone's Weapon transform. The new path resolves the hand-space local from the exact source partClone's nearest Weapon ancestor before cloning, uses the live biped resolver only as a fallback, promotes the complete clone to `Weapon` under `RArm_Hand`, and retains `Scb` beneath it. New telemetry reports `transformSource='source-weapon-ancestor'` or the fallback and `ScbRetained=true`. Runtime acceptance requires correct alignment on the first open, after switching among pistols and long guns, and after closing and reopening PIP-OS.

**0.0.109 STATUS, sidebar, and map correction:** native code now publishes the player's current `rads` actor value and plausible `RadHealthMax` pool at menu open and during the existing live equipment refresh. STATUS polls those shared values and updates its RADS value and fill only when they change. Each main and extension sidebar button now owns an isolated retained Graphics object, preventing STAT/MAP/RADIO icon paths from joining the active button fill into a triangular fan. The shipped Map page is restored byte-for-byte to the 93,570-byte transplanted engine-backed page used through 0.0.104. Chrome adds only a mouse-transparent green frame while page 3 is active, leaving vanilla `MapHolder`, `RegisterMap(this)`, world/local image loading, markers, pan, zoom, and fast travel under engine ownership.

**0.0.109 static delivery:** releasedbg `xmake build -y` passed. The Stats page and Chrome compile, `tools/verify_pages.ps1` passes for Stats, and the constructor-text gate passes. DLL and PDB are staged under root `Compile/F4SE/Plugins`. `dist/PipOSPipboy-TestA-0.0.109.zip` is layered from 0.0.108 and changes only the DLL, Stats, Chrome, Map, and FOMOD version metadata. The restored Map SHA-256 is `62789434164CFC527EE354B9A6C2139134731F2B1F875D33946D3C25352DF61F`, matching the preserved 0.0.104 transplant. DLL SHA-256 is `1E98BD5DA031CF7D8493D21D63EA5E302CD10FEAFCC5D37DB84E08A124B3FFA2`; PDB SHA-256 is `0D1BE5DB23B3F3141943CC6CD68535300465C146C795E98D982DA7DD1BA91DEE`; Stats SHA-256 is `D7DE9E9C76DE3957ECE3BA0D33FCEB8387453E500BBA6069674738A4A58230EE`; Chrome SHA-256 is `88045ED7239ACEC2C6E440CE946BB7B77362F44318A23485957F9C89D777F218`; archive SHA-256 is `73F173368A30CA80AEDADB27DB393D5BF52DC1B4E5BECE1817C672EEBEC685AE`. No deployment, commit, or push was performed. Static verification cannot prove weapon alignment, real radiation values, GFx artifact removal, or live map rendering.

**0.0.108 instant preview transitions:** the private preview graph now consumes every accepted mirrored source event through an immediate 0.0001-second graph update after synchronizing the live source variables and reapplying the preview-only overrides. This removes the stale-frame delay while preserving the beginning of attack, reload, melee, and other action clips. Configured stationary Ready, Sighted, and Relaxed changes now use the same instant base-state entry and two-second settle pass as first-open initialization, so changing the Menu Framework option while PIP-OS is open should show the final selected pose on the next visible renderer pass instead of playing the transition. Every synthetic graph advance preserves the preview root transform.

**0.0.108 static delivery:** releasedbg `xmake build -y` passed. DLL and PDB are staged under root `Compile/F4SE/Plugins`. `dist/PipOSPipboy-TestA-0.0.108.zip` is layered from 0.0.107; archive comparison proves only `00 Core/F4SE/Plugins/PipOSPipboy.dll` and `fomod/info.xml` changed. The shell, every SWF, INI, readmes, and 27,928-byte Baka background are preserved. DLL SHA-256 is `8D347894BFB3672B8BDE8225146A40B34E8D3C5B9AA6AA582E95BDB521A58FB7`; PDB SHA-256 is `67C35E72B2EBDB5AAAEC0964F6D8D139F893A20112E091544A8BC8A10F928AA6`; archive SHA-256 is `000BBEADE09F82362CF1C9BFE418C302EE983278F4A905C03CDED350A74C568A`. No deployment, commit, or push was performed. Runtime acceptance requires opening Inventory with a weapon and seeing the chosen Ready/Sighted pose already settled, switching that setting live with no visible blend, and triggering fire/reload/melee events that begin immediately but still play from their beginning. Expected telemetry includes `mirrored state transitions consume immediately` and `configured state transition fast-forwarded into idleState=`.

**0.0.107 legendary marker and card fade:** field feedback identified the filled diamond used for legendary entries as a remaining diagonal-line source. `Theme.legendaryMark` no longer uses any `moveTo` or `lineTo` polygon path; it is now a compact target marker built only from three filled `drawCircle` calls. The Inventory item-card panel was separated from the shared chrome graphics so its border can animate independently. Expanding the Inventory list now smoothsteps both the complete item-card contents and its panel border from alpha 1.00 to 0.25; collapsing restores both to 1.00 along the same 0.25-second animation. The card is no longer abruptly hidden.

**0.0.107 static delivery:** all five pages plus Chrome compile. `tools/verify_pages.ps1`, the constructor-text gate, and `tools/preview_pages.ps1` pass with zero ActionScript errors. `dist/PipOSPipboy-TestA-0.0.107.zip` is layered from 0.0.106 and changes only the five page SWFs, Chrome, and FOMOD version metadata. The DLL, shell, INI, and 27,928-byte Baka background are preserved. Archive SHA-256 is `F4458F242796296FAA89688726085DF4CD5823624D2E7003907F97B562F4EDCD`. No deployment, commit, or push was performed. Runtime acceptance requires repeatedly selecting and scrolling past legendary entries without any diagonal fan, then expanding and collapsing the Inventory list and confirming the complete item-card window fades smoothly between 100% and 25%.

**0.0.106 retained-stroke elimination:** the field screenshot after 0.0.105 proves the earlier filled panel-frame correction was incomplete. Fallout 4 GFx was still retaining visible `lineStyle` pen state from shared and repeatedly cleared `Graphics` objects, then connecting unrelated box, bracket, icon, selection-glow, and waveform paths into screen-spanning diagonal fans. All visible strokes have now been removed from the five shipped pages, shared Theme helpers, PipList redraws, and Chrome tab/bezel drawing. Straight lines and outlines use fill-only quads and edge rectangles; circles use fill-only segmented rings. Map telemetry, Radio graticule/waveform, Inventory expand/header/quick-access/inspect graphics, panel corner ticks, top telemetry, sidebar icons, and selection glow all follow the same rule. Explicit zero-alpha stroke state is retained only as a belt before fill paths. The only visible `lineStyle` source left is the unshipped replacement `PipboyBackgroundMenu.as`; the package continues to preserve Baka's 27,928-byte background SWF.

**0.0.106 static delivery:** all five pages plus Chrome compile. `tools/verify_pages.ps1`, the constructor-text gate, and `tools/preview_pages.ps1` pass with zero ActionScript errors; the composed Inventory preview has no diagonal artifacts. `dist/PipOSPipboy-TestA-0.0.106.zip` is layered from 0.0.105 and changes only the five page SWFs, Chrome, and FOMOD version metadata. The native DLL is unchanged at SHA-256 `F8AA1E8265E3EA00B2EDEEE55D9A0A73DE058532B7CBE6979949B188A5F47976`. The 27,928-byte Baka background is unchanged at SHA-256 `7541F86A1046C03C7D89B9C0D70FFFAAD6A551DCFDEC9E362B86AF99A2407185`. Archive SHA-256 is `042380A4CDE96B3AF55534BB6A177285406BA14D718D1541E181EB262F34E747`. No deployment, commit, or push was performed. Runtime acceptance requires switching across all main pages and Inventory categories, opening and closing several folders, moving selection and hover repeatedly, and leaving Radio open long enough to redraw its waveform. Static previews cannot prove the Fallout 4 GFx retained-pen artifact is gone.

**0.0.105 stable equipment and weapon hierarchy:** the 0.0.104 field log proves its copied live Weapon transform is lifecycle dependent. Every swap within one open reused one transform, while the next open reused a different transform. The fresh race skeleton now receives a conventional `Weapon` node under `RArm_Hand` before flattening, allowing the private preview skeleton to publish that hierarchy once instead of copying the current live pose into each weapon clone. New telemetry reports whether the authored node became a flattened bone and labels successful attachment as `transformSource='flattened-weapon-bone'`. Real armor and weapon `TESEquipEvent` changes now wait for three consecutive complete biped signatures before rebuilding, retaining the last good preview while armor clones finish publishing. Runtime acceptance requires `flattened Weapon bone published`, `parent='Weapon'`, stable hand alignment after several weapon swaps and menu reopens, and `equipment biped stabilized` followed by the newly equipped armor on the character. Static build success cannot prove animation-driven alignment.

**0.0.105 quest, card-stat, and Map pass:** Chrome no longer treats `DataObj.CurrentPage` as proof that the incoming page is installed. STATUS and DATA direct refreshes retry for a bounded interval until the matching staged page class exists, then DATA enters its existing `PipOSForceRefresh` path and reads `QuestsList`. Runtime quest acceptance requires `MD.activate2` plus `DA.f<tab>` in the life trail and a populated quest list after switching away and back. Weapon cards now call the same `CombatFormulas` functions used by the vanilla item card for display damage, fire rate, range, and player accuracy. ENERGY, RAD, and POISON cycle values come from the resolved weapon instance's typed-damage array instead of the former fabricated ENERGY multiplier. Shotguns retain `damage x projectileCount`. The Map page adds fixed telemetry plates for grid, region, and map name, a three-dot active WORLD/LOCAL indicator, and boxed uppercase PLAYER, QUEST TARGET, and LOCATION legend labels. In-game layout and real map-marker behavior remain runtime checks.

**0.0.105 static delivery:** releasedbg `xmake build -y` passed. All authored pages and Chrome compile, `tools/verify_pages.ps1` and the constructor-text gate pass, and the preview harness reports all five pages with zero ActionScript errors. DLL and PDB are staged under root `Compile/F4SE/Plugins`. `dist/PipOSPipboy-TestA-0.0.105.zip` is layered from 0.0.104 and changes only the DLL, DATA, Inventory, Map, Chrome, and FOMOD version metadata. The 27,928-byte Baka background, shell, Stats, Radio, INI, and readmes are preserved. DLL SHA-256 is `F8AA1E8265E3EA00B2EDEEE55D9A0A73DE058532B7CBE6979949B188A5F47976`; PDB SHA-256 is `26483941DA442A740104596A82FE9AAA8A4932689B76DE59DDF6C88994765B91`; archive SHA-256 is `3B6734A092A532C72BAD2E214AE01DFA79760F19281F69B479ACE871C6F8399A`. `git diff --check` passed with line-ending warnings only. No deployment, commit, or push was performed.

**0.0.104 live weapon transform:** the 0.0.103 screenshot proves direct root promotion restores the weapon, but the long gun is rotated incorrectly. The matching log reports `parent='RArm_Hand'`, `promotedRoot=true`, and an identity local transform. That makes the clone visible but omits the authored hand-space transform normally supplied by the engine's Weapon attachment. PIP-OS now resolves that transform from the equipped live `partClone`'s nearest Weapon ancestor, then the live flattened Weapon bone, then the live ordinary Weapon node. The complete rotation, translation, and scale are copied to the promoted clone root before attachment. The log reports the transform source and Euler angles. Releasedbg native build passed, DLL and PDB were staged under `Compile/F4SE/Plugins`, and `dist/PipOSPipboy-TestA-0.0.104.zip` was layered from 0.0.103. Archive comparison proves only the DLL and FOMOD version metadata changed. DLL SHA-256 is `2A916041F2E69601B2AA47570336960AAD5D72F51CEEA76D29ACF2FC10521CE3`; PDB SHA-256 is `CF6CA04AB266C0CDF819B072C3C4ADCDAA03704B61F9617C5EAD49E91BD7CE95`; archive SHA-256 is `72F14DE1C4611DDC313560188CBF54396E531D1A3D0B8FB566C700400DBCEA44`. `git diff --check` passed with line-ending warnings only. No deployment, commit, or push was performed. Runtime acceptance requires a visible weapon aligned with the hands and a non-fallback `transformSource` in the log. Static source evidence cannot prove alignment across pistol and long-gun animation sets.

**0.0.103 weapon-root promotion:** the 0.0.102 field log disproves the remaining TF3DHUD port assumption for this runtime tree. Every tested weapon reports `internalWeapon=false`; the vanilla 10mm reports `Prn='Weapon'`, while several mod weapons report no `Prn`; and the field race skeleton still has no authored Weapon entry. The complete weapon clone was therefore placed under a synthetic wrapper that is not part of the flattened animation tree. PIP-OS now uses the complete weapon clone root itself as the `Weapon` child of the existing animated `RArm_Hand` whenever neither the skeleton nor clone supplies a Weapon node. It also clears only the weapon clone root's inherited app-cull flag because opening the Pip-Boy hides the live weapon; child visibility remains intact for weapon-mod geometry. New telemetry reports `promotedRoot` and `rootWasCulled`. Releasedbg native build passed, DLL and PDB were staged under `Compile/F4SE/Plugins`, and `dist/PipOSPipboy-TestA-0.0.103.zip` was layered from 0.0.102. Archive comparison proves only the DLL and FOMOD version metadata changed. DLL SHA-256 is `CEC8415FC98A8615DA8EF4BB9F427E4E003C2DF03EB2459C6004EBA7AF381926`; PDB SHA-256 is `519461BC5E934974823A1A70F97551D522A4941942F87A37ACEF0E58D2466DC2`; archive SHA-256 is `4CFE40E4A1C0790E57E52BD315D91DCB33F46060DF5A18B95E6CBE1465A776F7`. `git diff --check` passed with line-ending warnings only. No deployment, commit, or push was performed. Runtime acceptance requires a visible weapon and `parent='RArm_Hand' ... internalWeapon=false promotedRoot=true` in the log. Static source evidence cannot prove visibility or hand alignment.

**0.0.102 TF3DHUD weapon hierarchy:** the 0.0.101 field log proves the synthetic `Weapon` node was created and every slot-41 clone was attached to it, but no tested weapon was visible. Source comparison found the remaining divergence: TF3DHUD treats the weapon `partClone` as an already engine-assembled hierarchy and resolves its attachment parent in the engine order of fixed special case, clone `Prn`, skeleton `Weapon` fallback, live parent chain, and preview root. PIP-OS instead forced the complete clone below a second synthetic `Weapon` wrapper before consulting `Prn`. The native path now uses TF3DHUD's order, preserving the clone's internal Weapon hierarchy under the `Prn` parent, normally `RArm_Hand`, while retaining a synthetic skeleton Weapon only as the no-Prn fallback. New log fields report `Prn` and whether the clone contains an internal Weapon node. Releasedbg native build passed, DLL and PDB were staged under `Compile/F4SE/Plugins`, and `dist/PipOSPipboy-TestA-0.0.102.zip` was layered from 0.0.101. Archive comparison proves only the DLL and FOMOD version metadata changed. DLL SHA-256 is `935E748A406116B8146DA438E478333E76D7BEC7327E4483C7F6EA01377F855B`; PDB SHA-256 is `A2EA7E716858E2A7C21B7F73E3E3C7C72DA45D60231DFDA4C62A0FF429C8E7E5`; archive SHA-256 is `FD101E5FDB864683C825C0B8A403AE7B9714C90945AA6A639674C26FCC50E4DA`. `git diff --check` passed with line-ending warnings only. No deployment, commit, or push was performed. Runtime acceptance requires a visible weapon aligned with the animated hands and a log line such as `weapon attach ... parent='RArm_Hand' Prn='RArm_Hand' internalWeapon=true`. Static source parity cannot prove visibility or alignment.

**0.0.101 fallback flash and missing Weapon node:** the 0.0.100 field log proves Inventory lifecycle switching now works repeatedly. Each transition records `source=inventory-page-lifecycle`, restores model offset zero, and pushes `available:true`. Inventory still displayed Vault Boy for startup frames because its poll required both `active:true` and `available:true`; the latter intentionally waits for native placement and compositor attachment. Inventory now reserves the figure slot immediately from `active:true`, hides Vault Boy without waiting, and uses `available` only for the `LIVE CAPTURE` caption. The same log proves every equipped weapon is rejected before cloning because the field race skeleton has 130 flattened bones but no `Weapon` entry. PIP-OS now creates a conventional identity `Weapon` NiNode directly under the authoritative animated `RArm_Hand` node when the skeleton omits it, adds it to the preview node map, and routes the weapon clone plus engine-style `Scb` reparent through that node. Runtime acceptance requires no Vault Boy flash and consecutive log lines containing `synthetic Weapon node created: parent='RArm_Hand'` and `weapon attach ... parent='Weapon' boneParent='RArm_Hand'`. The weapon must then be visibly present; identity placement is static-safe but hand alignment remains runtime-only. `dist/PipOSPipboy-TestA-0.0.101.zip` is layered from 0.0.100 and changes only the DLL, `Pipboy_InvPage.swf`, and FOMOD metadata. The Inventory page compiler, verifier, constructor-text gate, and releasedbg native build passed. DLL SHA-256 is `AFD1FFB4E7310599C851378791D55FD95BA585F928E8D5EA91E57741538B64F5`; PDB SHA-256 is `09918AC49AF1AF802D123CAF6C678907705682C5D6FDF9D61CCB0213FB84C8ED`; Inventory SWF SHA-256 is `829A179B4F6F2A9574156D50F27F4DB6F097426E73C84B56F69EEA0B6F42AD82`; archive SHA-256 is `6C850764598A33D249380C7E7B5C9FA774EFA1F66C00EFC01B5098C4560BD8E8`. No deployment, commit, or push was performed. Static verification cannot prove visible weapon placement or frame-perfect fallback suppression.

**0.0.100 Inventory lifecycle signal correction:** the 0.0.99 field log never emitted `page visibility changed`; every framing pass remained `inventory=false modelOffsetX=10000`, and every AS3 contract push remained `available:false`. The existing diagnostic independently confirmed `Menu_mc.DataObj.CurrentPage=-1` and a null shell `CurrentPage` getter on this setup. The offscreen placement itself was behaving as instructed, but the Inventory page could never bring the character back or suppress its fallback Vault Boy. `PipOS_InvPage` now publishes `root1.PipOS_inventoryPageActive=true` from its real `ADDED_TO_STAGE` lifecycle and publishes false from `REMOVED_FROM_STAGE`. The native UI probe consumes that explicit boolean first and retains the inaccessible shell property only as a fallback. Runtime acceptance requires a `page visibility changed: source=inventory-page-lifecycle ... inventory=true` line, a following `inventory page placement: inventory=true modelOffsetX=0` line, and an `available:true` contract push that hides Inventory's Vault Boy. Leaving Inventory must produce the corresponding false transition and restore the 10000-unit offset. `dist/PipOSPipboy-TestA-0.0.100.zip` is layered from 0.0.99 and changes only the DLL, `Pipboy_InvPage.swf`, and FOMOD metadata. The Inventory page compiler, verifier, constructor-text gate, and releasedbg native build passed. DLL SHA-256 is `30BD68D444E3BD262789FAE2B219B8CDDA09432BC0D348C8854ADBCD171E3351`; PDB SHA-256 is `05C2BAF2CBEFF078C100CDDBDD10CDAFDCA54A45A9E0DBD71A176809E6F14A63`; Inventory SWF SHA-256 is `C2BB2AF4B9D68A81C6A139BBBA0ED495059B29473B06C164B51182AB89F5C398`; archive SHA-256 is `1C9201C4F717E7A2CA8725C7DB3A918C048BB962A4ACD364ABFB3866ADF3F4C6`. No deployment, commit, or push was performed. Static verification cannot prove the page lifecycle signal is visible to native code in game. The same 0.0.99 log separately shows `weapon attach refused ... has no fresh-skeleton Weapon bone`; weapon attachment remains unresolved and is not changed by 0.0.100.

**0.0.99 Inventory-only offscreen placement:** page changes no longer app-cull or rebuild the live character. The existing Scaleform `CurrentPage` probe now participates in the live placement snapshot. Until Inventory is positively identified, and on STATUS, DATA, MAP, and RADIO, the model-space X anchor receives a temporary `+10000.0` offset. Returning to Inventory recomputes framing with the user's unchanged `Char3DScreenX` and `Char3DScreenY` values. Target-follow X uses the same temporary anchor, so follow mode cannot cancel the page offset. The clone, private animation graph, facial synchronization, renderer, and transparent compositor remain alive while offscreen. The AS3 availability contract remains false outside Inventory so STATUS retains its Vault Boy. Runtime acceptance requires no character flash on a non-Inventory open, no character on any non-Inventory page, immediate restoration at the saved position on Inventory, and log pairs containing `page visibility changed` plus `inventory page placement`. `dist/PipOSPipboy-TestA-0.0.99.zip` is layered from 0.0.98 and changes only the DLL plus FOMOD metadata; all SWFs are byte-identical. The releasedbg build passed, and DLL/PDB were staged under root `Compile/F4SE/Plugins`. The staged and packaged DLL SHA-256 is `864F070D7E5322F81A58DEF7A337607EC5EEE8C2C31C175EC091A27C54FE3160`; PDB SHA-256 is `4730345201795894BA6D00DE0AA298EFB22293C3A8420DF5E2C770283175F0FA`; archive SHA-256 is `B4B0BAC25E6EE4CB56FCCBC8E412CB444E47A70E9C2F96DE55E8FA55585DB640`. No deployment, commit, or push was performed. Static verification cannot prove page switching is visually clean in game.

**0.0.98 flattened weapon-bone correction:** the 0.0.96 runtime log conclusively reported `weapon attach refused` on every tested slot 41 weapon, including forms `00004822`, `000CE97D`, `2A0055BF`, and `00171B2B`. The failed guard assumed `Weapon` would be discoverable through `RArm_Hand->GetObjectByName`, but a `BSFlattenedBoneTree` stores its logical hierarchy in `FlattenedBone::parent` indices rather than conventional `NiNode::children`. TF3DHUD's current resolver reads the flattened bone table directly. PIP-OS now does the same: it resolves the authoritative flattened `Weapon` entry, walks its parent-index chain to verify `RArm_Hand`, confirms the preview node map points to the same skeleton node, and attaches there. The next successful log must contain `flattened Weapon bone resolved` followed by a normal `weapon attach` line. `dist/PipOSPipboy-TestA-0.0.98.zip` is layered from 0.0.97 and changes only the DLL plus FOMOD metadata. All SWFs remain byte-identical. The releasedbg native build passed, and DLL/PDB were staged under root `Compile/F4SE/Plugins`. The staged and packaged DLL SHA-256 is `C63AC421A3F62DD0A11FEC72841FC3727F25185FDFAD7BDF4731839E0A16D482`; archive SHA-256 is `E559CED32085B692F13DE512ED30A052152C77B29A34FCD227761EE99872DB94`. No deployment, commit, or push was performed. Static verification cannot prove the weapon is visible or aligned in game.

**0.0.97 left-navigation outline correction:** the artifact-safe filled border introduced in 0.0.94 used a default one movie-unit edge. Fullscreen scaling turns that into several physical pixels on the left page and extension buttons, making their outlines much heavier than the intended hairline. `Chrome.paintTabs` now passes a `0.35` movie-unit thickness only for those controls. Shared panel borders, the active left accent, and all other UI geometry are unchanged. `dist/PipOSPipboy-TestA-0.0.97.zip` is layered from 0.0.96 and changes only `PipOS_Chrome.swf` plus FOMOD metadata. The DLL and all page and background SWFs remain byte-identical to 0.0.96. The constructor-text gate, page build, page verifier, and five page previews passed with zero ActionScript errors. Chrome SHA-256 is `3A17109893D4E03AD7A45B05596A0BDF13C0BE7A0EAD65D40C018AAFE06E164C`; archive SHA-256 is `29B14F1A1438D4E9553C5E379F0C0A16C027EDF2D886B6CB921EF923298BF98F`. No native rebuild, deployment, commit, or push was performed. Runtime confirmation is still required at the user's fullscreen resolution.

**0.0.96 artifact and weapon-hierarchy correction:** the 0.0.95 screenshot showed huge diagonal fans originating at reusable box borders. `Theme.frameRect` had replaced unreliable stroked rectangles with four filled edge rectangles, but Flash GFx retains the previous graphics line pen and a fill does not disable it. The helper now clears `lineStyle` before and after drawing its filled edges, and `Theme.panel` clears the pen before its transparent hit-test fill. The preview equipment path now overrides a weapon model's `Prn=RArm_Hand` metadata and resolves the attachment only by traversing the fresh skeleton from `RArm_Hand` to its descendant `Weapon` node. It refuses attachment if that exact hierarchy is missing, so an unrelated duplicate `Weapon` node cannot win. Runtime acceptance requires no diagonal fans and a log line containing `parent='Weapon' boneParent='RArm_Hand'`. `dist/PipOSPipboy-TestA-0.0.96.zip` is layered from 0.0.95 and changes the DLL, authored Data, Inventory, Radio, and Stats page SWFs, `PipOS_Chrome.swf`, and FOMOD metadata. The transplanted Map page and Baka background movie remain byte-identical. The releasedbg build, page compiler, verifier, constructor-text gate, and five page previews passed. The staged and packaged DLL SHA-256 is `6351A4BEBCE876E37981C252679679AECF286CF3FBFBF36E98FB6E1D145BD402`; archive SHA-256 is `3245564AA6026EE74840D0906FC911A01C04C3A419ADEC9D7B34B065A73A2709`. No deployment, commit, or push was performed. Static verification cannot prove either in-game result.

**0.0.95 DATA quest recovery:** the field log constructs `PipOS_DataPage` (`DA.c`) but never records a DATA `PipboyChangeEvent`, so `QuestsList` never reaches `buildQuestDisplay`. STATUS already had a public `PipOSForceRefresh` entry point for the same shell-medic lifecycle gap, but DATA did not. DATA now routes both the normal event and Chrome's direct repaired-page refresh through one idempotent `applyData` method. New breadcrumbs distinguish `DA.e<tab>` for a normal event from `DA.f<tab>` for the direct recovery path. `dist/PipOSPipboy-TestA-0.0.95.zip` is layered from 0.0.94 and changes only `Pipboy_DataPage.swf` plus FOMOD metadata. All authored pages compile, `verify_pages` and `ctor_text_check` pass, and all five page previews render with zero ActionScript errors. Archive SHA-256 is `8B67700D0BE387B5D68359A6030FB2067F3CB10B1E12898F4282C3BBC042FC22`; the DATA SWF is `3D26E81FE902CD1E5667BFED32DA22AFC84B0183F5C3A006E28055B950F26778`. No native rebuild, deployment, commit, or push was performed. Runtime confirmation must verify quests populate both when PIP-OS opens on DATA and after switching away and back.

**0.0.94 inventory and box parity:** every reusable panel/chip/keybar outline now uses `Theme.frameRect`, four filled edge rectangles, instead of a stroked `drawRoundRect`. Fallout GFx had been dropping the closing/right segment of those stroked paths, which explains the same missing edge on Equipment, Inventory, item cards, Quick Access, Caps, and other shared boxes. The inventory expand control is 6 px lower. The inventory page now banks selection and top-visible display index separately for all seven categories in `root1.PipOS_invListMem`; the DLL captures it on close and seeds it on the next open. Quick Access embeds the exact 59-frame `FavoritesMenu_fla.HotkeyIcons_6` strip from the vanilla `FavoritesMenu.swf` and selects each frame with the engine's `FavIconType`, retaining the old vectors only as a fallback.

**0.0.94 drop and damage parity:** both the R hotkey and right-click context menu continue through the same guarded `doDrop` path, but it now calls vanilla `ItemDrop(invIndex, 1)`. The prior whole-stack count did not match vanilla's direct-drop contract; vanilla uses a separate quantity dialog before it ever passes a larger count. Native weapon stats now resolve ranged instance data, projectile count, override/ammo projectile, and thrown projectile explosion damage. The inventory card shows multi-projectile ballistic damage as `damage x projectileCount`, matching the vanilla shotgun convention, while grenades and mines use their explosion record rather than the usually meaningless WEAP attack-damage field.

**0.0.94 stable held weapon:** the 0.0.93 log proved that the open-time equipped slot 41 form `00004822` was later replaced in the player's third-person biped by form `00171B2B` when the inventory selected-item viewer advanced. PIP-OS treated that temporary BipedAnim and geometry-pointer mutation as an equipment change, rebuilt the clone, and then drove the selected item's model with the equipped 10mm pose. The new build keeps the menu-open loadout when those temporary biped and `Update3DModel` changes occur. Race, sex, head/morph changes remain in the stable visual signature, and real `TESEquipEvent` changes retain their explicit rebuild path.

**Static verification for 0.0.94:** all authored pages and Chrome compile with mxmlc. `tools/verify_pages.ps1` and `tools/ctor_text_check.py` pass, and `tools/preview_pages.ps1` renders all five pages with zero ActionScript errors. The releasedbg native build passes. DLL/PDB are staged under root `Compile/F4SE/Plugins`; build and staged DLLs match SHA-256 `6FFE1997D71951E6C0D071EEE2EFC0311F01EDD1C4B96FB741336D31AE9DDFCC`. `dist/PipOSPipboy-TestA-0.0.94.zip` is layered from 0.0.93 and changes only the DLL, the authored Data, Inventory, Radio, and Stats vanilla-name page SWFs, `PipOS_Chrome.swf`, and generated FOMOD metadata. The transplanted Map page is preserved at SHA-256 `62789434164CFC527EE354B9A6C2139134731F2B1F875D33946D3C25352DF61F`, and `PipboyBackgroundMenu.swf` is preserved at SHA-256 `7541F86A1046C03C7D89B9C0D70FFFAAD6A551DCFDEC9E362B86AF99A2407185`. Archive SHA-256 is `3C80B97DF9D5FC0D4978FDCED53ADE29EA449B784205C242D500A51B648089EA`. No deployment, commit, or push was performed. Static checks cannot prove these field-visible fixes.

**Required 0.0.94 runtime matrix:** open Inventory with a 10mm equipped and move selection across unrelated weapons, verifying the held model stays the 10mm and remains in both hands. Test R and context-menu DROP on a non-favorite single item and on a stack. Compare a grenade/mine card and a shotgun card against vanilla. Scroll each category, close/reopen PIP-OS, and verify the selection plus viewport returns. Inspect box right edges at multiple resolutions and verify Quick Access icons match the Favorites menu. Preserve the fresh log if any item fails, especially `[PipOS][DROP]`, `invListMem`, and the one-time `ignored transient Pip-Boy biped preview change` line.

**Runtime proof from the user:** the fresh-skeleton character now renders with complete equipment and animates in the PIP-OS inventory view. The latest screenshot before 0.0.88 still showed the equipped firearm offset from the hands and a relaxed weapon idle. Earlier clone-invisibility diagnosis and the 0.0.76 decision tree remain useful history, but they are no longer the current implementation state.

**Source completed in 0.0.87 and 0.0.88:** `dll/src/CharacterAnimation.cpp` owns an isolated engine behavior graph using the actor's resolved third-person project and live third-person default/weapon subgraphs. Equipped previews are forced into a user-selectable Ready or Sighted stationary state. `CharacterCapture.cpp` now recognizes all engine weapon attachment slots, falls back to the preview skeleton's `Weapon` node for WEAP forms, and reparents internal `Scb` like the engine/TF3DHUD path. Character X/Y settings translate the model in model space and no longer alter the display quad or projection. The renderer has key, fill, and rim lights plus an optional green hologram treatment.

**Uniform-background correction in 0.0.88:** source inspection proved that Baka Fullscreen Pip-Boy owns a separate `PipboyBackgroundScreenModel`, while PIP-OS owns a full-frame black veil in `InterfaceSource/pipos/Chrome.as`. The broad fixed vignette was PIP-OS code: four 230-unit black gradient bands at alpha 0.20. Those bands ignored `VeilAlpha`, making the center respond to the opacity slider while the edges stayed dark. The bands are now behind a new `CrtVignette` option, default off. The F4SE Menu Framework exposes `Background opacity` from 0.00 through 1.00 and `Edge vignette`; scanlines, phosphor glow, and frame borders remain independent. Keep the transplanted 27,928-byte Baka-compatible background SWF. Do not ship the 1,301-byte compiler output.

**Screen Archer Menu finding:** its relevant source changes the world/cell imagespace, applies GFx color multipliers, and edits ordinary materials/lights. It does not provide an isolated character-preview post-process or a reusable screen-space outline pipeline. Do not apply its global cell imagespace path to the Pip-Boy preview. Its material flags may be useful for a future per-clone material treatment, but that requires a separately audited clone-only implementation.

**0.0.89 lifecycle corrections:** the hologram setting no longer changes Chrome's fullscreen scanline or sweep alpha; only the native character lights consume it. STATUS now exposes `PipOSForceRefresh`, and Chrome's shell medic calls that direct idempotent render path on a freshly repaired page before retaining the normal full-mask broadcast. This addresses the field-observed re-entry state where the page instance staged but never received the event needed to draw meters, numbers, and Vault Boy. The first-open character/red-box size mismatch was traced to attaching the stock full-frame display quad while its GPU buffers were still pending; later opens reused the already clipped quad. The renderer now withholds the display root until `ApplyDisplayClipRect` has succeeded, then attaches it once.

**0.0.90 weapon synchronization correction:** the user's 0.0.89 screenshot proves the private graph drives the body into a two-handed pistol pose and the 10mm model is present, but the model does not meet the hands. The fresh log proves two third-person subgraphs load and the ready event is accepted. Source comparison found a concrete divergence from TF3DHUD: PIP-OS held `iSyncWeaponDrawState=2` every frame and used `iSyncReadyAlertRelaxed=0`; TF3DHUD treats draw-state 2 as an initialization pulse, settles it to zero, and owns the equipped preview weapon state with ready/relaxed sync value 2. PIP-OS now follows that settled state. One-shot `[3D] weapon attach` telemetry reports the runtime slot, form ID, resolved parent, and `Scb` (or root) local transform for the next test.

**0.0.91 first-open/pose/filter correction:** the 0.0.89 log proves the first open built and enabled the renderer without ever logging `clipRect applied` or `clipped display root attached`; the second open immediately logged both. The initial quad's GPU buffers were pending and the paused Pip-Boy supplied no later actor-update task. The render-boundary hook now queues main-thread retries until attachment, and `available` remains false until the clipped display surface genuinely exists. The private animation graph now consumes its instant ready/sighted events through a 0.0001-second initialization update plus TF3DHUD-style settle update before its first visible renderer pass. Hologram key/fill lights remain their normal warm/cool colors; only the rear rim becomes strong green. The old menu wording falsely promised a character-masked scan sweep and has been corrected: no true silhouette-masked scanline shader exists yet.

**0.0.92 uniform-background correction:** Baka Fullscreen Pip-Boy can render an independent `PipboyBackgroundScreenModel` HUD-glass surface behind its background movie. PIP-OS already set both GFx movie background alphas to zero, but that does not affect the Interface3D surface's `opacityAlpha`; it can therefore remain as a darker central rectangle even with `VeilAlpha` near zero. On each PIP-OS open, the bridge now sets that optional Baka backing surface to opacity zero. Chrome's single full-frame veil remains the only adjustable world dimmer, while the separate CRT scanlines, phosphor texture, and borders remain untouched.

**0.0.93 TF3DHUD weapon-pose synchronization:** the 0.0.92 runtime log reports the firearm in engine slot 41, parent `RArm_Hand`, no `Scb`, and an identity root-local transform. Direct source comparison shows that this parent is the model's `Prn` result and that TF3DHUD's basic attachment path would choose the same parent; adding an arbitrary weapon offset or forcing another parent would therefore conceal rather than fix the graph divergence. PIP-OS now suppresses TF3DHUD's three idle-preview-owned animation channels (`bEquipOk`, `iSyncReadyAlertRelaxed`, and `iSyncWeaponDrawState`), applies its complete non-locomotion neutral pose overrides, keeps live aim IK disabled even for the sighted branch, and issues `weapEquip`/pose events after the linked weapon subgraph has received its first initialization tick. This is intended to settle the hands and `Weapon` bone in the same graph generation. The Menu Framework advanced-framing section also adds live, persisted model Pitch and Roll controls beside Yaw; these rotate the model root and do not resize the compositor surface.

**Static verification for 0.0.89:** releasedbg xmake build passed. `tools/ctor_text_check.py` passed. `tools/build_pages.ps1` built all pages and Chrome. `tools/verify_pages.ps1` passed every page contract. `tools/preview_pages.ps1` rendered all five pages with zero ActionScript errors. The layered archive is `dist/PipOSPipboy-TestA-0.0.89.zip`; it was seeded from 0.0.88 and overlays only the DLL, `Pipboy_StatsPage.swf`, and `PipOS_Chrome.swf`, plus generated FOMOD version metadata. The transplanted 27,928-byte Baka-compatible `PipboyBackgroundMenu.swf` was hash-verified unchanged from 0.0.88. DLL and PDB are staged under `Compile/F4SE/Plugins`. No deployment, commit, or push was performed. These are static checks; all three lifecycle corrections still require in-game confirmation.

**Static verification for 0.0.90:** releasedbg xmake build passed. The archive is layered from 0.0.89 with only the DLL and FOMOD version metadata changed; no SWF or INI is replaced. Static success does not prove the weapon is aligned in game.

**Static verification for 0.0.91:** releasedbg xmake build passed with only the existing F4SE Menu Framework `<codecvt>` warnings. The archive is layered from 0.0.90 with only the DLL and FOMOD version metadata changed. Runtime checks: first open must eventually log `clipRect applied` then `clipped display root attached`; initial animation should log `private state machine pre-rolled`; hologram on/off must not recolor the character's key/fill illumination.

**Static verification for 0.0.92:** releasedbg xmake build passed. The archive is layered from 0.0.91; SHA-256 comparison proves only `PipOSPipboy.dll` and `fomod/info.xml` changed. DLL/PDB are staged under root `Compile/F4SE/Plugins`, and the staged and archived DLLs match the build output (`EDC8D65B78147A65F5CED83F21B82888CF73FE09B4E7CAFE3B2C07AD056739E6`). Runtime check: opening PIP-OS must log either `Baka background screen-model opacity=0` (surface found and neutralized) or `not active`; the correction runs immediately and again after 45 UI-task hops so Baka's independent menu-advance lifecycle cannot recreate the surface after PIP-OS applies transparency. If the central dark rectangle persists with `not active`, it belongs to the character compositor rather than Baka and should be isolated there next. No deployment, commit, or push was performed.

**Static verification for 0.0.93:** releasedbg xmake build passed with only the existing F4SE Menu Framework `<codecvt>` warnings. `dist/PipOSPipboy-TestA-0.0.93.zip` is layered from 0.0.92; SHA-256 comparison proves only `00 Core/F4SE/Plugins/PipOSPipboy.dll` and `fomod/info.xml` changed. DLL/PDB are staged under root `Compile/F4SE/Plugins`; build, staged, and archived DLLs match at `5D034BD7A2A534A0A63DBE2C4D686F35828E8BDADF8AA2BC637739665437A6C0`. No SWF or INI is replaced. No deployment, commit, or push was performed. Static success cannot prove in-game hand/weapon convergence.

**Runtime checks still required, in priority order:**

1. Open PIP-OS on STATUS, switch to any other main page, then return to STATUS. Confirm meters, numbers, boxes, and Vault Boy remain populated. The life trail should include `MD.direct>ST.f0` on a medic-assisted return.
2. Close and reopen PIP-OS several times without changing character settings. Confirm the character has the same apparent size on first and later opens; the log should report `clipRect applied` before `clipped display root attached` on a fresh display root.
3. Enable the hologram option and confirm only the character changes green; Chrome borders, global scanlines, and sweep strength must remain identical with the option off/on.
4. Confirm the 0.0.89 background is spatially uniform with Edge vignette off at opacity 0.00, 0.10, and a visibly higher value. CRT scanlines and borders should remain.
5. Install 0.0.96 and confirm the weapon meets both hands for pistol and long-gun slots in both Ready and Sighted. The log must contain `parent='Weapon' boneParent='RArm_Hand'`. A `weapon attach refused` line means the required fresh-skeleton hierarchy was absent and the mesh was intentionally not attached.
6. Move Yaw, Pitch, and Roll while PIP-OS remains open. Confirm all three rotate the complete model immediately and survive Save; confirm Character X/Y still translate without resizing or stretching it.

**Agent cleanup:** an inherited `renderer_depth_audit` child never started and produced no findings. The interrupt control was called twice, but the client continued to list it as `pending_init`; there is no result or identified child rollout to preserve or safely remove.

---

## 1. Project at a glance

| Thing | Value |
|---|---|
| What it is | Full visual replacement of the Fallout 4 Pip-Boy menu ("PIP-BOY OS V2.7.1"), companion to **Baka Fullscreen Pip-Boy** |
| Repo root | `E:\Fallout 4 Modding\F4SE\PipOSPipboy` |
| Git remote | `https://github.com/DCCStudios/F4-PIP-OS.git`, branch **main** |
| **Runtime target** | **Fallout 4 OG 1.10.163 ONLY** (not NG/next-gen). All REL IDs below are OG. |
| commonlib (build against) | `E:\Fallout 4 Modding\F4SE\FOV Slider F4SE\lib\commonlibf4` — the **FOV-Slider fork** of CommonLibF4 |
| TF3DHUD reference source | `E:\Fallout 4 Modding\F4SE\PluginTemplate\TF3DHUD-master\src` — a **working** live-3D-character HUD mod; our north star for the Live 3D feature |
| Live game log | `%USERPROFILE%\Documents\My Games\Fallout4\F4SE\PipOSPipboy.log` (+ `.prev.log`) |
| Build tool | **xmake** (in `dll/`) |
| Current MO2 instance | `F:\Modlists\MagnumOpus` (see memory `mo2-active-instance`) |

**Two halves of the codebase:**
- **DLL** (`dll/src/*.cpp`) — F4SE plugin: page-mode bridge, native data pushes to the movie, the customization menu, and the Live 3D capture. Built with xmake → `dll\Compile\F4SE\Plugins\PipOSPipboy.dll`.
- **ActionScript SWFs** (`InterfaceSource/*.as`, `InterfaceSource/pipos/*.as`) — the actual menu pages. Built with mxmlc (Apache Flex) via `tools/build_pages.ps1`.

The mod is **fully functional without the DLL** (shell defaults every tab to the PipOS page). The DLL adds native data, the customization page, and Live 3D.

---

## 2. Build / test / package / ship workflow

### Build the DLL
```
cd "E:\Fallout 4 Modding\F4SE\PipOSPipboy\dll"; xmake
```
Output: `dll\Compile\F4SE\Plugins\PipOSPipboy.dll`. Build is ~2–6s.

### Build + gate the SWF pages (only if you touched `InterfaceSource/*.as`)
```
cd "E:\Fallout 4 Modding\F4SE\PipOSPipboy"
python tools\ctor_text_check.py      # CRASH-LAW GATE — must say "ALL PASS"
.\tools\build_pages.ps1              # mxmlc build → build\pages\*.swf + Package\Interface\
.\tools\preview_pages.ps1           # Ruffle render check — must say "ALL PAGES RENDERED CLEAN"
```

### Package a versioned test zip (the **layered** method — see the gotcha in §4)
The shipped zip must contain the pages under the **vanilla load names** (`Pipboy_*.swf`) plus transplanted art the build doesn't regenerate. The reliable recipe is: **extract the previous version's zip, overlay only what changed, re-zip.**
```powershell
$stage = "<scratchpad>\pipos_stageNN"; New-Item -ItemType Directory -Force -Path $stage | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory("$pwd\dist\PipOSPipboy-TestA-0.0.<PREV>.zip", $stage)
$core = Join-Path $stage "00 Core"
$dll = Get-ChildItem -Recurse -Filter "PipOSPipboy.dll" -Path "dll\Compile" | Select-Object -First 1
Copy-Item $dll.FullName "$core\F4SE\Plugins\PipOSPipboy.dll" -Force
# For AS changes ALSO overlay (note the RENAME to vanilla load names):
#   build\pages\PipOS_InvPage.swf   -> $core\Interface\Pipboy_InvPage.swf
#   build\pages\PipOS_StatsPage.swf -> $core\Interface\Pipboy_StatsPage.swf   (etc.)
#   build\pages\PipOS_Chrome.swf    -> $core\Interface\PipOS_Chrome.swf       (chrome keeps its name)
.\tools\make_fomod_zip.ps1 -PayloadDir $core -Version "0.0.NN" -OutZip "dist\PipOSPipboy-TestA-0.0.NN.zip"
```
`make_fomod_zip.ps1` wraps `00 Core` + a generated `fomod/` (MO2 reads `<Version>`). **DLL-only rounds** just overlay the DLL; leave the SWFs from the prior zip untouched.

### Commit + push
```
git add -A
git commit -F "<scratchpad>\commitmsgNN.txt"   # USE -F: inline -m with quotes breaks PowerShell arg passing
git push origin main
```
End commit bodies with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

### Read the game log after a test
The current session writes `PipOSPipboy.log`; `main.cpp` pre-rotates the previous session to `.prev.log` on each launch, with `flush_on(trace)` so nothing is lost. **Check timestamps** — the freshest file is the one the user just tested. Handy filters:
```powershell
$f = "$env:USERPROFILE\Documents\My Games\Fallout4\F4SE\PipOSPipboy.log"
Select-String -Path $f -Pattern "\[3D\]" | Select-Object -Last 20 | % { $_.Line }
```

---

## 3. Things NOT to do (hard-won)

1. **Do NOT switch the Live 3D display quad to `HUDGlassFlat:0`.** 0.0.69 tried mirroring the vanilla item preview's quad name → log said `clipRect skipped: display geometry not ready`, the quad was never created, nothing composited. The engine auto-creates a screen-attached display quad **only for the `ModMenuRenderMesh:0` name** for third-party renderers; `HUDGlassFlat` is a NIF the *Pip-Boy machinery* attaches to *its own* renderer. **Keep `ModMenuRenderMesh:0`.**
2. **Do NOT use `PostEffect kModMenu` on our OWN renderer.** Its deferred composite samples per-tile light lists that are never populated in an offscreen menu render → geometry contributes zero pixels. **Use `kHUDGlass`** (forward composite, no tile dependency). This is why the vanilla item preview works with zero hooks.
3. **Do NOT call `Inventory3DManager::Begin3D()` on an idle manager.** It can deref the null `itemBase`/`tempRef` of an idle manager = main-thread AV. (Removed in the 0.0.72 audit.) The `PipboyScreenModel` renderer already exists at idle in practice — the log shows `enabled=true` without an item selected — so you don't need Begin3D anyway.
4. **Do NOT `Release()` / `End3D()` / `Disable()` the vanilla `PipboyScreenModel` renderer.** The engine owns it. We only **borrow its offscreen slot** (`Offscreen_Set3D`) and do a **tracked symmetric enable** (enable only while our clone occupies the slot; restore the prior disabled state on teardown; see `g_weEnabledVanilla`, `g_usingVanilla`).
5. **Do NOT hand-build `loadedModels` (`BSTArray<LoadedInventoryModel>`) entries.** `LoadedInventoryModel` is exe-internal (forward-declared only); the async `NewInventoryMenuItemLoadTask` would clobber a hand-built entry. That path is a dead end.
6. **Do NOT write pose to `node->SetLocalTransform()` for flattened bones.** The engine's flattened-tree world update walks `BSFlattenedBoneTree::bone[].local` (a raw heap array) and **ignores** node locals for cache efficiency. Write `bone[].local` **directly** (see `CopyFlattenedPose`).
7. **Do NOT point a skin's `worldTransforms[i]` at `node->world` for flattened bones.** Use `&FlattenedBone::world` (the array entry the engine maintains). Node worlds on a flattened skeleton may never be written. (Fixed in 0.0.76.)
8. **Do NOT overwrite the user's `PipOSPipboy.ini`.** In-game customization saves go to `PipOSPipboy_User.ini` (never shipped in the FOMOD; parsed **after** the main ini as an override). A shipped ini would wipe saves on every install (this actually happened pre-0.0.59). Never write diagnostics/red-RT test values to any ini.
9. **Do NOT trust the IDE (clangd) diagnostics.** They constantly show bogus errors (`'F4SE/F4SE.h' file not found`, `std has no string_view`, `RE has no NiAVObject`, `Scaleform undeclared`, etc.) because clangd's include paths are wrong for this project. **xmake is the only arbiter.** Ignore the red squiggles; build to check.
10. **Do NOT ship the red-RT diagnostic.** The 0.0.66 test (`Offscreen_SetClearRenderTarget(true)` + red `Offscreen_SetBackgroundColor`) was a temporary bisection tool; it also **leaked into the vanilla preview's shared render target** (turned the native item-examine view fully red). It's already reverted; don't reintroduce it into a shipping build.
11. **Do NOT run scene-graph / Interface3D / D3D / NiAVObject::Update off the main thread.** The `RunActorUpdates` hook fires on **worker threads >1×/frame**; it only does atomic reads + schedules an F4SE task. All mutation happens in `RunCaptureTask`→`Tick` on the main thread. Keep that discipline for anything you add.

---

## 4. The packaging gotcha (read once, save yourself an hour)

`Package\Interface\` holds our built SWFs named `PipOS_*.swf`, but the **shipped FOMOD zip must rename them to the vanilla load names** the shell requests: `Pipboy_StatsPage.swf`, `Pipboy_InvPage.swf`, `Pipboy_DataPage.swf`, `Pipboy_RadioPage.swf`, `Pipboy_MapPage.swf`. The zip **also** needs, unchanged from the shipped base:
- `PipboyMenu.swf` (the shell copy, 41KB),
- `Pipboy_MapPage.swf` (a **transplanted** 93KB art build — NOT regenerated by `build_pages.ps1`),
- `PipboyBackgroundMenu.swf` (the **transplanted** 27KB build — the `build_pages.ps1` output is a 1.3KB untransplanted version; do NOT ship that one),
- `PipOS_Chrome.swf` (keeps its own name).

Because of this, the reliable packaging method is **§2's layered extract-overlay-rezip**, seeding from the previous version's zip so all the transplanted art carries forward. `tools/package.ps1` exists but does the rename incompletely; the manual layering is what's been used since ~0.0.58.

---

## 5. Live 3D — the whole story

### Goal
Render a live, rotatable capture of the **player's equipped character** into the Pip-Boy inventory figure slot (behind the CRT UI), instead of the vector Vault Boy. Toggle: `bLive3D` in the customization page (default OFF), applies on next Pip-Boy open. The AS side hides the Vault Boy when `root1.PipOS_char3d.available == true`.

### Mechanism (current, 0.0.76)
A `RunActorUpdates` `write_call<5>` hook (`REL::ID(556439)+0x17`) fires on worker threads and schedules `RunCaptureTask` as an F4SE main-thread task. `Tick()` then, **vanilla-renderer-first**:
1. `AcquireVanillaRenderer()` — resolves `PipboyManager::GetSingleton()->inv3DModelManager.str3DRendererName` (`"PipboyScreenModel"`) → `Interface3D::Renderer::GetByName`. This is the engine's own item-preview renderer — **field-proven to composite 3D over this exact fullscreen menu** (it draws the floating weapon when you select an item).
2. Clone the player: `CloneSubtree(player->Get3D(false))` (kCopyExact; controllers detached during clone, restored on source, cleared on clone).
3. `SanitizeClone(clone, source)` — the fix pipeline (see §6).
4. `FrameClone(clone, /*distanceCap*/80)` — scale/yaw/translate to center the framing target at the offscreen origin (cap 80 because the item camera is short-range).
5. `Offscreen_Set3D(clone)` onto the vanilla renderer, add an offscreen light, tracked-enable, log a pose probe.
Own-renderer path (`ConfigureRenderer`/`BuildPreview`/`AttachToRenderer`) is the **fallback** if the vanilla renderer can't be resolved.

### The diagnostic arc (why each version exists)
Two independent bugs were crossed for most of this, which is why it took so long:

| Ver | Change | Result / lesson |
|---|---|---|
| 0.0.58–0.0.64 | fade-node repair (`RepairShaderFadeNodes`) | Cloned geometry's `BSShaderProperty::fadeNode` back-pointer isn't remapped by clone → deferred path drops draw passes. Fixed; **necessary but not sufficient.** |
| 0.0.60 | depth `kStandard3DModel(7)` → `kTerminal(9)` | WRONG (my error, chasing the fade bug). The engine doesn't composite depth 9 under the Pip-Boy. Reverted 0.0.67. |
| 0.0.66 | **red-RT bisection** | Red block composited on screen → **the compositing path works; the model is what's missing.** Also leaked into the vanilla preview's shared RT. |
| 0.0.67 | depth → `kMessage(15)` + `alwaysRenderWhenEnabled` | `[3DDIAG]` dump proved vanilla `PipboyScreenModel` composites at **depth 15**. |
| 0.0.68 | right-click via UI input hook; `[3DDIAG]` renderer diff | Got the vanilla renderer's exact config (see below). |
| 0.0.69 | mirror vanilla quad (`HUDGlassFlat`) | Broke it — quad never created (see NOT-to-do #1). |
| 0.0.70 | `ModMenuRenderMesh` quad @ depth 15 | Proven quad + proven depth; still nothing → model, not compositing. |
| 0.0.71 | `kModMenu` → `kHUDGlass` | Forward composite (dodges tiled-lighting geometry drop). Still nothing on its own. |
| 0.0.72 | **borrow the vanilla renderer** (Plan A.2) | Clone attached to the PROVEN, enabled `PipboyScreenModel` and **still invisible** ⇒ **the fault is the CLONE**, not any renderer. |
| 0.0.73 | rebind skin instances to clone skeleton + `CreateBoneMap` | Skinned meshes skin against the **source player's live skeleton** (raw pointers not remapped). Rebind by name. `102 bound / 229 unresolved`. |
| 0.0.74 | whole-tree name fallback for the 229 | `0 via whole-tree` — the 229 aren't elsewhere; they're **null slots**. |
| 0.0.75 | 4-agent consensus batch: pose copy, alpha restore, segment enable, vanilla-path lights, bhkWorld strip, pose probe | **Pose probe: `Chest world=(-0.0, 50.0, 0.0)`** = clone's flattened tree updates, pose sits exactly at the framed origin ⇒ **pose/framing/tree-update all GOOD.** Still invisible. |
| 0.0.76 | **null skin-bone recovery by pointer identity** | The 229 null slots' stale `worldTransforms[i]` still point into the SOURCE skeleton's bone array → identify the bone by pointer, rebind to the clone's same bone; unrecoverable → NULL the pointer (was: ~70% of the palette sampling the player's world position, shredding the mesh across thousands of units). **← awaiting test result.** |

### `[3DDIAG]` ground truth (the two renderers side by side)
```
VANILLA PipboyScreenModel: depth=15 postfx=2(kHUDGlass) geom=HUDGlassFlat:0
    mat=Materials\Interface\HUDGlassFlat.BGEM mask=HUDShadowFlat:0
    fullPremult=false hideWhenDisabled=true longRange=false offLights=0 alwaysRender=true customRT=-1
OURS  PipOS_Char3D (0.0.71+): depth=15 postfx=2(kHUDGlass) geom=ModMenuRenderMesh:0
    fullPremult=false hideWhenDisabled=true longRange=true(deliberate)  customRT=-1
```
We deliberately keep `ModMenuRenderMesh:0` (NOT-to-do #1) and `longRange=true` (our character sits ~80 units out; the item camera is short-range). Everything else mirrors vanilla.

### The pose-probe fact that matters most
`Chest world=(-0.0, 50.0, 0.0)` in the 0.0.75 log is *decisive*: it means (a) the cloned `BSFlattenedBoneTree` DOES update its bone worlds via `root.Update()`, and (b) framing lands the body at the origin as intended. So **do not** re-chase "the pose is wrong / the tree doesn't update / the model is off-camera." Those are settled. The remaining variable in 0.0.76 was the **skin binding** (the 229 null slots).

---

## 6. Current `CharacterCapture.cpp` map

Anonymous-namespace functions (line numbers as of 0.0.76; they drift — grep by name):

| Function | Role |
|---|---|
| `ForEachAVObject` | recursive NiAVObject visitor (the workhorse) |
| `FindFlattenedBoneTree` | locate the `BSFlattenedBoneTree` in a subtree |
| `FindFlattenedBoneByName` | linear search of `tree->bone[]` by name |
| `TryGetFramingTargetWorld` | framing-target bone world (Head/Chest/Pelvis/Root) |
| `CloneSubtree` | `NiCloningProcess` kCopyExact of the source, controllers detached/restored |
| `RepairShaderFadeNodes` | re-own each geometry's `BSShaderProperty::fadeNode` to the clone (0.0.64) |
| `EngineCreateBoneMap` | `REL::ID(1131947)` — rebuild flattened tree's node ptrs + name hash after clone |
| `EngineEnableAllSegments` | `REL::ID(246125)` — force-enable dismember segments |
| `RestoreShaderAlpha` | force `BSShaderProperty::alpha<=0 → 1` (transparent-material guard) |
| `CopyFlattenedPose` | copy SOURCE `bone[].local` → clone array by name (0.0.75) |
| `LogPoseProbe` | log Chest/Root/COM world at attach (telemetry) |
| `FindNodeByNameRecursive` | whole-clone-tree name search (0.0.74 fallback) |
| `RebindClonedSkins` | **the skin fix** — `CreateBoneMap`, shared-skin guard, per-bone rebind (flattened-array world first, then whole-tree), **null-slot recovery by pointer identity (0.0.76)** |
| `SanitizeClone` | orchestrates the fix pipeline (see below) |
| `FrameClone` | scale/yaw/translate framing (opt `a_distanceCap`) |
| `ApplyIdle` | per-pass breathing wobble + `root.Update()` |
| `ConfigureRenderer` | build OUR renderer (fallback path): kHUDGlass, depth 15, ModMenu quad |
| `ApplyDisplayClipRect` / `EnsureDisplayRoot` | reshape the screen-attached quad to the figure window |
| `AttachToRenderer` | own-path attach: display root, `Offscreen_Set3D`, lights |
| `BuildPreview` | own-path clone→sanitize→frame→attach |
| `AcquireVanillaRenderer` | resolve `PipboyScreenModel` (no Begin3D) |
| `HideAndRelease` | teardown: return borrowed slot, restore enable, drop clone |
| `Tick` | the per-pass driver (vanilla-first, own fallback) |
| `DumpOneRenderer`/`DumpRendererDiag` | `[3DDIAG]` one-time renderer config dump |
| `RunCaptureTask` | main-thread task body (calls Tick, `PushContract` on availability flip) |
| `HookedRunActorUpdates` | worker-thread hook: atomics + schedule only |
| `PushContract`/`SchedulePushContract`/`RegisterContractSink` | `root1.PipOS_char3d` contract to AS |

**`SanitizeClone` order (all before the single flush `root.Update`):** `RepairShaderFadeNodes` → `bhkWorld::RemoveObjects` → `CopyFlattenedPose` → `RestoreShaderAlpha` → `EnableAllSegments` (per geometry) → `RebindClonedSkins` → `root.Update()`. This mirrors TF3DHUD's "all structural fixups precede the final Update" ordering.

`RE_BSSkin.h` in `dll/src/` is a **copied, offset-asserted** `BSSkin::Instance` layout from TF3DHUD (the FOV-Slider fork only forward-declares it). Verified for 1.10.163 (sizeof 0xC0; `bones`@0x10, `worldTransforms`@0x28, `boneData`@0x40, `rootNode`@0x48, `paletteStamp`@0xBC).

---

## 7. Live 3D — decision tree for the next test

After the user tests **0.0.76**, read the log line:
```
[PipOS][3D] skin rebind: N bones rebound (T via whole-tree, F null-slots recovered by pointer identity, D null-slots dropped) across G geometries (S shared skipped, U unresolved)
```
and whether a character appears.

- **Character appears (even distorted/wrong-lit/wrong-size)** → **the chain is CLOSED.** Everything remaining is tuning via the in-game **Figure placement sliders** (Char3DScale / Char3DDistance / Char3DTarget / clip window) — these apply on the next Pip-Boy open, no rebuild. Then polish: lighting intensity, framing, the breathing idle. **This is the win condition.**
- **`F ≈ 229` but distorted/partial body** → the same-index shortcut in the pointer-identity recovery mis-mapped some bones. Change `RebindClonedSkins`'s null-recovery to **name-only** mapping (drop the `k < flattened->boneCount` same-index assumption; always resolve via `FindFlattenedBoneByName` on the source bone's name).
- **`F ≈ 0` (pointer identity matched nothing)** → the stale `worldTransforms` pointers don't aim into the source `BSFlattenedBoneTree::bone[].world` array. Next: also pointer-match against **source NODE `->world`** addresses via a recursive walk of `a_source`, and/or dump a few sample `worldTransforms[i]` addresses next to the source tree's bone-array range to see where they actually point.
- **Still nothing with F≈229 and no distortion** → pose/framing/skin are all correct and it *still* won't draw ⇒ escalate to the **banked endgame (§8): full fresh-skeleton construction.** All four deep-dive agents concluded a whole-root clone is the fragile approach precisely here; TF3DHUD never clones the live actor root.

Always confirm the supporting lines each pass: `pose copy: N` (>0), `pose probe: Chest world=(~0, ~+distance, ~0)`, `shader alpha: N`, `segments: N`, `clone attached to vanilla renderer 'PipboyScreenModel' (enabled=true) + offscreen light configured`.

---

## 8. Banked endgame — full fresh-skeleton construction (if 0.0.76 + name-only don't yield pixels)

This is TF3DHUD's actual recipe (from the deep-dive sweep, agent "construction pipeline" §5). It abandons the whole-root clone and **builds** the preview. Ordered steps with TF3DHUD `Previewer.cpp` refs and OG REL IDs:

1. **Fresh skeleton** — compute `race.skeletonModel[sex]` path (`GetRaceSkeletonModelPath`, `Previewer.cpp:971-984`) → `RE::BSModelDB::Demand(path, loadLevel=3,…)` (`1049-1063`) → clone via a seeded clone.
2. **Flatten** — `g_getActorBodyPart3D(player, root, &kRoot, false)` (`GetActorBodyPart3D` = **157573**) → `g_convertNodeTree(target)` (`ConvertNodeTree` = **633230**) → `CreateBoneMap(root)` (**1131947**, already used) → `FindFlattenedBoneTree` → `CreateBoneMap(flattened)`. (`986-1024`)
3. **Detach/prepare** — `bhkWorld::RemoveObjects(root,true,true)`, `StripControllerChains`, `PreparePreviewTree`.
4. **Per-part body/armor** (`SyncEquipmentsFromBiped`, `1934-2115`) — for each biped slot, clone `biped.object[i].partClone` **with `SeedSkinCloneMappings`** (`PreviewClone.cpp:57-104`): pre-seed `cloneProcess.cloneMap` with `skin->rootNode → previewRoot` and every `sourceBone → previewNode-by-name`, so the cloned armor **shares the fresh skeleton's real bones with zero rebind gaps** (this is why TF3DHUD never has our 229-null problem). Resolve parent (`FindPreviewAttachParent`, `805`), `AttachChild`, strip, `ResolveNullSkinBonesFromFlattenedTree` (`1296`), `MergeAttachmentSkinBones` (`1365`), `RebindSkinInstance` (`1758`).
5. **Default-skin fallback biped** for mask-excluded slots (naked/underwear body): `GetSkin` (**1042540**), `ArmorAddonUseModel` (**976291**).
6. **Segment reset** — `RestoreDisabledSlotVisibility` / `ApplyBipedSkinPartsVisibility` (`PreviewHeadParts.cpp:227,353`).
7. **Body tint + alpha** — `CalculateBodyTintColor` (**134537**), `UpdateBodyTintColorsOnScene` (**49935**), `RestorePreviewShaderAlpha`.
8. **Final rebind** (`RebindPreviewSkinInstances`, `1813`) → **sanitize** (`SanitizePreviewRenderTree`, `PreviewRenderTree.cpp:140`) → **frame** → `PrepareForInterface3DOffscreen` (`PreviewRenderTree.cpp:81`).

Optional fidelity (defer): head (`FixFaceGenHeadSkinInstances` **1131949**, `ResetFaceGenCurrentMorphs` **1174798**, `GetNPCHeadPart` **946253**, `GetDefaultRaceHeadPart` **1120148**); OMOD visuals (`TryAttachMod3DRecurse` **832528**); cloth (`CreateClothFor3D` **1322043**, `SetClothWorld` **19064**, `SetClothSettleOnTransitionToSim` **638869**); segments (`GetNumSegments` **331465**, `SetSegmentDisableCount` **1227683**, `EnableSegment` **1134184**, `DisableSegment` **1466142**).

This is a big round — do it via an **implementation subagent + adversarial audit** (see §11). It's fully scoped; no more investigation needed to start.

**Ruled out by the sweep (don't waste time here):** per-frame animation graph (our clone carries a valid captured pose — NOT required for a first frame); the render-boundary commit hook (`RenderPrepassesAndMenus`) is LOW for the vanilla path (the engine self-commits `offscreenElement`); cloth (cosmetic — static mesh renders without sim); Morph (cosmetic body sliders); the tiled-lighting hooks (structurally can't fire for the vanilla/kHUDGlass path).

---

## 9. TF3DHUD reference map (file:line, OG-relevant)

```
Previewer.cpp
  RebuildPreview .......................... 2239-2321   (once-per-build pipeline)
  LoadPreviewRaceSkeleton ................. 1026-1086
  ConvertPreviewSkeletonToFlattenedTree ... 986-1024
  RefreshPreviewBoneLookup (CreateBoneMap) 1251-1263
  ResolveNullSkinBonesFromFlattenedTree ... 1296-1348  (← ported in 0.0.76)
  RefreshSkinWorldTransformsFromBones ..... 1350-1362
  MergeAttachmentSkinBones ................ 1365-1438
  RebindSkinInstance ...................... 1758-1796  (← model for RebindClonedSkins)
  RebindPreviewSkinInstances .............. 1813-1852  (whole-tree final rebind + sourceSkins guard)
  SyncEquipmentsFromBiped ................. 1934-2115  (per-part body build)
  EnsurePreviewHead ....................... 2159-2228
  ApplyPreviewBodyTint .................... 2230-2237
  CommitRenderState / Impl ................ 2420-2580  (render-boundary; per-frame tail 2564-2579)
PreviewClone.cpp
  SeedSkinCloneMappings ................... 57-104     (the fresh-skeleton "no rebind gaps" trick)
PreviewRenderTree.cpp
  RepairShaderFadeNodes ................... 39-66      (← ported)
  PrepareForInterface3DOffscreen .......... 81-113
  SanitizePreviewRenderTree ............... 140-167    (selective cull: missing-material + NeckGore)
  RestorePreviewShaderAlpha ............... 169-183    (← ported in 0.0.75)
PreviewHeadParts.cpp
  EnableAllSegments ....................... 323-330    (← ported in 0.0.75)
  ApplyBipedSkinPartsVisibility ........... 227-259
  RestoreDisabledSlotVisibility ........... 353-385
Renderer.cpp
  ConfigureImpl ........................... 519-579
  AttachPreviewRoot ....................... 744-759
  ApplyRendererFOV ........................ 276-289
  ApplyDisplayPlacement ................... 458-517
Hooks.cpp
  InstallHooks ............................ 282-324
  HookedRunActorUpdates ................... 130-       (← we use the same call site)
  HookedRenderPrepassesAndMenus ........... 225-234    (render-boundary commit; not ported)
  HookedRenderSceneDeferred / CompositePassCtor 161-223 (tiled-lighting; N/A for kHUDGlass)
Lights.cpp
  ConfigureOffscreenLights ................ 267-286
  ResolveDirectionalLight ................. 161-179    (early-returns interior!)
Animations.cpp
  UpdateAnimationGraphManagerFloat ........ ~3805      (the per-frame pose writer; NOT needed for first pixel)
  SetAnimationGraphTarget ................. ~1819-1830
Address.cpp
  CreateBoneMap ........................... 102
src/RE/BSSkin.h ........................... (source of our RE_BSSkin.h)
```

---

## 10. Engine / commonlib reference

**Key commonlib headers** (`E:\Fallout 4 Modding\F4SE\FOV Slider F4SE\lib\commonlibf4\include\RE\`):
- `I/Interface3D.h` — the `Renderer` (all `Offscreen_*` / `MainScreen_*`, fields: `enabled@04C`, `alwaysRenderWhenEnabled@055`, `depth@074`, `offscreenElement@088`, `offscreenLights@1E0`, cameras `pipboyAspect/nativeAspect/nativeAspectLongRange@1A8-1B8`). **Note `Enable(bool a_unhideGeometries=false)`** — the bool is "also unhide geometries", NOT an on/off flag; `Enable()` turns the renderer on. Passing `false` is correct.
- `P/PipboyManager.h` — `GetSingleton`; `inv3DModelManager` (Inventory3DManager) @040.
- `I/Inventory3DManager.h` — `str3DRendererName@0C0`; `Begin3D`/`End3D`/`ClearModel`/etc. (REL VariantIDs in the header). **`LoadedInventoryModel` is only forward-declared** (exe-internal).
- `B/BSFlattenedBoneTree.h` — `FlattenedBone{ NiTransform local; NiTransform world; i16 parent/child/childCount/sibling; NiPointer<NiNode> node; BSFixedString name; }` (0xA0); tree has `boneCount`, `FlattenedBone* bone`, `BSTHashMap boneMap`.
- `B/BSGeometry.h` — `skinInstance@140`; virtual `GetSegmentData()` (vtable 3B).
- `B/BSShaderProperty.h` — `fadeNode@48`, `alpha@28`. `B/BSLightingShaderProperty.h` derives it.
- `B/bhkWorld.h` — `static RemoveObjects(NiAVObject*, bool recurse, bool force)`.
- `A/Actor.h` — `DropObject(...)` vtable **0EB** (native drop fallback candidate).
- `B/BSInputEventReceiver.h`, `B/ButtonEvent.h`, `I/IDEvent.h`, `U/UI.h` (`VTABLE::UI[0]` = `PerformInputProcessing`).

**REL IDs currently USED in our DLL:** `556439` (RunActorUpdates call site), `1131947` (CreateBoneMap), `1417022` (ForceUpgradeTextures), `246125` (EnableAllSegments).

**Cached vanilla/PBT decompiles** (scratchpad, for the AS side): `as_vanilla_inv`, `as_vanilla_menu`, `as_vanilla_DataPage/RadioPage/MapPage`, `pbt_decomp`, `shell_vanilla_decomp`. ffdec at `E:\Fallout 4 Modding\F4SE\PluginTemplate\jpexs-gui\ffdec.jar`. (Scratchpad root: `C:\Users\rober\AppData\Local\Temp\claude\e--Fallout-4-Modding-F4SE\800cd7d8-599e-4ebe-940c-b0690f31f037\scratchpad`.)

---

## 11. Subagent workflow (what worked)

The Live 3D breakthroughs came from **read-only investigation subagents** (opus, backgrounded) with tightly scoped prompts against BOTH codebases, followed by an **adversarial audit subagent** before shipping anything structural. This pattern repeatedly caught fatal issues:
- The audit of the skin-rebind (0.0.73) returned **DON'T SHIP** and caught (a) the clone's flattened tree needing its own `CreateBoneMap`, and (b) a live-player-corruption path (shared skin instances) — both fixed pre-ship.
- The 4-agent parallel sweep of all of TF3DHUD **cross-validated** findings: two agents independently fingering the flattened bone array, two the shader alpha; and one agent's "commit hook" theory was *demoted* by another's stronger analysis, saving the most expensive port.

Recommended: for the endgame (§8) or any clone-pipeline change, spawn one implementation-plan agent + one adversarial audit agent. Give them exact file paths, the current symptom, the relevant log lines, and "cite file:line; say 'unknown-exe-internal' where headers don't expose it." Do NOT let an agent guess REL IDs — have it read `Address.cpp`.

---

## 12. Other open bugs (not Live 3D)

### Inventory DROP — STILL BROKEN
Pressing R (or the context-menu Drop) plays a select sound but doesn't drop. Diagnostics are **armed** in the current build:
- `onKey` logs `IV.rK` when R (keyCode 82) reaches the handler; `doDrop` logs `IV.d<idx>` pre-guard (shows folder-header `-1` too).
- `doDrop` writes `root1.PipOS_droplog = "<seq>|list=<displayIdx>|inv=<invIdx>|cnt|fav|eq|fid=<unsignedFormID>|<name>"`; the DLL logs it as `[DROP] ...` (bypasses the AS life-trail's 700-char cap that was eating `IV.dr` marks).
Read those on the next test. **Hypothesis:** the engine's `ItemDrop` wants the **display index** (`this._list.selectedIndex`) not the InvItems index (`invIdx`) we currently pass — vanilla passes `List_mc.selectedIndex`; OR it reads the vanilla `List_mc` we don't populate. If the engine call is genuinely inert, **fallback: native `Actor::DropObject`** (vtable 0EB) on the player, using the formID already in the `[DROP]` line (the AS `fidKey()` gives the canonical unsigned form).
Note: engine inventory calls use `uint()`-normalized signed formIDs — the engine hands AS a **signed** formID (high-bit forms read negative); `PipOS_InvPage.as::fidKey()` converts to unsigned. That fixed the weapon-stats join (0.0.63); the same signedness may matter for any formID-keyed engine call.

### Right-click context menu — should WORK, verify
GFx never delivers `RIGHT_MOUSE_DOWN` to the movie, and `GetAsyncKeyState` is blind to the RMB under FO4 raw input (both field-proven). So right-click is forwarded via a **vfunc hook on `UI::PerformInputProcessing`** (`VTABLE::UI[0]`, `write_vfunc(0)`) that watches for a mouse `ButtonEvent` `idCode==1` `QJustPressed` while the Pip-Boy is open and bumps `root1.PipOS_rclickN`. AS `onCharPoll` reads the counter and opens the menu at the row under the cursor (position-based `PipList.rowAtMouse()`, since hover goes stale). Menu actions dispatch **by coordinates** in a capture-phase stage handler. Log lines: `[RC] right-button press seen in UI input chain`, `[RC] SetVariable root1.PipOS_rclickN=N ok=true`, trail `IV.rc`, `CX.<act>`. This worked in the 0.0.68 test; re-verify after the churn.

### Recently FIXED (don't re-open)
Weapon stats "DAMAGE 17 / ACC 0" (0.0.60 `TESBoundObject::ApplyMods` instance data + 0.0.63 signed-formID `fidKey`); equipped indicator; apparel +/- color coding; STATUS/DATA blank-on-re-entry (medic always pumps a data event after a heal); vanilla keybar (removed + `BottomBar_mc` hidden); transparency (`SetBackgroundAlpha(0)` on both pipboy movies); user-ini settings persistence.

---

## 13. Broader project state (context)

Pages STAT/INV/DATA/RADIO/MAP are implemented and rendering; the **Shell Medic** (in `Chrome.as`) works around a vanilla shell wedge where a page loads but never stages (heals by `addChild` + a substitute `PipboyChangeEvent` pump). The **crash law** governs all AS: never create a `TextField` or write geometry on interaction/tick/data paths — pool everything and only update text/visibility/graphics; `tools/ctor_text_check.py` enforces it. `pipos/PipList.as` is the shared list widget; `pipos/Theme.as` the palette/helpers; `pipos/Chrome.as` the CRT overlay + medic. Backlog (non-blocking): legendary-marker polish, open-anim speed already added, Map page round, Misc-objective tracking, QA real icons. See the memory file for the full feature history and the FunctionalitySpec/DESIGN.md ("every UI element has purpose").

---

## 14. Quick start for the continuing agent

1. Read the top of `…\memory\pipos-pipboy-state.md` (0.0.76 entry) and this doc's §5, §7, §12.
2. Ask the user to install **0.0.76** (`dist\PipOSPipboy-TestA-0.0.76.zip`), enable Live 3D, open the Pip-Boy, and send the log.
3. Grep the log for `\[3D\]`, `\[RC\]`, `\[DROP\]`. Apply the §7 decision tree for Live 3D; read `[DROP]` for the drop bug.
4. Build → gate (if AS) → package (§2 layered) → commit `-F` → push. Update the memory file's top entry each round.
