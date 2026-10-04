import 'ability.dart';
import 'effect.dart';
import 'json_utils.dart';

/// Anything that can live in the campaign catalog and be added to a character.
abstract class CatalogItem {
  String get id;
  String get name;
  String get summary;
  Map<String, dynamic> toJson();
}

List<Effect> _effects(dynamic v) => asMapList(v).map(Effect.fromJson).toList();

class Weapon implements CatalogItem {
  Weapon({
    this.id = '',
    this.name = '',
    this.ammoType = '',
    this.ammo = 0,
    this.ammoMax = 0,
    this.roundsPerShot = 1,
    this.damage = '',
    this.attackAbility = Ability.dex,
    this.proficient = true,
    this.attackBonus = 0,
    this.hp = 0,
    this.hpMax = 0,
    this.properties = '',
    this.origin = '',
    List<Effect>? effects,
  }) : effects = effects ?? [];

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
        'damage': damage,
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
    this.rating = 0,
    this.hp = 0,
    this.hpMax = 0,
    this.equipped = true,
    this.properties = '',
    this.origin = '',
    List<Effect>? effects,
  }) : effects = effects ?? [];

  @override
  String id;
  @override
  String name;
  int rating;
  int hp;
  int hpMax;
  bool equipped;
  String properties;
  String origin;
  List<Effect> effects;

  @override
  String get summary => 'Rating $rating · HP $hpMax';

  factory Armor.fromJson(Map<String, dynamic> j) {
    final name = asStr(j['name']);
    return Armor(
      id: idFor(j, name),
      name: name,
      rating: asInt(j['rating']),
      hp: asInt(j['hp']),
      hpMax: asInt(j['hpMax'], asInt(j['hp'])),
      equipped: asBool(j['equipped'], true),
      properties: asStr(j['properties']),
      origin: asStr(j['origin']),
      effects: _effects(j['effects']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rating': rating,
        'hp': hp,
        'hpMax': hpMax,
        'equipped': equipped,
        'properties': properties,
        'origin': origin,
        'effects': effects.map((e) => e.toJson()).toList(),
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
    this.origin = '',
    this.active = false,
    List<Effect>? effects,
  })  : kind = kind,
        category = category ?? (kind == 'ammo' ? 'ammo' : 'misc'),
        effects = effects ?? [];

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
  String origin;
  bool active;
  List<Effect> effects;

  bool get isAmmo => kind == 'ammo';

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
    return InventoryItem(
      id: idFor(j, name),
      name: name,
      kind: kind,
      category: j.containsKey('category')
          ? asStr(j['category'])
          : _legacyInventoryCategory(name, description, kind),
      description: description,
      quantity: asInt(j['quantity'], 1),
      uses: asInt(j['uses'], usesMax),
      usesMax: usesMax,
      ammoType: asStr(j['ammoType']),
      origin: asStr(j['origin']),
      active: asBool(j['active']),
      effects: _effects(j['effects']),
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
        'origin': origin,
        'active': active,
        'effects': effects.map((e) => e.toJson()).toList(),
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
