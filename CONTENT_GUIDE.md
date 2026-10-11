# Content Pack Guide: turning game content into JSON

This guide explains how to write **classes, subclasses, level progression,
features, traits, ammo, weapons, armor, items and backgrounds** as JSON so
they can be imported into the app.

Import a standalone pack file at runtime from **Catalog -> Import JSON file**.
On Android, first copy the JSON file into a location available in the system
file picker (such as Downloads), then select it. For pasted content, use the
paste button in the Catalog app bar; the "Insert sample" button loads a working
example. Imported entries are saved into the campaign catalog and can be added
to characters with the library button on the matching panel.

---

## 1. The basics

A content pack is one JSON object. Every section is optional; include only
what you need.

```json
{
  "pack": "My Pack",
  "weapons":      [ ],
  "armor":        [ ],
  "items":        [ ],
  "skills":       [ ],
  "feats":        [ ],
  "spells":       [ ],
  "actions":      [ ],
  "traits":       [ ],
  "features":     [ ],
  "backgrounds":  [ ],
  "classes":      [ ]
}
```

- `pack`, `description`, `author`, `schemaVersion` are optional notes and are ignored.
- Every section shown above is supported. Any other top-level key produces a
  **warning** and is skipped. The legacy `affiliations` key is still accepted
  and imported as `backgrounds`.
- **Ammo is an item** with `"kind": "ammo"` and `"category": "ammo"` (see
  section 5).
- Skills, feats, spells, and actions are data-defined catalog sections. Skills
  define the ability used for a check; feats can carry `effects`; actions are a
  grouped reference list. Spells can include any fields, and the character
  sheet's **Spells** tab edits their name, level, school, casting time, range,
  components, duration, and description.
- Class definitions are selected from the character's level-up control; they
  are not added to a character with the Catalog library button.

### Spells

Import spells into the Catalog, then add them to a character from the **Spells**
tab. The app keeps spell entries as generic JSON, so additional fields in a
content pack are preserved when characters are saved and exported.

```json
{
  "spells": [
    {
      "id": "fire_bolt",
      "name": "Fire Bolt",
      "level": "Cantrip",
      "school": "Evocation",
      "castingTime": "1 action",
      "range": "120 feet",
      "components": "V, S",
      "duration": "Instantaneous",
      "description": "A streak of fire."
    }
  ]
}
```

