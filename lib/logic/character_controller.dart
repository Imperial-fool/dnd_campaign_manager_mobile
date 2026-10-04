import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/logic/dice.dart';
import 'package:dnd_campaign_manager/logic/inventory.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

/// Edits ONE character and runs its dice rolls. UI calls [edit] with a
/// mutation; this notifies listeners and debounces a save to the repository.
/// Roll methods return the [RollEntry] they logged so the UI can show it.
class CharacterController extends ChangeNotifier {
  CharacterController({
    required this.character,
    required this.repository,
    this.onSaved,
    DiceRoller? dice,
  }) : dice = dice ?? DiceRoller();

  final Character character;
  final CampaignRepository repository;
  final VoidCallback? onSaved;
  final DiceRoller dice;

  /// Session-only (not saved).
  final List<RollEntry> rollLog = [];
  RollMode rollMode = RollMode.normal;

  Timer? _debounce;
  bool _dirty = false;

  void edit(void Function(Character c) change) {
    change(character);
    _dirty = true;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), flush);
  }

  Future<void> flush() async {
    _debounce?.cancel();
    if (!_dirty) return;
    _dirty = false;
    await repository.saveCharacter(character);
    onSaved?.call();
  }

  // ---- list helpers -------------------------------------------------------
  void addBlankWeapon() =>
      edit((c) => c.weapons.add(Weapon(name: 'New Weapon')));
  void addBlankArmor() => edit((c) => c.armor.add(Armor(name: 'New Armor')));
  void addBlankItem({bool ammo = false}) => edit((c) => c.items.add(ammo
      ? InventoryItem(name: 'New Ammo', kind: 'ammo', quantity: 30)
      : InventoryItem(name: 'New Item')));
  void addBlankTrait({String category = 'trait'}) =>
      edit((c) => c.traits.add(Trait(
          name: 'New ${category == 'feature' ? 'Feature' : 'Trait'}',
          category: category)));

  void addSkill(Skill s) => edit((c) => c.skills.add(s));

  void changeLevel(int delta) {
    if (delta >= 0) {
      edit((c) => c.level = (c.level + delta).clamp(1, 20));
      return;
    }
    edit((c) {
      for (var i = 0; i < -delta && c.level > 1; i++) {
        final oldLevel = c.level;
        if (c.classId.isNotEmpty) {
          final classOrigin = 'class:${c.classId}:level:$oldLevel';
          final subclassOrigin =
              'subclass:${c.classId}:${c.subclassId}:level:$oldLevel';
          c.traits.removeWhere((trait) =>
              _hasOrigin(trait.origin, classOrigin) ||
              (c.subclassId.isNotEmpty &&
                  _hasOrigin(trait.origin, subclassOrigin)));
          for (final skill in c.skills) {
            skill.proficiencySources
                .removeWhere((source) => _hasOrigin(source, classOrigin));
            skill.expertiseSources
                .removeWhere((source) => _hasOrigin(source, classOrigin));
            if (c.subclassId.isNotEmpty) {
              skill.proficiencySources
                  .removeWhere((source) => _hasOrigin(source, subclassOrigin));
              skill.expertiseSources
                  .removeWhere((source) => _hasOrigin(source, subclassOrigin));
            }
          }
          c.weapons.removeWhere((item) =>
              _hasOrigin(item.origin, classOrigin) ||
              (c.subclassId.isNotEmpty &&
                  _hasOrigin(item.origin, subclassOrigin)));
          c.armor.removeWhere((item) =>
              _hasOrigin(item.origin, classOrigin) ||
              (c.subclassId.isNotEmpty &&
                  _hasOrigin(item.origin, subclassOrigin)));
          c.items.removeWhere((item) =>
              _hasOrigin(item.origin, classOrigin) ||
              (c.subclassId.isNotEmpty &&
                  _hasOrigin(item.origin, subclassOrigin)));
          if (c.classHitDie > 0 && c.classHpLevels > 0) {
            final hpGain = max(
                1,
                c.classHitDie ~/ 2 +
                    1 +
                    Rules.modifier(c.abilityScores[Ability.con] ?? 10));
            c.hpMax = max(1, c.hpMax - hpGain);
            c.hpCurrent = min(c.hpCurrent, c.hpMax);
            c.classHpLevels--;
          }
          c.hitDiceTotal = max(0, c.hitDiceTotal - 1);
          c.hitDiceUsed = min(c.hitDiceUsed, c.hitDiceTotal);
        }
        c.level--;
      }
    });
  }

  /// Selects a class at the character's current level or advances one level.
  /// Returns a validation message without changing the character on failure.
  String? advanceLevel(
    ClassDefinition definition, {
    required Catalog catalog,
    ClassSubclass? subclass,
    bool requireXp = false,
    Map<String, List<String>> selections = const {},
  }) {
    final c = character;
    final selectingClass = c.classId.isEmpty;
    if (!selectingClass && c.classId != definition.id) {
      return 'This character is already following ${c.className}.';
    }
    final targetLevel = selectingClass ? c.level : c.level + 1;
    if (targetLevel > 20) return 'A character cannot advance beyond level 20.';
    final nextXp = Rules.xpForNextLevel(c);
    if (!selectingClass && requireXp && nextXp != null && c.xp < nextXp) {
      return 'This character needs $nextXp XP to reach level $targetLevel.';
    }

    final selectedSubclass = c.subclassId.isEmpty
        ? subclass
        : subclassById(definition, c.subclassId);
    if (c.subclassId.isNotEmpty && selectedSubclass == null) {
      return 'The selected subclass is missing from this class definition.';
    }
    if (definition.subclasses.isNotEmpty &&
        targetLevel >= definition.subclassLevel &&
        selectedSubclass == null) {
      return 'Choose a subclass to reach level ${definition.subclassLevel}.';
    }
    if (subclass != null &&
        !definition.subclasses
            .any((data) => ClassSubclass(data).id == subclass.id)) {
      return 'That subclass does not belong to ${definition.name}.';
    }
    if (subclass != null && targetLevel < definition.subclassLevel) {
      return 'Subclasses unlock at level ${definition.subclassLevel}.';
    }

    final firstClassLevel = selectingClass ? 1 : targetLevel;
    final choices = <Map<String, dynamic>>[];
    for (var level = firstClassLevel; level <= targetLevel; level++) {
      choices.addAll(definition.choicesAtLevel(
        level,
        availableFeats: catalog.items('feats'),
      ));
      if (selectedSubclass != null) {
        choices.addAll(
          selectedSubclass.choicesAtLevel(level, definition.id),
        );
      }
    }
    final selectedOptions = <(String, Map<String, dynamic>)>[];
    for (final choice in choices) {
      final key = asStr(choice['selectionKey']);
      final selected = selections[key] ?? const <String>[];
      final count = asInt(choice['count'], 1);
      if (asMapList(choice['options']).isEmpty) {
        return 'Import at least one feat before advancing to level $targetLevel.';
      }
      if (selected.length != count || selected.toSet().length != count) {
        return 'Choose exactly $count option(s): ${asStr(choice['prompt'])}.';
      }
      final options = asMapList(choice['options']);
      for (final id in selected) {
        final matches = options.where((option) => asStr(option['id']) == id);
        if (matches.length != 1) {
          return 'Invalid selection for ${asStr(choice['prompt'])}.';
        }
        final option = matches.single;
        if (asStr(option['grantType'], 'feature') == 'catalog') {
          final catalogKey = asStr(option['catalogKey']);
          final itemId = asStr(option['itemId']);
          if (!catalog.items(catalogKey).any((item) => item.id == itemId)) {
            return 'The selected ${asStr(option['name'])} is missing from the $catalogKey catalog.';
          }
          if (asStr(option['grantType']) == 'feat' &&
              !catalog
                  .items('feats')
                  .any((feat) => feat.id == asStr(option['featId']))) {
            return 'The selected feat is missing from the feats catalog.';
          }
        }
        selectedOptions.add((asStr(choice['selectionOrigin']), option));
      }
    }

    edit((character) {
      if (selectingClass) {
        character.classId = definition.id;
        character.className = definition.name;
        character.classHitDie = definition.hitDie;
        for (final key in definition.savingThrows) {
          character.saveProficiencies.add(Ability.fromKey(key));
        }
      }

      for (var level = firstClassLevel; level <= targetLevel; level++) {
        _grantFeatures(
          character,
          definition.featuresAtLevel(level),
          'class:${definition.id}:level:$level',
          '${definition.name} (level $level)',
          '${definition.id}_level_$level',
        );
        if (selectedSubclass != null) {
          _grantFeatures(
            character,
            selectedSubclass.featuresAtLevel(level),
            'subclass:${definition.id}:${selectedSubclass.id}:level:$level',
            '${selectedSubclass.name} (level $level)',
            '${definition.id}_${selectedSubclass.id}_level_$level',
          );
        }
      }

      for (final (origin, option) in selectedOptions) {
        _applyChoiceOption(character, catalog, option, origin);
      }

      if (selectingClass) {
        character.hitDiceTotal = max(character.hitDiceTotal, targetLevel);
      } else {
        character.level = targetLevel;
        character.hitDiceTotal++;
        final hpGain = max(
          1,
          definition.hitDie ~/ 2 +
              1 +
              Rules.modifier(character.abilityScores[Ability.con] ?? 10),
        );
        character.hpMax += hpGain;
        character.hpCurrent += hpGain;
        character.classHpLevels++;
      }

      if (selectedSubclass != null && character.subclassId.isEmpty) {
        character.subclassId = selectedSubclass.id;
        character.subclassName = selectedSubclass.name;
      }
    });
    return null;
  }

  bool _hasOrigin(String value, String levelOrigin) =>
      value == levelOrigin || value.startsWith('$levelOrigin:');

  void _applyChoiceOption(
    Character character,
    Catalog catalog,
    Map<String, dynamic> option,
    String origin,
  ) {
    switch (asStr(option['grantType'], 'feature')) {
      case 'skill':
        final name = asStr(option['name']);
        final key = slug(name);
        var matches = character.skills.where((skill) => skill.key == key);
        if (matches.isEmpty) {
          character.skills.add(Skill(
            name: name,
            ability: Ability.fromKey(asStr(option['skillAbility'], 'str')),
          ));
          matches = character.skills.where((skill) => skill.key == key);
        }
        for (final skill in matches) {
          if (asBool(option['expertise'])) {
            skill.expertiseSources.add(origin);
          } else {
            skill.proficiencySources.add(origin);
          }
        }
        break;
      case 'feat':
        final feat = catalog
            .items('feats')
            .firstWhere((item) => item.id == asStr(option['featId']));
        character.traits.add(
          Trait.fromJson(feat.toJson(), defaultCategory: 'feat')
            ..id = '${slug(origin)}_${feat.id}'
            ..category = 'feat'
            ..origin = origin,
        );
        break;
      case 'catalog':
        final catalogKey = asStr(option['catalogKey']);
        final itemId = asStr(option['itemId']);
        final template =
            catalog.items(catalogKey).firstWhere((item) => item.id == itemId);
        switch (catalogKey) {
          case 'weapons':
            character.weapons
                .add(Weapon.fromJson(template.toJson())..origin = origin);
            break;
          case 'armor':
            character.armor
                .add(Armor.fromJson(template.toJson())..origin = origin);
            break;
          case 'items':
            character.items.add(
                InventoryItem.fromJson(template.toJson())..origin = origin);
            break;
        }
        break;
      default:
        final json = Map<String, dynamic>.from(option)
          ..['id'] = '${slug(origin)}_${asStr(option['id'])}'
          ..['category'] = 'feature'
          ..['origin'] = origin;
        character.traits.add(Trait.fromJson(json, defaultCategory: 'feature'));
        break;
    }
  }

  void _grantFeatures(
    Character character,
    List<Map<String, dynamic>> features,
    String origin,
    String source,
    String idPrefix,
  ) {
    for (var index = 0; index < features.length; index++) {
      final json = Map<String, dynamic>.from(features[index]);
      json['id'] = '${idPrefix}_${json['id'] ?? index}';
      json['category'] = 'feature';
      if (asStr(json['source']).trim().isEmpty) json['source'] = source;
      json['origin'] = origin;
      character.traits.add(Trait.fromJson(json, defaultCategory: 'feature'));
    }
  }

  /// Clone a catalog item onto this character via its binding.
  void applyCatalogItem(ContentBinding binding, CatalogItem item) {
    final copy =
        binding.parse(item.toJson()); // fresh instance, catalog stays untouched
    edit((c) => binding.apply(c, copy));
  }

  // ---- rolling ------------------------------------------------------------
  void setRollMode(RollMode m) {
    rollMode = m;
    notifyListeners();
  }

  RollEntry _log(RollEntry e) {
    rollLog.insert(0, e);
    if (rollLog.length > 40) rollLog.removeLast();
    notifyListeners();
    return e;
  }

  void clearLog() {
    rollLog.clear();
    notifyListeners();
  }

  /// d20 + [bonus], honouring advantage/disadvantage. Used for skills, saves,
  /// ability checks.
  RollEntry rollCheck(String label, int bonus) {
    final r = dice.d20(rollMode);
    return _log(RollEntry(
      title: label,
      total: r.chosen + bonus,
      lines: [
        'd20 ${r.describe()} ${Rules.signed(bonus)}',
        if (r.crit) 'Natural 20',
        if (r.fumble) 'Natural 1'
      ],
      crit: r.crit,
      fumble: r.fumble,
    ));
  }

  /// Free-form roll such as "2d6+3".
  RollEntry rollText(String text) {
    try {
      final d = dice.roll(text);
      return _log(
          RollEntry(title: d.expression, total: d.total, lines: [d.parts]));
    } on FormatException catch (e) {
      return _log(RollEntry(title: 'Roll failed', lines: [e.message]));
    }
  }

  RollEntry attack(Weapon w) {
    final r = dice.d20(rollMode);
    final bonus = Rules.attackBonus(character, w);
    return _log(RollEntry(
      title: '${w.name} attack',
      total: r.chosen + bonus,
      lines: [
        'd20 ${r.describe()} ${Rules.signed(bonus)}',
        if (r.crit) 'Critical hit!',
        if (r.fumble) 'Natural 1'
      ],
      crit: r.crit,
      fumble: r.fumble,
    ));
  }

  RollEntry damage(Weapon w, {bool crit = false}) {
    if (w.damage.trim().isEmpty) {
      return _log(RollEntry(
          title: '${w.name} damage', lines: const ['No damage dice set.']));
    }
    try {
      final d = dice.roll(_weaponDamage(w, w.damage), doubleDice: crit);
      return _log(RollEntry(
        title: '${w.name} damage',
        total: d.total,
        lines: [d.parts, if (crit) 'Crit: dice doubled'],
      ));
    } on FormatException catch (e) {
      return _log(RollEntry(title: '${w.name} damage', lines: [e.message]));
    }
  }

  /// Spend ammo, roll to hit, roll damage (doubled dice on a natural 20,
  /// no damage on a natural 1).
  ///
  /// Ammo source:
  ///  - weapon.ammoMax > 0  -> magazine: rounds come from the loaded count
  ///    (use [reload] to refill it from inventory)
  ///  - weapon.ammoMax == 0 -> rounds are removed from matching inventory ammo
  ///  - weapon.ammoType blank -> no ammo needed
  RollEntry fire(Weapon w) {
    final mode = w.firingMode;
    final modeDamage = _weaponDamage(
      w,
      mode == 'burst' ? w.burstDamage : w.damage,
    );
    final need = mode == 'fullAuto'
        ? _maximumDiceResult(w.bulletDice)
        : mode == 'burst'
            ? (w.burstRounds > 0 ? w.burstRounds : max(1, w.roundsPerShot))
            : max(1, w.roundsPerShot);
    final type = w.ammoType.trim();
    final lines = <String>[];

    if (mode == 'fullAuto' && w.bulletDice.trim().isEmpty) {
      return _log(RollEntry(
        title: '${w.name}: full auto unavailable',
        lines: const ['Set a bullet dice expression first.'],
      ));
    }
    if (mode == 'burst' && w.burstDamage.trim().isEmpty) {
      return _log(RollEntry(
        title: '${w.name}: burst unavailable',
        lines: const ['Set a burst damage expression first.'],
      ));
    }
    if (!{'semi', 'burst', 'fullAuto'}.contains(mode)) {
      return _log(RollEntry(
        title: '${w.name}: invalid firing mode',
        lines: ['Unsupported firing mode "$mode".'],
      ));
    }

    if (type.isNotEmpty) {
      if (w.ammoMax > 0) {
        if (w.ammo < need) {
          return _log(RollEntry(
              title: '${w.name}: click!',
              lines: ['Only ${w.ammo} loaded, needs $need. Reload first.']));
        }
        edit((_) => w.ammo -= need);
        lines.add('Used $need round(s); ${w.ammo}/${w.ammoMax} loaded');
      } else {
        final have = Inventory.available(character, type);
        if (have < need) {
          return _log(RollEntry(
              title: '${w.name}: out of ammo',
              lines: ['Inventory has $have $type, needs $need.']));
        }
        edit((c) => Inventory.consumeAmmo(c, type, need));
        lines.add(
            'Used $need $type; ${Inventory.available(character, type)} left in inventory');
      }
    }

    final a = dice.d20(rollMode);
    final bonus = Rules.attackBonus(character, w);
    final total = a.chosen + bonus;
    lines.add('Attack: d20 ${a.describe()} ${Rules.signed(bonus)} = $total');

    if (a.fumble) {
      lines.add('Natural 1: miss');
    } else if (mode == 'burst') {
      try {
        final d = dice.roll(modeDamage, doubleDice: a.crit);
        lines
          ..add('Burst: all $need rounds hit')
          ..add('${a.crit ? 'CRIT! ' : ''}Damage: ${d.total} (${d.parts})');
      } on FormatException catch (e) {
        lines.add('Burst damage not rolled: ${e.message}');
      }
    } else if (mode == 'fullAuto') {
      try {
        final hits = dice.roll(w.bulletDice).total.clamp(0, need).toInt();
        lines.add('Full auto: $hits hits from $need rounds');
        var damageTotal = 0;
        for (var i = 0; i < hits; i++) {
          final d = dice.roll(modeDamage, doubleDice: a.crit);
          damageTotal += d.total;
          lines.add('Hit ${i + 1}: ${d.total} (${d.parts})');
        }
        return _log(RollEntry(
          title: '${w.name} full auto',
          total: damageTotal,
          lines: lines,
          crit: a.crit,
          fumble: a.fumble,
        ));
      } on FormatException catch (e) {
        lines.add('Full-auto damage not rolled: ${e.message}');
      }
    } else if (modeDamage.trim().isNotEmpty) {
      try {
        final d = dice.roll(modeDamage, doubleDice: a.crit);
        lines.add('${a.crit ? 'CRIT! ' : ''}Damage: ${d.total}  (${d.parts})');
      } on FormatException catch (e) {
        lines.add('Damage not rolled: ${e.message}');
      }
    }
    return _log(RollEntry(
        title: '${w.name} fires',
        total: total,
        lines: lines,
        crit: a.crit,
        fumble: a.fumble));
  }

  int _maximumDiceResult(String expression) {
    final match = RegExp(r'(?:^|[+-])(\d*)d(\d+)').firstMatch(expression);
    if (match == null) return 1;
    final count = int.tryParse(match.group(1) ?? '') ?? 1;
    final sides = int.tryParse(match.group(2) ?? '') ?? 1;
    return max(1, count * sides);
  }

  String _weaponDamage(Weapon weapon, String expression) {
    if (weapon.damageAbility.isEmpty || expression.trim().isEmpty) {
      return expression;
    }
    final ability = Ability.fromKey(weapon.damageAbility);
    return '$expression${Rules.signed(Rules.abilityMod(character, ability))}';
  }

  /// Magazine weapons only: move rounds from inventory ammo into the weapon.
  RollEntry reload(Weapon w) {
    final type = w.ammoType.trim();
    if (w.ammoMax <= 0 || type.isEmpty) {
      return _log(RollEntry(title: '${w.name} reload', lines: const [
        'No magazine configured (set an ammo type and magazine size).'
      ]));
    }
    final room = w.ammoMax - w.ammo;
    if (room <= 0) {
      return _log(
          RollEntry(title: '${w.name} reload', lines: const ['Already full.']));
    }
    final take = min(room, Inventory.available(character, type));
    if (take == 0) {
      return _log(RollEntry(
          title: '${w.name} reload', lines: ['No $type in inventory.']));
    }
    edit((c) {
      Inventory.consumeAmmo(c, type, take);
      w.ammo += take;
    });
    return _log(RollEntry(title: '${w.name} reloaded', lines: [
      '+$take rounds -> ${w.ammo}/${w.ammoMax}; ${Inventory.available(character, type)} $type left'
    ]));
  }

  /// Consume one use of an inventory item.
  RollEntry useItem(InventoryItem it) {
    if (it.quantity <= 0) {
      return _log(RollEntry(title: it.name, lines: const ['None left.']));
    }
    edit((_) => Inventory.useOne(it));
    final left = it.usesMax > 0
        ? '${it.uses}/${it.usesMax} uses left, ${it.quantity} in stack'
        : '${it.quantity} left';
    final lines = <String>[left];
    int? total;
    if (it.damage.trim().isNotEmpty) {
      try {
        final result = dice.roll(it.damage);
        total = result.total;
        lines.add('Damage: ${result.total} (${result.parts})'
            '${it.damageType.isEmpty ? '' : ' ${it.damageType}'}');
      } on FormatException catch (e) {
        lines.add('Damage not rolled: ${e.message}');
      }
    }
    if (it.areaRadius > 0) lines.add('Area radius: ${it.areaRadius} ft');
    if (it.saveDc > 0) {
      lines.add(
        'Saving throw: DC ${it.saveDc}'
        '${it.saveAbility.isEmpty ? '' : ' ${it.saveAbility.toUpperCase()}'}',
      );
    }
    return _log(
        RollEntry(title: 'Used ${it.name}', total: total, lines: lines));
  }

  @override
  void dispose() {
    flush();
    super.dispose();
  }
}
