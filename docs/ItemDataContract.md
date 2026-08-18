# PIP-OS Item-Data DLL to AS3 Contract

Status: DLL side implemented (0.0.25, additive, always on at Pip-Boy open). AS3 wiring (item card, inspect
"Current Mods", quick-access boxes, tooltips) is a LATER round. This file is the exact spec that round joins.

Source: `dll/src/PipboyBridge.cpp` `PushItemStatsNow` (idiom mirrors `PushEquipmentNow` / `PushItemInfoNow`).
Log tag: `[PipOS]` (lines `itemstats:` / `favorites:`).

## Why this exists

The engine `_cardInfo` selection callback fills nothing (`_cardInfo.length == 0`), so the item card, the
inspect overlay, and the quick-access hotbar had no real data. This push supplies that data natively. It is
ADDITIVE: `PipOS_equip` and `PipOS_iteminfo` are unchanged. Absent members must degrade to blank fields.

## Join key

All three members key by the inventory row's form ID, as the DECIMAL string of the base object form ID
(`String(formID)`, e.g. `"73530"`). The AS3 inventory rows carry that form ID (row `.formID` / engine
`formId:Number`); join with `String(row.formId)` (adjust the field name to whatever the engine populates).
When two stacks share a base form ID (same base, different mods) the FIRST stack seen wins, deterministically.

## Members pushed on root1 (each Pip-Boy open, on the UI task)

### 1. `root1.PipOS_itemstats` : Object (map, formID -> stats)

Every entry has a `type` string; the remaining fields depend on `type`. Fields are OMITTED (not null) on any
miss, so AS3 must feature-test each field. All numeric fields are AS3 Numbers; names are Strings.

```
PipOS_itemstats["<formID>"] = {
    type : "weapon" | "apparel" | "aid" | "ammo" | "note" | "misc",

    // type == "weapon"
    dmg      : Number,   // base attack damage (weaponData.attackDamage)
    firerate : Number,   // 10 * speed / attackDelaySec (shots-per-10s, vanilla "FIRE RATE"); see gap note below
    rpm      : Number,   // rounds-per-minute == 60 * speed / attackDelaySec == 6 * firerate (same guarded divide)
    range    : Number,   // weaponData.maxRange (game units)
    acc      : Number,   // DLL-derived accuracy proxy 0..100 (from aim-model min cone); OMITTED if no aim model
    ammo     : String,   // ammo/caliber full name (weaponData.ammo); OMITTED if none

    // type == "apparel"
    dr     : Number,     // physical damage resist == armorData.rating
    er     : Number,     // energy resist  (from per-damage-type resist array); OMITTED if the piece has none
    rr     : Number,     // rad resist     (from per-damage-type resist array); OMITTED if the piece has none
    effect : String,     // first enchantment full name (legendary / effect); OMITTED if unenchanted

    // type == "aid"
    effect    : String,  // primary magic-effect full name (first effect's base effect); OMITTED if none
    magnitude : Number,  // first effect magnitude (e.g. 30 for "+30% HP")
    duration  : Number,  // first effect duration in seconds (0 == instant)
    addiction : Number,  // addiction risk as a percent 0..100 (AlchemyItem addictionChance * 100)

    // type == "ammo"
    usedby : String      // a representative weapon that fires this ammo; OMITTED if none derivable
}
```

Notes for the card layout (mockup `showCard` stat pairs):
- Weapons -> Damage / Fire Rate / Range / Accuracy come from `dmg` / `firerate` / `range` / `acc`. The
  Ballistic<->Energy toggle and the ~0.35x energy value is an AS3 presentation concern (mockup `dmgMode`); the
  DLL pushes the ballistic base only.
- Both `firerate` AND `rpm` are ALWAYS pushed for weapons; `PipOS_settings.showRPM` (see below) selects which
  the card shows -- `showRPM ? ("RPM " + rpm) : ("FIRE RATE " + firerate)` -- with no extra native read. Each is
  rounded to an int at display time like the other stats.
- Apparel -> DMG / Energy / Rad Resist + Effect come from `dr` / `er` / `rr` / `effect`.
- Aid -> Effect / Duration / Addiction come from `effect` (+ `magnitude`) / `duration` / `addiction`.
- Ammo -> "Used By" comes from `usedby`.

### 2. `root1.PipOS_itemmods` : Object (map, formID -> Array<String>)

The installed object-mod full names on the item instance (weapons AND armor), for the inspect "Current Mods"
panel (mockup line 784 `mods:[...]`). Only present for items that actually have named mods installed. Nameless
mods (mods that name via instance-naming rules rather than a full name) are skipped. Capped at 16 per item.

