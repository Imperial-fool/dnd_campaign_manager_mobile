import 'ability.dart';
import 'gear.dart';
import 'json_utils.dart';

class Skill {
  Skill({
    required this.name,
    required this.ability,
    this.proficient = false,
    this.expertise = false,
    this.misc = 0,
    Set<String>? proficiencySources,
    Set<String>? expertiseSources,
  })  : proficiencySources = proficiencySources ?? <String>{},
        expertiseSources = expertiseSources ?? <String>{};

  String name;
  Ability ability;
  bool proficient;

  /// Double proficiency. Implies proficient.
  bool expertise;
  int misc;
  Set<String> proficiencySources;
  Set<String> expertiseSources;

  bool get isProficient =>
      proficient ||
      expertise ||
      proficiencySources.isNotEmpty ||
      expertiseSources.isNotEmpty;
  bool get hasExpertise => expertise || expertiseSources.isNotEmpty;

  /// Effect target suffix, e.g. "skill.sleight_of_hand".
  String get key => slug(name);

  factory Skill.fromJson(Map<String, dynamic> j) => Skill(
        name: asStr(j['name']),
        ability: Ability.fromKey(asStr(j['ability'], 'str')),
        proficient: asBool(j['proficient']) || asBool(j['expertise']),
        expertise: asBool(j['expertise']),
        misc: asInt(j['misc']),
        proficiencySources: _stringSet(j['proficiencySources']),
        expertiseSources: _stringSet(j['expertiseSources']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'ability': ability.key,
        'proficient': proficient,
        'expertise': expertise,
        'misc': misc,
        'proficiencySources': proficiencySources.toList(),
        'expertiseSources': expertiseSources.toList(),
      };

  static Set<String> _stringSet(dynamic value) =>
      value is List ? value.map((item) => item.toString()).toSet() : <String>{};
}

List<Skill> defaultSkills() => [
      Skill(name: 'Acrobatics', ability: Ability.dex),
      Skill(name: 'Animal Handling', ability: Ability.wis),
      Skill(
          name: 'Armaments',
          ability: Ability.intelligence), // campaign-specific
      Skill(name: 'Athletics', ability: Ability.str),
      Skill(name: 'Deception', ability: Ability.cha),
      Skill(name: 'History', ability: Ability.intelligence),
      Skill(name: 'Insight', ability: Ability.wis),
      Skill(name: 'Intimidation', ability: Ability.cha),
      Skill(name: 'Investigation', ability: Ability.intelligence),
      Skill(name: 'Medicine', ability: Ability.wis),
      Skill(name: 'Nature', ability: Ability.intelligence),
      Skill(name: 'Perception', ability: Ability.wis),
      Skill(name: 'Performance', ability: Ability.cha),
      Skill(name: 'Persuasion', ability: Ability.cha),
      Skill(name: 'Religion', ability: Ability.intelligence),
      Skill(name: 'Technology', ability: Ability.intelligence),
      Skill(name: 'Sleight of Hand', ability: Ability.dex),
      Skill(name: 'Stealth', ability: Ability.dex),
    ];

class Character {
  Character({required this.id});

  static const int schemaVersion = 2;

  final String id;

  // Identity
  String name = 'New Character';
  String player = '';
  String race = '';
  String affiliation = '';
  String alignment = '';
  String background = '';
  String backgroundId = '';
  int xp = 0;
  int level = 1; // 1..20; proficiency bonus is derived from this
  String classId = '';
  String className = '';
  int classHitDie = 0;
  int classHpLevels = 0;
  String subclassId = '';
  String subclassName = '';

  // Core numbers (base values; Rules adds effects on top)
  int initiativeBonus = 0;
  int speed = 30;
  int armorClass = 10;
  bool inspiration = false;

  // Health
  int hpCurrent = 10;
  int hpMax = 10;
  int hitDiceTotal = 0;
  int hitDiceUsed = 0;
  int deathSuccesses = 0; // 0..3
  int deathFailures = 0; // 0..3
  int exhaustion = 0; // 0..6

  // Campaign-specific pools shown on the weapon/armor headers
  int weaponHp = 0;
  int armorHp = 0;

  final Map<Ability, int> abilityScores = {
    for (final a in Ability.values) a: 10
  };
  final Set<Ability> saveProficiencies = {};
  List<Skill> skills = defaultSkills();

  List<Weapon> weapons = [];
  List<Armor> armor = [];
  List<InventoryItem> items = [];
  List<Trait> traits = [];

  String equipment = '';
  String proficiencies = '';
  String notes = '';

  /// Unknown JSON keys are preserved here so nothing is lost on round-trip.
  /// Content bindings for new types can also store data here.
  Map<String, dynamic> extras = {};

  static const _known = {
    'schemaVersion',
    'id',
    'name',
    'player',
    'race',
    'affiliation',
    'alignment',
    'background',
    'backgroundId',
    'affiliationId',
    'xp',
    'level',
    'classId',
    'className',
    'classHitDie',
    'classHpLevels',
    'subclassId',
    'subclassName',
    'items',
    'proficiencyBonus',
    'initiativeBonus',
    'speed',
    'armorClass',
    'inspiration',
    'hpCurrent',
    'hpMax',
    'hitDiceTotal',
    'hitDiceUsed',
    'deathSuccesses',
    'deathFailures',
    'exhaustion',
    'weaponHp',
    'armorHp',
    'abilityScores',
    'saveProficiencies',
    'skills',
    'weapons',
    'armor',
    'traits',
    'equipment',
    'proficiencies',
    'notes',
  };

