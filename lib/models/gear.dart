import 'ability.dart';
import 'effect.dart';
import 'equipment_rule_effect.dart';
import 'fire_mode.dart';
import 'json_utils.dart';

/// Anything that can live in the campaign catalog and be added to a character.
abstract class CatalogItem {
  String get id;
  String get name;
  String get summary;
  Map<String, dynamic> toJson();
}

List<Effect> _effects(dynamic v) => asMapList(v).map(Effect.fromJson).toList();

List<EquipmentRuleEffect> _equipmentRuleEffects(dynamic value) =>
    asMapList(value).map(EquipmentRuleEffect.fromJson).toList();

double _nonNegativeDouble(dynamic value, String field) {
  final result = value is num ? value.toDouble() : double.tryParse('$value');
  if (result == null || !result.isFinite || result < 0) {
    throw FormatException('"$field" must be a non-negative number.');
  }
  return result;
}

Map<String, List<InventoryItem>> _storedItems(dynamic value) {
  if (value == null) return {};
  if (value is! Map) {
    throw const FormatException('"stored" must be an object.');
  }
  return {
    for (final entry in value.entries)
      entry.key.toString():
          asMapList(entry.value).map(InventoryItem.fromJson).toList(),
  };
}

Map<String, dynamic> _storedToJson(Map<String, List<InventoryItem>> stored) => {
      for (final entry in stored.entries)
        if (entry.value.isNotEmpty)
          entry.key: entry.value.map((item) => item.toJson()).toList(),
    };

double _storedWeightKg(Map<String, List<InventoryItem>> stored) => stored.values
    .expand((items) => items)
    .fold<double>(0, (sum, item) => sum + item.totalWeightKg);

Map<String, int> _storageSlots(dynamic value) {
  if (value == null) return {};
  if (value is! Map) {
    throw const FormatException('"storageSlots" must be an object.');
  }
  final slots = <String, int>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    final count = entry.value;
    if (key.isEmpty || count is! int || count < 0) {
      throw const FormatException(
          'Storage slots need non-empty names and non-negative integer counts.');
    }
    slots[key] = count;
  }
  return slots;
}

List<FireMode> _normalizedFireModes(List<FireMode>? modes, FireMode selected) {
  final normalized = modes == null || modes.isEmpty
      ? <FireMode>[FireMode.semi]
      : FireMode.values.where(modes.contains).toList();
  if (!normalized.contains(selected)) normalized.add(selected);
  return normalized;
}

class Weapon implements CatalogItem {
  Weapon({
    this.id = '',
    this.name = '',
    this.ammoType = '',
    this.ammo = 0,
    this.ammoMax = 0,
    int roundsPerShot = 1,
    int? semiRoundsPerShot,
    int burstRounds = 0,
    this.lastFullAutoRounds,
    List<FireMode>? fireModes,
    this.bulletDice = '',
    this.burstDamage = '',
    this.firingMode = FireMode.semi,
    this.damageAbility = '',
    this.weightKg = 0,
    this.weaponType = '',
    this.damage = '',
    this.attackAbility = Ability.dex,
    this.proficient = true,
    this.attackBonus = 0,
    this.hp = 0,
    this.hpMax = 0,
    this.properties = '',
    this.origin = '',
    List<Effect>? effects,
  })  : effects = effects ?? [],
        roundsPerShot = roundsPerShot < 1 ? 1 : roundsPerShot,
        semiRoundsPerShot = (semiRoundsPerShot ?? roundsPerShot) < 1
            ? 1
            : (semiRoundsPerShot ?? roundsPerShot),
        burstRounds = burstRounds < 0 ? 0 : burstRounds,
        fireModes = _normalizedFireModes(fireModes, firingMode) {
    switch (firingMode) {
      case FireMode.semi:
        this.roundsPerShot = this.semiRoundsPerShot;
        break;
      case FireMode.burst:
        this.roundsPerShot =
            this.burstRounds > 0 ? this.burstRounds : this.semiRoundsPerShot;
        break;
      case FireMode.fullAuto:
        this.roundsPerShot = lastFullAutoRounds ?? this.semiRoundsPerShot;
        break;
    }
  }

  @override
  String id;
  @override
  String name;

  /// Must match an inventory ammo item's ammoType. Blank = needs no ammo.
  String ammoType;

  /// Rounds currently loaded (only used when [ammoMax] > 0).
  int ammo;