```
PipOS_itemmods["<formID>"] = [ "Long Barrel", "Reflex Sight", "Suppressor", ... ]
```

Extraction: the stack `ExtraDataList` -> `BGSObjectInstanceExtra` -> `GetIndexData()` gives the installed OMOD
index records; each `objectID` resolves to a `BGSMod::Attachment::Mod` form whose full name is listed
(disabled records skipped).

### 3. `root1.PipOS_favorites` : Array (12 entries, one per Pip-Boy quick-key slot)

Fixed length 12 (the engine `FavoritesManager::storedFavTypes` array). Index i == quick-key slot i. Empty
slots are still present with `formID == 0` and empty strings, so AS3 can render an empty box without a
length check.

```
PipOS_favorites[i] = {
    slot   : Number,   // 0..11 (== array index)
    formID : String,   // decimal form ID of the favorited base object, or "0"/Number 0 if the slot is empty
    name   : String,   // full item name (long; reveal in the hover tooltip, do not bake into the box)
    count  : Number,   // total count of that item in the player inventory (0 if none / empty slot)
    type   : "weapon" | "apparel" | "aid" | "ammo" | "note" | "misc"   // drives the per-box icon glyph
}
```

Use `type` for the quick-access box icon (mockup `#qa`) and `name` for the hover tooltip (QOL spec item 2/3).

### 4. `root1.PipOS_settings` : Object (customization mirror)

The F4SE-Menu-Framework-editable customization settings, pushed on each Pip-Boy open alongside the item maps.
ADDITIVE and fully optional: AS3 must feature-test each member and fall back to its own const defaults (the same
numbers) whenever the object or a member is absent, so an old shell / missing DLL / marshalling failure all
degrade to shipping behavior.

```
PipOS_settings = {
    veil     : Number,   // PIP-OS world-dim veil alpha (default 0.10)
    breathe  : Boolean,  // CRT phosphor breathing (default true)
    openAnim : Boolean,  // power-on open animation (default true)
    folders  : Boolean,  // FIS / Complex-Sorter folder grouping (default true)
    showRPM  : Boolean   // weapon card stat select: false = FIRE RATE (default), true = RPM
}
```

`showRPM` selects which weapon-card stat the shell displays from the always-present `itemstats[fid].firerate` /
`itemstats[fid].rpm` pair: `showRPM ? ("RPM " + rpm) : ("FIRE RATE " + firerate)`.

## Hard caps

- Stats + mods maps: at most 1024 inventory objects processed (`kMaxStatEntries`).
- Mods list: at most 16 names per item (`kMaxModsPerItem`).
- Favorites: exactly 12 slots (`kMaxFavorites`).

## Safety

Read-only, null-guarded at every dereference, on the UI-task thread (same proven affinity as the equipment /
iteminfo pushes). `catch(...)` wraps each section but does NOT catch a Windows AV under `/EHsc`, so the null
guards are the real protection; any miss omits the field or degrades the whole section to a partial/empty map,
never a CTD. Additive only: the existing equipment / iteminfo / transform pushes are untouched.

## Honest scope / documented gaps

- **Stats are BASE-form values, not per-instance modded values.** `weaponData` / `armorData` are read as plain
  member fields (no engine calls, no AV risk). They are the authored UNMODDED numbers. The per-instance stat
  deltas that installed mods apply are NOT folded in, because safely building fully-modded `TBO_InstanceData`
  requires engine instantiation calls that would risk an AV in this untestable auto-install build. The installed
  mod NAMES are still fully listed via `PipOS_itemmods`, so the inspect "Current Mods" panel is accurate even
  though the headline stat numbers are the base values. If a later round wants modded numbers, it should do so
  on a worker task with heavy guarding, or read the engine-derived values through a card callback.
- **Weapon `acc` is a DLL proxy**, computed as `clamp(100 - aimModelMinConeDegrees * 40, 0, 100)`, not the
  engine's exact 0..150 derived accuracy stat (which lives behind an engine call). Lower cone -> higher value.
- **`firerate` is the attack-speed field** (`weaponData.speed`), a monotonic proxy for rate of fire, not the
  engine's rounded rounds-per-second display value.
- **Apparel `er` / `rr`** are bucketed by matching the damage type's resistance actor-value editorID substring
  ("energy" / "rad"). Non-standard damage types (modded resist AVs whose editorID does not contain those
  substrings) are not bucketed and are omitted. Physical `dr` uses the dedicated `armorData.rating` field and
  is always present for apparel.
- **Ammo `usedby`** is derived from the player's own weapons only (the weapon->ammo table built during the same
  inventory pass). Ammo for which the player holds no matching weapon has no `usedby` and the field is omitted.