  factory Character.fromJson(Map<String, dynamic> j) {
    final idStr = asStr(j['id']);
    final c = Character(id: idStr.isEmpty ? newId() : idStr);
    c.name = asStr(j['name'], c.name);
    c.player = asStr(j['player']);
    c.race = asStr(j['race']);
    c.alignment = asStr(j['alignment']);
    c.xp = asInt(j['xp']);
    c.level = asInt(j['level'], 1).clamp(1, 20);
    c.classId = asStr(j['classId']);
    c.className = asStr(j['className']);
    c.classHitDie = asInt(j['classHitDie']);
    c.classHpLevels = asInt(j['classHpLevels']);
    c.subclassId = asStr(j['subclassId']);
    c.subclassName = asStr(j['subclassName']);
    c.items = asMapList(j['items']).map(InventoryItem.fromJson).toList();
    c.initiativeBonus = asInt(j['initiativeBonus']);
    c.speed = asInt(j['speed'], 30);
    c.armorClass = asInt(j['armorClass'], 10);
    c.inspiration = asBool(j['inspiration']);
    c.hpCurrent = asInt(j['hpCurrent'], 10);
    c.hpMax = asInt(j['hpMax'], 10);
    c.hitDiceTotal = asInt(j['hitDiceTotal']);
    c.hitDiceUsed = asInt(j['hitDiceUsed']);
    c.deathSuccesses = asInt(j['deathSuccesses']).clamp(0, 3);
    c.deathFailures = asInt(j['deathFailures']).clamp(0, 3);
    c.exhaustion = asInt(j['exhaustion']).clamp(0, 6);
    c.weaponHp = asInt(j['weaponHp']);
    c.armorHp = asInt(j['armorHp']);

    final scores = j['abilityScores'];
    if (scores is Map) {
      for (final a in Ability.values) {
        c.abilityScores[a] = asInt(scores[a.key], 10);
      }
    }
    final saves = j['saveProficiencies'];
    if (saves is List) {
      c.saveProficiencies
        ..clear()
        ..addAll(saves.map((e) => Ability.fromKey(e.toString())));
    }
    if (j['skills'] is List) {
      c.skills = asMapList(j['skills']).map(Skill.fromJson).toList();
    }
    c.weapons = asMapList(j['weapons']).map(Weapon.fromJson).toList();
    c.armor = asMapList(j['armor']).map(Armor.fromJson).toList();
    c.traits = asMapList(j['traits']).map((m) => Trait.fromJson(m)).toList();
    if (asInt(j['schemaVersion']) < schemaVersion) {
      c.affiliation = asStr(j['background']);
      c.background = asStr(j['affiliation']);
      c.backgroundId = asStr(j['affiliationId']);
      final oldOrigin =
          c.backgroundId.isEmpty ? '' : 'affiliation:${c.backgroundId}';
      final newOrigin =
          c.backgroundId.isEmpty ? '' : 'background:${c.backgroundId}';
      if (oldOrigin.isNotEmpty) {
        for (final trait in c.traits.where((t) => t.origin == oldOrigin)) {
          trait.origin = newOrigin;
          if (trait.source.startsWith('Affiliation: ')) {
            trait.source =
                trait.source.replaceFirst('Affiliation: ', 'Background: ');
          }
        }
      }
    } else {
      c.affiliation = asStr(j['affiliation']);
      c.background = asStr(j['background']);
      c.backgroundId = asStr(j['backgroundId']);
    }
    c.equipment = asStr(j['equipment']);
    c.proficiencies = asStr(j['proficiencies']);
    c.notes = asStr(j['notes']);
    c.extras = Map<String, dynamic>.of(j)
      ..removeWhere((k, _) => _known.contains(k));
    return c;
  }

  Map<String, dynamic> toJson() => {
        ...extras,
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'player': player,
        'race': race,
        'affiliation': affiliation,
        'alignment': alignment,
        'background': background,
        'backgroundId': backgroundId,
        'xp': xp,
        'level': level,
        'classId': classId,
        'className': className,
        'classHitDie': classHitDie,
        'classHpLevels': classHpLevels,
        'subclassId': subclassId,
        'subclassName': subclassName,
        'items': items.map((i) => i.toJson()).toList(),
        'initiativeBonus': initiativeBonus,
        'speed': speed,
        'armorClass': armorClass,
        'inspiration': inspiration,
        'hpCurrent': hpCurrent,
        'hpMax': hpMax,
        'hitDiceTotal': hitDiceTotal,
        'hitDiceUsed': hitDiceUsed,
        'deathSuccesses': deathSuccesses,
        'deathFailures': deathFailures,
        'exhaustion': exhaustion,
        if (weapons.isNotEmpty) 'weaponHp': weaponHp,
        if (armor.isNotEmpty) 'armorHp': armorHp,
        'abilityScores': {
          for (final a in Ability.values) a.key: abilityScores[a]
        },
        'saveProficiencies': saveProficiencies.map((a) => a.key).toList(),
        'skills': skills.map((s) => s.toJson()).toList(),
        'weapons': weapons.map((w) => w.toJson()).toList(),
        'armor': armor.map((a) => a.toJson()).toList(),
        'traits': traits.map((t) => t.toJson()).toList(),
        'equipment': equipment,
        'proficiencies': proficiencies,
        'notes': notes,
      };
}