### JSON rules (the usual cause of "Invalid JSON")
- Double quotes only: `"name"`, not `'name'`.
- No trailing commas after the last entry in a list or object.
- No comments.
- Numbers are written without quotes: `"hp": 30` (`"30"` is tolerated, but don't).
- `true` / `false` are lowercase and unquoted.

### Fields every entry shares
| Field  | Required | Notes |
|--------|----------|-------|
| `name` | **yes**  | An entry with no name is rejected (others still import). |
| `id`   | no       | Unique key within its section. Defaults to the name in lowercase with underscores (`"PP-19 Bizon"` -> `pp_19_bizon`). **Importing an entry with an existing `id` replaces it**, so keep ids stable. |

Importing never deletes anything; it only adds or updates. A bad entry is
reported in the result dialog and the rest still import. Catalog entries are
**templates**: adding one to a character makes a copy, so editing the catalog
later does not change existing characters.

---

## 2. Effects (modifiers)

Weapons, armor, traits, features, background features and inventory items can
carry `effects`. Use the sheet's **Edit effects** control to choose a stat by
its readable name and enter a bonus; JSON uses the target keys shown below.
An effect adds a number to something on the sheet. Base values you typed stay
untouched; the sheet shows the combined result. Ability scores show the base
score, the separate bonus, and the resulting total.

```json
"effects": [
  { "target": "ac", "value": 2 },
  { "target": "skill.stealth", "value": -1 }
]
```

| `target` | What it changes |
|----------|-----------------|
| `ac` | Armor class |
| `speed` | Speed (ft) |
| `initiative` | Initiative bonus |
| `proficiency` | Proficiency bonus (on top of the level-based value) |
| `hp.max` | Maximum HP |
| `attack` | Attack bonus of **all** weapons |
| `ability.str` `ability.dex` `ability.con` `ability.int` `ability.wis` `ability.cha` | An ability **score** (modifiers follow automatically) |
| `save.str` ... `save.cha` | A saving-throw bonus |
| `skill.<name>` | A skill bonus (see below) |

Note Intelligence is `int` (`ability.int`, `save.int`).

**Skill names** are written in lowercase with underscores replacing spaces and
punctuation:

| Skill | Target |
|-------|--------|
| Stealth | `skill.stealth` |
| Sleight of Hand | `skill.sleight_of_hand` |
| Animal Handling | `skill.animal_handling` |
| Armaments | `skill.armaments` |
| Technology | `skill.technology` |

Skills are loaded from [`content/skills.json`](content/skills.json). Add skills
to that section with an `id`, `name`, and ability key to include them in new
characters. Class skill choices may also define a skill directly with
`grantType: "skill"` and `skillAbility`.

For compatibility with existing content, skill descriptions on a character's
traits/features also grant proficiency or expertise when they explicitly say
`proficient in/with <skill>` or `expertise in/with <skill>`. Prefer structured
`skillProficiencies` or `grantType: "skill"` data for newly authored content.

### Programmatic effects

Effects may include `components` to calculate a modifier from current ability
scores instead of storing a fixed number. A component's `calculation` is
`modifier` (the ability modifier) or `score` (the full ability score); the
optional `multiplier` and `divisor` scale that component. Components are added
to `value`.

```json
{
  "target": "ac",
  "value": 10,
  "components": [
    { "ability": "dex", "calculation": "modifier" },
    { "ability": "wis", "calculation": "modifier" }
  ],
  "condition": "noBallisticProtection",
  "operation": "setBase"
}
```

The supported condition `noBallisticProtection` applies only when the
character has no equipped armor with a rating above zero. The supported
operation `setBase` replaces the editable base AC while its condition is met;
ordinary additive AC effects are then added. This supports Scout's Unarmored
Defense (10 + DEX modifier + WIS modifier) and returns to base/equipment AC
when ballistic armor is equipped. `add` is the default operation.

Rules to remember:
- Additive effects **add together**; use negative values for penalties.
- Armor effects only count while the armor is **Equipped**.
- Trait/feature effects always count. Weapon effects count while the weapon is on the sheet.
- Inventory item effects apply only while that item is marked **Active**.
- Expertise or proficiency described in a trait/feature is included in the
  matching skill bonus. Numeric modifiers should still use `effects`.
- A misspelled target is **silently ignored**. If a bonus isn't showing, check the spelling first.

Armor Class is displayed as the calculated total: base AC plus effects from
equipped armor and active inventory items. Edit the base separately from the
equipment bonuses.

### Equipment rule effects

Armor and ordinary inventory items can also carry `ruleEffects` for gear rules
that are not numeric sheet modifiers:

```json
"ruleEffects": [
  { "type": "ricochetChance", "value": 65 },
  {
    "type": "factionDisposition",
    "faction": "Killa",
    "disposition": "friendly"
  }
]
```

- `ricochetChance` sets the character's evaluated chance to an integer from 0
  to 100. The last matching equipped/active gear effect takes precedence.
- `factionDisposition` sets a faction's disposition to `friendly`, `neutral`,
  or `hostile`. Faction names are matched without regard to case; the last
  matching equipped/active gear effect takes precedence.
- Armor rule effects apply only while equipped. Inventory-item rule effects
  apply only while the item is active.

These values are available to the character rules layer and shown with the
gear; they do not perform a ricochet roll or change an NPC's AI automatically.

---

## 3. Weapons

```json
{
  "id": "pp19",
  "name": "PP-19 Bizon",
  "ammoType": "9x18mm",
  "ammoMax": 30,
  "ammo": 30,
  "roundsPerShot": 3,
  "damage": "2d6+2",
  "attackAbility": "dex",
  "proficient": true,
  "attackBonus": 0,
  "hp": 40,
  "hpMax": 40,
  "properties": "Burst fire, two-handed",
  "effects": []
}
```

| Field | Default | Meaning |
|-------|---------|---------|
| `ammoType` | `""` | Must match an ammo item's `ammoType` (not case-sensitive). **Blank = needs no ammo** (melee). |
| `ammoMax` | `0` | Magazine size. **0 = fire straight from inventory ammo.** Above 0 = the weapon holds loaded rounds; the DM can allow firing to pull a shortfall from inventory, otherwise use **Reload**. |
| `ammo` | `0` | Rounds currently loaded. Only used when `ammoMax` > 0. |
| `roundsPerShot` | `1` | Current rounds per shot: the semi-auto setting, burst count, or most recent full-auto die result. |
| `semiRoundsPerShot` | `roundsPerShot` | Semi-auto rounds per shot, retained when switching firing modes. |
| `lastFullAutoRounds` | unset | Most recent full-auto bullet-die result; becomes `roundsPerShot` while full auto is selected. |
| `burstRounds` | `0` | Exact number of bullets spent in burst mode. When zero, burst falls back to the semi-auto rounds-per-shot setting. |
| `damage` | `""` | Dice expression: `1d8`, `2d6+2`, `1d10-1`, `1d8+1d6+3`. |
| `fireModes` | `["semi"]` | Available modes: `"semi"`, `"burst"`, `"fullAuto"` (represented in app code by the `FireMode` enum). |
| `firingMode` | `"semi"` | Selected firing mode; chosen by the player in the weapon panel. JSON stores enum names as strings. |
| `bulletDice` | `""` | Full-auto dice, e.g. `"1d6"`. The roll result is the rounds spent and, on a hit, the number of bullets that hit. |
| `burstDamage` | `""` | Combined damage expression for the burst (e.g. `"3d6"` for three rounds). |
| `damageAbility` | `""` | Optional ability modifier (`"str"` or `"dex"`) added to the damage roll. |
| `weightKg` | `0` | Optional weapon weight, in kilograms. |
| `weaponType` | `""` | Optional equipment classification. |
| `attackAbility` | `"dex"` | `str`, `dex`, `con`, `int`, `wis`, `cha`. |
| `proficient` | `true` | Adds proficiency bonus to the attack roll. |
| `attackBonus` | `0` | Flat bonus to attack (magic, optics, ...). |
| `hp` / `hpMax` | `0` | Weapon durability. `hpMax` defaults to `hp` if omitted. |
| `properties` | `""` | Free text. |
| `effects` | `[]` | See section 2. |

Semi/full-auto attack roll = d20 + ability modifier + proficiency (if proficient) + `attackBonus`
(+ any `attack` effects). **Put damage bonuses in the `damage` text** (e.g.
`2d6+2`); the ability modifier is not added to damage automatically unless
`damageAbility` is set.

For full auto, set `bulletDice` (for example `"1d6"`). Each trigger pull rolls
that expression and spends exactly the result from the magazine or matching
ammo stack. On a successful attack, that many rounds hit; damage is rolled
once per hit. The weapon's `roundsPerShot` shows the roll result and restores
the saved `semiRoundsPerShot` when switching back to semi-auto. Burst mode spends
`burstRounds`, rolls one d20 attack, and on a hit all bullets in that burst
hit; it does not roll `bulletDice`. `burstDamage` is rolled once for the
combined burst. The selected mode is saved with the weapon.

The DM setting **Pull ammo from inventory when firing** controls magazine
weapons (`ammoMax` > 0): when enabled, a shot uses loaded rounds first and
pulls only any remaining rounds it needs from matching inventory ammo. The
magazine capacity still limits a shot. When disabled, the magazine must already
hold the complete shot and the weapon must be explicitly reloaded. Weapons with
`ammoMax` of 0 always draw directly from inventory, regardless of this setting.

A minimal melee weapon:
```json
{ "name": "Combat Knife", "damage": "1d4+2", "attackAbility": "str" }
```

---

## 4. Armor

```json
{
  "id": "6b45",
  "name": "6B45 Plate Carrier",
  "rating": 3,
  "hp": 30,
  "hpMax": 30,
  "equipped": true,
  "properties": "Class 4 plates",
  "effects": [
    { "target": "ac", "value": 2 },
    { "target": "skill.stealth", "value": -1 }
  ]
}
```

| Field | Default | Meaning |
|-------|---------|---------|
| `rating` | `0` | The armor rating shown on the sheet (the "3" and "2" in your armor boxes). **Display only.** |
| `hp` / `hpMax` | `0` | Armor durability (the "30" and "50"). `hpMax` defaults to `hp`. |
| `equipped` | `true` | Only equipped armor applies its effects. |
| `equipmentSlot` | `""` | Optional classification: `"head"`, `"body"`, `"rig"`, or `"other"`. Display only; it does not enforce one item per slot. |
| `weightKg` | `0` | Armor weight in kilograms; included in known carried weight. |
| `carryCapacityKg` | `0` | Optional container capacity in kilograms; counts only while the armor is equipped. |
| `storageSlots` | `{}` | Optional slot counts by type, e.g. `{"magazine":4,"grenade":2}`. Displayed as capacity reference; slot occupancy is not assigned or enforced. |
| `properties` | `""` | Free text. |
| `effects` | `[]` | **This is how armor changes AC.** Use `{"target":"ac","value":N}`. |
| `ruleEffects` | `[]` | Equipment rules such as ricochet chance or faction disposition (see section 2). |

Important: `rating` does not change AC by itself. If the armor should raise AC,
add an `ac` effect.

For an armor formula such as `"AC=12+DEX"` on a sheet with base AC 10, encode
the delta and ability modifier as an additive effect:

```json
{
  "target": "ac",
  "value": 2,
  "components": [{ "ability": "dex", "calculation": "modifier" }]
}
```

---

## 5. Items and ammo

Everything carried that isn't a weapon or armor goes in `items`.

### Ammo
```json
{
  "id": "ammo_9x18_fmj",
  "name": "9x18mm FMJ",
  "kind": "ammo",
  "category": "ammo",
  "ammoType": "9x18mm",
  "quantity": 90
}
```
`quantity` is the number of **rounds**. `ammoType` identifies the caliber or
cartridge; a round/load subtype such as FMJ or AP is not part of compatibility.
For example, a weapon with `ammoType: ".338"` can use an ammo item whose type is
`.338 Lapua Magnum FMJ`. Firing and reloading match by the leading caliber and
cartridge designation, ignoring subtype text; distinct cartridges such as
`7.62x39` and `7.62x51` remain separate. Matching stacks are consumed first
stack first. For display, the catalog picker sorts ammunition by type first,
then subtype/name; medical and miscellaneous items are sorted alphabetically.

### Ordinary items
```json
{
  "id": "afak",
  "name": "AFAK Medical Kit",
  "kind": "item",
  "category": "medical",
  "description": "Heals 2d4+2 HP per use.",
  "quantity": 1,
  "usesMax": 3,
  "active": false,
  "effects": [
    { "target": "ability.dex", "value": 1 }
  ]
}
```

| Field | Default | Meaning |
|-------|---------|---------|
| `kind` | `"item"` | `"item"` or `"ammo"`. Anything else is treated as `"item"`. |
| `category` | inferred for older packs; `"misc"` for new blank items | Catalog grouping: `"ammo"`, `"medical"`, or `"misc"`. Set this explicitly so the item picker groups the entry correctly. This does not change item behavior; use `kind` to mark ammunition. |
| `quantity` | `1` | Stack size (rounds for ammo). |
| `weightKg` | `0` | Weight per unit (per round for ammo); stacked item weight is multiplied by quantity. |
| `carryCapacityKg` | `0` | Optional container capacity in kilograms. Only active items contribute. If more than one container is active, only the greatest capacity counts; capacities do not stack. |
| `storageSlots` | `{}` | Optional slot counts by type, e.g. `{"magazine":4,"grenade":2}`. Displayed as capacity reference; slot occupancy is not assigned or enforced. |
| `usesMax` | `0` | Uses per unit. `0` = no uses; pressing **Use** just removes one from the stack. |
| `uses` | `usesMax` | Uses left on the current unit. |
| `ammoType` | `""` | Ammo only. Caliber/cartridge used to match a weapon; any round/load subtype is ignored. |
| `penetration` | `0` | Ammunition penetration rating, if provided. |
| `durabilityBurn` | `1` | Weapon durability multiplier for this ammunition. |
| `damage` | `""` | Optional damage dice rolled by **Use**, e.g. for a grenade. |
| `damageType` | `""` | Damage type displayed with the roll. |
| `areaRadius` | `0` | Optional area radius in feet, shown when the item is used. |
| `saveDc` / `saveAbility` | `0` / `""` | Optional saving-throw details shown when the item is used. |
| `description` | `""` | Free text. |
| `active` | `false` | When true, non-ammo item effects apply to the character. |
| `effects` | `[]` | Numeric modifiers; only apply while the item is active. |
| `ruleEffects` | `[]` | Ricochet/faction rules; apply only while the item is active. |

The inventory panel shows known carried weight: weapon weight, armor weight,
and item weight multiplied by quantity. Entries with no weight data contribute
zero. An over-capacity warning appears only when an active/equipped container
has a configured capacity. The active/equipped container with the largest
capacity is used; capacities are not added together. The Active toggle also
controls item effects and backpack capacity.

The catalog item picker groups inventory under **Ammo**, **Medical
equipment**, and **Tools / misc**. Ammo is sorted by `ammoType` and then its
subtype/name; medical and miscellaneous items are sorted alphabetically. Set
`category` on every new catalog item:

- `"ammo"` for ammunition. Also set `"kind": "ammo"` and `ammoType`.
- `"medical"` for medical supplies and treatment kits. Use `"kind": "item"`.
- `"misc"` for tools, equipment, consumables, and anything outside the other
  groups. Use `"kind": "item"`.

Ammo entries may also define `penetration` (integer penetration rating) and
`durabilityBurn` (weapon-durability multiplier). These values are retained in
the item data; the detailed armor-vs-ammo outcome table is currently a
reference in [`content/tarkov_mechanics.json`](content/tarkov_mechanics.json),
not an automatic target-damage calculator.

`category` only controls the catalog picker group; `kind` controls ammunition
behavior. For compatibility, older entries without `category` continue to
load: ammo is inferred from `kind`, and familiar medical terms in the name or
description are used to identify medical equipment. New packs should not rely
on that inference.

How **Use** works with `usesMax: 3`, `quantity: 2`: uses go 3 -> 2 -> 1 -> 0;
when a unit hits 0, `quantity` drops by one and `uses` resets to 3 (if any
units remain).

---

## 6. Traits and features

Traits and features are identical in structure. The only difference is which
section you put them in (which sets their label on the sheet).

```json
{
  "id": "iron_nerves",
  "name": "Iron Nerves",
  "description": "Advantage on saving throws against fear.",
  "source": "Background",
  "effects": []
}
```

```json
{
  "id": "second_wind",
  "name": "Second Wind",
  "description": "Once per rest, regain hit points.",
  "effects": [ { "target": "hp.max", "value": 2 } ]
}
```

| Field | Default | Meaning |
|-------|---------|---------|
| `description` | `""` | Rules text. |
| `source` | `""` | Where it comes from (shown on the sheet). |
| `category` | `"trait"` in `traits`, `"feature"` in `features` | Only set this to override the section's default. |
| `effects` | `[]` | See section 2. |

Rules text that has no numeric effect (advantage, once-per-rest abilities,
narrative perks) goes in `description` only. Add `effects` for numeric bonuses
or penalties. Skill proficiency and expertise explicitly described in a
granted trait/feature also affect that skill's bonus.

### Feats

Feats are imported as catalog entries under the top-level `feats` key. A feat
uses the same fields as a feature and may define numeric `effects`:

```json
{
  "feats": [
    {
      "id": "field_awareness",
      "name": "Field Awareness",
      "description": "A campaign-specific feat.",
      "effects": [{ "target": "initiative", "value": 1 }]
    }
  ]
}
```

Define the class levels at which characters choose a feat with `featLevels`.
The standard progression is levels 4, 8, and 12. At those levels, level-up
requires choosing one feat from the imported catalog; the selected feat is
copied onto the character and its effects apply. Import at least one feat
before advancing a character to one of those levels.

```json
{
  "id": "vanguard",
  "name": "Vanguard",
  "hitDie": 10,
  "featLevels": [4, 8, 12],
  "levels": []
}
```

### Actions and player stash

Entries in the top-level `actions` list use `id`, `name`, `actionType`
(`"action"`, `"bonus"`, or `"reaction"`), and `description`. They appear in
the character sheet's Combat Actions lookup.

The player stash is saved separately from each character and keyed by the
character's Player field (case-insensitive). Use **Move to player stash** on
weapons, armor, and items, then transfer them to any character assigned to the
same player. Characters without a player name cannot use the shared stash.

---

## 7. Backgrounds

A background is a faction or organisation in this campaign. It **bundles
features** and can grant proficiencies. Applying it sets the character's
Background and adds all its features. The character's separate Affiliation
field is plain text.

```json
{
  "id": "fsb",
  "name": "FSB",
  "description": "Federal Security Service operative.",
  "skillProficiencies": ["investigation", "deception"],
  "saveProficiencies": ["dex", "con"],
  "features": [
    {
      "id": "fsb_clearance",
      "name": "Agency Clearance",
      "description": "Access to restricted sites and records."
    },
    {
      "id": "fsb_tradecraft",
      "name": "Tradecraft",
      "description": "+1 to Stealth.",
      "effects": [ { "target": "skill.stealth", "value": 1 } ]
    }
  ]
}
```

| Field | Meaning |
|-------|---------|
| `features` | A list of full feature objects (same fields as section 6). Written **inline** inside the background. |
| `skillProficiencies` | Skill names in the same lowercase-underscore form as effects (`"sleight_of_hand"`). Unknown names are ignored. |
| `saveProficiencies` | Ability keys: `str`, `dex`, `con`, `int`, `wis`, `cha`. |

Behavior:
- Choosing a different background **removes the features the previous one
  granted** and adds the new ones. Features you added by hand stay.
- Granted proficiencies are **not** removed when switching (they might also
  come from somewhere else); untick them manually if needed.

---

## 8. Classes, subclasses and level progression

Class data lives in the top-level `classes` list. A character chooses one class
through the level-up control. The first class selection applies the class's
features through the character's current level; subsequent level-ups advance
that class by one level. This system is single-class (multiclassing is not
currently supported).

```json
{
  "id": "vanguard",
  "name": "Vanguard",
  "hitDie": 10,
  "featLevels": [4, 8, 12],
  "savingThrows": ["str", "con"],
  "subclassLevel": 3,
  "levels": [
    {
      "level": 1,
      "features": [
        {
          "name": "Combat Training",
          "description": "Trained for frontline combat."
        }
      ]
    },
    {
      "level": 2,
      "features": [
        {
          "name": "Tactical Surge",
          "description": "Gain an additional burst of tactical effort."
        }
      ]
    }
  ],
  "subclasses": [
    {
      "id": "sentinel",
      "name": "Sentinel",
      "description": "Protect allies and hold the line.",
      "features": [
        {
          "level": 3,
          "name": "Guardian Stance",
          "description": "Improve your ability to defend nearby allies."
        }
      ]
    }
  ]
}
```

| Field | Required | Meaning |
|-------|----------|---------|
| `id` | no | Stable class id; defaults to a slug of `name`. Keep it stable after characters use the class. |
| `name` | **yes** | Class name shown on the character. |
| `hitDie` | **yes** | Hit die size from 1 to 20 (normally 6, 8, 10 or 12). It determines automatic average HP gained on level-up. |
| `savingThrows` | no | Ability keys (`str`, `dex`, `con`, `int`, `wis`, `cha`) granted when the class is first selected. |
| `featLevels` | no | Levels that require a feat choice. The standard progression is `[4, 8, 12]`; options come from imported `feats`. |
| `subclassLevel` | no | Level at which a subclass is selected; defaults to 3. |
| `levels` | no | Level entries with class features unlocked at that level. Levels must be 1-20. |
| `subclasses` | no | Subclass definitions; each has an optional `id`, required `name`, optional `description`, and `features`. |
| `features` | no | Feature entries use the same `name`, `description`, `source`, and `effects` fields as section 6. |

Each `levels` entry has a `level` and optional `features` list. Each subclass
feature is an object with its own `level`, `name`, and optional `description`,
`source`, and `effects`. Feature effects work like any other trait effects:
they apply automatically and appear in Features & Traits.

If `featLevels` is present, those class levels require choosing an imported
feat. Import feat definitions with the top-level `feats` section, using the
same `name`, `description`, and `effects` fields as features. The chosen feat
is copied to the character and its effects recalculate like other traits.

### Enforced level-up choices

Add a `choices` list to a class level entry, or to a subclass definition. A
subclass choice also specifies its `level`. The level-up dialog requires the
specified number of distinct options before it can advance. Class selection at
an existing level asks for choices from every applicable earlier level.

```json
{
  "level": 3,
  "choices": [
    {
      "id": "virtuoso_level_3",
      "prompt": "Choose one level 3 benefit",
      "count": 1,
      "options": [
        {
          "id": "glukhar_aggression",
          "name": "Glukhar's Aggression",
          "description": "Gain advantage on eligible firearm attacks."
        },
        {
          "id": "shturmans_cunning",
          "name": "Shturman's Cunning",
          "description": "Find a better angle when hearing unrelated gunfire."
        }
      ]
    }
  ]
}
```

`count` defaults to 1; for a pick-N selection, set it to N. Each option needs
unique `id` and `name` fields. By default an option is granted as a character
feature. Set `"grantType": "skill"` with a `skillAbility` (`str`, `dex`, `con`,
`int`, `wis`, or `cha`) to grant skill proficiency. Set
`"grantType": "catalog"` with `catalogKey` (`weapons`, `armor`, or `items`) and
`itemId` to add that catalog item to the character. Choice grants are saved
with their level and are removed if that level is undone.

When a class is selected, its saving throws and all class features through the
current character level are applied. At an advancement, the handler raises the
level, adds one hit die, increases current and maximum HP by
`max(1, floor(hitDie / 2) + 1 + Constitution modifier)`, and adds that level's
class and subclass features. Subclasses are required at their configured
unlock level when the class defines any subclasses. Advancement is player-triggered. The campaign setting **Require XP to level
up** is off by default; when enabled, the handler blocks advancement until the
character has the XP threshold for the next level. Class selection itself is
not XP-gated.

Class ids and subclass ids must remain stable because characters save those
selections. Keep class definitions in the Catalog so characters can continue
to level and the app can resolve their subclass descriptions. Class definitions
are imported/updated with the same add-or-replace-by-id behavior as other
catalog entries.

---

## 9. Worked example: converting a character sheet to JSON

Taking entries from a sheet like the one this app was based on:

| On the sheet | Becomes |
|--------------|---------|
| Weapon "Bullet Dice, 100" | Weapon with `"ammoType": "Bullet Dice"`, `"ammoMax": 0`; plus an **ammo item** `"ammoType": "Bullet Dice"`, `"quantity": 100` |
| Armor box "3 / 30" | `"rating": 3`, `"hp": 30`, `"hpMax": 30` (add an `ac` effect if it should change AC) |
| Armor box "2 / 50" | `"rating": 2`, `"hp": 50`, `"hpMax": 50` |
| "30 rnd PP-19 magazine x3" | Ammo item: `"ammoType": "9x18mm"`, `"quantity": 90` (30 x 3 rounds), or a weapon with `"ammoMax": 30` and the extra magazines as ammo |
| "8 rnd Makarov magazine x2" | Ammo item: `"quantity": 16` |
| "Flash Bang (DC 18 CON)" | Item: `"description": "DC 18 CON save."`, `"quantity": 1` |
| "AFAK Medical Kit x1" | Item with `"usesMax"` set to its number of uses |
| "CAT Tourniquet x1" | Item, `"quantity": 1` |
| "Blackhawk Tactical Rig" | Item (or armor, if it has HP/effects) |

Full pack for the above:

```json
{
  "pack": "Igor's kit",
  "weapons": [
    {
      "id": "pp19",
      "name": "PP-19 Bizon",
      "ammoType": "9x18mm",
      "ammoMax": 0,
      "roundsPerShot": 1,
      "damage": "2d6",
      "attackAbility": "dex",
      "hp": 40
    }
  ],
  "armor": [
    {
      "id": "plate_carrier",
      "name": "Plate Carrier",
      "rating": 3,
      "hp": 30,
      "effects": [ { "target": "ac", "value": 2 } ]
    }
  ],
  "items": [
    { "id": "ammo_9x18", "name": "9x18mm rounds", "kind": "ammo", "ammoType": "9x18mm", "quantity": 106 },
    { "id": "flashbang", "name": "Flash Bang", "description": "DC 18 CON save.", "quantity": 1 },
    { "id": "afak", "name": "AFAK Medical Kit", "description": "Heals 2d4+2 HP per use.", "usesMax": 3 },
    { "id": "cat", "name": "CAT Tourniquet", "quantity": 1 }
  ],
  "traits": [
    { "id": "iron_nerves", "name": "Iron Nerves", "description": "Advantage on saves against fear." }
  ],
  "features": [
    { "id": "second_wind", "name": "Second Wind", "description": "Regain HP once per rest." }
  ],
  "backgrounds": [
    {
      "id": "fsb",
      "name": "FSB",
      "description": "Federal Security Service operative.",
      "skillProficiencies": ["investigation"],
      "features": [ { "name": "Agency Clearance", "description": "Access to restricted sites." } ]
    }
  ]
}
```

---

## 10. Checklist and common mistakes

| Symptom | Likely cause |
|---------|--------------|
| "Invalid JSON" | Trailing comma, single quotes, or a comment. Paste into any JSON validator. |
| An entry is missing after import | It had no `name`; check the result dialog's error list. |
| Weapon says "out of ammo" but you have rounds | `ammoType` differs in spelling (`9x18` vs `9x18mm`) or the item's `kind` isn't `"ammo"`. Case and surrounding spaces don't matter. |
| "Click! ... Reload first." | `ammoMax` is above 0 and the magazine does not hold enough rounds; reload it, or ask the DM to enable **Pull ammo from inventory when firing**. |
| Reload does nothing | Weapon needs both `ammoType` and `ammoMax` above 0, and matching ammo must be in the inventory. |
| Armor doesn't change AC | `rating` is display-only; add an `ac` effect, and make sure the armor is Equipped. |
| An effect does nothing | Misspelled `target`; skill names are lowercase with underscores. |
| Imported a changed item but the character still has the old one | Catalog entries are copied when added; remove the old copy and add the updated one. |
| Two entries overwrote each other | They share an `id`. Give each a unique `id`. |
| Unknown section warning | The top-level key isn't a supported content section such as `weapons`, `armor`, `items`, `traits`, `features`, `backgrounds`, `skills`, `feats`, `spells`, `actions`, or `classes` (legacy `affiliations` is also accepted as `backgrounds`). |
| Class missing from level-up selection | Import a valid entry under `classes`; check the result dialog for an invalid `hitDie`, subclass, or progression level. |
| Cannot choose a subclass | The subclass dropdown appears at `subclassLevel`; a class with subclasses requires a choice at that level. |
| Class features are not appearing | Add features to a `levels` entry for the exact target level; subclass feature objects also need a `level`. |
| Level-up is blocked | Import/restore the chosen class definition in the Catalog; saved characters keep class ids, not a full copy of the class catalog. |

### Tip: converting book text with an AI assistant
Paste this guide plus the rules text and ask: *"Convert these entries into a
content pack following CONTENT_GUIDE.md. Use `effects` for supported numeric
bonuses and programmatic stat formulas. Put everything else in `description`."*
Then review the output and
import it. The result dialog lists any entry that failed.