  /// Magazine size. 0 = no magazine: firing draws straight from inventory ammo.
  int ammoMax;
  int roundsPerShot;
  int semiRoundsPerShot;
  int burstRounds;
  int? lastFullAutoRounds;
  List<FireMode> fireModes;
  String bulletDice;
  String burstDamage;
  FireMode firingMode;
  String damageAbility;
  double weightKg;
  String weaponType;

  /// Dice expression, e.g. "2d6+2".
  String damage;
  Ability attackAbility;
  bool proficient;
  int attackBonus;
  int hp;
  int hpMax;
  String properties;
  String origin;
  List<Effect> effects;

  void selectFiringMode(FireMode mode) {
    firingMode = mode;
    switch (mode) {
      case FireMode.semi:
        roundsPerShot = semiRoundsPerShot;
        break;
      case FireMode.burst:
        roundsPerShot = burstRounds > 0 ? burstRounds : semiRoundsPerShot;
        break;
      case FireMode.fullAuto:
        roundsPerShot = lastFullAutoRounds ?? semiRoundsPerShot;
        break;
    }
  }

  void setSemiRoundsPerShot(int value) {
    semiRoundsPerShot = value < 1 ? 1 : value;
    if (firingMode == FireMode.semi) roundsPerShot = semiRoundsPerShot;
  }

  void setBurstRounds(int value) {
    burstRounds = value < 1 ? 1 : value;
    if (firingMode == FireMode.burst) roundsPerShot = burstRounds;
  }

  void recordFullAutoRounds(int value) {
    final rounds = value < 1 ? 1 : value;
    lastFullAutoRounds = rounds;
    if (firingMode == FireMode.fullAuto) roundsPerShot = rounds;
  }

  @override
  String get summary => [
        damage,
        if (ammoType.isNotEmpty) ammoType,
        if (hpMax > 0) 'HP $hpMax'
      ].where((s) => s.isNotEmpty).join(' · ');

