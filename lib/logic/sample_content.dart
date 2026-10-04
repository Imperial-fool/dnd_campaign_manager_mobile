/// Example content pack shown in the import dialog.
const String sampleContentPack = r'''{
  "pack": "Core Armory",
  "weapons": [
    {
      "id": "pp19",
      "name": "PP-19 Bizon",
      "ammoType": "9x18mm",
      "ammo": 30,
      "ammoMax": 30,
      "roundsPerShot": 3,
      "damage": "2d6+2",
      "attackAbility": "dex",
      "hp": 40,
      "hpMax": 40,
      "properties": "Burst fire, two-handed"
    },
    {
      "id": "makarov",
      "name": "Makarov PM",
      "ammoType": "9x18mm",
      "ammoMax": 0,
      "damage": "1d8+1",
      "attackAbility": "dex"
    }
  ],
  "armor": [
    {
      "id": "6b45",
      "name": "6B45 Plate Carrier",
      "rating": 3,
      "hp": 30,
      "hpMax": 30,
      "properties": "Class 4 plates",
      "effects": [
        { "target": "ac", "value": 2 },
        { "target": "skill.stealth", "value": -1 }
      ]
    }
  ],
  "items": [
    {
      "id": "ammo_9x18_fmj",
      "name": "9x18mm FMJ",
      "kind": "ammo",
      "ammoType": "9x18mm",
      "quantity": 90
    },
    {
      "id": "afak",
      "name": "AFAK Medical Kit",
      "kind": "item",
      "description": "Heals 2d4+2 HP per use.",
      "quantity": 1,
      "usesMax": 3
    }
  ],
  "traits": [
    {
      "id": "iron_nerves",
      "name": "Iron Nerves",
      "description": "Advantage on saves against fear.",
      "source": "Background"
    }
  ],
  "features": [
    {
      "id": "second_wind",
      "name": "Second Wind",
      "description": "Once per rest, regain hit points.",
      "effects": [ { "target": "hp.max", "value": 2 } ]
    }
  ],
  "affiliations": [
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
  ],
  "classes": [
    {
      "id": "vanguard",
      "name": "Vanguard",
      "hitDie": 10,
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
  ]
}''';