  factory Weapon.fromJson(Map<String, dynamic> j) {
    final name = asStr(j['name']);
    return Weapon(
      id: idFor(j, name),
      name: name,
      ammoType: asStr(j['ammoType']),
      ammo: asInt(j['ammo']),
      ammoMax: asInt(j['ammoMax']),
      roundsPerShot:
          asInt(j['roundsPerShot'], 1) < 1 ? 1 : asInt(j['roundsPerShot'], 1),
      burstRounds: asInt(j['burstRounds']),
      fireModes: FireMode.listFromJson(j['fireModes']),
      bulletDice: asStr(j['bulletDice']),
      burstDamage: asStr(j['burstDamage']),
      firingMode: j['firingMode'] == null
          ? FireMode.semi
          : FireMode.fromJson(j['firingMode']),
      semiRoundsPerShot: asInt(
        j['semiRoundsPerShot'],
        asInt(j['roundsPerShot'], 1),
      ),
      lastFullAutoRounds: j['lastFullAutoRounds'] == null
          ? null
          : asInt(j['lastFullAutoRounds']),
      damageAbility: asStr(j['damageAbility']),
      weightKg: j['weightKg'] is num
          ? (j['weightKg'] as num).toDouble()
          : double.tryParse(asStr(j['weightKg'])) ?? 0,
      weaponType: asStr(j['weaponType']),
      damage: asStr(j['damage']),
      attackAbility: Ability.fromKey(asStr(j['attackAbility'], 'dex')),
      proficient: asBool(j['proficient'], true),
      attackBonus: asInt(j['attackBonus']),
      hp: asInt(j['hp']),
      hpMax: asInt(j['hpMax'], asInt(j['hp'])),
      properties: asStr(j['properties']),
      origin: asStr(j['origin']),
      effects: _effects(j['effects']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ammoType': ammoType,
        'ammo': ammo,
        'ammoMax': ammoMax,
        'roundsPerShot': roundsPerShot,
        'semiRoundsPerShot': semiRoundsPerShot,
        if (burstRounds > 0) 'burstRounds': burstRounds,
        if (lastFullAutoRounds != null)
          'lastFullAutoRounds': lastFullAutoRounds,
        'fireModes': fireModes.map((mode) => mode.name).toList(),
        'bulletDice': bulletDice,
        'damage': damage,
        'burstDamage': burstDamage,
        'firingMode': firingMode.name,
        if (damageAbility.isNotEmpty) 'damageAbility': damageAbility,
        if (weightKg > 0) 'weightKg': weightKg,
        if (weaponType.isNotEmpty) 'weaponType': weaponType,
        'attackAbility': attackAbility.key,
        'proficient': proficient,
        'attackBonus': attackBonus,
        'hp': hp,
        'hpMax': hpMax,
        'properties': properties,
        'origin': origin,
        'effects': effects.map((e) => e.toJson()).toList(),
      };
}

class Armor implements CatalogItem {
  Armor({
    this.id = '',
    this.name = '',
    this.equipmentSlot = '',
    this.rating = 0,
    this.hp = 0,
    this.hpMax = 0,
    this.equipped = true,
    this.weightKg = 0,
    this.carryCapacityKg = 0,
    Map<String, int>? storageSlots,
    Map<String, List<InventoryItem>>? stored,
    this.properties = '',
    this.origin = '',
    List<Effect>? effects,
    List<EquipmentRuleEffect>? ruleEffects,
  })  : storageSlots = storageSlots ?? {},
        stored = stored ?? {},
        effects = effects ?? [],
        ruleEffects = ruleEffects ?? [];

  @override
  String id;
  @override
  String name;
  String equipmentSlot;
  int rating;
  int hp;
  int hpMax;
  bool equipped;
  double weightKg;
  double carryCapacityKg;
  Map<String, int> storageSlots;

  /// Items placed in this container, keyed by storage slot name.
  Map<String, List<InventoryItem>> stored;
  String properties;
  String origin;
  List<Effect> effects;
  List<EquipmentRuleEffect> ruleEffects;

  bool get isContainer => equipmentSlot == 'rig';

  double get storedWeightKg => _storedWeightKg(stored);

  @override
  String get summary => 'Rating $rating · HP $hpMax';

  factory Armor.fromJson(Map<String, dynamic> j) {
    final name = asStr(j['name']);
    final equipmentSlot = asStr(j['equipmentSlot']);
    if (equipmentSlot.isNotEmpty &&
        !{'head', 'body', 'rig', 'other'}.contains(equipmentSlot)) {
      throw FormatException(
          'Unsupported armor equipment slot "$equipmentSlot".');
    }
    return Armor(
      id: idFor(j, name),
      name: name,
      equipmentSlot: equipmentSlot,
      rating: asInt(j['rating']),
      hp: asInt(j['hp']),
      hpMax: asInt(j['hpMax'], asInt(j['hp'])),
      equipped: asBool(j['equipped'], true),
      weightKg: _nonNegativeDouble(j['weightKg'] ?? 0, 'weightKg'),
      carryCapacityKg: equipmentSlot == 'rig'
          ? _nonNegativeDouble(j['carryCapacityKg'] ?? 0, 'carryCapacityKg')
          : 0,
      storageSlots:
          equipmentSlot == 'rig' ? _storageSlots(j['storageSlots']) : null,
      stored: equipmentSlot == 'rig' ? _storedItems(j['stored']) : null,
      properties: asStr(j['properties']),
      origin: asStr(j['origin']),
      effects: _effects(j['effects']),
      ruleEffects: _equipmentRuleEffects(j['ruleEffects']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (equipmentSlot.isNotEmpty) 'equipmentSlot': equipmentSlot,
        'rating': rating,
        'hp': hp,
        'hpMax': hpMax,
        'equipped': equipped,
        if (weightKg > 0) 'weightKg': weightKg,
        if (isContainer && carryCapacityKg > 0)
          'carryCapacityKg': carryCapacityKg,
        if (isContainer && storageSlots.isNotEmpty)
          'storageSlots': storageSlots,
        if (isContainer && _storedToJson(stored).isNotEmpty)
          'stored': _storedToJson(stored),
        'properties': properties,
        'origin': origin,
        'effects': effects.map((e) => e.toJson()).toList(),
        if (ruleEffects.isNotEmpty)
          'ruleEffects': ruleEffects.map((effect) => effect.toJson()).toList(),
      };
}

/// Used for both "features" and "traits" (distinguished by [category]).
class Trait implements CatalogItem {
  Trait({
    this.id = '',
    this.name = '',
    this.category = 'trait',
    this.description = '',
    this.source = '',
    this.origin = '',
    List<Effect>? effects,
  }) : effects = effects ?? [];

  @override
  String id;
  @override
  String name;
  String category; // 'trait' | 'feature'
  String description;
  String source;

  /// Which catalog entry granted this (e.g. "background:outdoorsman"); lets us
  /// remove it again when that grant is replaced. Empty = added by hand.
  String origin;
  List<Effect> effects;

  @override
  String get summary => description;

  factory Trait.fromJson(Map<String, dynamic> j,
      {String defaultCategory = 'trait'}) {
    final name = asStr(j['name']);
    return Trait(
      id: idFor(j, name),
      name: name,
      category: asStr(j['category'], defaultCategory),
      description: asStr(j['description']),
      source: asStr(j['source']),
      origin: asStr(j['origin']),
      effects: _effects(j['effects']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'description': description,
        'source': source,
        'origin': origin,
        'effects': effects.map((e) => e.toJson()).toList(),
      };
}

/// Schema-less item for content types the app has no class for yet
/// (spells, vehicles, ...). Kept verbatim as JSON.
class GenericItem implements CatalogItem {
  GenericItem(this.data);

  final Map<String, dynamic> data;

  @override
  String get id => idFor(data, name);
  @override
  String get name => asStr(data['name'], 'Unnamed');
  @override
  String get summary => asStr(data['description']);
  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(data);
}

/// Something carried. kind 'ammo' feeds weapons with a matching ammoType;
/// kind 'item' can have limited uses (usesMax) per unit.
class InventoryItem implements CatalogItem {
  InventoryItem({
    this.id = '',
    this.name = '',
    String kind = 'item',
    String? category,
    this.description = '',
    this.quantity = 1,
    this.uses = 0,
    this.usesMax = 0,
    this.ammoType = '',
    this.damage = '',
    this.damageType = '',
    this.areaRadius = 0,
    this.saveDc = 0,
    this.saveAbility = '',
    this.penetration = 0,
    this.durabilityBurn = 1,
    this.origin = '',
    this.active = false,
    this.weightKg = 0,
    this.carryCapacityKg = 0,
    Map<String, int>? storageSlots,
    Map<String, List<InventoryItem>>? stored,
    List<Effect>? effects,
    List<EquipmentRuleEffect>? ruleEffects,
  })  : kind = kind,
        category = category ?? (kind == 'ammo' ? 'ammo' : 'misc'),
        storageSlots = storageSlots ?? {},
        stored = stored ?? {},
        effects = effects ?? [],
        ruleEffects = ruleEffects ?? [];

  @override
  String id;
  @override
  String name;
  String kind; // 'item' | 'ammo'
  String category; // 'ammo' | 'medical' | 'misc'
  String description;
  int quantity;
  int uses; // remaining uses of the current unit
  int usesMax; // 0 = no per-unit uses
  String ammoType;
  String damage;
  String damageType;
  int areaRadius;
  int saveDc;
  String saveAbility;
  int penetration;
  int durabilityBurn;
  String origin;
  bool active;
  double weightKg;
  double carryCapacityKg;
  Map<String, int> storageSlots;

  /// Items placed in this container, keyed by storage slot name.
  Map<String, List<InventoryItem>> stored;
  List<Effect> effects;
  List<EquipmentRuleEffect> ruleEffects;

  bool get isAmmo => kind == 'ammo';
  bool get isContainer => !isAmmo && category == 'backpack';

  double get storedWeightKg => _storedWeightKg(stored);

  /// Own weight plus everything packed inside.
  double get totalWeightKg =>
      weightKg * (quantity < 0 ? 0 : quantity) + storedWeightKg;

  @override
  String get summary => isAmmo
      ? '$ammoType · x$quantity'
      : [
          if (usesMax > 0) '$usesMax uses',
          if (description.isNotEmpty) description
        ].join(' · ');

  factory InventoryItem.fromJson(Map<String, dynamic> j) {
    final name = asStr(j['name']);
    final usesMax = asInt(j['usesMax']);
    final kind = asStr(j['kind']) == 'ammo' ? 'ammo' : 'item';
    final description = asStr(j['description']);
    var category = j.containsKey('category')
        ? asStr(j['category'])
        : _legacyInventoryCategory(name, description, kind);
    // Legacy data: anything that stored things is a backpack.
    if (kind != 'ammo' &&
        category == 'misc' &&
        ((double.tryParse('${j['carryCapacityKg'] ?? 0}') ?? 0) > 0 ||
            (j['storageSlots'] is Map &&
                (j['storageSlots'] as Map).isNotEmpty))) {
      category = 'backpack';
    }
    final isContainer = kind != 'ammo' && category == 'backpack';
    return InventoryItem(
      id: idFor(j, name),
      name: name,
      kind: kind,
      category: category,
      description: description,
      quantity: asInt(j['quantity'], 1),
      uses: asInt(j['uses'], usesMax),
      usesMax: usesMax,
      ammoType: asStr(j['ammoType']),
      damage: asStr(j['damage']),
      damageType: asStr(j['damageType']),
      areaRadius: asInt(j['areaRadius']),
      saveDc: asInt(j['saveDc']),
      saveAbility: asStr(j['saveAbility']),
      penetration: asInt(j['penetration']),
      durabilityBurn: asInt(j['durabilityBurn'], 1),
      origin: asStr(j['origin']),
      active: asBool(j['active']),
      weightKg: _nonNegativeDouble(j['weightKg'] ?? 0, 'weightKg'),
      carryCapacityKg: isContainer
          ? _nonNegativeDouble(j['carryCapacityKg'] ?? 0, 'carryCapacityKg')
          : 0,
      storageSlots: isContainer ? _storageSlots(j['storageSlots']) : null,
      stored: isContainer ? _storedItems(j['stored']) : null,
      effects: _effects(j['effects']),
      ruleEffects: _equipmentRuleEffects(j['ruleEffects']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'category': category,
        'description': description,
        'quantity': quantity,
        'uses': uses,
        'usesMax': usesMax,
        'ammoType': ammoType,
        'damage': damage,
        'damageType': damageType,
        'areaRadius': areaRadius,
        'saveDc': saveDc,
        'saveAbility': saveAbility,
        if (penetration > 0) 'penetration': penetration,
        if (durabilityBurn != 1) 'durabilityBurn': durabilityBurn,
        'origin': origin,
        'active': active,
        if (weightKg > 0) 'weightKg': weightKg,
        if (isContainer && carryCapacityKg > 0)
          'carryCapacityKg': carryCapacityKg,
        if (isContainer && storageSlots.isNotEmpty)
          'storageSlots': storageSlots,
        if (isContainer && _storedToJson(stored).isNotEmpty)
          'stored': _storedToJson(stored),
        'effects': effects.map((e) => e.toJson()).toList(),
        if (ruleEffects.isNotEmpty)
          'ruleEffects': ruleEffects.map((effect) => effect.toJson()).toList(),
      };
}

String _legacyInventoryCategory(String name, String description, String kind) {
  if (kind == 'ammo') return 'ammo';
  final searchable = '${name.toLowerCase()} ${description.toLowerCase()}';
  const medicalTerms = [
    'medical',
    'med kit',
    'medkit',
    'bandage',
    'tourniquet',
    'splint',
    'ifak',
    'cms kit',
    'salewa',
    'hemostatic',
    'surgical',
  ];
  return medicalTerms.any(searchable.contains) ? 'medical' : 'misc';
}

/// A character background. Applying it grants its features and proficiencies.
class BackgroundDefinition implements CatalogItem {
  BackgroundDefinition({
    this.id = '',
    this.name = '',
    this.description = '',
    List<Trait>? features,
    List<String>? skillProficiencies,
    List<String>? saveProficiencies,
  })  : features = features ?? [],
        skillProficiencies = skillProficiencies ?? [],
        saveProficiencies = saveProficiencies ?? [];

  @override
  String id;
  @override
  String name;
  String description;
  List<Trait> features;
  List<String> skillProficiencies; // skill slugs, e.g. "stealth"
  List<String> saveProficiencies; // ability keys, e.g. "dex"

  @override
  String get summary => [
        if (description.isNotEmpty) description,
        '${features.length} feature(s)'
      ].join(' · ');

  static List<String> _strings(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : <String>[];

  factory BackgroundDefinition.fromJson(Map<String, dynamic> j) {
    final name = asStr(j['name']);
    return BackgroundDefinition(
      id: idFor(j, name),
      name: name,
      description: asStr(j['description']),
      features: asMapList(j['features'])
          .map((m) => Trait.fromJson(m, defaultCategory: 'feature'))
          .toList(),
      skillProficiencies: _strings(j['skillProficiencies']),
      saveProficiencies: _strings(j['saveProficiencies']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'features': features.map((f) => f.toJson()).toList(),
        'skillProficiencies': skillProficiencies,
        'saveProficiencies': saveProficiencies,
      };
}
